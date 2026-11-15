import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/device_inbox.dart';
import 'package:wintermute_mobile/screens/inbox_screen.dart';

Json row(String id, {bool expired = false}) => {
  'id': id,
  'title': '会议资料',
  'body': '核对报价',
  'created_at': '2026-11-16T02:00:00Z',
  'expired': expired,
  'read_at': null,
  'attachments': [
    {
      'id': 'pdf',
      'name': '报价.pdf',
      'content_type': 'application/pdf',
      'size_bytes': 1234,
    },
    {
      'id': 'text',
      'name': '清单.txt',
      'content_type': 'text/plain',
      'size_bytes': 3,
    },
  ],
};

class InboxApi extends AgentApi {
  final calls = <String>[];
  @override
  Future<Json> request(Connection conn, String path, {Json? body}) async {
    calls.add(path);
    if (body != null) return {};
    if (!path.contains('pending=1')) {
      return {
        'items': [row('live')],
        'next_cursor': null,
      };
    }
    if (path.contains('cursor=')) {
      return {
        'items': [row('older', expired: true)],
        'next_cursor': null,
      };
    }
    return {
      'items': [row('live')],
      'next_cursor': '5',
    };
  }
}

void main() {
  final conn = Connection('https://example.test', 'phone', 'fixture');
  test(
    'receipt is per arrival; expired page acknowledges silently, blocked system alert remains pending',
    () async {
      final api = InboxApi(), presentations = <String>[];
      await receiveNotices(api, conn, (notice) async {
        presentations.add(notice.id);
        return true;
      }, active: () => true);
      expect(presentations, ['live']);
      expect(api.calls.where((p) => p.endsWith('/received')), [
        'notifications/live/received',
        'notifications/older/received',
      ]);
      expect(
        api.calls.any((p) => p.endsWith('/read') || p.contains('/files/')),
        false,
      );
      api.calls.clear();
      await receiveNotices(api, conn, (_) async => false, active: () => true);
      expect(api.calls.length, 1);
    },
  );
  testWidgets(
    'receipt detail lists multiple attachment names and only saves selected file',
    (tester) async {
      final api = InboxApi(), inbox = DeviceInbox(api)..connect(conn);
      final saved = <Map>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(noticeChannel, (call) async {
        if (call.method == 'saveAttachment') {
          saved.add(call.arguments as Map);
          return true;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(noticeChannel, null),
      );
      await tester.pumpWidget(MaterialApp(home: InboxScreen(inbox: inbox)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('会议资料'));
      await tester.pumpAndSettle();
      expect(api.calls.contains('notifications/live/read'), true);
      expect(find.text('报价.pdf'), findsOneWidget);
      expect(find.text('清单.txt'), findsOneWidget);
      expect(saved, isEmpty);
      await tester.tap(find.text('清单.txt'));
      await tester.pumpAndSettle();
      expect(
        saved.single['url'],
        'https://example.test/v1/notifications/live/files/text',
      );
      expect(saved.single['size'], 3);
      expect(saved.single['terminal'], 'phone');
      expect(find.text('附件已保存'), findsOneWidget);
    },
  );
}
