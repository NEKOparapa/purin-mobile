import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'agent_api.dart';

class AndroidDeviceStatus {
  bool get supported => Platform.isAndroid;

  Future<Json> read() async {
    const channel = MethodChannel('dev.wintermute/mobile_signals');
    final status = await channel.invokeMapMethod<String, dynamic>(
      'deviceStatus',
    );
    if (status == null) throw StateError('无法读取设备状态');
    return status;
  }
}

bool secureToolConnection(Connection connection) {
  final uri = Uri.parse(connection.url);
  return uri.scheme == 'https' ||
      uri.host == 'localhost' ||
      InternetAddress.tryParse(uri.host)?.isLoopback == true;
}

// The session's ordered writer serializes polling, setting changes and persistence.
class AndroidTerminalTools {
  AndroidTerminalTools(Json saved)
    : enabled = saved['enabled'] == true,
      _withdraw = saved['withdraw'] == true,
      _pending = saved['pending'] as Json?;

  bool enabled;
  bool _withdraw;
  Json? _pending;
  String? error;
  Json toJson() => {
    'enabled': enabled,
    'withdraw': _withdraw,
    'pending': _pending,
  };

  void setEnabled(bool value) {
    enabled = value;
    _withdraw = !value;
    error = null;
  }

  Future<void> poll(
    AgentApi api,
    Connection connection,
    Future<Json> Function() read,
    Future<void> Function() persist,
    bool Function() active,
  ) async {
    if (!active() ||
        !secureToolConnection(connection) ||
        (!enabled && !_withdraw && _pending == null)) {
      return;
    }
    try {
      await _deliver(api, connection, persist);
      if (!active()) return;
      final response = await api.request(
        connection,
        'terminal-tools/claim',
        body: {
          'tools': enabled ? ['device_status'] : <String>[],
        },
      );
      final call = response['call'];
      if (call == null) {
        if (_withdraw) {
          _withdraw = false;
          await persist();
        }
      } else {
        if (call is! Json ||
            call['id'] is! String ||
            call['claim_token'] is! String ||
            (call['claim_token'] as String).isEmpty ||
            !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(call['id'] as String)) {
          throw const FormatException('无效的终端调用凭据');
        }
        final body = <String, dynamic>{
          'claim_token': call['claim_token'],
          'status': 'failed',
          'exit_code': null,
          'stdout': '',
          'stderr': '设备状态查询被中断',
          'truncated': false,
        };
        // Save a terminal receipt before invoking the platform. A restart resends
        // the saved result and never executes an already claimed call a second time.
        _pending = {'id': call['id'], 'body': body};
        await persist();
        final timeout = call['timeout_seconds'];
        if (!enabled || !active()) {
          body['stderr'] = '设备状态查询已暂停';
        } else if (call['tool'] != 'device_status' ||
            call['arguments'] is! Map ||
            (call['arguments'] as Map).isNotEmpty ||
            timeout is! int ||
            timeout < 1 ||
            timeout > 120) {
          body['stderr'] = '仅支持无参数的 device_status';
        } else {
          try {
            final status = await read().timeout(Duration(seconds: timeout));
            body.addAll({
              'status': 'succeeded',
              'exit_code': 0,
              'stdout': jsonEncode(status),
              'stderr': '',
            });
          } on TimeoutException {
            body.addAll({'status': 'timed_out', 'stderr': '设备状态查询超时'});
          } catch (_) {
            body['stderr'] = '无法读取设备状态';
          }
        }
        await persist();
        await _deliver(api, connection, persist);
      }
      error = null;
    } catch (e) {
      error = e.toString();
    }
  }

  Future<void> _deliver(
    AgentApi api,
    Connection connection,
    Future<void> Function() persist,
  ) async {
    final item = _pending;
    if (item == null) return;
    try {
      await api.request(
        connection,
        'terminal-tools/${item['id']}/result',
        body: item['body'] as Json,
      );
    } on ApiError catch (e) {
      if (![404, 409, 410].contains(e.status)) rethrow;
    }
    _pending = null;
    await persist();
  }
}
