import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:purin_mobile/data/agent_api.dart';
import 'package:purin_mobile/data/chat_attachment.dart';
import 'package:purin_mobile/data/mobile_session.dart';
import 'package:purin_mobile/data/mobile_store.dart';

class _Store extends DeviceStore {
  Json saved = {};

  @override
  Future<void> saveHistory(String scope, Json value) async {
    saved = jsonDecode(jsonEncode(value)) as Json;
  }
}

class _Api extends AgentApi {
  final calls = <({String path, Json body})>[];

  @override
  Future<Json> request(Connection connection, String path, {Json? body}) async {
    calls.add((path: path, body: body!));
    if (calls.length == 1) throw const SocketException('offline');
    return {'event_id': 'stored', 'job_id': 'job'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('仅附件也能发送，失败时保留图片、文件和消息 ID 以便重试', () async {
    final api = _Api();
    final store = _Store();
    final session = MobileSession(store, api)
      ..connection = Connection('http://localhost', 'phone', 'token');
    const images = ['data:image/jpeg;base64,/9j/'];
    const names = ['照片.jpg'];
    const documents = [
      {'id': 'doc_test', 'name': '便签.txt'},
    ];
    await session.send(
      '',
      images: images,
      imageNames: names,
      documents: documents,
    );
    final pending = (store.saved['outgoing'] as List).single;
    expect(pending['status'], 'unsent');
    expect(api.calls.single.path, 'messages/images');
    expect(api.calls.single.body, {
      'message_id': pending['id'],
      'text': '请阅读附件。',
      'images': images,
      'image_names': names,
      'documents': documents,
    });
    expect(pending['images'], images);
    expect(pending['documents'], documents);
    await session.retry(session.messages.single);
    expect(api.calls.last.body, api.calls.first.body);
    expect(store.saved['outgoing'], isEmpty);
    await session.send('', documents: documents);
    expect(api.calls.last.path, 'messages');
    expect(api.calls.last.body['documents'], documents);
    expect(api.calls.last.body.containsKey('images'), isFalse);
    await expectLater(
      session.send(
        '',
        images: [...images, ...images],
        imageNames: [...names, ...names],
        documents: [...documents, ...documents, ...documents],
      ),
      throwsFormatException,
    );
    session.dispose();
  });

  test('透明图片按桌面端尺寸和白底转成 JPEG，过大附件在读取前拒绝', () async {
    final dir = await Directory.systemTemp.createTemp('chat-media-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/test.png');
    final pixels = img.Image(width: 2200, height: 110, numChannels: 4);
    await file.writeAsBytes(img.encodePng(pixels));
    final attachment = await ChatAttachment.prepare('照片.PNG', file);
    expect(attachment.name, '照片.PNG');
    expect(attachment.jpeg!.length, lessThanOrEqualTo(512 * 1024));
    final decoded = img.decodeJpg(attachment.jpeg!)!;
    expect((decoded.width, decoded.height), (1920, 96));
    expect(decoded.getPixel(5, 5).r, greaterThan(250));
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(ChatAttachment.maxBytes + 1);
    await handle.close();
    await expectLater(
      ChatAttachment.prepare('太大了.txt', file),
      throwsFormatException,
    );
  });
}
