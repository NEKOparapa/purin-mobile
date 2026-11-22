import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/device_inbox.dart';
import 'package:wintermute_mobile/data/schedule.dart';
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
          onInbox: () {},
          onNotice: (_) {},
          onSettings: () {},
        ),
      ),
    ),
  );
}

void main() {
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
