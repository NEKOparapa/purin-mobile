import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

typedef Json = Map<String, dynamic>;

String newEventId() {
  final random = Random.secure();
  return base64Url.encode(List.generate(18, (_) => random.nextInt(256)));
}

class Connection {
  Connection(String address, String id, String secret)
    : url = address.trim().replaceFirst(RegExp(r'/+$'), ''),
      terminal = id.trim(),
      token = secret.trim() {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        terminal.isEmpty ||
        token.isEmpty ||
        !RegExp(r'^[!-~]+$').hasMatch(terminal) ||
        !RegExp(r'^[!-~]+$').hasMatch(token)) {
      throw const FormatException('请填写完整服务地址、终端 ID 和令牌');
    }
  }

  factory Connection.fromJson(Json data) =>
      Connection(data['url'], data['terminal'], data['token']);
  final String url;
  final String terminal;
  final String token;
  String get scope => jsonEncode([url, terminal]);
  Json toJson() => {'url': url, 'terminal': terminal, 'token': token};
}

class ApiError implements Exception {
  ApiError(this.status, this.code);
  final int status;
  final String code;
  @override
  String toString() => 'HTTP $status · $code';
}

class AgentApi {
  Future<Json> request(Connection connection, String path, {Json? body}) =>
      _request(connection, path, body: body);

  Future<Json> uploadScreenshot(
    Connection connection,
    Json record,
    String platform,
    Uint8List jpeg, {
    Future<void>? cancel,
  }) {
    final at = DateTime.fromMillisecondsSinceEpoch(
      record['at'] as int,
      isUtc: true,
    );
    final context = {
      'platform': platform,
      for (final key in ['app', 'package', 'start', 'activity_id'])
        if (record[key] != null) key: record[key],
    };
    return _request(
      connection,
      'image/slices',
      jpeg: jpeg,
      cancel: cancel,
      headers: {
        'X-Event-ID': record['id'] as String,
        'X-Occurred-At': at.toIso8601String(),
        'X-Capture-Context': base64Url.encode(utf8.encode(jsonEncode(context))),
      },
    );
  }

  Future<Json> _request(
    Connection connection,
    String path, {
    Json? body,
    Uint8List? jpeg,
    Map<String, String> headers = const {},
    Future<void>? cancel,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    if (cancel != null) cancel.then((_) => client.close(force: true));
    Future<Json> perform() async {
      final uri = Uri.parse('${connection.url}/v1/$path');
      final request = await client.openUrl(
        body == null && jpeg == null ? 'GET' : 'POST',
        uri,
      );
      request.followRedirects = false;
      request.headers.set('X-Terminal-ID', connection.terminal);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${connection.token}',
      );
      headers.forEach(request.headers.set);
      if (jpeg != null) {
        request.headers.contentType = ContentType('image', 'jpeg');
        request.contentLength = jpeg.length;
        request.add(jpeg);
      } else if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close();
      final raw = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String code = '请求失败';
        try {
          final value = jsonDecode(raw);
          if (value is Map && value['error'] is String) code = value['error'];
        } on FormatException {
          /* An upstream proxy may respond with HTML. */
        }
        throw ApiError(response.statusCode, code);
      }
      return jsonDecode(raw) as Json;
    }

    try {
      return await perform().timeout(Duration(seconds: jpeg == null ? 9 : 60));
    } finally {
      client.close(force: true);
    }
  }
}
