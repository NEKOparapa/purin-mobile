import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../l10n/app_language.dart';
import 'mobile_session.dart';
import 'schedule.dart';

String islandTime(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

/// Publishes the folded session to Android Live Updates or iOS ActivityKit.
class IslandActivity {
  IslandActivity(this.session, this._token);
  final MobileSession session;
  static const _channel = MethodChannel('dev.purin/island');
  static IslandActivity? _owner;
  static String? _androidFold;
  static bool get _android => defaultTargetPlatform == TargetPlatform.android;
  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;
  final String _token;
  String _status = '待机';
  String? _message, _job, _finishedInBackground;
  var _lines = <String>[];
  int? _dayEnd;
  Timer? _poll;
  bool _checking = false, _background = false, _attached = false;
  bool get tracking => _message != null && _message != _finishedInBackground;
  bool get watchesToday =>
      _attached && (_android ? _androidFold == _token : tracking);

  static Future<String?> foldAndroid(
    String owner,
    bool connected,
    AppLanguage language,
  ) async {
    if (!_android) return null;
    _androidFold = owner;
    String? result;
    try {
      result = await _channel.invokeMethod<String>('fold', {
        'owner': owner,
        'status': connected ? '待机' : '未连接',
        'language': language.locale.toLanguageTag(),
      });
      return result;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return 'unavailable';
    } finally {
      if (result != 'promoted' && _androidFold == owner) _androidFold = null;
    }
  }

  static void listenForOpen(VoidCallback? open) {
    if (!_ios && !_android) return;
    if (open == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openChat') open();
      if (call.method == 'stopPolling') _owner?._stopPolling();
    });
  }

  void attach() {
    if (!_ios && !_android) return;
    _owner = this;
    _attached = true;
  }

  void sync(String status) {
    if (!_attached || (_android && !watchesToday)) return;
    if (_android &&
        _status != status &&
        !(_background &&
            _message != null &&
            _finishedInBackground == _message)) {
      _status = status;
      _publish('status');
    }
    final pending = session.pendingIslandReply;
    if (pending != null) {
      _job = pending.job;
      if (_message != pending.id) {
        _message = pending.id;
        _finishedInBackground = null;
        _publish('working');
      }
    } else if (_message != null) {
      final last = session.messages.lastOrNull;
      if (tracking) _publish(last?['role'] == 'assistant' ? 'reply' : 'ended');
      _message = _job = _finishedInBackground = null;
      _stopPolling();
    }
  }

  void today(List<ScheduleEntry> entries, DateTime day) {
    if (!watchesToday) return;
    final lines = <String>[];
    for (final notices in [true, false]) {
      final items = entries.where((e) => (e.notification != null) == notices);
      final e =
          items.where((e) => !e.at.isBefore(DateTime.now())).firstOrNull ??
          items.lastOrNull;
      if (e != null) {
        final title = (e.notification?.title ?? e.title).characters.take(35);
        lines.add(
          '${notices ? session.language.value.text('通知') : session.language.value.text('安排')}  ${islandTime(e.at)}  $title',
        );
      }
    }
    if (lines.isEmpty) lines.add(session.language.value.text('今天没有通知或安排'));
    _dayEnd = DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch;
    _lines = lines;
    _publish('status');
  }

  void todayUnavailable() {
    if (!_android || !watchesToday) return;
    _lines = [session.language.value.text('今日内容暂时无法读取')];
    _publish('status');
  }

  void _publish(String phase) {
    if (phase == 'reply') _status = '收到新回复';
    if (phase == 'ended' && _status == '正在回复') _status = '处理已结束';
    unawaited(
      _send('set', {
        'owner': _token,
        'phase': phase == 'status' ? 'working' : phase,
        'status': _status,
        'language': session.language.value.locale.toLanguageTag(),
        'lines': _lines,
        'dayEnd': _dayEnd,
      }),
    );
  }

  /// Android can dismiss a session while Flutter is in the background.
  Future<bool> stillOnAndroid() async {
    if (!_android || !watchesToday) return false;
    try {
      if (await _channel.invokeMethod<bool>('active', _token) == true) {
        return true;
      }
    } on PlatformException {
      // The notification service is temporarily unavailable.
    } on MissingPluginException {
      // The host does not support live updates.
    }
    if (_androidFold == _token) _androidFold = null;
    _stopPolling();
    return false;
  }

  static Future<void> _send(String method, Object args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // The in-app capsule also works without ActivityKit.
    } on PlatformException {
      // iOS can disable or decline a Live Activity.
    }
  }

  void lifecycle(AppLifecycleState state) {
    if (!_attached || (_android && !watchesToday)) return;
    if (state == AppLifecycleState.resumed) {
      _background = false;
      _stopPolling();
      if (tracking) _publish('working');
    }
    if (state != AppLifecycleState.paused || !tracking || _job == null) return;
    _background = true;
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _checkJob());
    _checkJob();
  }

  Future<void> _checkJob() async {
    final conn = session.connection, job = _job;
    if (_checking || conn == null || job == null || !_background || !tracking) {
      return;
    }
    _checking = true;
    try {
      final result = await session.api.request(
        conn,
        'jobs/${Uri.encodeComponent(job)}',
      );
      if (!_attached ||
          !_background ||
          _poll == null ||
          _job != job ||
          conn != session.connection) {
        return;
      }
      final status = result['status'];
      if (status == 'queued' || status == 'running') return;
      _finishedInBackground = _message;
      _publish(
        status == 'completed' &&
                (result['outputs'] as List?)?.isNotEmpty == true
            ? 'reply'
            : 'ended',
      );
      _stopPolling();
    } on Exception {
      // A brief background window may expire before the server responds.
    } finally {
      _checking = false;
    }
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  void dispose() {
    if (!_attached) return;
    _attached = false;
    _stopPolling();
    if (_androidFold == _token) _androidFold = null;
    if (_owner == this) {
      _owner = null;
    }
    unawaited(_send('clear', _token));
  }
}
