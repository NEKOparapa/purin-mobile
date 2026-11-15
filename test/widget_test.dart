import 'mobile_screenshots_test.dart' show TestScreenshots;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wintermute_mobile/main.dart';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/mobile_session.dart';
import 'package:wintermute_mobile/data/mobile_signals.dart';
import 'mobile_session_test.dart' show MeetingApi, MemoryStore;

class SettingsSignals extends MobileSignals {
  String location = 'denied';
  String usage = 'blocked';
  bool background = false;
  bool locationOn = false;
  final calls = <String>[];
  final records = <Json>[];

  @override
  Future<Json> configure(String scope, bool location, bool usage) async {
    locationOn = location;
    return {
      'location': this.location,
      'usage': this.usage,
      'backgroundLocation': background,
    };
  }

  @override
  Future<void> request(String source) async {
    calls.add('request $source');
    if (source == 'location') location = 'granted';
    if (source == 'backgroundLocation') background = true;
  }

  @override
  Future<void> settings(String source) async => calls.add('settings $source');

  @override
  Future<List<Json>> read(String scope) async =>
      locationOn && location == 'granted' ? List.of(records) : [];

  @override
  Future<void> ack(String scope, List<String> ids) async =>
      records.removeWhere((r) => ids.contains(r['id']));
}

void main() {
  testWidgets(
    'screen sharing settings request consent and change the interval',
    (tester) async {
      final native = TestScreenshots();
      final store = MemoryStore()
        ..saved = Connection('http://localhost', 'phone', 'test');
      final session = MobileSession(store, MeetingApi(), screenshots: native);
      await tester.pumpWidget(WintermuteApp(session: session));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('连接与采集'));
      await tester.pumpAndSettle();
      final toggle = find.widgetWithText(SwitchListTile, '定时截屏');
      await tester.dragUntilVisible(
        toggle,
        find.byType(ListView),
        const Offset(0, -250),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, false);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(native.prompts, 1);
      final interval = find.byType(DropdownButton<int>);
      await tester.drag(find.byType(ListView), const Offset(0, -350));
      await tester.pumpAndSettle();
      await tester.tap(interval);
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 分钟').last);
      await tester.pumpAndSettle();
      expect(native.interval, 60);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(native.active, false);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'offline appearance follows the OS or restores a fixed preference',
    (tester) async {
      final platform = tester.platformDispatcher;
      platform.platformBrightnessTestValue = Brightness.dark;
      addTearDown(platform.clearPlatformBrightnessTestValue);
      final store = MemoryStore();
      var session = MobileSession(store, MeetingApi());
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(Scaffold).last)).brightness;
      await tester.pumpWidget(WintermuteApp(session: session));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      await tester.tap(find.byTooltip('连接与采集'));
      await tester.pumpAndSettle();
      platform.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      expect(store.mode, ThemeMode.dark);
      await tester.pumpWidget(const SizedBox());
      session.dispose();

      session = MobileSession(store, MeetingApi());
      await tester.pumpWidget(WintermuteApp(session: session));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      await tester.tap(find.byTooltip('连接与采集'));
      await tester.pumpAndSettle();
      platform.platformBrightnessTestValue = Brightness.dark;
      await tester.tap(find.text('浅色'));
      await tester.pumpAndSettle();
      expect(store.mode, ThemeMode.light);
      expect(brightness(), Brightness.light);
      await tester.tap(find.text('跟随系统'));
      await tester.pumpAndSettle();
      expect(store.mode, ThemeMode.system);
      expect(brightness(), Brightness.dark);
      platform.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
      expect(store.saved, isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  for (final size in [
    const Size(360, 800),
    const Size(844, 390),
    const Size(1024, 1366),
  ]) {
    testWidgets(
      'disconnected chat and settings fit ${size.width} with enlarged text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        tester.view.padding = const FakeViewPadding(top: 32, bottom: 16);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final session = MobileSession(MemoryStore(), MeetingApi());
        await tester.pumpWidget(WintermuteApp(session: session));
        await tester.pumpAndSettle();
        expect(find.text('连接你的 Agent'), findsOneWidget);
        await tester.ensureVisible(find.text('设置连接'));
        await tester.tap(find.text('设置连接'));
        await tester.pumpAndSettle();
        expect(find.text('服务地址'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }

  testWidgets(
    'conversation, notifications and memory search remain reachable',
    (tester) async {
      final store = MemoryStore()
        ..saved = Connection('http://localhost', 'http-mobile', 'test');
      final api = MeetingApi()..failFirstSend = false;
      api.outputs.add({
        'output_id': 'reminder',
        'text': '会议提醒',
        'status': 'pending',
        'layer': 'notification',
      });
      api.history.add({
        'id': 'reminder',
        'role': 'assistant',
        'text': '会议提醒',
        'layer': 'notification',
      });
      final session = MobileSession(store, api);
      await tester.pumpWidget(WintermuteApp(session: session));
      await tester.pumpAndSettle();
      expect(find.text('后台通知'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '你好');
      await tester.pump();
      await tester.tap(find.byTooltip('发送消息'));
      await tester.pumpAndSettle();
      await session.sync();
      await tester.pumpAndSettle();
      expect(find.text('会议改到周五'), findsOneWidget);
      expect(find.byTooltip('写手记'), findsNothing);
      await tester.tap(find.byTooltip('连接与采集'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('记录应用活动'),
        find.byType(ListView),
        const Offset(0, -250),
      );
      expect(find.text('记录应用活动'), findsOneWidget);
      expect(find.text('写手记'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('浏览记忆'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '没有的条目');
      await tester.pumpAndSettle();
      expect(find.text('没有找到相关记忆。'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '专注');
      await tester.pumpAndSettle();
      await tester.tap(find.text('专注，也需要一些边界'));
      await tester.pumpAndSettle();
      expect(find.textContaining('尚未创建真实日程'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('你好'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'location and usage have independent switches and system access actions',
    (tester) async {
      final signals = SettingsSignals();
      signals.records.add({
        'id': 'first-fix',
        'source': 'location',
        'at': DateTime.now().millisecondsSinceEpoch,
        'lat': 22.2,
        'lon': 113.1,
        'accuracy': 12,
      });
      final store = MemoryStore()
        ..saved = Connection('http://localhost', 'http-mobile', 'test');
      final session = MobileSession(store, MeetingApi(), signals: signals);
      await tester.pumpWidget(WintermuteApp(session: session));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('连接与采集'));
      await tester.pumpAndSettle();
      Future<void> reveal(String text) async {
        await tester.dragUntilVisible(
          find.text(text),
          find.byType(ListView),
          const Offset(0, -180),
        );
        await tester.ensureVisible(find.text(text));
        await tester.pumpAndSettle();
      }

      Future<void> activate(String text) async {
        await reveal(text);
        await tester.tap(find.text(text));
        await tester.pumpAndSettle();
      }

      await activate('地点变化');
      expect(session.locationEnabled, isTrue);
      expect(session.usageEnabled, isFalse);
      expect(signals.calls, contains('request location'));
      await activate('允许后台定位');
      expect(signals.calls, contains('request backgroundLocation'));
      await activate('命名当前位置');
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '公司',
      );
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(session.placeNames, ['公司']);
      final remove = find.byTooltip('移除地点「公司」');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(session.placeNames, isEmpty);
      await activate('其他 App 使用时段');
      expect(session.usageEnabled, isTrue);
      await activate('打开系统设置');
      expect(signals.calls, contains('settings usage'));
      await activate('其他 App 使用时段');
      expect(session.locationEnabled, isTrue);
      expect(session.usageEnabled, isFalse);
      signals.usage = 'unsupported';
      session.foreground(false);
      session.foreground(true);
      await tester.pumpAndSettle();
      final usageTile = find.widgetWithText(SwitchListTile, '其他 App 使用时段');
      expect(tester.widget<SwitchListTile>(usageTile).onChanged, isNull);
      expect(find.textContaining('此项适用于 Android'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'small phone composer stays usable with keyboard and enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 236);
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final session = MobileSession(
        MemoryStore()
          ..saved = Connection('http://localhost', 'http-mobile', 'test'),
        MeetingApi(),
      );
      await tester.pumpWidget(WintermuteApp(session: session));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '给我会议决定\n以及接下来的安排。');
      await tester.pumpAndSettle();
      expect(
        tester.getBottomRight(find.byTooltip('发送消息')).dy,
        lessThan(568 - 236),
      );
      await tester.tap(find.byTooltip('发送消息'));
      await tester.pumpAndSettle();
      expect(find.text('重试发送'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
