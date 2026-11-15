import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wintermute_mobile/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('AGENT_TEST_URL');
  const token = String.fromEnvironment('AGENT_TEST_TOKEN');
  const terminal = String.fromEnvironment(
    'AGENT_TEST_TERMINAL',
    defaultValue: 'http-mobile',
  );
  const expected = String.fromEnvironment('AGENT_EXPECT_REPLY');

  testWidgets(
    'mobile meeting against a configured Wintermute service',
    (tester) async {
      Future<void> waitFor(Finder finder) async {
        final until = DateTime.now().add(const Duration(seconds: 50));
        while (finder.evaluate().isEmpty && DateTime.now().isBefore(until)) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(finder, findsWidgets);
      }

      await tester.pumpWidget(const WintermuteApp());
      await tester.tap(find.byTooltip('连接与采集'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), url);
      await tester.enterText(fields.at(1), terminal);
      await tester.enterText(fields.at(2), token);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('验证并保存'));
      await tester.tap(find.text('验证并保存'));
      await waitFor(find.text('已验证并保存连接'));

      final toggle = find.widgetWithText(SwitchListTile, '记录应用活动');
      await tester.ensureVisible(toggle);
      if (!tester.widget<SwitchListTile>(toggle).value) {
        await tester.tap(toggle);
      }
      await waitFor(find.textContaining('最近上传'));
      expect(find.textContaining('采集上传失败'), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      const question = '会上决定周五演示。请确认演示是哪一天。';
      await tester.enterText(find.byType(TextField), question);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('发送消息'));
      await waitFor(find.text(question));
      if (expected.isNotEmpty) await waitFor(find.textContaining(expected));
      await waitFor(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data != question,
        ),
      );
    },
    skip: url.isEmpty || token.isEmpty,
  );
}
