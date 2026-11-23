import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'agent_api.dart';

class NoticeFile {
  NoticeFile.fromJson(Json row)
    : id = row['id'] as String,
      name = row['name'] as String,
      size = row['size_bytes'] as int,
      type = row['content_type'] as String;
  final String id, name, type;
  final int size;
}

class DeviceNotice {
  DeviceNotice.fromJson(Json row)
    : id = row['id'] as String,
      title = row['title'] as String,
      body = row['body'] as String,
      notifyAt = DateTime.parse(
        (row['notify_at'] ?? row['created_at']) as String,
      ).toLocal(),
      targetNames =
          ((row['target_names'] ?? row['targets'] ?? const []) as List)
              .cast<String>(),
      status = row['status'] as String? ?? 'sent',
      inInbox = row['in_inbox'] as bool? ?? true,
      read = row['read_at'] != null,
      expired = row['expired'] == true,
      files = (row['attachments'] as List)
          .cast<Json>()
          .map(NoticeFile.fromJson)
          .toList();
  final String id, title, body;
  final DateTime notifyAt;
  final List<String> targetNames;
  final String status;
  final bool inInbox;
  String get statusLabel => expired
      ? '已过期'
      : switch (status) {
          'scheduled' => '待发送',
          'partial' => '部分发送',
          'failed' => '发送失败',
          _ => '已发送',
        };
  bool read;
  final bool expired;
  final List<NoticeFile> files;
}

const noticeChannel = MethodChannel('dev.wintermute/user_notifications');

String _segment(String value) {
  if (value.isEmpty ||
      value == '.' ||
      value == '..' ||
      value.contains(RegExp(r'[/\\\x00-\x1f]'))) {
    throw const FormatException('无效的通知或附件标识');
  }
  return Uri.encodeComponent(value);
}

typedef PresentNotice = Future<bool> Function(DeviceNotice notice);

/// A receipt records arrival at this device; opening a notice uses a separate endpoint.
Future<void> receiveNotices(
  AgentApi api,
  Connection conn,
  PresentNotice present, {
  required bool Function() active,
}) async {
  String? cursor;
  final seen = <String>{};
  do {
    final page = await api.request(
      conn,
      'notifications?pending=1&limit=20${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}',
    );
    for (final row in (page['items'] as List).cast<Json>()) {
      if (!active()) return;
      final notice = DeviceNotice.fromJson(row);
      if (!notice.expired && !notice.read && !await present(notice)) return;
      if (!active()) return;
      await api.request(
        conn,
        'notifications/${_segment(notice.id)}/received',
        body: {},
      );
    }
    cursor = page['next_cursor'] as String?;
    if (cursor != null && !seen.add(cursor)) {
      throw const FormatException('重复的通知分页位置');
    }
  } while (cursor != null && active());
}

class DeviceInbox extends ChangeNotifier {
  DeviceInbox(this.api);
  final AgentApi api;
  Connection? connection;
  List<DeviceNotice> notices = [];
  bool hasUnread = false;
  String? cursor, error;
  bool available = true, loading = false;
  bool? allowed;
  bool foreground = true;
  void Function(String scope, String id)? _onOpen;
  set onOpen(void Function(String scope, String id)? handler) {
    _onOpen = handler;
    if (handler != null && supported && connection != null) {
      unawaited(_takeOpen(_generation));
    }
  }

  int _generation = 0;
  int _permissionRevision = 0;
  bool _disposed = false, _polling = false;
  int _listGeneration = 0;
  Future<void>? _listing;
  bool _listingMore = false;
  DateTime? _probeAt;

  bool get supported => Platform.isAndroid || Platform.isIOS;

  void connect(Connection conn) {
    connection = conn;
    _generation++;
    _listGeneration++;
    notices = [];
    hasUnread = false;
    cursor = null;
    error = null;
    available = true;
    loading = false;
    _listing = null;
    _polling = false;
    _probeAt = null;
    if (!supported) return;
    noticeChannel.setMethodCallHandler((call) async {
      if (call.method == 'openNotice') {
        await _takeOpen(_generation);
      }
    });
    unawaited(refreshPermission());
    notifyListeners();
  }

  bool _current(int gen) => !_disposed && gen == _generation;

  Future<void> refreshPermission({bool request = false}) async {
    if (!supported) return;
    final gen = _generation;
    final revision = ++_permissionRevision;
    try {
      final enabled = await noticeChannel.invokeMethod<bool>(
        request ? 'enable' : 'status',
      );
      if (!_current(gen) || revision != _permissionRevision) return;
      allowed = enabled == true;
      notifyListeners();
      if (connection != null) await _takeOpen(gen);
    } on PlatformException catch (e) {
      if (_current(gen) && revision == _permissionRevision) {
        error = e.message;
        notifyListeners();
      }
    }
  }

  Future<void> _takeOpen(int gen) async {
    if (_onOpen == null || !_current(gen)) return;
    final tap = await noticeChannel.invokeMapMethod<String, dynamic>(
      'takeOpen',
    );
    if (_current(gen) && tap != null && tap['scope'] == connection?.scope) {
      _onOpen?.call(tap['scope'], tap['id']);
    }
  }

  Future<void> poll() async {
    final conn = connection;
    if (!supported ||
        !foreground ||
        _disposed ||
        conn == null ||
        _polling ||
        (_probeAt?.isAfter(DateTime.now()) ?? false)) {
      return;
    }
    _polling = true;
    final gen = _generation;
    try {
      await refresh();
      if (!_current(gen) || !foreground) return;
      if (!available) {
        _probeAt = DateTime.now().add(const Duration(minutes: 1));
        return;
      }
      await receiveNotices(api, conn, (notice) async {
        final presented = await noticeChannel
            .invokeMethod<bool>('foregroundArrival', {
              'scope': conn.scope,
              'id': notice.id,
              'title': notice.title,
              'body': notice.body,
            });
        return presented != null;
      }, active: () => foreground && _current(gen));
    } on ApiError catch (e) {
      if (!_current(gen)) return;
      if (e.status == 404) {
        available = false;
        notices = [];
        hasUnread = false;
        cursor = null;
        error = null;
        _probeAt = DateTime.now().add(const Duration(minutes: 1));
      } else {
        error = e.toString();
      }
      notifyListeners();
    } catch (e) {
      if (_current(gen)) {
        error = e.toString();
        notifyListeners();
      }
    } finally {
      if (_current(gen)) _polling = false;
    }
  }

  Future<void> refresh({bool more = false}) {
    if (_listing case final pending?) {
      if (_listingMore == more) return pending;
      final gen = _generation;
      return pending.then((_) async {
        if (_current(gen)) await refresh(more: more);
      });
    }
    final conn = connection;
    if (conn == null || _disposed || (more && cursor == null)) {
      return Future.value();
    }
    _listingMore = more;
    return _listing = _readPage(conn, more);
  }

  Future<void> _readPage(Connection conn, bool more) async {
    final gen = _generation, request = ++_listGeneration;
    loading = true;
    try {
      final page = await api.request(
        conn,
        'notifications?limit=30${more ? '&cursor=${Uri.encodeQueryComponent(cursor!)}' : ''}',
      );
      if (!_current(gen) || request != _listGeneration) return;
      final rows = (page['items'] as List)
          .cast<Json>()
          .map(DeviceNotice.fromJson)
          .toList();
      var tail = page['next_cursor'] as String?;
      if (more) {
        final ids = notices.map((n) => n.id).toSet();
        notices = [...notices, ...rows.where((n) => ids.add(n.id))];
      } else {
        final overlap = (rows.isNotEmpty && tail != null)
            ? notices.indexWhere((n) => n.id == rows.last.id)
            : -1;
        if (overlap >= 0) {
          rows.addAll(notices.skip(overlap + 1));
          tail = cursor;
        }
        notices = rows;
      }
      cursor = tail;
      available = true;
      error = null;
      var found = notices.any((n) => !n.read && !n.expired);
      if (!found && tail != null) {
        final older = await api.request(conn, 'notifications?unread=1&limit=1');
        if (!_current(gen) || request != _listGeneration) return;
        found = (older['items'] as List).isNotEmpty;
      }
      hasUnread = found;
    } on ApiError catch (e) {
      if (!_current(gen)) return;
      if (e.status == 404) {
        available = false;
        notices = [];
        hasUnread = false;
        cursor = null;
        error = null;
      } else {
        error = e.toString();
      }
    } catch (e) {
      if (_current(gen)) error = e.toString();
    } finally {
      if (_current(gen) && request == _listGeneration) {
        _listing = null;
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<DeviceNotice?> findNotice(String id) async {
    final gen = _generation;
    await refresh();
    final seen = <String>{};
    while (_current(gen)) {
      final notice = notices.where((item) => item.id == id).firstOrNull;
      if (notice != null) return notice;
      final next = cursor;
      if (next == null || error != null || !seen.add(next)) break;
      await refresh(more: true);
    }
    return null;
  }

  Future<void> markRead(DeviceNotice notice) async {
    final conn = connection;
    if (conn == null || !notice.inInbox || notice.read) return;
    await api.request(
      conn,
      'notifications/${_segment(notice.id)}/read',
      body: {},
    );
    if (connection != conn) return;
    notice.read = true;
    for (final item in notices) {
      if (item.id == notice.id) item.read = true;
    }
    await noticeChannel.invokeMethod<void>('dismiss', {
      'scope': conn.scope,
      'id': notice.id,
    });
    _listGeneration++;
    loading = false;
    _listing = null;
    await refresh();
  }

  Future<bool> save(DeviceNotice notice, NoticeFile file) async {
    final conn = connection!;
    final url =
        '${conn.url}/v1/notifications/${_segment(notice.id)}/files/${_segment(file.id)}';
    if (Platform.isIOS) {
      if (file.size < 0 || file.size > 8 * 1024 * 1024) {
        throw const FormatException('附件大小超出限制');
      }
      final dir = await Directory.systemTemp.createTemp('wintermute-notice-');
      final name = file.name
          .split(RegExp(r'[/\\]'))
          .last
          .replaceAll(RegExp(r'[\x00-\x1f:]'), '')
          .trim();
      final output = File.fromUri(
        dir.uri.resolveUri(
          Uri(
            pathSegments: [
              name.isEmpty || name == '.' || name == '..' ? '附件' : name,
            ],
          ),
        ),
      );
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.followRedirects = false;
        conn.identify(request.headers);
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${conn.token}',
        );
        final response = await request.close().timeout(
          const Duration(seconds: 20),
        );
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('附件下载失败（HTTP ${response.statusCode}）');
        }
        var total = 0;
        final sink = output.openWrite();
        try {
          await for (final bytes in response.timeout(
            const Duration(seconds: 20),
          )) {
            total += bytes.length;
            if (total > file.size) throw const FormatException('附件大小不匹配');
            sink.add(bytes);
          }
        } finally {
          await sink.close();
        }
        if (total != file.size) throw const FormatException('附件下载不完整');
        if (connection != conn || _disposed) return false;
        return await noticeChannel.invokeMethod<bool>(
              'exportAttachment',
              output.path,
            ) ??
            false;
      } finally {
        client.close(force: true);
        await dir.delete(recursive: true);
      }
    }
    return await noticeChannel.invokeMethod<bool>('saveAttachment', {
          'url': url,
          'deviceId': conn.deviceId,
          'installation': conn.installation,
          'token': conn.token,
          'name': file.name,
          'size': file.size,
          'type': file.type,
        }) ??
        false;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    if (supported) noticeChannel.setMethodCallHandler(null);
    super.dispose();
  }
}
