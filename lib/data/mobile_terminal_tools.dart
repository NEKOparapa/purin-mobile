import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'agent_api.dart';
import 'mobile_connectors.dart';

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
class MobileTerminalTools {
  MobileTerminalTools(Json saved, ConnectorPlatform platform)
    : this._(
        (saved['platform'] ?? 'android') == platform.name ? saved : {},
        platform,
      );

  MobileTerminalTools._(Json saved, this.platform)
    : enabled =
          platform == ConnectorPlatform.android && saved['enabled'] == true,
      selected = {
        for (final item in platform.catalog)
          if ((saved['connectors'] as List? ?? []).contains(item.id) ||
              (platform == ConnectorPlatform.android &&
                  saved['platform'] == null &&
                  (saved['connectors'] as List? ?? []).contains(item.key)))
            item,
      },
      _withdraw = saved['withdraw'] == true,
      _pending = saved['pending'] as Json?;

  final ConnectorPlatform platform;

  bool enabled;
  final Set<MobileConnector> selected;
  final Map<MobileConnector, bool> _registered = {};
  Map<String, bool> access = {};
  bool _withdraw;
  Json? _pending;
  String? error;
  Json toJson() => {
    'platform': platform.name,
    'enabled': enabled,
    'connectors': selected.map((item) => item.id).toList(),
    'withdraw': _withdraw,
    'pending': _pending,
  };

  void setEnabled(bool value) {
    enabled = value;
    _withdraw = !value;
    error = null;
  }

  void disableConnector(MobileConnector item) {
    selected.remove(item);
    _withdraw = true;
  }

  Future<void> poll(
    AgentApi api,
    Connection connection,
    Future<Json> Function() read,
    MobileConnectors connectors,
    Future<void> Function() persist,
    bool Function() active,
  ) async {
    if (!active() ||
        platform == ConnectorPlatform.unsupported ||
        platform != connectors.platform ||
        !secureToolConnection(connection)) {
      return;
    }
    try {
      await _deliver(api, connection, persist);
      if (selected.isNotEmpty) {
        access = await connectors.access(connection.scope);
      }
      String? catalogError;
      for (final item in platform.catalog) {
        if (!active()) return;
        final on = selected.contains(item) && access[item.key] == true;
        if (_registered[item] == on) continue;
        try {
          await api.request(
            connection,
            'connectors/device-sync',
            body: {
              'id': item.id,
              'name': item.title,
              'enabled': on,
              'config': {'tools': item.tools},
            },
          );
          _registered[item] = on;
        } catch (e) {
          catalogError = e.toString();
          break;
        }
      }
      final available = {
        if (enabled && platform == ConnectorPlatform.android) 'device_status',
        for (final item in platform.catalog)
          if (selected.contains(item) && access[item.key] == true)
            ...item.tools,
      };
      if (selected.isEmpty && !enabled && !_withdraw) {
        error = catalogError;
        return;
      }
      if (!active()) return;
      final response = await api.request(
        connection,
        'terminal-tools/claim',
        body: {'tools': available.toList()},
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
          throw const FormatException('无效的设备调用凭据');
        }
        final body = <String, dynamic>{
          'claim_token': call['claim_token'],
          'status': 'failed',
          'exit_code': null,
          'stdout': '',
          'stderr': '设备调用中断，执行结果未知',
          'truncated': false,
        };
        // Save a terminal receipt before invoking the platform. A restart resends
        // the saved result and never executes an already claimed call a second time.
        _pending = {'id': call['id'], 'body': body};
        await persist();
        final timeout = call['timeout_seconds'];
        final tool = call['tool'];
        final args = call['arguments'];
        if (!available.contains(tool) || !active()) {
          body['stderr'] = '连接器未启用、未授权或设备已离开前台';
        } else if (tool is! String ||
            args is! Json ||
            (tool == 'device_status' && args.isNotEmpty) ||
            timeout is! int ||
            timeout < 1 ||
            timeout > 120) {
          body['stderr'] = '设备调用参数无效';
        } else {
          try {
            final operation = tool == 'device_status'
                ? read()
                : connectors.execute(connection.scope, tool, args, timeout);
            final data = await operation.timeout(Duration(seconds: timeout));
            var output = jsonEncode(data);
            final rawRows = data['items'];
            final rows = rawRows is List ? rawRows.toList() : null;
            if (rows != null) data['items'] = rows;
            while (utf8.encode(output).length > 8192 &&
                rows != null &&
                rows.isNotEmpty) {
              rows.removeLast();
              data['truncated'] = true;
              output = jsonEncode(data);
            }
            if (utf8.encode(output).length > 8192) {
              throw const FormatException('设备结果过长');
            }
            body.addAll({
              'status': 'succeeded',
              'exit_code': 0,
              'stdout': output,
              'truncated': data['truncated'] == true,
              'stderr': '',
            });
          } on TimeoutException {
            body.addAll({'status': 'timed_out', 'stderr': '设备调用超时'});
          } on PlatformException catch (e) {
            body['stderr'] = String.fromCharCodes(
              (e.message ?? '系统拒绝了此操作').runes.take(160),
            );
          } catch (_) {
            body['stderr'] = '无法完成设备调用';
          }
        }
        await persist();
        await _deliver(api, connection, persist);
      }
      error = catalogError;
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
