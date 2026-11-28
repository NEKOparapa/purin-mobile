import 'package:flutter_test/flutter_test.dart';
import 'package:purin_mobile/data/agent_api.dart';
import 'package:purin_mobile/data/mobile_signals.dart';

void main() {
  test('前台和后台使用同一个结构化感知事件', () {
    final start = DateTime.utc(
      2026,
      11,
      24,
      12,
      0,
      0,
      123,
    ).millisecondsSinceEpoch;
    final row = {
      'id': 'span-1',
      'package': 'com.example.app',
      'label': ' 示例 ',
      'start': start,
      'end': start + 3650,
      'at': start + 3650,
    };
    final usage = AppUsage.fromRecord(row)!;
    final body = usage.perception;
    expect(AppUsage.path, 'perceptions');
    expect(body, {
      'event_id': 'app-usage:span-1',
      'occurred_at': '2026-11-24T12:00:03.773Z',
      'state_key': 'mobile.app_usage',
      'value': {
        'activity_id': 'span-1',
        'foreground_app': '示例',
        'device_platform': 'android',
        'started_at': '2026-11-24T12:00:00.123Z',
        'ended_at': '2026-11-24T12:00:03.773Z',
        'duration_seconds': 4,
      },
    });
    expect(AppUsage.fromRecord({...row})!.perception, body);
    expect(AppUsage.fromRecord({...row, 'label': ''})?.app, 'com.example.app');
    expect(AppUsage.fromRecord({...row, 'end': start}), isNull);
    final home = {...row, 'deviceName': 'winrt-test', 'isHomeApp': true};
    expect(AppUsage.fromRecord(home)!.perception['value'], {
      ...body['value'] as Json,
      'device_name': 'winrt-test',
      'is_home_app': true,
    });
    final app = {...home, 'isHomeApp': false};
    expect(AppUsage.fromRecord(app)!.perception['value']['is_home_app'], false);
  });

  test('仅自动命名的设备跟随系统名称', () {
    final automatic = Connection(
      'https://example.test',
      'phone',
      'token',
      name: 'AAK-AN00',
      followsSystemName: true,
    );
    final synced = automatic.withSystemName('winrt-test')!;
    final restored = Connection.fromJson(synced.toJson());
    expect(restored.deviceName, 'winrt-test');
    expect(restored.withSystemName('winrt-test'), isNull);
    expect(restored.withSystemName('新名字')!.deviceName, '新名字');
    final custom = Connection(
      'https://example.test',
      'phone',
      'token',
      name: '值班手机',
    );
    expect(custom.withSystemName('winrt-test'), isNull);
    final manual = Connection(
      'https://example.test',
      'phone',
      'token',
      name: 'AAK-AN00',
      followsSystemName: false,
    );
    expect(manual.withSystemName('winrt-test'), isNull);
  });
}
