import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purin_mobile/data/agent_api.dart';
import 'package:purin_mobile/data/mobile_session.dart';
import 'package:purin_mobile/data/mobile_store.dart';
import 'package:purin_mobile/l10n/app_language.dart';
import 'package:purin_mobile/main.dart';

class _Preferences extends DeviceStore {
  AppLanguage saved = AppLanguage.chinese;

  @override
  Future<ThemeMode> readTheme() async => ThemeMode.light;

  @override
  Future<AppLanguage> readLanguage() async => saved;

  @override
  Future<void> saveLanguage(AppLanguage language) async => saved = language;
}

class _OfflineSession extends MobileSession {
  _OfflineSession(MobileStore store) : super(store, AgentApi());

  @override
  Future<void> initialize() async {
    ready = true;
    installation = 'test-phone';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'device language survives a new store and falls back for unknown values',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'purin-language-',
      );
      addTearDown(() => directory.delete(recursive: true));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getApplicationSupportDirectory');
        return directory.path;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect((await getApplicationSupportDirectory()).path, directory.path);
      final store = DeviceStore();
      expect(await store.readLanguage(), AppLanguage.chinese);
      await store.saveLanguage(AppLanguage.english);
      await store.saveTheme(ThemeMode.dark);
      expect(await DeviceStore().readLanguage(), AppLanguage.english);
      await File('${directory.path}/language').writeAsString('unsupported');
      expect(await DeviceStore().readLanguage(), AppLanguage.chinese);
      expect(await DeviceStore().readTheme(), ThemeMode.dark);
    },
  );

  testWidgets(
    'switch language in settings, keep the draft and restore on restart',
    (tester) async {
      final store = _Preferences();
      final session = _OfflineSession(store);
      tester.view.physicalSize = const Size(390, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(PurinApp(session: session));
      await tester.pumpAndSettle();
      await tester.tap(find.text('聊聊今天'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('English'));
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('App settings'), findsOneWidget);
      expect(store.saved, AppLanguage.english);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Device pairing'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '我想跟你聊聊今天发生的事。',
      );
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      session.dispose();
      final restored = _OfflineSession(store);
      await tester.pumpWidget(PurinApp(session: restored));
      await tester.pumpAndSettle();
      expect(find.text('How was your day?'), findsOneWidget);
      expect(
        Localizations.localeOf(tester.element(find.byType(TextField))),
        const Locale('en'),
      );
      await restored.setLanguage(AppLanguage.chinese);
      await tester.pumpAndSettle();
      expect(find.text('今天过得怎么样？'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      restored.dispose();
    },
  );
}
