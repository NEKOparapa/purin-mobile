import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/mobile_session.dart';
import 'package:wintermute_mobile/data/mobile_store.dart';
import 'package:wintermute_mobile/screens/chat_screen.dart';
import 'package:wintermute_mobile/widgets/app_theme.dart';

class _Session extends MobileSession {
  _Session() : super(DeviceStore(), AgentApi()) {
    ready = true;
    connection = Connection('http://localhost', 'phone', 'test');
  }

  @override
  final List<Json> messages = [];
  @override
  bool chatHistoryLoaded = false;

  @override
  Future<void> send(String text) async => add('user', text, status: 'queued');

  void add(String role, String text, {String? status}) {
    messages.add({
      'id': 'm${messages.length}',
      'role': role,
      'text': text,
      'status': status,
    });
    chatHistoryLoaded = true;
    notifyListeners();
  }
}

Future<_Session> _openChat(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.android,
  bool connected = true,
}) async {
  final session = _Session();
  if (!connected) session.connection = null;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 680);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: terminalTheme(lightColors).copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: ChatScreen(session: session),
    ),
  );
  return session;
}

Finder _pose(String name) =>
    find.image(AssetImage('assets/mascot/$name-still.webp'));

void main() {
  testWidgets('话题草稿在键盘展开、收起和切换页面后保留', (tester) async {
    await _openChat(tester, connected: false);
    expect(find.text('今天过得怎么样？'), findsOneWidget);
    expect(_pose('idle'), findsOneWidget);
    await tester.tap(find.text('想想晚饭'));
    await tester.pump();
    final field = find.byType(TextField);
    final original = tester.widget<TextField>(field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 290);
    await tester.pump();
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(
      tester.widget<TextField>(field).controller,
      same(original.controller),
    );
    expect(original.controller!.text, '今晚吃点什么好呢？');
    expect(find.text('想想晚饭'), findsNothing);
    expect(tester.getBottomRight(field).dy, lessThanOrEqualTo(390));
    tester.view.resetViewInsets();
    await tester.pump();
    await tester.tap(find.byTooltip('导航菜单'));
    await tester.pumpAndSettle();
    expect(find.text('记忆'), findsNothing);
    await tester.tap(find.text('日程'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开月历'), findsOneWidget);
    expect(find.text('打开连接设置'), findsOneWidget);
    await tester.tap(find.byTooltip('导航菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('对话').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '今晚吃点什么好呢？');
  });

  testWidgets('iOS 菜单保留记忆页', (tester) async {
    await _openChat(tester, platform: TargetPlatform.iOS);
    await tester.tap(find.byTooltip('导航菜单'));
    await tester.pumpAndSettle();
    expect(find.text('日程'), findsNothing);
    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    expect(find.text('示例记忆'), findsOneWidget);
  });

  testWidgets('新回复触发发言，搜索和消息发送使用同一段历史', (tester) async {
    final session = await _openChat(tester);
    session.add('assistant', '之前的消息');
    await tester.pump();
    expect(_pose('idle'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '晚餐吃什么？');
    await tester.pump();
    expect(_pose('listening'), findsOneWidget);
    await tester.tap(find.byTooltip('发送消息'));
    await tester.pump();
    expect(_pose('thinking'), findsOneWidget);
    expect(find.text('今天过得怎么样？'), findsNothing);
    session.add('assistant', '来一碗热汤面吧。');
    await tester.pump();
    expect(_pose('speaking'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('来一碗热汤面吧。')).dx,
      lessThan(tester.getTopLeft(find.text('晚餐吃什么？')).dx),
    );
    await tester.pump(const Duration(seconds: 4));
    expect(_pose('idle'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索对话'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, '搜索对话内容…'), '热汤');
    await tester.pump();
    expect(find.text('来一碗热汤面吧。'), findsOneWidget);
    expect(find.text('之前的消息'), findsNothing);
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pump();
    expect(find.text('之前的消息'), findsOneWidget);
  });
}
