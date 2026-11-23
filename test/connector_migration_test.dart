import 'package:flutter_test/flutter_test.dart';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/mobile_connectors.dart';
import 'package:wintermute_mobile/data/mobile_terminal_tools.dart';

class _Connectors extends MobileConnectors {
  @override
  ConnectorPlatform get platform => ConnectorPlatform.android;

  @override
  Future<Map<String, bool>> access(String scope) async => {'calendar': true};
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
}
