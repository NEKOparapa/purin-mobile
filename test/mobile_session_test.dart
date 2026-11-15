import 'dart:convert';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/mobile_session.dart';
import 'package:wintermute_mobile/data/mobile_store.dart';

class MemoryStore implements MobileStore {
  ThemeMode mode = ThemeMode.system;
  @override
  Future<ThemeMode> readTheme() async => mode;
  @override
  Future<void> saveTheme(ThemeMode value) async => mode = value;
  Connection? saved;
  final histories = <String, String>{};
  @override
  Future<Connection?> connection() async => saved;
  @override
  Future<void> saveConnection(Connection value) async => saved = value;
  @override
  Future<Json> history(String scope) async =>
      jsonDecode(histories[scope] ?? '{}');
  @override
  Future<void> saveHistory(String scope, Json value) async =>
      histories[scope] = jsonEncode(value);
}

class MeetingApi extends AgentApi {
  bool failFirstSend = true;
  bool failUpload = false;
  final submissions = <Json>[];
  final captures = <Json>[];
  final outputs = <Json>[];
  final history = <Json>[];
  bool legacy = false;
  bool historyOffline = false;
  int historyRequests = 0;
  void Function()? onAck;
  @override
  Future<Json> request(Connection connection, String path, {Json? body}) async {
    if (path.startsWith('history?')) {
      historyRequests++;
      if (historyOffline) throw ApiError(503, 'offline');
      final query = Uri.parse(path).queryParameters;
      final view = query['view'];
      if (view == 'dialogue' && legacy) throw ApiError(400, 'invalid_query');
      final rows = history.reversed
          .where(
            (row) =>
                (row['scope'] == null || row['scope'] == connection.scope) &&
                (view == 'dialogue' || row['layer'] == view),
          )
          .toList();
      final start = int.parse(query['cursor'] ?? '0');
      const size = 2;
      return {
        'items': rows.skip(start).take(size).toList(),
        'next_cursor': start + size < rows.length ? '${start + size}' : null,
      };
    }
    if (path.startsWith('outputs?')) {
      return {
        'outputs': outputs.where((o) => o['status'] == 'pending').toList(),
      };
    }
    if (path == 'messages') {
      submissions.add(body!);
      if (failFirstSend) {
        failFirstSend = false;
        throw ApiError(503, 'timeout');
      }
      outputs.add({
        'output_id': 'reply-1',
        'text': '会议改到周五',
        'status': 'pending',
      });
      history.addAll([
        {
          'id': 'evt-1',
          'role': 'user',
          'text': body['text'],
          'message_id': body['message_id'],
          'terminal_id': connection.terminal,
          'scope': connection.scope,
          'layer': 'conversation',
        },
        {
          'id': 'reply-1',
          'role': 'assistant',
          'text': '会议改到周五',
          'scope': connection.scope,
          'layer': 'conversation',
        },
      ]);
      return {'event_id': 'evt-1', 'job_id': 'job-1'};
    }
    if (path == 'jobs/job-1') {
      return {'status': 'completed', 'outputs': outputs};
    }
    if (path.startsWith('outputs/') && path.endsWith('/ack')) {
      onAck?.call();
      outputs.singleWhere(
        (o) => o['output_id'] == path.split('/')[1],
      )['status'] = 'delivered';
      return {'status': 'delivered'};
    }
    if (path == 'perceptions' || path == 'slices') {
      captures.add({'path': path, ...body!});
      if (failUpload) throw ApiError(503, 'offline');
      return {'event_id': 'server-id', 'duplicate': false};
    }
    throw StateError('unexpected path $path');
  }
}

void main() {
  test(
    'new pages join the known tail and a new database replaces the entire list',
    () async {
      final api = MeetingApi();
      Json row(int i) => {'id': 'evt-$i', 'role': 'user', 'text': 'row $i'};
      api.history.addAll(List.generate(9, row));
      final store = MemoryStore()
        ..saved = Connection('https://local.test', 'phone', 'test');
      final session = MobileSession(store, api);
      addTearDown(session.dispose);
      await session.initialize();
      expect(api.historyRequests, 5);
      api.history.addAll([row(9), row(10), row(11)]);
      api.historyRequests = 0;
      await session.sync();
      expect(api.historyRequests, 2);
      expect(
        session.messages.map((m) => m['id']),
        List.generate(12, (i) => 'evt-$i'),
      );
      api.history
        ..clear()
        ..addAll([row(20), row(21), row(22)]);
      api.historyRequests = 0;
      await session.sync();
      expect(api.historyRequests, 2);
      expect(session.messages.map((m) => m['id']), [
        'evt-20',
        'evt-21',
        'evt-22',
      ]);
    },
  );
  for (final legacy in [false, true]) {
    test(
      'self-reminder without inbox delivery and backend reset (legacy=$legacy)',
      () async {
        final api = MeetingApi()..legacy = legacy;
        final store = MemoryStore()
          ..saved = Connection('https://local.test', 'phone', 'test');
        final session = MobileSession(store, api);
        addTearDown(session.dispose);
        await session.initialize();
        api.history.addAll([
          {
            'id': 'external',
            'role': 'user',
            'text': '桌面发言',
            'layer': 'conversation',
            'occurred_at': '2026-11-16T10:00:00Z',
          },
          {
            'id': 'reminder',
            'role': 'assistant',
            'text': '十分钟到了',
            'layer': 'notification',
            'occurred_at': '2026-11-16T10:10:00Z',
          },
          if (legacy)
            for (var i = 0; i < 7; i++)
              {
                'id': 'internal-$i',
                'role': 'user',
                'text': '通知正文',
                'layer': 'notification',
                'occurred_at': '2026-11-16T10:11:00Z',
              },
        ]);
        await session.sync();
        expect(session.messages.map((m) => m['text']), ['桌面发言', '十分钟到了']);
        await session.sync();
        expect(session.messages.length, 2);
        expect(api.outputs, isEmpty);
        api.history.clear();
        api.historyOffline = true;
        await session.sync();
        expect(session.error, contains('offline'));
        expect(session.messages.length, 2);
        api.historyOffline = false;
        await session.sync();
        expect(session.error, isNull);
        expect(session.messages, isEmpty);
      },
    );
  }
  test(
    'server identity resolves a lost POST receipt and preserves unrelated equal drafts',
    () async {
      final api = MeetingApi();
      final store = MemoryStore()
        ..saved = Connection('https://local.test', 'phone', 'test');
      final session = MobileSession(store, api);
      addTearDown(session.dispose);
      await session.initialize();
      await session.send('相同正文');
      final id = api.submissions.single['message_id'];
      api.history.add({
        'id': 'remote',
        'text': '相同正文',
        'role': 'user',
        'message_id': id,
        'terminal_id': 'desktop',
      });
      await session.sync();
      expect(session.messages.length, 2);
      api.history.add({
        'id': 'own',
        'text': '相同正文',
        'role': 'user',
        'message_id': id,
        'terminal_id': 'phone',
      });
      await session.sync();
      expect(session.messages.map((m) => m['id']), ['remote', 'own']);
      expect((await store.history(store.saved!.scope))['outgoing'], isEmpty);
      expect(api.submissions.length, 1);
    },
  );
  test(
    'a process stopped before its POST receipt can retry the persisted id',
    () async {
      final api = MeetingApi()..failFirstSend = false;
      final store = MemoryStore()
        ..saved = Connection('https://local.test', 'http-mobile', 'test');
      await store.saveHistory(store.saved!.scope, {
        'messages': [
          {
            'id': 'interrupted-id',
            'role': 'user',
            'text': '会议',
            'status': 'sending',
          },
        ],
      });
      final session = MobileSession(store, api);
      await session.initialize();
      expect(session.messages.single['status'], 'unsent');
      await session.retry(session.messages.single);
      expect(api.submissions.single['message_id'], 'interrupted-id');
      session.dispose();
    },
  );
  test(
    'retries the original message, reads server history before ACK, and switches scopes',
    () async {
      final api = MeetingApi();
      final store = MemoryStore();
      final connection = Connection(
        'http://localhost:8000',
        'http-mobile',
        'test',
      );
      await store.saveConnection(connection);
      var session = MobileSession(store, api);
      await session.initialize();
      await session.send('会议改到哪天？');
      expect(session.messages.single['status'], 'unsent');
      session.dispose();
      session = MobileSession(store, api);
      await session.initialize();
      await session.retry(session.messages.single);
      expect(api.submissions.first, equals(api.submissions.last));
      api.onAck = () =>
          expect(session.messages.map((row) => row['id']), contains('reply-1'));
      await session.sync();
      expect(session.messages.map((m) => m['text']), ['会议改到哪天？', '会议改到周五']);
      expect(session.messages.first['id'], 'evt-1');
      expect(store.histories[connection.scope], isNot(contains('会议改到周五')));
      expect(
        await session.configure(
          Connection('http://elsewhere', 'another', 'test'),
        ),
        true,
      );
      expect(session.messages, isEmpty);
      session.dispose();
    },
  );

  test(
    'opt-in state changes retain their ids and times across an offline restart',
    () async {
      final api = MeetingApi();
      final store = MemoryStore()
        ..saved = Connection('http://localhost:8000', 'http-mobile', 'test');
      var session = MobileSession(store, api);
      await session.initialize();
      session.page('记忆');
      await session.sync();
      expect(api.captures, isEmpty);
      await session.setCollecting(true);
      session.page('Agent 对话');
      session.page('Agent 对话');
      session.foreground(false);
      await session.setCollecting(false);
      session.page('设备');
      await session.sync();
      expect(api.captures.map((m) => m['value']), [
        '前台 · 记忆',
        '前台 · Agent 对话',
        '后台',
      ]);
      session.page('主页');
      session.foreground(true);
      api.failUpload = true;
      await session.setCollecting(true);
      expect(session.pending.length, 1);
      expect(DateTime.parse(api.captures.last['occurred_at']).isUtc, true);
      final attempt = api.captures.last;
      session.dispose();
      api.failUpload = false;
      session = MobileSession(store, api);
      await session.initialize();
      expect(api.captures.last, attempt);
      expect(session.pending, isEmpty);
      expect(session.collecting, true);
      api.failUpload = true;
      session.page('记忆');
      await session.setCollecting(false);
      expect(session.pending, isEmpty);
      expect(session.collecting, false);
      session.dispose();
    },
  );

  test(
    'restoring a terminal discards its queued notes before any upload',
    () async {
      final connection = Connection(
        'https://local.test',
        'http-mobile',
        'test',
      );
      final store = MemoryStore()..saved = connection;
      final message = {'id': 'message-1', 'role': 'user', 'text': '会议笔记'};
      final perception = {
        'path': 'perceptions',
        'body': {
          'state_key': 'mobile.app_activity',
          'value': '后台',
          'event_id': 'activity-1',
          'occurred_at': '2026-11-01T11:00:00Z',
        },
      };
      final oldNote = {
        'path': 'slices',
        'body': {
          'text': '旧版待传手记',
          'event_id': 'note-1',
          'occurred_at': '2026-11-01T10:00:00Z',
        },
      };
      await store.saveHistory(connection.scope, {
        'messages': [message],
        'collecting': true,
        'lastActivity': '前台 · 主页',
        'pending': [oldNote, perception],
      });
      final api = MeetingApi()..failUpload = true;
      final session = MobileSession(store, api);
      addTearDown(session.dispose);
      await session.initialize();
      final restored = await store.history(connection.scope);
      expect(restored.containsKey('messages'), false);
      expect(session.messages, isEmpty);
      expect(restored['pending'], [perception]);
      api.failUpload = false;
      await session.sync();
      expect(
        api.captures.map((item) => item['path']),
        everyElement('perceptions'),
      );
      expect(api.captures.last['event_id'], 'activity-1');
      expect(session.pending, isEmpty);
    },
  );
}
