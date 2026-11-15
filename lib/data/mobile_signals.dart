import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'agent_api.dart';

class MobileSignals {
  static const _channel = MethodChannel('dev.wintermute/mobile_signals');
  static const unavailable = {
    'location': 'unsupported',
    'usage': 'unsupported',
    'backgroundLocation': false,
  };

  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  Future<Json> configure(String scope, bool location, bool usage) async {
    if (!_mobile) return unavailable;
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'configure',
      {'scope': scope, 'location': location, 'usage': usage},
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

class _Position {
  _Position(this.lat, this.lon, this.accuracy, this.at);
  final double lat, lon, accuracy;
  final DateTime at;

  static _Position? from(Json record, DateTime at) {
    final lat = record['lat'],
        lon = record['lon'],
        accuracy = record['accuracy'];
    if (lat is! num ||
        lon is! num ||
        accuracy is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        !accuracy.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180 ||
        accuracy < 0) {
      return null;
    }
    return _Position(lat.toDouble(), lon.toDouble(), accuracy.toDouble(), at);
  }

  double distanceTo(Json place) {
    const radians = math.pi / 180;
    final a =
        math.pow(math.sin((place['lat'] - lat) * radians / 2), 2) +
        math.cos(lat * radians) *
            math.cos(place['lat'] * radians) *
            math.pow(math.sin((place['lon'] - lon) * radians / 2), 2);
    return 12742000 * math.asin(math.sqrt(a.clamp(0, 1)));
  }
}

/// Reduces raw fixes on the phone. Only named places or rounded areas leave it.
class MobileTimeline {
  MobileTimeline(Json saved)
    : places = List<Json>.from(saved['places'] ?? []),
      lastArea = saved['lastArea'],
      lastPlace = saved['lastPlace'],
      lastLocationLabel = saved['lastLocationLabel'],
      lastUsageLabel = saved['lastUsageLabel'],
      _locationAt = saved['locationAt'] ?? 0;

  final List<Json> places;
  String? lastArea, lastPlace, lastLocationLabel, lastUsageLabel;
  int _locationAt;
  _Position? _current;
  static const _radius = 250;

  Json toJson() => {
    'places': places,
    'lastArea': lastArea,
    'lastPlace': lastPlace,
    'locationAt': _locationAt,
    'lastLocationLabel': lastLocationLabel,
    'lastUsageLabel': lastUsageLabel,
  };

  bool get canNameLocation {
    final fix = _current;
    if (fix == null || fix.accuracy > _radius) return false;
    final age = DateTime.now().difference(fix.at);
    return !age.isNegative && age < const Duration(minutes: 15);
  }

  void forgetLocation() {
    _current = null;
    lastArea = lastPlace = lastLocationLabel = null;
    _locationAt = 0;
  }

  void nameLocation(String input) {
    final name = input.trim();
    if (!canNameLocation) {
      throw const FormatException('需要最近 15 分钟内、精度在 250 米以内的位置');
    }
    if (name.isEmpty || name.length > 40 || name.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('请输入 1 至 40 字的地点名称');
    }
    places.removeWhere((p) => p['name'] == name);
    places.add({'name': name, 'lat': _current!.lat, 'lon': _current!.lon});
  }

  void removePlace(String name) {
    places.removeWhere((p) => p['name'] == name);
    if (lastPlace == name) {
      lastArea = lastPlace = lastLocationLabel = null;
    }
  }

  String? _near(_Position point, bool historical) {
    if (point.accuracy > _radius) return null;
    String? nearest;
    double best = double.infinity;
    for (final place in places) {
      final distance = point.distanceTo(place);
      final retained = !historical && place['name'] == lastPlace;
      final threshold = retained ? _radius + point.accuracy : _radius;
      if (distance <= threshold && distance <= best) {
        nearest = place['name'] as String;
        best = distance;
      }
    }
    return nearest;
  }

  String? currentPlaceUpdate() {
    if (!canNameLocation) return null;
    return _location(_current!, 'fix');
  }

  String? location(Json record, DateTime at) {
    final point = _Position.from(record, at);
    if (point == null) return null;
    return _location(point, record['kind'] as String? ?? 'fix');
  }

  String? _location(_Position point, String kind) {
    final time = point.at.millisecondsSinceEpoch;
    final historical = time < _locationAt;
    final name = _near(point, historical);
    // Ignore a coarse fix whose uncertainty still overlaps the previous place.
    if (kind == 'fix' && lastPlace != null && point.accuracy > _radius) {
      for (final place in places) {
        if (place['name'] == lastPlace &&
            point.distanceTo(place) <= _radius + point.accuracy) {
          if (!historical) _current = point;
          return null;
        }
      }
    }
    final area =
        '${point.lat.toStringAsFixed(2)}, ${point.lon.toStringAsFixed(2)}';
    final uncertainty = point.accuracy > 1000
        ? '（定位误差约 ${(point.accuracy / 1000).ceil()} 公里）'
        : '';
    final where = name == null ? '约 $area$uncertainty' : '「$name」';
    if (historical) {
      if (kind == 'fix') return null;
      return kind == 'departure' ? '离开$where' : '到达$where';
    }
    _locationAt = time;
    if (kind == 'departure') {
      _current = null;
      lastArea = lastPlace = null;
      return lastLocationLabel = '离开$where';
    }
    _current = point;
    if (name == lastPlace && (name != null || area == lastArea)) return null;
    final previous = lastPlace;
    lastPlace = name;
    lastArea = area;
    final next = name != null || kind == 'arrival' ? '到达$where' : '所在区域$where';
    return lastLocationLabel = previous == null ? next : '离开「$previous」，$next';
  }

  String? usage(Json record) {
    final start = record['start'], end = record['end'];
    if (start is! int || end is! int || end <= start) return null;
    final label = (record['label'] as String?)?.trim();
    final app = label == null || label.isEmpty ? record['package'] : label;
    if (app is! String || app.isEmpty) return null;
    String utc(int millis) => DateTime.fromMillisecondsSinceEpoch(
      millis,
      isUtc: true,
    ).toIso8601String().replaceAll('T', ' ').substring(0, 19);
    final seconds = ((end - start) / 1000).round();
    return lastUsageLabel =
        '手机前台使用「$app」，${utc(start)} 至 ${utc(end)}（UTC），约 $seconds 秒。';
  }
}
