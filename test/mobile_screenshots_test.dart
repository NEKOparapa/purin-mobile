import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/mobile_screenshots.dart';
import 'package:wintermute_mobile/data/mobile_session.dart';
import 'mobile_session_test.dart' show MemoryStore;

class TestScreenshots extends MobileScreenshots {
  @override
  String get platform => 'ios';
  final rows = <Json>[];
  bool active = false;
  int interval = 0;
  int prompts = 0;
  String? scope;
  @override
  void onChange(void Function()? callback) {}
  @override
  Future<Json> configure(String scope, bool enabled, int seconds) async {
    if (!enabled || (this.scope != null && this.scope != scope)) {
      rows.clear();
      active = false;
    }
    this.scope = scope;
    interval = seconds;
    return {'access': active ? 'active' : 'ready', 'pending': rows.length};
  }

  @override
  Future<void> request() async {
    prompts++;
    active = true;
  }

  @override
  Future<List<Json>> read(String scope) async => List.of(rows);
  @override
  Future<Uint8List?> bytes(String scope, String id) async =>
      Uint8List.fromList([255, 216, 255, 217]);
  @override
  Future<void> ack(String scope, String id) async =>
      rows.removeWhere((r) => r['id'] == id);
}

Future<void> until(bool Function() check) async {
  for (var i = 0; i < 100; i++) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(check(), isTrue);
}

void main() {
  test(
    'offline screenshot retries the same JPEG and context after restart, then waits for receipt before ack',
    () async {
      final received = <Json>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      bool online = false;
      final gate = Completer<void>();
      server.listen((r) async {
        if (r.uri.path == '/v1/image/slices') {
          final bytes = await r.fold(
            <int>[],
            (all, chunk) => all..addAll(chunk),
          );
          received.add({
            'bytes': bytes,
            'id': r.headers.value('X-Event-ID'),
            'when': r.headers.value('X-Occurred-At'),
            'terminal': r.headers.value('X-Terminal-ID'),
            'auth': r.headers.value('Authorization'),
            'type': r.headers.contentType?.mimeType,
            'context': jsonDecode(
              utf8.decode(
                base64Url.decode(r.headers.value('X-Capture-Context')!),
              ),
            ),
          });
          if (online) await gate.future;
          r.response.statusCode = online ? 202 : 503;
          r.response.write(
            online ? '{"event_id":"server-image"}' : '{"error":"offline"}',
          );
        } else if (r.uri.path == '/v1/history') {
          r.response.write('{"items":[],"next_cursor":null}');
        } else {
          r.response.write('{"outputs":[]}');
        }
        await r.response.close();
      });
      final native = TestScreenshots();
      final store = MemoryStore()
        ..saved = Connection(
          'http://127.0.0.1:${server.port}',
          'phone',
          'token',
        );
      MobileSession open() =>
          MobileSession(store, AgentApi(), screenshots: native);
      var session = open();
      await session.initialize();
      await session.setScreenshots(true);
      await session.setScreenshotInterval(60);
      const id = '106d54bb-0b78-4c58-a4e9-3f3600cc4bbb';
      final at = DateTime.utc(2026, 11, 14).millisecondsSinceEpoch;
      native.rows.add({'id': id, 'at': at});
      await session.sync();
      await until(() => session.screenshotError != null);
      expect(native.rows.length, 1);
      session.dispose();
      online = true;
      native.active = false;
      session = open();
      addTearDown(session.dispose);
      await session.initialize();
      await until(() => received.length == 2);
      expect(native.prompts, 1);
      expect(native.interval, 60);
      expect(received.first, received.last);
      expect(received.first, {
        'bytes': [255, 216, 255, 217],
        'id': id,
        'when': '2026-11-14T00:00:00.000Z',
        'terminal': 'phone',
        'auth': 'Bearer token',
        'type': 'image/jpeg',
        'context': {'platform': 'ios'},
      });
      expect(native.rows.length, 1);
      gate.complete();
      await until(() => native.rows.isEmpty);
      await session.setScreenshots(false);
      expect(session.pendingScreenshots, 0);
    },
  );
}
