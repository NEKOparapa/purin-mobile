import 'package:flutter_test/flutter_test.dart';
import 'package:wintermute_mobile/data/agent_api.dart';

void main() {
  test('扫码和粘贴只接受完整的 HTTPS 配对链接', () {
    const target = (url: 'https://unit.test:8443', code: '1234567890');
    expect(
      pairingAddress(' https://unit.test:8443/#wm-pair=12345-67890 '),
      target,
    );
    for (final input in [
      '1234567890',
      '12345-67890',
      'https://unit.test/',
      'http://unit.test/#wm-pair=12345-67890',
      'https://unit.test/admin#wm-pair=12345-67890',
      'https://unit.test/#wm-pair=12345-6789',
    ]) {
      expect(pairingAddress(input), isNull);
    }
  });
}
