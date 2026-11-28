import 'dart:io';
import 'package:flutter/services.dart';
import 'agent_api.dart';

class MobileSignals {
  static const _channel = MethodChannel('dev.purin/mobile_signals');
  void onLocationReady(Future<void> Function()? handler) {
    if (!Platform.isIOS) return;
    _channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              if (call.method == 'locationReady') await handler();
            },
    );
  }

  Future<String> pairingName() async {
    try {
      final value = await _channel.invokeMethod<String>('deviceName');
      final name = value
          ?.replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), '')
          .trim();
      if (name != null && name.isNotEmpty) {
        return String.fromCharCodes(name.runes.take(80));
      }
    } on PlatformException {
      return Connection.defaultDeviceName;
    } on MissingPluginException {
      return Connection.defaultDeviceName;
    }
    return Connection.defaultDeviceName;
  }

  static const unavailable = {
    'location': 'unsupported',
    'usage': 'unsupported',
    'backgroundLocation': false,
  };

  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  Future<Json> configure(
    String scope,
    bool location,
    bool usage, {
    bool network = false,
  }) async {
    if (!_mobile) return unavailable;
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'configure',
      {
        'scope': scope,
        'location': location,
        'usage': usage,
        'network': location && network,
      },
    );
    return result ?? unavailable;
  }

  Future<void> request(String source) =>
      _channel.invokeMethod<void>('request', {'source': source});

  Future<void> settings(String source) =>
      _channel.invokeMethod<void>('settings', {'source': source});

  Future<List<Json>> read(String scope) async {
    final result = await _channel.invokeListMethod<dynamic>('read', {
      'scope': scope,
    });
    return [for (final item in result ?? []) Json.from(item as Map)];
  }

  Future<void> ack(String scope, List<String> ids) =>
      _channel.invokeMethod<void>('ack', {'scope': scope, 'ids': ids});
}

class LocationFix {
  LocationFix(
    this.latitude,
    this.longitude,
    this.accuracy,
    this.kind,
    this.wifi,
  );
  final double latitude, longitude, accuracy;
  final String kind;
  final Json? wifi;

  static LocationFix? fromRecord(Json record) {
    final lat = record['lat'],
        lon = record['lon'],
        accuracy = record['accuracy'];
    final kind = record['kind'] ?? 'fix';
    if (lat is! num ||
        lon is! num ||
        accuracy is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        !accuracy.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180 ||
        accuracy < 0 ||
        !const {'fix', 'arrival', 'departure'}.contains(kind)) {
      return null;
    }
    return LocationFix(
      lat.toDouble(),
      lon.toDouble(),
      accuracy.toDouble(),
      kind as String,
      ifWifi(record),
    );
  }

  static Json? ifWifi(Json row) {
    final state = row['wifiState'];
    if (!const {'connected', 'disconnected', 'unknown'}.contains(state)) {
      return null;
    }
    return {
      'state': state,
      if (state == 'connected' && row['wifiSsid'] is String)
        'ssid': row['wifiSsid'],
    };
  }

  Json perception(String id, DateTime at) => {
    'event_id': id,
    'occurred_at': at.toUtc().toIso8601String(),
    'state_key': 'mobile.location',
    'value': value,
  };

  Json get value => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy_m': accuracy,
    if (wifi != null) 'wifi': wifi,
    'coordinate_system': 'wgs84',
    'kind': kind,
  };
}

class AppUsage {
  AppUsage(
    this.id,
    this.app,
    this.start,
    this.end,
    this.seconds, {
    this.isHomeApp,
    this.deviceName,
  });

  static const path = 'perceptions';
  static const stateKey = 'mobile.app_usage';
  final String id, app;
  final DateTime start, end;
  final int seconds;
  final bool? isHomeApp;
  final String? deviceName;

  static AppUsage? fromRecord(Json record) {
    final id = record['id'], start = record['start'], end = record['end'];
    if (id is! String || id.isEmpty) return null;
    if (start is! int || end is! int || end <= start) return null;
    final label = (record['label'] as String?)?.trim();
    final app = label == null || label.isEmpty ? record['package'] : label;
    if (app is! String || app.isEmpty) return null;
    return AppUsage(
      id,
      app,
      DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
      DateTime.fromMillisecondsSinceEpoch(end, isUtc: true),
      ((end - start) / 1000).round(),
      isHomeApp: record['isHomeApp'] as bool?,
      deviceName: record['deviceName'] as String?,
    );
  }

  String get description {
    String utc(DateTime time) =>
        time.toIso8601String().replaceFirst('T', ' ').substring(0, 19);
    return '手机前台使用「$app」，${utc(start)} 至 ${utc(end)}（UTC），约 $seconds 秒。';
  }

  Json get perception => {
    'event_id': 'app-usage:$id',
    'occurred_at': end.toIso8601String(),
    'state_key': stateKey,
    'value': {
      'activity_id': id,
      'foreground_app': app,
      'device_platform': 'android',
      if (deviceName != null) 'device_name': deviceName,
      if (isHomeApp != null) 'is_home_app': isHomeApp,
      'started_at': start.toIso8601String(),
      'ended_at': end.toIso8601String(),
      'duration_seconds': seconds,
    },
  };
}
