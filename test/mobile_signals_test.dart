import 'package:flutter_test/flutter_test.dart';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/mobile_session.dart';
import 'package:wintermute_mobile/data/mobile_signals.dart';
import 'mobile_session_test.dart' show MeetingApi, MemoryStore;

class _Native extends MobileSignals {
  final rows = <Json>[];
  bool failAck = false;
  String location = 'granted', usage = 'granted';
  String? scope;

  @override
  Future<Json> configure(String scope, bool location, bool usage) async {
    if (this.scope != null && this.scope != scope) rows.clear();
    this.scope = scope;
    rows.removeWhere((r) => r['source'] == 'location' ? !location : !usage);
    return {
      'location': this.location,
      'usage': this.usage,
      'backgroundLocation': false,
    };
  }

  @override
  Future<List<Json>> read(String scope) async => List.of(rows);
  @override
  Future<void> ack(String scope, List<String> ids) async {
    if (failAck) throw StateError('interrupted before native acknowledgement');
    rows.removeWhere((r) => ids.contains(r['id']));
  }
}

void main() {
  final now = DateTime.now().toUtc().subtract(const Duration(seconds: 12));
  Json fix(
    String id,
    int seconds,
    double lat, {
    String kind = 'fix',
    double accuracy = 15,
  }) => {
    'id': id,
    'at': now.millisecondsSinceEpoch + seconds * 1000,
    'source': 'location',
    'lat': lat,
    'lon': 121.47372,
    'accuracy': accuracy,
    'kind': kind,
  };
  Json usage() => {
    'id': 'usage-event',
    'source': 'usage',
    'label': '会议 App',
    'package': 'test.meeting',
    'start': now.millisecondsSinceEpoch - 60000,
    'end': now.millisecondsSinceEpoch,
    'at': now.millisecondsSinceEpoch,
  };
  final terminal = Connection('http://localhost', 'signals', 'test');

  test(
    'named places stay local, preserve arrival and departure, and coalesce repeated fixes',
    () async {
      final store = MemoryStore()..saved = terminal;
      final api = MeetingApi();
      final native = _Native();
      final session = MobileSession(store, api, signals: native);
      addTearDown(session.dispose);
      await session.initialize();
      await session.setSignalEnabled('location', true);
      native.rows.add(fix('f1', 0, 31.23042));
      await session.sync();
      expect(session.canNameLocation, isTrue);
      await session.nameCurrentLocation('公司');
      native.rows.addAll([
        fix('jitter', 1, 31.23043),
        fix('uncertain', 2, 31.232, accuracy: 500),
        fix('away', 3, 31.31),
      ]);
      await session.sync();
      expect(api.captures.map((r) => r['value']), [
        '所在区域约 31.23, 121.47',
        '到达「公司」',
        '离开「公司」，所在区域约 31.31, 121.47',
      ]);
      expect(api.captures.toString(), isNot(contains('121.47372')));
      await session.setSignalEnabled('location', false);
      expect(session.canNameLocation, isFalse);
      expect(session.lastLocationLabel, isNull);
      expect(session.placeNames, ['公司']);
      await session.removePlace('公司');
      expect(session.placeNames, isEmpty);
    },
  );

  test(
    'offline app spans keep their IDs and survive process death between native read and ack',
    () async {
      final native = _Native()..failAck = true;
      final api = MeetingApi()..failUpload = true;
      final store = MemoryStore()..saved = terminal;
      var session = MobileSession(store, api, signals: native);
      await session.initialize();
      await session.setSignalEnabled('usage', true);
      native.rows.add(usage());
      await session.sync();
      final recorded = api.captures.single;
      expect(recorded['path'], 'slices');
      expect(recorded['text'], contains('约 60 秒'));
      expect(recorded['text'], contains('会议 App'));
      await session.setCollecting(false);
      expect(session.pending.length, 1);
      session.dispose();
      api.failUpload = native.failAck = false;
      session = MobileSession(store, api, signals: native);
      addTearDown(session.dispose);
      await session.initialize();
      expect(api.captures, [recorded, recorded]);
      expect(session.pending, isEmpty);
      expect(native.rows, isEmpty);
    },
  );

  test(
    'revoking location before retry preserves usage and isolates terminal history',
    () async {
      final native = _Native();
      final api = MeetingApi()..failUpload = true;
      final store = MemoryStore()..saved = terminal;
      final session = MobileSession(store, api, signals: native);
      addTearDown(session.dispose);
      await session.initialize();
      await session.setSignalEnabled('location', true);
      await session.setSignalEnabled('usage', true);
      native.rows.addAll([fix('area', 0, 31.23042), usage()]);
      await session.sync();
      expect(session.pending.length, 2);
      api.failUpload = false;
      api.captures.clear();
      native.location = 'blocked';
      await session.sync();
      expect(api.captures.single['event_id'], 'usage-event');
      expect(session.lastLocationLabel, isNull);
      await session.configure(
        Connection('http://localhost', 'another', 'test'),
      );
      expect(session.locationEnabled, isFalse);
      expect(session.usageEnabled, isFalse);
      expect(session.lastUsageLabel, isNull);
    },
  );
}
