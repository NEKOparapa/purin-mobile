import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/device_inbox.dart';
import 'package:wintermute_mobile/data/mobile_session.dart';
import 'package:wintermute_mobile/data/mobile_store.dart';
import 'package:wintermute_mobile/data/schedule.dart';
import 'package:wintermute_mobile/screens/chat_screen.dart';
import 'package:wintermute_mobile/screens/schedule_screen.dart';

class _Api extends AgentApi {
  final requests = <Uri>[];
  final pages = <Completer<Json>>[];

  @override
  Future<Json> request(Connection connection, String path, {Json? body}) {
    requests.add(Uri.parse(path));
    final page = Completer<Json>();
    pages.add(page);
    return page.future;
  }
}

class _PhoneInbox extends DeviceInbox {
  _PhoneInbox(super.api);
  @override
  bool get supported => true;
}

class _NoticeSession extends MobileSession {
  _NoticeSession(AgentApi api) : super(DeviceStore(), api);
  late final _inbox = _PhoneInbox(api);
  @override
  DeviceInbox get inbox => _inbox;
}

class _NoticeApi extends AgentApi {
  bool read = false;
  final today = DateUtils.dateOnly(DateTime.now());
  DateTime get other => DateTime(
    today.year,
    today.month,
    today.day + (today.weekday == 7 ? -1 : 1),
  );
  @override
  Future<Json> request(Connection connection, String path, {Json? body}) async {
    if (path.startsWith('schedule?')) {
      expect(Uri.parse(path).queryParameters['include_notifications'], '1');
      final items = <Json>[];
      for (var i = 0; i < 5; i++) {
        final day = i == 4 ? other : today;
        final at = DateTime(day.year, day.month, day.day, 8, i);
        items.add({
          ..._entry('s$i', '提醒$i', at),
          'action': 'notify_device',
          'notification': {
            'id': 'n$i',
            'title': '提醒$i',
            'body': '后端正文$i',
            'notify_at': at.toUtc().toIso8601String(),
            'target_names': ['手机', '电脑'],
            'in_inbox': i != 4,
            'status': i == 4 ? 'scheduled' : 'sent',
            'attachments': [],
            'read_at': i == 0 && read ? 'now' : null,
          },
        });
      }
      return {'items': items, 'next_cursor': null};
    }
    if (path == 'notifications/n0/read') {
      read = true;
      return {};
    }
    expect(path, startsWith('notifications?limit='));
    return {
      'items': [
        for (var i = 0; i < 4; i++)
          {
            'id': 'n$i',
            'title': '提醒$i',
            'body': '后端正文$i',
            'created_at': '2026-01-01T08:00:00Z',
            'read_at': i == 0 && read ? 'now' : null,
            'attachments': [],
          },
      ],
      'next_cursor': null,
    };
  }
}

Json _entry(String id, String title, DateTime at, {bool triggered = false}) => {
  'id': id,
  'title': title,
  'trigger_at': at.toUtc().toIso8601String(),
  'content': '日程内容',
  'action': 'notify_agent',
  'status': triggered ? 'triggered' : 'scheduled',
};

Future<void> _open(WidgetTester tester, _Api api) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 720);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ScheduleScreen(
          api: api,
          connection: Connection('http://localhost', 'test', 'token'),
          inbox: DeviceInbox(api),
          onSettings: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('系统通知直接打开原定日期，关闭详情再返回可回到对话', (tester) async {
    final session = _NoticeSession(_NoticeApi());
    final conn = Connection('http://localhost', 'phone', 'test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var launch = true;
    messenger.setMockMethodCallHandler(noticeChannel, (call) async {
      if (call.method == 'takeOpen' && launch) {
        launch = false;
        return {'scope': conn.scope, 'id': 'n0'};
      }
      return call.method == 'status' ? true : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(noticeChannel, null));
    session.connection = conn;
    session.inbox.connect(conn);
    addTearDown(session.inbox.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ChatScreen(session: session),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('后端正文0'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final day = DateTime.parse('2026-01-01T08:00:00Z').toLocal();
    expect(
      find.bySemanticsLabel(RegExp('^${day.year}年${day.month}月${day.day}日')),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('日程'), findsOneWidget);
    expect(find.text('Wintermute'), findsOneWidget);
  });

  testWidgets('按所选日展示通知时间和设备，支持授权、展开和已读', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var allowed = false;
    messenger.setMockMethodCallHandler(noticeChannel, (MethodCall call) async {
      if (call.method == 'enable') allowed = true;
      return ['status', 'enable'].contains(call.method) ? allowed : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(noticeChannel, null));
    final api = _NoticeApi();
    final conn = Connection('http://localhost', 'phone', 'test');
    final inbox = _PhoneInbox(api)..connect(conn);
    addTearDown(inbox.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleScreen(
            api: api,
            connection: conn,
            inbox: inbox,
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当日通知'), findsOneWidget);
    expect(find.text('当日安排'), findsOneWidget);
    expect(find.textContaining('目标设备 · 手机、电脑'), findsWidgets);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('提醒4'), findsNothing);
    expect(find.text('后端正文0'), findsOneWidget);
    await tester.tap(find.text('获取通知权限'));
    await tester.pumpAndSettle();
    expect(find.text('获取通知权限'), findsNothing);
    await tester.tap(find.text('显示全部 4 条'));
    await tester.pumpAndSettle();
    expect(find.text('后端正文3'), findsOneWidget);
    await tester.tap(find.text('提醒0'));
    await tester.pumpAndSettle();
    expect(api.read, isTrue);
    expect(find.byType(SelectableText), findsOneWidget);
    Navigator.of(tester.element(find.byType(SelectableText))).pop();
    await tester.pumpAndSettle();
    final day = api.other;
    await tester.tap(
      find.bySemanticsLabel(RegExp('^${day.year}年${day.month}月${day.day}日，')),
    );
    await tester.pumpAndSettle();
    expect(find.text('提醒4'), findsOneWidget);
    expect(find.text('提醒0'), findsNothing);
    expect(find.text('08:04'), findsOneWidget);
    expect(find.text('当天没有安排'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('日程分页去重、按本地时间排列，过期的翻页响应不会覆盖本月', (tester) async {
    final api = _Api();
    await _open(tester, api);
    final now = DateTime.now();
    final morning = DateTime(now.year, now.month, now.day, 9);
    final later = DateTime(now.year, now.month, now.day, 16, 30, 15);
    final start = DateTime(now.year, now.month, now.day + 1 - now.weekday);
    final end = DateTime(start.year, start.month, start.day + 7);
    final week = api.requests.single;
    expect(week.path, 'schedule');
    expect(week.queryParameters['start'], start.toUtc().toIso8601String());
    expect(week.queryParameters['end'], end.toUtc().toIso8601String());
    api.pages[0].complete({
      'items': [_entry('a', '下午的安排', later)],
      'next_cursor': 'test+cursor|2',
    });
    await tester.pump();
    expect(api.requests.last.queryParameters['cursor'], 'test+cursor|2');
    api.pages[1].complete({
      'items': [
        _entry('a', '下午的安排', later),
        _entry('b', '早上的安排', morning, triggered: true),
      ],
      'next_cursor': null,
    });
    await tester.pumpAndSettle();
    expect(find.text('下午的安排'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('早上的安排')).dy,
      lessThan(tester.getTopLeft(find.text('下午的安排')).dy),
    );
    expect(find.text('已触发'), findsOneWidget);
    expect(find.text('待触发'), findsOneWidget);
    expect(find.text('16:30:15'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('今天，2项安排')), findsOneWidget);

    final other = DateTime(
      now.year,
      now.month,
      now.day + (now.weekday == 7 ? -1 : 1),
    );
    await tester.tap(
      find.bySemanticsLabel('${other.year}年${other.month}月${other.day}日，0项安排'),
    );
    await tester.pump();
    expect(find.text('当天没有安排'), findsOneWidget);
    expect(api.requests.length, 2);
    await tester.tap(find.byTooltip('下一周'));
    await tester.pump();
    await tester.tap(find.byTooltip('展开月历'));
    await tester.pump();
    final monthStart = DateTime.parse(
      api.requests[3].queryParameters['start']!,
    ).toLocal();
    expect(monthStart.day, 1);
    expect(
      api.requests[3].queryParameters['end'],
      DateTime(monthStart.year, monthStart.month + 1).toUtc().toIso8601String(),
    );
    api.pages[3].complete({'items': [], 'next_cursor': null});
    await tester.pump();
    api.pages[2].completeError(ApiError(404, 'not_found'));
    await tester.pumpAndSettle();
    expect(find.text('当天没有安排'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('分页错误可重试，刷新失败时仍可阅读已加载的安排', (tester) async {
    final api = _Api();
    await _open(tester, api);
    for (var i = 0; i < 2; i++) {
      api.pages[i].complete({'items': [], 'next_cursor': 'repeat'});
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('分页位置无效'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    api.pages[2].complete({
      'items': [_entry('a', '读书', DateTime.now())],
      'next_cursor': null,
    });
    await tester.pumpAndSettle();
    expect(find.text('读书'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    api.pages[3].completeError(ApiError(404, 'not_found'));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前显示上次读取的安排'), findsOneWidget);
    expect(find.text('读书'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('缺少时区的日程时间不可当作手机本地时间', () {
    expect(
      () => ScheduleEntry.fromJson({
        ..._entry('x', '测试', DateTime.now()),
        'trigger_at': '2026-01-01T18:00:00',
      }),
      throwsFormatException,
    );
  });
}
