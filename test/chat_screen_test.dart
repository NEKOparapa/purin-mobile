import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/mobile_session.dart';
import 'package:wintermute_mobile/data/mobile_store.dart';
import 'package:wintermute_mobile/screens/chat_screen.dart';
import 'package:wintermute_mobile/screens/connection_screen.dart';
import 'package:wintermute_mobile/screens/schedule_screen.dart';
import 'package:wintermute_mobile/widgets/app_theme.dart';

class _Session extends MobileSession {
  _Session() : super(DeviceStore(), AgentApi()) {
    ready = true;
    installation = 'test-installation';
    connection = Connection('http://localhost', 'phone', 'test');
  }

  @override
  final List<Json> messages = [];
  @override
  bool chatHistoryLoaded = false;

  @override
  Future<void> send(
    String text, {
    List<String> images = const [],
    List<String> imageNames = const [],
    List<Json> documents = const [],
    Connection? expectedConnection,
  }) async => add('user', text, status: 'queued');

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
  bool animate = false,
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
        data: MediaQuery.of(context).copyWith(disableAnimations: !animate),
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
  testWidgets('聊天与日程右上角一键打开设置，返回后保留草稿和原页面', (tester) async {
    final session = await _openChat(tester, animate: true);
    session.add('assistant', '散步吗？');
    await tester.pump();
    expect(find.byTooltip('搜索对话'), findsNothing);
    expect(find.byTooltip('更多'), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    final editor = find.byType(TextField);
    await tester.enterText(editor, '周末');
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pump();
    await tester.tap(find.byTooltip('设置'));
    tester.view.resetViewInsets();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    expect(find.byType(ConnectionScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.widget<TextField>(editor).controller!.text, '周末');
    await tester.tap(find.text('日程'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byTooltip('设置').last);
    await tester.pump();
    tester.view.physicalSize = const Size(680, 360);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    expect(find.byType(ConnectionScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final calendar = find.byType(ScheduleScreen);
    expect(calendar, findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('当日通知'),
      140,
      scrollable: find
          .descendant(of: calendar, matching: find.byType(Scrollable))
          .first,
    );
    expect(find.text('当日通知'), findsOneWidget);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('${platform.name} 输入区按可用宽度和换行切换，保留输入法状态', (tester) async {
      final session = await _openChat(tester, platform: platform);
      final field = find.byType(TextField);
      final editor = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      final initialState = tester.state<EditableTextState>(editor);
      final controller = tester.widget<TextField>(field).controller!;

      void checkLayout({required bool expanded}) {
        final text = tester.getRect(field);
        final attach = tester.getRect(find.byTooltip('添加附件'));
        final mic = tester.getRect(find.byTooltip('语音输入'));
        final send = tester.getRect(find.byTooltip('发送消息'));
        expect(attach.center.dy, closeTo(mic.center.dy, .01));
        expect(attach.center.dy, closeTo(send.center.dy, .01));
        if (expanded) {
          expect(text.bottom, lessThanOrEqualTo(attach.top));
          expect(text.left, lessThanOrEqualTo(attach.left));
          expect(text.right, greaterThanOrEqualTo(send.right));
        } else {
          expect(text.center.dy, closeTo(attach.center.dy, .01));
          expect(text.left, greaterThanOrEqualTo(attach.right));
          expect(text.right, lessThanOrEqualTo(mic.left));
        }
        expect(tester.state<EditableTextState>(editor), same(initialState));
      }

      checkLayout(expanded: false);
      await tester.enterText(field, '你好');
      tester.view.viewInsets = const FakeViewPadding(bottom: 290);
      await tester.pump();
      checkLayout(expanded: false);

      const draft = TextEditingValue(
        text: '今天天气很好，我们一起去散步吧。🙂',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      );
      tester.testTextInput.updateEditingValue(draft);
      await tester.pump();
      checkLayout(expanded: true);
      tester.view.physicalSize = const Size(760, 680);
      await tester.pump();
      checkLayout(expanded: false);
      expect(controller.value, draft);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      tester.view.physicalSize = const Size(360, 680);
      await tester.pump();
      checkLayout(expanded: true);
      expect(controller.value, draft);

      await tester.enterText(field, '短');
      await tester.pump();
      checkLayout(expanded: false);
      await tester.enterText(field, '123456');
      await tester.pump();
      checkLayout(expanded: false);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pump();
      checkLayout(expanded: true);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pump();
      checkLayout(expanded: false);
      await tester.enterText(field, '甲\u2028乙');
      await tester.pump();
      checkLayout(expanded: true);
      final twoLines = tester.getSize(field).height;
      await tester.enterText(field, '甲\n乙\n丙\n丁\n戊');
      await tester.pump();
      expect(tester.getSize(field).height, greaterThan(twoLines));
      tester.view.physicalSize = const Size(760, 360);
      tester.view.viewInsets = const FakeViewPadding(bottom: 205);
      await tester.pump();
      checkLayout(expanded: true);
      expect(tester.getSize(field).height, lessThanOrEqualTo(twoLines));
      await tester.enterText(field, '短\n');
      await tester.pump();
      checkLayout(expanded: true);
      await tester.tap(find.byTooltip('发送消息'));
      await tester.pump();
      expect(session.messages.last['text'], '短\n');
      expect(controller.text, isEmpty);
      checkLayout(expanded: false);
    });
  }

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
    expect(
      tester.getTopLeft(field).dx,
      greaterThanOrEqualTo(tester.getTopRight(find.byTooltip('添加附件')).dx),
    );
    expect(
      tester.getTopRight(field).dx,
      lessThanOrEqualTo(tester.getTopLeft(find.byTooltip('语音输入')).dx),
    );
    tester.view.resetViewInsets();
    await tester.pump();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionScreen), findsOneWidget);
    expect(find.text('记忆'), findsNothing);
    expect(find.text('通知'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('日程'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开月历'), findsOneWidget);
    expect(find.text('打开连接设置'), findsOneWidget);
    await tester.tap(find.text('对话'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field).controller,
      same(original.controller),
    );
    await tester.tap(find.text('日程'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '今晚吃点什么好呢？');
  });

  testWidgets('iOS 可从设置的通用分组进入记忆页', (tester) async {
    await _openChat(tester, platform: TargetPlatform.iOS);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionScreen), findsOneWidget);
    await tester.ensureVisible(find.text('记忆'));
    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    expect(find.text('示例记忆'), findsOneWidget);
  });

  testWidgets('新回复触发发言并保留对话历史', (tester) async {
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
    expect(find.text('之前的消息'), findsOneWidget);
  });
}
