import 'package:flutter_test/flutter_test.dart';
import 'package:purin_mobile/data/mobile_signals.dart';

void main() {
  test('地点感知保留原始经纬度、误差和系统定位类型', () {
    final row = {
      'lat': 30.123456789,
      'lon': 120.987654321,
      'accuracy': 15.75,
      'kind': 'arrival',
    };
    expect(LocationFix.fromRecord(row)!.value, {
      'latitude': row['lat'],
      'longitude': row['lon'],
      'accuracy_m': 15.75,
      'coordinate_system': 'wgs84',
      'kind': 'arrival',
    });
    expect(LocationFix.fromRecord({...row, 'accuracy': -1}), isNull);
    final wifi = LocationFix.fromRecord({
      ...row,
      'wifiState': 'connected',
      'wifiSsid': '测试网络',
    })!;
    expect(wifi.value['wifi'], {'state': 'connected', 'ssid': '测试网络'});
    final offline = LocationFix.fromRecord({
      ...row,
      'wifiState': 'disconnected',
    })!;
    expect(offline.value['wifi'], {'state': 'disconnected'});
  });
}
