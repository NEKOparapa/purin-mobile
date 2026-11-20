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
      created = DateTime.parse(row['created_at'] as String),
      read = row['read_at'] != null,
      expired = row['expired'] == true,
      files = (row['attachments'] as List)
          .cast<Json>()
          .map(NoticeFile.fromJson)
          .toList();
  final String id, title, body;
  final DateTime created;
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
  int unread = 0;
  String? cursor, error;
  bool available = true, allowed = false, loading = false;
  bool foreground = true;
  void Function(DeviceNotice notice)? onArrival;
  void Function(String scope, String id)? onOpen;
  int _generation = 0;
  bool _disposed = false, _polling = false;
  int _listGeneration = 0;
  DateTime? _probeAt;

  bool get supported => Platform.isAndroid;

  void connect(Connection conn) {
    connection = conn;
    _generation++;
    _listGeneration++;
    notices = [];
    unread = 0;
    cursor = null;
    error = null;
    available = true;
    loading = false;
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
    if (!supported || connection == null) return;
    final gen = _generation;
    try {
      final enabled = await noticeChannel.invokeMethod<bool>(
        request ? 'enable' : 'status',
      );
      if (!_current(gen)) return;
      allowed = enabled == true;
      notifyListeners();
      await _takeOpen(gen);
    } on PlatformException catch (e) {
      if (_current(gen)) {
        error = e.message;
        notifyListeners();
      }
    }
  }

  Future<void> _takeOpen(int gen) async {
    final tap = await noticeChannel.invokeMapMethod<String, dynamic>(
      'takeOpen',
    );
    if (_current(gen) && tap != null && tap['scope'] == connection!.scope) {
      onOpen?.call(tap['scope'], tap['id']);
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
      await receiveNotices(api, conn, (notice) async {
        final fresh = await noticeChannel.invokeMethod<bool>(
          'foregroundArrival',
          {'scope': conn.scope, 'id': notice.id},
        );
        if (_current(gen) && fresh == true) onArrival?.call(notice);
        return fresh != null;
      }, active: () => foreground && _current(gen));
      if (!_current(gen)) return;
      await refresh();
    } on ApiError catch (e) {
      if (!_current(gen)) return;
      if (e.status == 404) {
        available = false;
        notices = [];
        unread = 0;
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

  Future<void> refresh({bool more = false}) async {
    final conn = connection;
    if (conn == null || _disposed || loading || (more && cursor == null)) {
      return;
    }
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
      unread = notices.where((n) => !n.read && !n.expired).length;
    } on ApiError catch (e) {
      if (!_current(gen)) return;
      if (e.status == 404) {
        available = false;
        notices = [];
        unread = 0;
        cursor = null;
        error = null;
      } else {
        error = e.toString();
      }
    } catch (e) {
      if (_current(gen)) error = e.toString();
    } finally {
      if (_current(gen) && request == _listGeneration) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> markRead(DeviceNotice notice) async {
    final conn = connection;
    if (conn == null || notice.read) return;
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
    await refresh();
  }

  Future<bool> save(DeviceNotice notice, NoticeFile file) async {
    final conn = connection!;
    return await noticeChannel.invokeMethod<bool>('saveAttachment', {
          'url':
              '${conn.url}/v1/notifications/${_segment(notice.id)}/files/${_segment(file.id)}',
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
