import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purin_mobile/data/agent_api.dart';
import 'package:purin_mobile/data/mobile_connectors.dart';
import 'package:purin_mobile/data/mobile_session.dart';
import 'package:purin_mobile/data/mobile_store.dart';
import 'package:purin_mobile/data/mobile_terminal_tools.dart';
import 'package:purin_mobile/screens/mobile_connectors_screen.dart';
import 'package:purin_mobile/widgets/app_theme.dart';

class _Connectors extends MobileConnectors {
  _Connectors([super.platform = ConnectorPlatform.android]);
  final granted = <String>{'calendar'};

  @override
  Future<Map<String, bool>> access(String scope) async => {
    for (final key in granted) key: true,
  };

  @override
  Future<bool> authorize(MobileConnector item, String scope) async {
    if (item.platform != platform) return false;
    granted.add(item.key);
    return true;
  }
}

class _MemoryStore implements MobileStore {
  final scopes = <String, Json>{};
  Connection? savedConnection;

  @override
  Future<String> installationId() async => 'test-install';

  @override
  Future<ThemeMode> readTheme() async => ThemeMode.system;

  @override
  Future<void> saveTheme(ThemeMode mode) async {}

  @override
  Future<Connection?> connection() async => savedConnection;

  @override
  Future<void> saveConnection(Connection value) async =>
      savedConnection = value;

  @override
  Future<Json> history(String scope) async => scopes[scope] ?? {};

  @override
  Future<void> saveHistory(String scope, Json value) async =>
      scopes[scope] = value;
}

class _Api extends AgentApi {
  final claims = <List<String>>[];
  @override
  Future<Json> request(Connection conn, String path, {Json? body}) async {
    if (path == 'terminal-tools/claim') {
      claims.add(List<String>.from(body!['tools']));
      return {'call': null};
    }
    expect(path, 'connectors/device-sync');
    return {};
  }
}

void main() {
  test('旧版设备状态授权在同步时撤回，保留已选连接器', () async {
    final conn = Connection('https://example.test', 'phone', 'test');
    final connectors = _Connectors();
    for (final selected in [
      <String>[],
      ['android_calendar'],
    ]) {
      final api = _Api();
      final tools = MobileTerminalTools({
        'enabled': true,
        'connectors': selected,
      }, connectors.platform);
      await tools.poll(api, conn, connectors, () async {}, () => true);
      expect(
        api.claims.single,
        selected.isEmpty ? isEmpty : equals(MobileConnector.calendar.tools),
      );
      expect(tools.toJson(), isNot(contains('enabled')));
      expect(tools.toJson()['withdraw'], false);
    }
  });

  testWidgets('Android 设备同时展示 Android 与 iOS 连接器，仅可启用 Android 连接器', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.reset);

    final api = _Api();
    final session = MobileSession(
      _MemoryStore(),
      api,
      connectors: _Connectors(ConnectorPlatform.android),
    )..connection = Connection('https://example.test', 'pixel', 'secret');
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: terminalTheme(lightColors),
        home: MobileConnectorsScreen(session: session),
      ),
    );

    expect(find.text('Android'), findsOneWidget);
    expect(find.text('iOS'), findsOneWidget);
    expect(find.text('仅限 iOS 设备'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Android')).dy,
      lessThan(tester.getTopLeft(find.text('iOS')).dy),
    );
    expect(find.text('安卓日历'), findsOneWidget);
    expect(find.text('Apple Health'), findsOneWidget);

    await tester.tap(find.text('Apple Health'));
    await tester.pumpAndSettle();
    expect(find.text('此连接器仅可在 iOS 设备上启用。'), findsOneWidget);
    final iosEnableBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '启用连接器'),
    );
    expect(iosEnableBtn.onPressed, isNull);
    expect(
      await session.setMobileConnector(MobileConnector.iosHealth, true),
      '此连接器仅可在 iOS 设备上启用。',
    );
    expect(session.connectorEnabled(MobileConnector.iosHealth), isFalse);

    Navigator.of(tester.element(find.text('此连接器仅可在 iOS 设备上启用。'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('安卓日历'));
    await tester.pumpAndSettle();
    final androidEnableBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '启用连接器'),
    );
    expect(androidEnableBtn.onPressed, isNotNull);
    await tester.tap(find.widgetWithText(FilledButton, '启用连接器'));
    await tester.pumpAndSettle();
    expect(session.connectorEnabled(MobileConnector.calendar), isTrue);
  });

  testWidgets('iOS 设备同时展示 iOS 与 Android 连接器，仅可启用 iOS 连接器', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.reset);

    final api = _Api();
    final session = MobileSession(
      _MemoryStore(),
      api,
      connectors: _Connectors(ConnectorPlatform.ios),
    )..connection = Connection('https://example.test', 'iphone', 'secret');
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: terminalTheme(lightColors),
        home: MobileConnectorsScreen(session: session),
      ),
    );

    expect(find.text('iOS'), findsOneWidget);
    expect(find.text('Android'), findsOneWidget);
    expect(find.text('仅限 Android 设备'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('iOS')).dy,
      lessThan(tester.getTopLeft(find.text('Android')).dy),
    );
    expect(find.text('Apple Calendar'), findsOneWidget);
    expect(find.text('闹钟和计时器'), findsOneWidget);

    await tester.tap(find.text('闹钟和计时器'));
    await tester.pumpAndSettle();
    expect(find.text('此连接器仅可在 Android 设备上启用。'), findsOneWidget);
    final androidEnableBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '启用连接器'),
    );
    expect(androidEnableBtn.onPressed, isNull);
    expect(
      await session.setMobileConnector(MobileConnector.clock, true),
      '此连接器仅可在 Android 设备上启用。',
    );
    expect(session.connectorEnabled(MobileConnector.clock), isFalse);

    Navigator.of(tester.element(find.text('此连接器仅可在 Android 设备上启用。'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apple Calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '启用连接器'));
    await tester.pumpAndSettle();
    expect(session.connectorEnabled(MobileConnector.iosCalendar), isTrue);
  });
}
