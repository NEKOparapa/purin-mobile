import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/mobile_session.dart';
import 'package:wintermute_mobile/data/mobile_store.dart';
import 'package:wintermute_mobile/main.dart';

// On a disposable emulator, grant foreground location and usage access first.
// At SIGNALS_ENABLED inject (31.23456, 121.54321) and open/close Android
// Settings. At SIGNALS_DISABLED repeat with another location and Settings visit.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const optIn = bool.fromEnvironment('TEST_EMULATOR_SIGNALS');
  testWidgets(
    'native location and completed App usage reach the local HTTP service',
    (tester) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final observations = <Json>[];
      final spans = <Json>[];
      server.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        final json = body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(body) as Json;
        final path = req.uri.path;
        final response = req.response;
        if (path == '/v1/history') {
          response.write('{"items":[],"next_cursor":null}');
        } else if (path == '/v1/outputs') {
          response.write('{"outputs":[]}');
        } else if (path == '/v1/perceptions' || path == '/v1/slices') {
          (path == '/v1/perceptions' ? observations : spans).add(json);
          response.statusCode = HttpStatus.accepted;
          response.write(jsonEncode({'event_id': json['event_id']}));
        } else {
          response.statusCode = HttpStatus.notFound;
          response.write('{}');
        }
        await response.close();
      });
      final store = DeviceStore();
      await store.saveConnection(
        Connection(
          'http://127.0.0.1:${server.port}',
          'emulator-signals',
          'fixture',
        ),
      );
      final session = MobileSession(store, AgentApi());
      Future<void> waitFor(
        bool Function() condition, {
        int seconds = 60,
      }) async {
        final until = DateTime.now().add(Duration(seconds: seconds));
        while (!condition() && DateTime.now().isBefore(until)) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(
          condition(),
          isTrue,
          reason:
              'location=${session.locationAccess} usage=${session.usageAccess} error=${session.signalError ?? session.collectionError}',
        );
      }

      try {
        await tester.pumpWidget(WintermuteApp(session: session));
        await waitFor(() => session.ready);
        if (session.locationAccess != 'granted' ||
            session.usageAccess != 'granted') {
          markTestSkipped(
            'Grant location and usage access on the test emulator.',
          );
          return;
        }
        await session.setSignalEnabled('location', true);
        await session.setSignalEnabled('usage', true);
        debugPrint('SIGNALS_ENABLED');
        bool isSettings(Json row) => RegExp(
          r'「(?:Settings|设置|com\.android\.settings)」',
        ).hasMatch(row['text'] as String);
        bool isInjectedFix(Json row) =>
            row['state_key'] == 'mobile.location' &&
            (row['value'] as String).contains('31.23, 121.54');
        await waitFor(
          () => observations.any(isInjectedFix) && spans.any(isSettings),
        );
        final fix = observations.firstWhere(isInjectedFix);
        expect(fix['value'], isNot(contains('31.23456')));
        expect(DateTime.parse(fix['occurred_at']).isUtc, isTrue);
        final span = spans.firstWhere(isSettings);
        final match = RegExp(
          r'(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d) 至 (\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d)（UTC），约 (\d+) 秒',
        ).firstMatch(span['text']);
        expect(match, isNotNull);
        final seconds = int.parse(match!.group(3)!);
        final start = DateTime.parse('${match.group(1)}Z');
        final end = DateTime.parse('${match.group(2)}Z');
        expect(seconds, greaterThanOrEqualTo(1));
        expect(
          (end.difference(start).inSeconds - seconds).abs(),
          lessThanOrEqualTo(1),
        );
        debugPrint('SIGNALS_RECEIVED ${fix['value']} | ${span['text']}');
        await session.setSignalEnabled('location', false);
        await session.setSignalEnabled('usage', false);
        final total = observations.length + spans.length;
        debugPrint('SIGNALS_DISABLED');
        await tester.pump(const Duration(seconds: 12));
        await session.sync();
        expect(observations.length + spans.length, total);
        expect(session.pending, isEmpty);
      } finally {
        await session.setSignalEnabled('location', false);
        await session.setSignalEnabled('usage', false);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
        await server.close(force: true);
      }
    },
    skip: !Platform.isAndroid || !optIn,
  );
}
