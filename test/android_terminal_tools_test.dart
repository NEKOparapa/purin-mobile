import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/android_terminal_tools.dart';
import 'package:wintermute_mobile/data/mobile_session.dart';
import 'mobile_session_test.dart' show MeetingApi, MemoryStore;

class TestStatus extends AndroidDeviceStatus {
  int reads = 0;
  bool fail = false;
  @override
  bool get supported => true;
  @override
  Future<Json> read() async {
    reads++;
    if (fail) throw StateError('unavailable');
    return {'android_sdk': 35, 'battery_percent': 82, 'charging': true};
  }
}

class ToolApi extends MeetingApi {
  final claims = <List>[];
  final results = <Json>[];
  Json? call;
  int? rejectResult;

  @override
  Future<Json> request(Connection connection, String path, {Json? body}) async {
    if (path == 'terminal-tools/claim') {
      claims.add(body!['tools'] as List);
      final item = call;
      call = null;
      return {'call': item};
    }
    if (path == 'terminal-tools/run-1/result') {
      results.add(Json.from(body!));
      if (rejectResult != null) throw ApiError(rejectResult!, 'unavailable');
      return {'status': body['status']};
    }
    return super.request(connection, path, body: body);
  }
}

Json statusCall({String tool = 'device_status', Json arguments = const {}}) => {
  'id': 'run-1',
  'claim_token': 'single-use-token',
  'tool': tool,
  'arguments': arguments,
  'timeout_seconds': 15,
};

void main() {
  test(
    'defaults off, advertises only device_status in foreground and withdraws on opt-out',
    () async {
      final store = MemoryStore()
        ..saved = Connection('https://local.test', 'phone', 'test');
      final api = ToolApi()..call = statusCall();
      final device = TestStatus();
      final session = MobileSession(store, api, deviceStatus: device);
      addTearDown(session.dispose);
      await session.initialize();
      expect(api.claims, isEmpty);
      expect(session.deviceStatusEnabled, isFalse);
      await session.setDeviceStatusEnabled(true);
      expect(api.claims.single, ['device_status']);
      final result = api.results.single;
      expect(result['claim_token'], 'single-use-token');
      expect(result['status'], 'succeeded');
      expect(result['exit_code'], 0);
      final status = jsonDecode(result['stdout']);
      expect(status['platform'], 'android');
      expect(status['battery_percent'], 82);
      expect(status['collection']['location'], false);
      session.foreground(false);
      await session.sync();
      expect(api.claims.length, 1);
      await session.setDeviceStatusEnabled(false);
      session.foreground(true);
      await Future<void>.delayed(Duration.zero);
      expect(api.claims, [
        ['device_status'],
        [],
      ]);
      await session.sync();
      expect(api.claims.length, 2);
    },
  );

  test(
    'retries the same result after restart without rerunning and drops expired receipts',
    () async {
      final store = MemoryStore()
        ..saved = Connection('https://local.test', 'phone', 'test');
      final api = ToolApi()
        ..call = statusCall()
        ..rejectResult = 503;
      final device = TestStatus();
      final first = MobileSession(store, api, deviceStatus: device);
      await first.initialize();
      await first.setDeviceStatusEnabled(true);
      expect(api.results, hasLength(1));
      expect(first.deviceStatusError, contains('503'));
      first.dispose();
      api.rejectResult = 410;
      final next = MobileSession(store, api, deviceStatus: device);
      addTearDown(next.dispose);
      await next.initialize();
      expect(api.results, [api.results.first, api.results.first]);
      expect(device.reads, 1);
      await next.sync();
      expect(api.results.length, 2);
      expect(next.deviceStatusError, isNull);
    },
  );

  test(
    'unknown tools, unexpected parameters and untrusted HTTP never execute',
    () async {
      final store = MemoryStore()
        ..saved = Connection('https://local.test', 'phone', 'test');
      final api = ToolApi()..call = statusCall(tool: 'shell');
      final device = TestStatus();
      final session = MobileSession(store, api, deviceStatus: device);
      addTearDown(session.dispose);
      await session.initialize();
      await session.setDeviceStatusEnabled(true);
      api.call = statusCall(arguments: {'command': 'whoami'});
      await session.sync();
      expect(api.results.map((r) => r['status']), ['failed', 'failed']);
      expect(device.reads, 0);
      device.fail = true;
      api.call = statusCall();
      await session.sync();
      expect(api.results.last['status'], 'failed');
      expect(api.results.last['stdout'], '');
      final count = api.claims.length;
      final other = Connection('http://host.test', 'phone', 'test');
      await session.configure(other);
      expect(session.canEnableDeviceStatus, isFalse);
      await session.setDeviceStatusEnabled(true);
      expect(session.deviceStatusEnabled, isFalse);
      expect(api.claims.length, count);
      expect(
        secureToolConnection(Connection('http://127.0.0.1', 'phone', 'test')),
        isTrue,
      );
      expect(
        secureToolConnection(Connection('http://[::1]', 'phone', 'test')),
        isTrue,
      );
    },
  );
}
