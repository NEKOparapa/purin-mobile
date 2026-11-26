import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data' show BytesBuilder;
import 'dart:ui' as ui;
import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_selector_ios/file_selector_ios.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'agent_api.dart';
import '../l10n/app_language.dart';

class ChatAttachment {
  ChatAttachment._(this.name, this.file, this.jpeg);
  final String name;
  final File file;
  final Uint8List? jpeg;
  Json? uploaded;
  static const maxCount = 4;
  static const maxBytes = 32 * 1024 * 1024;

  static Future<List<ChatAttachment>> pick(int remaining) async {
    final List<({String name, String path})> files;
    if (Platform.isIOS) {
      files = [
        for (final item in await FileSelectorIOS().openFiles())
          (name: item.name, path: item.path),
      ];
    } else {
      files = [
        for (final item in await FilePickerAndroid().pickFiles())
          (
            name: item.name,
            path: item.path ?? (throw const FormatException('无法读取所选文件')),
          ),
      ];
    }
    if (files.length > remaining) {
      throw const FormatException('每条消息最多可添加 4 个附件');
    }
    return [
      for (final item in files) await prepare(item.name, File(item.path)),
    ];
  }

  Future<Uint8List> read() => _read(name, file);

  static Future<Uint8List> _read(String name, File file) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > maxBytes) {
        throw LocalizedFormatException('{0} 超过单个附件 32 MiB 的限制', [name]);
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  static Future<ChatAttachment> prepare(String name, File file) async {
    if (name.trim().isEmpty ||
        name.runes.length > 255 ||
        name == '.' ||
        name == '..' ||
        name.contains(RegExp(r'[/\\\x00-\x1f\x7f-\x9f]'))) {
      throw const FormatException('文件名无效，请重命名后重试');
    }
    if ((await file.length()) > maxBytes) {
      throw LocalizedFormatException('{0} 超过单个附件 32 MiB 的限制', [name]);
    }
    if (!RegExp(
      r'\.(jpe?g|png|webp|gif)$',
      caseSensitive: false,
    ).hasMatch(name)) {
      return ChatAttachment._(name, file, null);
    }
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(
        await _read(name, file),
      );
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (width, height) {
          final scale = math.min(1.0, 1920 / math.max(width, height));
          return ui.TargetImageSize(
            width: math.max(1, (width * scale).round()),
            height: math.max(1, (height * scale).round()),
          );
        },
      );
      try {
        final frame = (await codec.getNextFrame()).image;
        try {
          final rgba = (await frame.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          ))!;
          final jpeg = await compute(_encodeJpeg, (
            rgba,
            frame.width,
            frame.height,
          ));
          return ChatAttachment._(name, file, jpeg);
        } finally {
          frame.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      throw LocalizedFormatException('无法读取图片「{0}」', [name]);
    }
  }
}

Uint8List _encodeJpeg((ByteData, int, int) pixels) {
  final (rgba, width, height) = pixels;
  var image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
  );
  while (true) {
    final bytes = img.encodeJpg(image, quality: 88);
    if (bytes.length <= 512 * 1024) return bytes;
    image = img.copyResize(
      image,
      width: math.max(1, (image.width * .8).round()),
      height: math.max(1, (image.height * .8).round()),
    );
  }
}

String chatMediaError(
  Object error, [
  AppLanguage language = AppLanguage.chinese,
]) {
  if (error is LocalizedFormatException) {
    return language.text(error.template, error.values);
  }
  return language.text(switch (error) {
    FormatException(:final message) || StateError(:final message) => message,
    ApiError(code: 'asr_key_missing') => '请先在后端配置语音转写密钥',
    ApiError(code: 'unsupported_file') => '后端无法解析此文件格式',
    ApiError(code: 'invalid_filename') => '文件名无效，请重命名后重试',
    ApiError(code: 'file_conversion_failed') => '文件无法解析，请检查文件是否损坏或加密',
    ApiError(code: 'file_conversion_timeout') => '文件解析超时，请重试',
    ApiError(code: 'transcription_failed' || 'audio_conversion_failed') =>
      '语音转写失败，请重试',
    ApiError(code: 'invalid_wav') => '录音格式无效，请重新录音',
    ApiError(status: 429) => '后端正忙，请稍后重试',
    _ => '操作失败，请检查设备连接后重试',
  });
}
