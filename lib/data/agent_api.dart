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
    this.followsSystemName = false,
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
    data['deviceId'],
    data['token'],
    installation: data['installation'],
    name: data['deviceName'],
    followsSystemName: data['followsSystemName'] == true,
  );
  static String get defaultDeviceName =>
      DevicePlatform.current == DevicePlatform.ios ? 'iOS 设备' : 'Android 手机';
  final String? installation;
  final bool followsSystemName;
  final String deviceName;
  Connection? withSystemName(String systemName) {
    if (!followsSystemName || deviceName == systemName) {
      return null;
    }
    return Connection(
      url,
      deviceId,
      token,
      installation: installation,
      name: systemName,
      followsSystemName: true,
    );
  }

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
    'followsSystemName': followsSystemName,
  };
}

class OnlineDevice {
  const OnlineDevice({
    required this.deviceId,
    required this.name,
    this.deviceType,
    this.platform,
    this.lastSeenSeconds,
    this.isCurrent = false,
  });

  factory OnlineDevice.fromJson(Json data) {
    final rawId = data['device_id'];
    final id = rawId is String ? rawId.trim() : '';
    final rawName = data['name'];
    final resolvedName = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : id;
    return OnlineDevice(
      deviceId: id,
      name: resolvedName,
      deviceType: data['device_type'] as String?,
      platform: data['platform'] as String?,
      lastSeenSeconds: (data['last_seen_seconds'] as num?)?.toInt(),
      isCurrent: data['is_current'] == true,
    );
  }

  final String deviceId;
  final String name;
  final String? deviceType;
  final String? platform;
  final int? lastSeenSeconds;
  final bool isCurrent;

  String get platformLabel => switch (platform) {
    'windows' => 'Windows',
    'macos' => 'macOS',
    'android' => 'Android',
    'ios' => 'iOS',
    'esp32' => 'ESP32',
    _ => switch (deviceType) {
      'desktop' => '桌面端',
      'mobile' => '手机',
      'esp32' => 'ESP32',
      _ => 'HTTP 设备',
    },
  };

  String get resolvedKind {
    if (deviceType == 'desktop' ||
        platform == 'windows' ||
        platform == 'macos') {
      return 'desktop';
    }
    if (deviceType == 'mobile' || platform == 'android' || platform == 'ios') {
      return 'mobile';
    }
    if (deviceType == 'esp32' || platform == 'esp32') {
      return 'esp32';
    }
    return 'other';
  }
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

final _pairingFragment = RegExp(r'^purin-pair=([0-9]{5}-?[0-9]{5})$');

({String url, String code})? pairingAddress(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return null;
  }
  final code = _pairingFragment.firstMatch(uri.fragment)?.group(1);
  if (code == null) return null;
  return (url: uri.origin, code: code.replaceAll('-', ''));
}

class AgentApi {
  ({String url, String code, String token, String id})? _pairAttempt;

  Future<Connection> pair(
    String value, {
    required String installation,
    required String name,
    bool followsSystemName = false,
  }) async {
    final target = pairingAddress(value);
    if (target == null) {
      throw const FormatException('请扫描管理页的二维码或粘贴完整配对链接');
    }
    final (:url, :code) = target;
    var attempt = _pairAttempt;
    if (attempt == null || attempt.url != url || attempt.code != code) {
      final random = Random.secure();
      final suffix = List.generate(
        12,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final token = base64Url
          .encode(List.generate(32, (_) => random.nextInt(256)))
          .replaceAll('=', '');
      attempt = _pairAttempt = (
        url: url,
        code: code,
        token: token,
        id: 'mobile-$suffix',
      );
    }
    final response = await _send(
      url,
      'devices/pair',
      headers: {
        'X-Device-ID': attempt.id,
        if (DevicePlatform.current case final platform?)
          'X-Device-Platform': platform.name,
      },
      body: {
        'code': code,
        'token': attempt.token,
        'installation': installation,
        'device_type': 'mobile',
        'device_name': name,
      },
    );
    final id = response['device_id'];
    if (id is! String || !RegExp(r'^mobile-[a-f0-9]{24}$').hasMatch(id)) {
      throw const FormatException('后端返回的设备信息无效');
    }
    return Connection(
      url,
      id,
      attempt.token,
      installation: installation,
      name: name,
      followsSystemName: followsSystemName,
    );
  }

  void finishPairing() => _pairAttempt = null;

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
      _send(
        connection.url,
        path,
        connection: connection,
        body: body,
        timeout: Duration(seconds: path == 'messages/images' ? 60 : 9),
      );

  Future<List<OnlineDevice>> onlineDevices(Connection connection) async {
    final result = await request(connection, 'devices/online');
    final items = result['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((row) => OnlineDevice.fromJson(Json.from(row)))
        .where((item) => item.deviceId.isNotEmpty)
        .toList(growable: false);
  }

  Future<Json> uploadAppVisit(Connection connection, Json body, Json frame) {
    final at = DateTime.fromMillisecondsSinceEpoch(
      frame['at'] as int,
      isUtc: true,
    );
    return _send(
      connection.url,
      'perceptions/mobile-app',
      connection: connection,
      body: {
        ...body,
        'frames': [
          {
            'occurred_at': at.toIso8601String(),
            'jpeg_base64': base64Encode(frame['jpeg'] as Uint8List),
          },
        ],
      },
      timeout: const Duration(seconds: 60),
    );
  }

  Future<Json> uploadChatFile(
    Connection conn,
    String name,
    Uint8List bytes, {
    Future<void>? cancel,
  }) async {
    if (bytes.length > 32 * 1024 * 1024) {
      throw const FormatException('单个附件不能超过 32 MiB');
    }
    final file = await _send(
      conn.url,
      'chat/files?name=${Uri.encodeQueryComponent(name)}',
      connection: conn,
      bytes: bytes,
      contentType: ContentType.binary,
      timeout: const Duration(seconds: 330),
      cancel: cancel,
    );
    final id = file['id'];
    if (id is! String ||
        !RegExp(r'^doc_[a-f0-9]{64}$').hasMatch(id) ||
        file['name'] != name) {
      throw const FormatException('文件回执无效，请重试');
    }
    return {'id': id, 'name': name};
  }

  Future<String> transcribe(
    Connection conn,
    Uint8List wav, {
    Future<void>? cancel,
  }) async {
    if (wav.length <= 44 || wav.length > 3840044) {
      throw const FormatException('录音为空或超过两分钟');
    }
    final result = await _send(
      conn.url,
      'transcriptions',
      connection: conn,
      bytes: wav,
      contentType: ContentType('audio', 'wav'),
      timeout: const Duration(seconds: 200),
      cancel: cancel,
    );
    final text = result['text'];
    if (text is! String) throw const FormatException('转写结果无效');
    if (text.trim().isEmpty) throw const FormatException('没有识别到语音，请再试一次');
    return text.trim();
  }

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
    return _send(
      connection.url,
      'image/slices',
      connection: connection,
      bytes: jpeg,
      contentType: ContentType('image', 'jpeg'),
      timeout: const Duration(seconds: 60),
      cancel: cancel,
      headers: {
        'X-Event-ID': record['id'] as String,
        'X-Occurred-At': at.toIso8601String(),
        'X-Capture-Context': base64Url.encode(utf8.encode(jsonEncode(context))),
      },
    );
  }

  Future<Json> _send(
    String url,
    String path, {
    Connection? connection,
    Json? body,
    Uint8List? bytes,
    ContentType? contentType,
    Duration timeout = const Duration(seconds: 9),
    Map<String, String> headers = const {},
    Future<void>? cancel,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    if (cancel != null) cancel.then((_) => client.close(force: true));
    Future<Json> perform() async {
      final uri = Uri.parse('$url/v1/$path');
      final request = await client.openUrl(
        body == null && bytes == null ? 'GET' : 'POST',
        uri,
      );
      request.followRedirects = false;
      if (connection != null) {
        connection.identify(request.headers);
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${connection.token}',
        );
      }
      headers.forEach(request.headers.set);
      if (bytes != null) {
        request.headers.contentType = contentType;
        request.contentLength = bytes.length;
        request.add(bytes);
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
      return await perform().timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }
}
