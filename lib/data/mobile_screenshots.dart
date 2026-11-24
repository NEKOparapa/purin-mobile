import 'dart:io';
import 'package:flutter/services.dart';
import 'agent_api.dart';

class MobileScreenshots {
  static const _channel = MethodChannel('dev.wintermute/screenshots');
  static const intervals = [60, 300, 900];

  String get platform => Platform.operatingSystem;
  bool get supported => platform == 'android' || platform == 'ios';

  void onChange(void Function()? callback) {
    if (!supported) return;
    _channel.setMethodCallHandler(
      callback == null
          ? null
          : (call) async {
              if (call.method == 'changed') callback();
            },
    );
  }

  Future<Json> configure(String scope, bool enabled, int interval) async {
    if (!supported) return {'access': 'unsupported', 'pending': 0};
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'configure',
      {'scope': scope, 'enabled': enabled, 'intervalSeconds': interval},
    );
    return result ?? {'access': 'unsupported', 'pending': 0};
  }

  Future<void> request() => _channel.invokeMethod<void>('request');

  Future<List<Json>> read(String scope) async {
    final rows = await _channel.invokeListMethod<dynamic>('read', {
      'scope': scope,
    });
    return [for (final row in rows ?? []) Json.from(row as Map)];
  }

  Future<Uint8List?> bytes(String scope, String id) =>
      _channel.invokeMethod<Uint8List>('bytes', {'scope': scope, 'id': id});

  Future<Json?> visitFrame(String scope, String id) =>
      _channel.invokeMapMethod<String, dynamic>('visitFrame', {
        'scope': scope,
        'id': id,
      });

  Future<void> ack(String scope, String id) =>
      _channel.invokeMethod<void>('ack', {
        'scope': scope,
        'ids': [id],
      });
}
