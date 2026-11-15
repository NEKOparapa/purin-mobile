import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/mobile_session.dart';
import 'package:wintermute_mobile/data/mobile_store.dart';
import 'package:wintermute_mobile/main.dart';

// Run only on a disposable emulator with usage access. Confirm the system's
// screen-sharing dialog, open Android Settings and return once two JPEGs arrive.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'screen sharing delivers a Settings frame and its matching usage span',
    (tester) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final images = <Json>[], spans = <Json>[];
      server.listen((req) async {
        final data = await req.fold<List<int>>(
          [],
          (bytes, part) => bytes..addAll(part),
        );
        final res = req.response;
        if (req.uri.path == '/v1/image/slices') {
          final raw = req.headers.value('x-capture-context')!;
          final ctx = jsonDecode(utf8.decode(base64Url.decode(raw))) as Json;
          images.add({
            ...ctx,
            'id': req.headers.value('x-event-id'),
            'at': req.headers.value('x-occurred-at'),
            'jpeg': data.take(2).join(','),
            'size': data.length,
          });
          debugPrint('EMULATOR_IMAGE ${ctx['package']} ${data.length}');
          res.statusCode = 202;
          res.write(jsonEncode({'event_id': req.headers.value('x-event-id')}));
        } else if (req.uri.path == '/v1/slices') {
          final span = jsonDecode(utf8.decode(data)) as Json;
          spans.add(span);
          res.statusCode = 202;
          res.write(jsonEncode({'event_id': span['event_id']}));
        } else if (req.uri.path == '/v1/history') {
          res.write('{"items":[],"next_cursor":null}');
        } else {
          res.write('{"outputs":[]}');
        }
        await res.close();
      });
      final store = DeviceStore();
      await store.saveConnection(
        Connection(
          'http://127.0.0.1:${server.port}',
          'capture-test',
          'fixture',
        ),
      );
      final session = MobileSession(store, AgentApi());
      Future<void> until(bool Function() ready) async {
        final end = DateTime.now().add(const Duration(seconds: 110));
        while (!ready() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(
          ready(),
          isTrue,
          reason:
              'access=${session.screenshotAccess} error=${session.screenshotError}',
        );
      }

      try {
        await tester.pumpWidget(WintermuteApp(session: session));
        await until(() => session.ready);
        if (session.usageAccess != 'granted') {
          markTestSkipped('Grant usage access on the disposable emulator.');
          return;
        }
        await session.setSignalEnabled('usage', true);
        await session.setScreenshotInterval(60);
        debugPrint('EMULATOR_CONSENT');
        await session.setScreenshots(true);
        await until(() => session.screenshotAccess == 'active');
        debugPrint('EMULATOR_OPEN_SETTINGS');
        await until(
          () =>
              images
                  .where((row) => row['package'] == 'com.android.settings')
                  .length >=
              2,
        );
        final shot = images.firstWhere(
          (row) => row['package'] == 'com.android.settings',
        );
        expect(shot['jpeg'], '255,216');
        expect(shot['size'], greaterThan(1000));
        expect(shot['platform'], 'android');
        final second = images.lastWhere(
          (row) => row['package'] == 'com.android.settings',
        );
        expect(second['id'], isNot(shot['id']));
        expect(second['activity_id'], shot['activity_id']);
        final elapsed = DateTime.parse(
          second['at'],
        ).difference(DateTime.parse(shot['at']));
        expect(elapsed.inSeconds, greaterThanOrEqualTo(60));
        debugPrint('EMULATOR_INTERVAL ${elapsed.inMilliseconds} ms');
        await until(
          () => spans.any((row) => row['event_id'] == shot['activity_id']),
        );
        await session.setScreenshots(false);
        expect(session.pendingScreenshots, 0);
        expect(session.screenshotAccess, 'ready');
        expect(
          images.any((r) => r['package'] == 'dev.wintermute.wintermute_mobile'),
          isFalse,
        );
      } finally {
        await session.setScreenshots(false);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
        await server.close(force: true);
      }
    },
    skip:
        !Platform.isAndroid ||
        !const bool.fromEnvironment('TEST_EMULATOR_SCREENSHOTS'),
  );
}
