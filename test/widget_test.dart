import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wintermute_mobile/main.dart';

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(844, 390),
    const Size(1024, 1366),
  ]) {
    testWidgets('home fits $size with enlarged text and safe area', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(1.3),
              padding: const EdgeInsets.only(top: 44, bottom: 34),
            ),
            child: const WintermuteApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('慢慢来，我一直在。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('search, details, navigation and mock conversation work', (
    tester,
  ) async {
    await tester.pumpWidget(const WintermuteApp());
    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不存在的关键词');
    await tester.pumpAndSettle();
    expect(find.textContaining('没有找到相关记忆'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '专注');
    await tester.pumpAndSettle();
    await tester.tap(find.text('专注，也需要一些边界'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未创建真实日程'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('聊一聊今天'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '你好');
    await tester.tap(find.byTooltip('发送消息'));
    await tester.pumpAndSettle();
    expect(find.text('你好'), findsOneWidget);
    expect(find.text('Wintermute · 模拟回复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
