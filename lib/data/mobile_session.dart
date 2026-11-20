import 'dart:async';
import 'package:flutter/material.dart'
    show ChangeNotifier, ThemeMode, ValueNotifier;
import 'agent_api.dart';
import 'mobile_terminal_tools.dart';
import 'mobile_connectors.dart';
import 'device_inbox.dart';
import 'chat_history.dart';
import 'mobile_store.dart';
import 'mobile_signals.dart';
import 'mobile_screenshots.dart';
import 'question.dart';

class MobileSession extends ChangeNotifier {
  MobileSession(
    this.store,
    this.api, {
    MobileSignals? signals,
    MobileScreenshots? screenshots,
    AndroidDeviceStatus? deviceStatus,
  }) : signals = signals ?? MobileSignals(),
       deviceStatus = deviceStatus ?? AndroidDeviceStatus(),
       screenshots = screenshots ?? MobileScreenshots();
  final MobileStore store;
  String? installation;
  final AgentApi api;
  late final inbox = DeviceInbox(api);
  final MobileSignals signals;
  final MobileScreenshots screenshots;
  final AndroidDeviceStatus deviceStatus;
  final connectors = MobileConnectors();
  bool connectorEnabled(MobileConnector item) => _tools.selected.contains(item);
  bool connectorGranted(MobileConnector item) =>
      item.platform == connectors.platform && _tools.access[item.key] == true;

  Future<String?> setMobileConnector(MobileConnector item, bool enabled) async {
    final conn = connection;
    if (item.platform != connectors.platform) return '此连接器不适用于当前设备。';
    if (!canEnableConnectors || conn == null) {
      return '请先通过 HTTPS 或本机回环地址连接服务。';
    }
    if (enabled && !await connectors.authorize(item, conn.scope)) {
      return item == MobileConnector.sms
          ? '系统未授予短信读取权限。部分安装渠道限制此权限。'
          : connectors.platform == ConnectorPlatform.ios
          ? '尚未获得授权，可在 iPhone 的「设置 → 隐私与安全性」中调整。'
          : '尚未获得系统授权。';
    }
    String? issue;
    await _run(() async {
      if (connection != conn) {
        issue = '连接已更改，请重试。';
        return;
      }
      final previous = _tools.toJson();
      if (enabled) {
        _tools.selected.add(item);
      } else {
        _tools.disableConnector(item);
      }
      try {
        await _save();
      } catch (_) {
        _tools = MobileTerminalTools(previous, connectors.platform);
        issue = '无法保存连接器设置，请重试。';
        return;
      }
      try {
        if (!enabled && item == MobileConnector.files) {
          await connectors.releaseFolder(conn.scope);
        }
      } finally {
        _notify();
        await _pollDeviceStatus();
        issue = _tools.error;
      }
    });
    return issue;
  }

  late var _tools = MobileTerminalTools({}, connectors.platform);
  bool get canEnableConnectors =>
      connectors.platform != ConnectorPlatform.unsupported &&
      connection != null &&
      secureToolConnection(connection!);
  bool get canEnableDeviceStatus =>
      deviceStatus.supported &&
      connection != null &&
      secureToolConnection(connection!);
  bool get deviceStatusEnabled => _tools.enabled;
  String? get deviceStatusError => _tools.error;
  bool screenshotsEnabled = false;
  int screenshotInterval = 300, pendingScreenshots = 0;
  String screenshotAccess = 'unsupported';
  String? screenshotError;
  bool _uploadingScreenshot = false;
  Completer<void>? _cancelUpload;
  int _captureRevision = 0;
  int _retrySeconds = 0;
  DateTime? _retryAfter;
  final themeMode = ValueNotifier(ThemeMode.system);

  Future<void> restoreTheme() async {
    try {
      final mode = await store.readTheme();
      if (!_disposed) themeMode.value = mode;
    } catch (e) {
      // A missing or unreadable appearance preference must not block startup.
      if (!_disposed) themeMode.value = ThemeMode.system;
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    await store.saveTheme(mode);
    if (!_disposed) themeMode.value = mode;
  }

  Connection? connection;
  var _history = ChatHistory();
  List<Json> _serverMessages = [];
  List<Json> _outgoing = [];
  List<PendingQuestion> questions = [];
  List<Json> get messages {
    if (_outgoing.isEmpty) return _serverMessages;
    final byEvent = {
      for (final m in _outgoing)
        if (m['event_id'] != null) m['event_id']: m,
    };
    final serverIds = {for (final m in _serverMessages) m['id']};
    return [
      for (final row in _serverMessages)
        if (byEvent.containsKey(row['id']))
          {...row, 'status': byEvent[row['id']]!['status']}
        else
          row,
      for (final m in _outgoing)
        if (!serverIds.contains(m['event_id'])) m,
    ];
  }

  List<Json> pending = [];
  bool collecting = false;
  bool locationEnabled = false, usageEnabled = false;
  String locationAccess = 'unsupported', usageAccess = 'unsupported';
  bool backgroundLocation = false;
  String? signalError;
  var _timeline = MobileTimeline({});
  final _unacknowledged = <String>{};
  String? get lastLocationLabel => _timeline.lastLocationLabel;
  String? get lastUsageLabel => _timeline.lastUsageLabel;
  bool get canNameLocation =>
      locationEnabled &&
      locationAccess == 'granted' &&
      _timeline.canNameLocation;
  List<String> get placeNames => [
    for (final p in _timeline.places) p['name'] as String,
  ];
  bool ready = false;
  String? error;
  String? collectionError;
  String? lastActivity;
  String? lastUpload;
  String _page = '主页';
  bool _foreground = true;
  bool _disposed = false;
  bool _syncing = false;
  Future<void> _tail = Future.value();
  Timer? _timer;

  // All changes to the outbox, chat and active deviceId share one ordered writer.
  Future<void> _run(Future<void> Function() action) {
    return _tail = _tail.then((_) async {
      if (_disposed) return;
      try {
        await action();
      } catch (e) {
        error = e.toString();
      } finally {
        _notify();
      }
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    screenshots.onChange(
      () => unawaited(
        _run(() async {
          await _configureScreenshots();
          unawaited(_uploadScreenshots());
        }),
      ),
    );
    await _run(() async {
      try {
        installation = await store.installationId();
        var saved = await store.connection();
        if (saved != null) {
          if (saved.installation != installation) {
            saved = Connection(
              saved.url,
              saved.deviceId,
              saved.token,
              installation: installation,
              name: saved.deviceName,
            );
            await store.saveConnection(saved);
          }
          await _load(saved);
        } else {
          await _refreshSignals();
          await _configureScreenshots();
        }
      } finally {
        ready = true;
      }
    });
    _armTimer();
    if (connection != null) {
      _observe();
      await sync();
    }
  }

  Future<void> _load(Connection value) async {
    _cancelScreenshotUpload();
    final saved = await store.history(value.scope);
    final outbox = List<Json>.from(saved['pending'] ?? []);
    // Older mobile clients queued handwritten notes at the slices endpoint.
    final queued = outbox.length;
    outbox.removeWhere(
      (event) => event['path'] == 'slices' && event['source'] != 'usage',
    );
    _history = ChatHistory();
    _serverMessages = [];
    _outgoing = List<Json>.from(saved['outgoing'] ?? saved['messages'] ?? [])
        .where(
          (row) =>
              row['role'] == 'user' &&
              row['event_id'] == null &&
              ['sending', 'unsent'].contains(row['status']),
        )
        .toList();
    for (final entry in _outgoing) {
      if (entry['status'] == 'sending' && entry['job'] == null) {
        entry['status'] = 'unsent';
      }
    }
    pending = outbox;
    _tools = MobileTerminalTools(
      saved['terminalTools'] as Json? ?? {},
      connectors.platform,
    );
    collecting = saved['collecting'] == true;
    locationEnabled = saved['locationEnabled'] == true;
    usageEnabled = saved['usageEnabled'] == true;
    screenshotsEnabled = saved['screenshotsEnabled'] == true;
    final interval = saved['screenshotInterval'];
    screenshotInterval = MobileScreenshots.intervals.contains(interval)
        ? interval as int
        : 300;
    screenshotError = null;
    _timeline = MobileTimeline(saved['timeline'] ?? {});
    _unacknowledged
      ..clear()
      ..addAll(List<String>.from(saved['nativeReceipts'] ?? []));
    lastActivity = saved['lastActivity'];
    lastUpload = saved['lastUpload'];
    collectionError = null;
    questions = [];
    connection = value;
    inbox.connect(value);
    if (saved.containsKey('messages') || outbox.length != queued) await _save();
    await _refreshSignals();
    await _configureScreenshots();
  }

  // Verify credentials without acknowledging or consuming any output.
  Future<bool> configure(Connection value) async {
    var ok = false;
    await _run(() async {
      await api.request(value, 'devices/self', body: {});
      await store.saveConnection(value);
      await _load(value);
      error = null;
      ok = true;
    });
    if (ok) {
      _armTimer();
      _observe();
      unawaited(sync());
    }
    return ok;
  }

  Future<void> _save() => store.saveHistory(connection!.scope, {
    'outgoing': _outgoing.where((entry) => entry['event_id'] == null).toList(),
    'pending': pending,
    'terminalTools': _tools.toJson(),
    'collecting': collecting,
    'locationEnabled': locationEnabled,
    'usageEnabled': usageEnabled,
    'screenshotsEnabled': screenshotsEnabled,
    'screenshotInterval': screenshotInterval,
    'timeline': _timeline.toJson(),
    'nativeReceipts': _unacknowledged.toList(),
    'lastActivity': lastActivity,
    'lastUpload': lastUpload,
  });

  void _armTimer() {
    _timer?.cancel();
    if (!_disposed && _foreground && connection != null) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) => sync());
    }
  }

  void foreground(bool active) {
    if (_foreground == active) return;
    _foreground = active;
    inbox.foreground = active;
    if (active) unawaited(inbox.refreshPermission());
    _armTimer();
    _observe();
    if (active && connection != null) unawaited(sync());
  }

  void page(String name) {
    if (_page == name) return;
    _page = name;
    _observe();
  }

  Future<void> send(String text) => _run(() async {
    if (connection == null || text.trim().isEmpty) return;
    final entry = <String, dynamic>{
      'id': newEventId(),
      'role': 'user',
      'text': text.trim(),
      'status': 'sending',
    };
    _outgoing.add(entry);
    await _save();
    _notify();
    await _submit(entry);
  });

  Future<void> retry(Json entry) => _run(() async {
    if (_outgoing.contains(entry) && entry['job'] == null) await _submit(entry);
  });

  Future<void> _refreshQuestions(Connection conn) async {
    try {
      final page = await api.request(conn, 'questions?status=pending&limit=20');
      final raw = (page['items'] as List? ?? const []).cast<Json>();
      questions = [for (final row in raw) PendingQuestion.fromJson(row)];
    } on ApiError catch (e) {
      if (e.status == 404) return;
      rethrow;
    }
  }

  Future<void> answerQuestion(
    String id, {
    List<String> selectedOptions = const [],
    String answerText = '',
  }) async {
    final conn = connection;
    if (conn == null) throw StateError('请先连接设备');
    try {
      await api.request(
        conn,
        'questions/${Uri.encodeComponent(id)}/answer',
        body: {'selected_options': selectedOptions, 'answer_text': answerText},
      );
      questions = questions.where((q) => q.id != id).toList();
      _notify();
      unawaited(sync());
    } on ApiError catch (e) {
      if (e.status == 409) {
        questions = questions.where((q) => q.id != id).toList();
        _notify();
        throw StateError('该提问已在其他设备处理');
      }
      if (e.status == 400) {
        throw StateError('请至少选择一个选项或填写回答内容');
      }
      rethrow;
    }
  }

  Future<void> dismissQuestion(String id) async {
    final conn = connection;
    if (conn == null) throw StateError('请先连接设备');
    try {
      await api.request(
        conn,
        'questions/${Uri.encodeComponent(id)}/dismiss',
        body: const {},
      );
      questions = questions.where((q) => q.id != id).toList();
      _notify();
      unawaited(sync());
    } on ApiError catch (e) {
      if (e.status == 409) {
        questions = questions.where((q) => q.id != id).toList();
        _notify();
        throw StateError('该提问已在其他设备处理');
      }
      rethrow;
    }
  }

  Future<void> _submit(Json entry) async {
    try {
      final result = await api.request(
        connection!,
        'messages',
        body: {'message_id': entry['id'], 'text': entry['text']},
      );
      entry['event_id'] = result['event_id'] as String;
      entry['job'] = result['job_id'] as String?;
      entry['status'] = 'queued';
      error = null;
    } catch (e) {
      entry['status'] = 'unsent';
      error = e.toString();
    }
    await _save();
  }

  Future<void> sync() async {
    if (_syncing || connection == null || _disposed) return;
    _syncing = true;
    if (_foreground) unawaited(inbox.poll());
    try {
      await _run(() async {
        final conn = connection!;
        await _refreshSignals();
        await _readSignals();
        await _configureScreenshots();
        unawaited(_uploadScreenshots());
        try {
          await _refreshChat(conn);
          await _refreshQuestions(conn);
          final inbox = await api.request(conn, 'outputs?limit=100');
          for (final row in (inbox['outputs'] as List).cast<Json>()) {
            if (row['status'] == 'pending' &&
                _serverMessages.any(
                  (m) =>
                      m['id'] == row['output_id'] && m['role'] == 'assistant',
                )) {
              await api.request(
                conn,
                'outputs/${Uri.encodeComponent(row['output_id'])}/ack',
                body: {},
              );
            }
          }
          error = null;
        } finally {
          await _flushCollection();
        }
      });
      if (connectors.platform != ConnectorPlatform.unsupported && _foreground) {
        await _run(_pollDeviceStatus);
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> setDeviceStatusEnabled(bool enabled) => _run(() async {
    if (!canEnableDeviceStatus) return;
    _tools.setEnabled(enabled);
    await _save();
    _notify();
    await _pollDeviceStatus();
  });

  Future<void> _pollDeviceStatus() async {
    final conn = connection;
    if (conn == null) return;
    await _tools.poll(
      api,
      conn,
      () async => {
        'platform': 'android',
        ...await deviceStatus.read(),
        'collection': {
          'app_activity': collecting,
          'location': locationEnabled,
          'app_usage': usageEnabled,
          'screenshots': screenshotsEnabled,
        },
      },
      connectors,
      _save,
      () => _foreground && !_disposed,
    );
  }

  Future<void> _refreshChat(Connection conn) async {
    final rows = await _history.read(api, conn);
    _serverMessages = rows;
    if (_outgoing.isEmpty) return;
    final eventIds = {for (final row in rows) row['id']};
    final accepted = {
      for (final row in rows)
        if (row['role'] == 'user' && row['device_id'] == conn.deviceId)
          row['message_id'],
    };
    var changed = false;
    for (final entry in _outgoing.toList()) {
      final eventId = entry['event_id'];
      if (eventId == null) {
        if (!accepted.contains(entry['id'])) continue;
      } else if (eventIds.contains(eventId) && entry['job'] != null) {
        // Preserve delivery feedback for our own running jobs while the
        // server event is present. A backend reset retires it immediately.
        if (!['queued', 'running'].contains(entry['status'])) continue;
        try {
          final job = Uri.encodeComponent(entry['job'] as String);
          final result = await api.request(conn, 'jobs/$job');
          final status = result['status'] as String;
          if (status != 'completed') {
            if (status != entry['status']) {
              entry['status'] = status;
              changed = true;
            }
            continue;
          }
        } on ApiError catch (e) {
          if (e.status != 404) rethrow;
        }
      }
      _outgoing.remove(entry);
      changed = true;
    }
    if (changed) await _save();
  }

  Future<void> setCollecting(bool enabled) => _run(() async {
    if (connection == null) return;
    collecting = enabled;
    lastActivity = null;
    if (!enabled) {
      pending.removeWhere(
        (event) =>
            event['path'] == 'perceptions' &&
            event['body']?['state_key'] == 'mobile.app_activity',
      );
      collectionError = null;
    }
    await _save();
    if (enabled) await _recordActivity(_activity, DateTime.now().toUtc());
  });

  Future<void> _refreshSignals() async {
    try {
      final status = await signals.configure(
        connection?.scope ?? '',
        locationEnabled,
        usageEnabled,
      );
      locationAccess = status['location'] ?? 'unsupported';
      usageAccess = status['usage'] ?? 'unsupported';
      backgroundLocation = status['backgroundLocation'] == true;
      // Reconcile with OS revocation before any upload, including a restart offline.
      final count = pending.length;
      bool changed = false;
      if (locationAccess != 'granted' && locationAccess != 'disabled') {
        pending.removeWhere((e) => e['source'] == 'location');
        if (_timeline.lastLocationLabel != null) {
          _timeline.forgetLocation();
          changed = true;
        }
      }
      if (usageAccess != 'granted') {
        pending.removeWhere((e) => e['source'] == 'usage');
      }
      if ((pending.length != count || changed) && connection != null) {
        await _save();
      }
      signalError = null;
    } catch (e) {
      locationAccess = usageAccess = 'unknown';
      backgroundLocation = false;
      signalError = '无法读取系统采集状态：$e';
    }
  }

  Future<void> setSignalEnabled(String source, bool enabled) => _run(() async {
    if (connection == null || !['usage', 'location'].contains(source)) return;
    if (source == 'location') {
      locationEnabled = enabled;
      if (!enabled) _timeline.forgetLocation();
    } else {
      usageEnabled = enabled;
      if (!enabled) _timeline.lastUsageLabel = null;
      if (!enabled && screenshots.platform == 'android' && screenshotsEnabled) {
        screenshotsEnabled = false;
        _cancelScreenshotUpload();
      }
    }
    if (!enabled) pending.removeWhere((e) => e['source'] == source);
    await _save();
    await _refreshSignals();
    if (source == 'usage') await _configureScreenshots();
    if (!enabled) return;
    final access = source == 'location' ? locationAccess : usageAccess;
    if (access == 'denied') await _requestSignal(source);
    await _readSignals();
    await _flushCollection();
  });

  void _cancelScreenshotUpload() {
    _captureRevision++;
    _cancelUpload?.complete();
    _cancelUpload = null;
    _retryAfter = null;
    _retrySeconds = 0;
  }

  Future<void> _configureScreenshots() async {
    try {
      final requiresUsage = screenshots.platform == 'android' && !usageEnabled;
      final result = await screenshots.configure(
        connection?.scope ?? '',
        screenshotsEnabled && !requiresUsage,
        screenshotInterval,
      );
      screenshotAccess = requiresUsage
          ? 'usageRequired'
          : result['access'] as String;
      pendingScreenshots = result['pending'] as int? ?? 0;
    } catch (e) {
      screenshotAccess = 'unavailable';
      screenshotError = '无法连接系统截屏服务：$e';
    }
  }

  Future<void> setScreenshots(bool enabled) async {
    if (!enabled) {
      screenshotsEnabled = false;
      _cancelScreenshotUpload();
      // Stop the native producer without waiting for an unrelated inbox request.
      unawaited(_configureScreenshots());
    }
    await _run(() async {
      if (connection == null) return;
      screenshotsEnabled = enabled;
      screenshotError = null;
      await _save();
      await _configureScreenshots();
      if (enabled && screenshotAccess == 'ready') {
        await _requestScreenshotSession();
      }
    });
  }

  Future<void> setScreenshotInterval(int seconds) => _run(() async {
    if (connection == null || !MobileScreenshots.intervals.contains(seconds)) {
      return;
    }
    screenshotInterval = seconds;
    await _save();
    await _configureScreenshots();
  });

  Future<void> startScreenshotCapture() => _run(() async {
    if (connection == null || !screenshotsEnabled) return;
    await _requestScreenshotSession();
  });

  Future<void> _requestScreenshotSession() async {
    screenshotError = null;
    try {
      await screenshots.request();
      await _configureScreenshots();
    } catch (e) {
      screenshotError = '未能开始共享屏幕：$e';
    }
  }

  // Upload pixels outside the chat/outbox writer so a slow network cannot
  // block switching off capture. Native keeps ownership until the HTTP receipt.
  Future<void> _uploadScreenshots() async {
    final conn = connection;
    if (conn == null ||
        !screenshotsEnabled ||
        pendingScreenshots == 0 ||
        _uploadingScreenshot ||
        _disposed ||
        !['active', 'ready', 'denied'].contains(screenshotAccess) ||
        (_retryAfter?.isAfter(DateTime.now()) ?? false)) {
      return;
    }
    _uploadingScreenshot = true;
    final revision = _captureRevision;
    bool valid() =>
        !_disposed &&
        revision == _captureRevision &&
        connection == conn &&
        screenshotsEnabled;
    try {
      final rows = await screenshots.read(conn.scope);
      for (final row in rows.take(4)) {
        if (!valid()) return;
        final id = row['id'] as String;
        final jpeg = await screenshots.bytes(conn.scope, id);
        if (!valid()) return;
        if (jpeg == null) continue;
        final cancel = Completer<void>();
        _cancelUpload = cancel;
        final result = await api.uploadScreenshot(
          conn,
          row,
          screenshots.platform,
          jpeg,
          cancel: cancel.future,
        );
        if (!valid()) return;
        if (result['event_id'] is! String) {
          throw const FormatException('截图回执缺少事件 ID');
        }
        await screenshots.ack(conn.scope, id);
        if (!valid()) return;
        if (pendingScreenshots > 0) pendingScreenshots--;
        screenshotError = null;
        _retrySeconds = 0;
      }
    } catch (e) {
      if (valid()) {
        screenshotError = '截图待重试：$e';
        _retrySeconds = _retrySeconds == 0
            ? 5
            : (_retrySeconds * 2).clamp(5, 120);
        _retryAfter = DateTime.now().add(Duration(seconds: _retrySeconds));
      }
    } finally {
      _cancelUpload = null;
      _uploadingScreenshot = false;
      _notify();
    }
  }

  Future<void> _requestSignal(String source) async {
    try {
      await signals.request(source);
      await _refreshSignals();
    } catch (e) {
      signalError = '无法请求系统权限：$e';
    }
  }

  Future<void> requestSignalAccess(String source) => _run(() async {
    if (connection == null ||
        (source == 'usage' ? !usageEnabled : !locationEnabled)) {
      return;
    }
    await _requestSignal(source);
    await _readSignals();
    await _flushCollection();
  });

  Future<void> openSignalSettings(String source) => _run(() async {
    try {
      await signals.settings(source);
    } catch (e) {
      signalError = '无法打开系统设置：$e';
    }
  });

  Future<void> nameCurrentLocation(String name) => _run(() async {
    if (connection == null || !canNameLocation) return;
    try {
      _timeline.nameLocation(name);
      final label = _timeline.currentPlaceUpdate();
      if (label != null) {
        _queueLocation(newEventId(), DateTime.now().toUtc(), label);
      }
      signalError = null;
      await _save();
      await _flushCollection();
    } on FormatException catch (e) {
      signalError = e.message;
    }
  });

  Future<void> removePlace(String name) => _run(() async {
    if (connection == null) return;
    _timeline.removePlace(name);
    await _save();
  });

  void _queueLocation(String id, DateTime at, String value) {
    pending.add({
      'source': 'location',
      'path': 'perceptions',
      'body': {
        'event_id': id,
        'occurred_at': at.toIso8601String(),
        'state_key': 'mobile.location',
        'value': value,
      },
    });
  }

  Future<void> _readSignals() async {
    final scope = connection?.scope;
    final location = locationEnabled && locationAccess == 'granted';
    final usage = usageEnabled && usageAccess == 'granted';
    if (scope == null || (!location && !usage)) return;
    try {
      final rows = await signals.read(scope);
      if (rows.isEmpty && _unacknowledged.isEmpty) return;
      for (final row in rows) {
        final id = row['id'] as String;
        if (!_unacknowledged.add(id)) continue;
        final at = DateTime.fromMillisecondsSinceEpoch(
          row['at'] as int,
          isUtc: true,
        );
        if (location && row['source'] == 'location') {
          final text = _timeline.location(row, at);
          if (text != null) _queueLocation(id, at, text);
        } else if (usage && row['source'] == 'usage') {
          final text = _timeline.usage(row);
          if (text != null) {
            pending.add({
              'source': 'usage',
              'path': 'slices',
              'body': {
                'event_id': id,
                'occurred_at': at.toIso8601String(),
                'text': text,
              },
            });
          }
        }
      }
      // Commit the outbox and its receipts in one write before releasing native rows.
      await _save();
      await signals.ack(scope, _unacknowledged.toList());
      _unacknowledged.clear();
      await _save();
    } catch (e) {
      signalError = '采集记录同步失败：$e';
    }
  }

  String get _activity => _foreground ? '前台 · $_page' : '后台';
  void _observe() {
    if (!collecting || connection == null) return;
    final scope = connection!.scope;
    final activity = _activity;
    final observedAt = DateTime.now().toUtc();
    unawaited(
      _run(() async {
        if (collecting && connection?.scope == scope) {
          await _recordActivity(activity, observedAt);
        }
      }),
    );
  }

  Future<void> _recordActivity(String activity, DateTime observedAt) async {
    if (lastActivity == activity) return;
    lastActivity = activity;
    pending.add({
      'path': 'perceptions',
      'body': {
        'state_key': 'mobile.app_activity',
        'value': activity,
        'event_id': newEventId(),
        'occurred_at': observedAt.toIso8601String(),
      },
    });
    await _save();
    _notify();
    await _flushCollection();
  }

  Future<void> _flushCollection() async {
    if (pending.any((item) => item.containsKey('source'))) {
      await _refreshSignals();
    }
    for (final item in pending.toList()) {
      if (item['source'] == 'usage' &&
          (!usageEnabled || usageAccess != 'granted')) {
        continue;
      }
      if (item['source'] == 'location' &&
          (!locationEnabled || locationAccess != 'granted')) {
        continue;
      }
      try {
        await api.request(connection!, item['path'], body: item['body']);
        pending.remove(item);
        lastUpload = DateTime.now().toLocal().toIso8601String();
        await _save();
        collectionError = null;
      } catch (e) {
        collectionError = e.toString();
        break;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    screenshots.onChange(null);
    _cancelScreenshotUpload();
    _timer?.cancel();
    themeMode.dispose();
    inbox.dispose();
    super.dispose();
  }
}
