import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

typedef Json = Map<String, dynamic>;

String newEventId() {
  final random = Random.secure();
  return base64Url.encode(List.generate(18, (_) => random.nextInt(256)));
}

enum DevicePlatform {
  android('Android'),
  ios('iOS');

  const DevicePlatform(this.label);
  final String label;

  static DevicePlatform? get current => switch (Platform.operatingSystem) {
    'android' => android,
    'ios' => ios,
    _ => null,
  };
}

class Connection {
  Connection(
    String address,
    String id,
    String secret, {
    this.installation,
    String? name,
  }) : url = address.trim().replaceFirst(RegExp(r'/+$'), ''),
       deviceId = id.trim(),
       deviceName = (name ?? defaultDeviceName).trim(),
       token = secret.trim() {
    if (deviceName.isEmpty ||
        deviceName.runes.length > 80 ||
        RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(deviceName)) {
      throw const FormatException('请输入 1 至 80 个字符的设备名称');
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        deviceId.isEmpty ||
        token.isEmpty ||
        !RegExp(r'^[!-~]+$').hasMatch(deviceId) ||
        !RegExp(r'^[!-~]+$').hasMatch(token)) {
      throw const FormatException('请填写服务根地址（不带 /v1 或其他路径）、设备 ID 和令牌');
    }
  }

  factory Connection.fromJson(Json data) => Connection(
    data['url'],
    data['deviceId'] ?? data['terminal'],
    data['token'],
    installation: data['installation'],
    name: data['deviceName'],
  );
  static String get defaultDeviceName =>
      DevicePlatform.current == DevicePlatform.ios ? 'iOS 设备' : 'Android 手机';
  final String? installation;
  final String deviceName;
  final DevicePlatform? devicePlatform = DevicePlatform.current;
  void identify(HttpHeaders headers) {
    headers.set('X-Device-ID', deviceId);
    if (installation != null) {
      headers.set('X-Device-Instance', installation!);
      headers.set('X-Device-Name', base64.encode(utf8.encode(deviceName)));
      final platform = devicePlatform;
      if (platform != null) headers.set('X-Device-Platform', platform.name);
    }
  }

  final String url;
  final String deviceId;
  final String token;
  String get scope => jsonEncode([url, deviceId]);
  Json toJson() => {
    'url': url,
    'deviceId': deviceId,
    'token': token,
    'installation': installation,
    'deviceName': deviceName,
  };
}

class ApiError implements Exception {
  ApiError(this.status, this.code);
  final int status;
  final String code;
  @override
  String toString() => code == 'device_id_in_use'
      ? '此设备 ID 已绑定其他设备，请为本机登记独立的设备 ID'
      : 'HTTP $status · $code';
}

class AgentApi {
  Future<Uint8List> chatImage(Connection connection, String id) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    Future<Uint8List> load() async {
      final uri = Uri.parse(
        '${connection.url}/v1/history/files/${Uri.encodeComponent(id)}',
      );
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      connection.identify(request.headers);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${connection.token}',
      );
      final response = await request.close();
      if (response.statusCode != 200 ||
          response.headers.contentType?.mimeType != 'image/jpeg') {
        throw const FormatException('无法读取聊天图片');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 512 * 1024) {
          throw const FormatException('聊天图片过大');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }

    try {
      return await load().timeout(const Duration(seconds: 30));
    } finally {
      client.close(force: true);
    }
  }

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
      connection.identify(request.headers);
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
