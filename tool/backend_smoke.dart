// Run by Wintermute/tools/check_clients.py using the standalone Dart SDK.
import 'dart:convert';
import 'dart:io';
import 'package:wintermute_mobile/data/agent_api.dart';
import 'package:wintermute_mobile/data/chat_history.dart';
import 'package:wintermute_mobile/data/question.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final url = Platform.environment['WINTERMUTE_TEST_URL'];
  check(url != null, 'Run through the backend tools/check_clients.py fixture');
  final connection = Connection(url!, 'mobile-test', 'test-token-mobile-test');
  // An API suffix used as a service root used to produce /v1/v1/... and HTTP 404.
  for (final suffix in ['/v1', '/v1/', '/unexpected/path']) {
    var rejected = false;
    try {
      Connection('$url$suffix', 'mobile-test', 'test-token-mobile-test');
    } on FormatException {
      rejected = true;
    }
    check(rejected, 'Non-root service address must be rejected: $suffix');
  }
  check(
    Connection('$url/', 'mobile-test', 'token').url == url,
    'A trailing slash must normalize to the service root',
  );
  final api = AgentApi();
  final body = {'message_id': 'mobile-smoke-message', 'text': 'mobile hello'};
  final receipt = await api.request(connection, 'messages', body: body);
  final duplicate = await api.request(connection, 'messages', body: body);
  check(
    duplicate['duplicate'] == true && duplicate['job_id'] == receipt['job_id'],
    'Message retries must be idempotent',
  );
  Json job = {};
  for (var attempt = 0; attempt < 100; attempt++) {
    job = await api.request(connection, 'jobs/${receipt['job_id']}');
    if (job['status'] == 'completed') break;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  check(job['status'] == 'completed', 'Mobile job must complete');
  final output = (job['outputs'] as List).first as Json;
  check(output['text'] == 'smoke reply', 'Output response shape changed');
  await api.request(connection, 'outputs/${output['output_id']}/ack', body: {});
  final history = await ChatHistory().read(api, connection);
  check(
    history.any((row) => row['text'] == 'mobile hello'),
    'Missing mobile input',
  );
  check(
    history.any((row) => row['text'] == 'desktop hello'),
    'Shared conversation was lost',
  );

  final stamp = DateTime.now().toUtc().toIso8601String();
  await api.request(
    connection,
    'perceptions',
    body: {
      'event_id': 'mobile-perception',
      'occurred_at': stamp,
      'state_key': 'mobile.location',
      'value': '到达公司',
    },
  );
  await api.request(
    connection,
    'slices',
    body: {
      'event_id': 'mobile-usage',
      'occurred_at': stamp,
      'text': '阅读文档 10 分钟',
    },
  );
  final screenshot = await api.uploadScreenshot(
    connection,
    {
      'id': '11111111-1111-4111-8111-111111111111',
      'at': DateTime.now().millisecondsSinceEpoch,
      'app': 'Contract Test',
      'package': 'dev.wintermute.test',
    },
    'android',
    base64Decode(Platform.environment['WINTERMUTE_TEST_JPEG']!),
  );
  check(screenshot['event_id'] is String, 'Screenshot upload failed');

  final page = await api.request(connection, 'notifications?limit=20');
  final notice = (page['items'] as List).cast<Json>().firstWhere(
    (row) => row['title'] == 'smoke-mobile-test',
  );
  await api.request(
    connection,
    'notifications/${notice['id']}/received',
    body: {},
  );
  await api.request(connection, 'notifications/${notice['id']}/read', body: {});
  final questions = await api.request(
    connection,
    'questions?status=pending&limit=20',
  );
  final question = (questions['items'] as List)
      .cast<Json>()
      .map(PendingQuestion.fromJson)
      .firstWhere((row) => row.title == 'smoke-mobile-test');
  check(question.options.contains('继续'), 'Question options changed');
  final answered = await api.request(
    connection,
    'questions/${question.id}/answer',
    body: {
      'selected_options': ['继续'],
      'answer_text': '',
    },
  );
  check(answered['status'] == 'answered', 'Question answer was not saved');
  final claim = await api.request(
    connection,
    'terminal-tools/claim',
    body: {
      'tools': ['device_status'],
    },
  );
  final call = claim['call'] as Json;
  check(call['tool'] == 'device_status', 'Wrong remote tool');
  await api.request(
    connection,
    'terminal-tools/${call['id']}/result',
    body: {
      'claim_token': call['claim_token'],
      'status': 'succeeded',
      'stdout': '{}',
      'stderr': '',
      'exit_code': 0,
      'truncated': false,
    },
  );
  try {
    await api.request(
      Connection(url, 'mobile-test', 'incorrect'),
      'outputs?limit=1',
    );
    throw StateError('Invalid credentials were accepted');
  } on ApiError catch (error) {
    check(
      error.status == 401,
      'Unexpected authentication status: ${error.status}',
    );
  }
  stdout.writeln(
    'Mobile: chat, shared history, perception, slices, JPEG, notifications, questions, tools OK',
  );
}
