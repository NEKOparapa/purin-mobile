import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/mobile_session.dart';
import 'package:wintermute_mobile/screens/connection_screen.dart';
import '../test/mobile_session_test.dart' show MemoryStore;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'foreground Android receives a status call and posts native data',
    (tester) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final receipt = Completer<Json>();
      final claims = <List>[];
      server.listen((request) async {
        final response = request.response;
        response.headers.contentType = ContentType.json;
        Json data = {};
        if (request.headers.value('X-Terminal-ID') != 'android-test' ||
            request.headers.value('Authorization') != 'Bearer emulator-test') {
          response.statusCode = HttpStatus.unauthorized;
        } else if (request.uri.path == '/v1/terminal-tools/claim') {
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          claims.add(body['tools']);
          data = {
            'call': claims.length == 2
                ? {
                    'id': 'on-device-1',
                    'tool': 'device_status',
                    'arguments': {},
                    'timeout_seconds': 15,
                    'claim_token': 'on-device-claim',
                  }
                : null,
          };
        } else if (request.uri.path ==
            '/v1/terminal-tools/on-device-1/result') {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Json;
          receipt.complete(body);
        } else if (request.uri.path == '/v1/outputs') {
          data = {'outputs': []};
        } else {
          data = {'items': [], 'next_cursor': null};
        }
        response.write(jsonEncode(data));
        await response.close();
      });
      final session = MobileSession(
        MemoryStore()
          ..saved = Connection(
            'http://127.0.0.1:${server.port}',
            'android-test',
            'emulator-test',
          ),
        AgentApi(),
      );
      addTearDown(session.dispose);
      await session.initialize();
      await tester.pumpWidget(
        MaterialApp(home: ConnectionScreen(session: session)),
      );
      final toggle = find.widgetWithText(SwitchListTile, '允许 Agent 查询设备状态');
      final list = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(toggle, 300, scrollable: list);
      expect(tester.widget<SwitchListTile>(toggle).value, false);
      expect(claims, isEmpty);
      await tester.tap(toggle);
      final result = await receipt.future.timeout(const Duration(seconds: 25));
      expect(claims, everyElement(['device_status']));
      expect(result['claim_token'], 'on-device-claim');
      expect(result['status'], 'succeeded');
      expect(result['exit_code'], 0);
      final value = jsonDecode(result['stdout']) as Json;
      expect(value['platform'], 'android');
      expect(value['android_sdk'], greaterThan(0));
      expect(value['android_version'], isNotEmpty);
      expect(value['app_version'], isNotEmpty);
      expect(value['battery_percent'], anyOf(isNull, inInclusiveRange(0, 100)));
      expect(value['charging'], anyOf(isNull, isA<bool>()));
      expect(
        value['collection'].keys,
        containsAll(['app_activity', 'location', 'app_usage', 'screenshots']),
      );
      debugPrint('Android device_status result: ${result['stdout']}');
    },
    skip: !Platform.isAndroid,
  );
}
