import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'agent_api.dart';

class ChatDictation {
  final _finish = Completer<bool>();
  final _cancelled = Completer<void>();
  Future<void> get cancelled => _cancelled.future;
  bool get isCancelled => _cancelled.isCompleted;

  void stop() {
    if (!_finish.isCompleted) _finish.complete(true);
  }

  void cancel() {
    if (!isCancelled) _cancelled.complete();
    if (!_finish.isCompleted) _finish.complete(false);
  }

  Future<Uint8List?> record(void Function() onRecording) async {
    final recorder = AudioRecorder();
    File? file;
    Timer? timer;
    StreamSubscription<RecordStop>? events;
    try {
      if (!await recorder.hasPermission()) {
        throw const FormatException('无法访问麦克风，请在系统设置中允许 Wintermute 使用麦克风');
      }
      if (isCancelled) return null;
      final dir = await getTemporaryDirectory();
      file = File('${dir.path}/dictation-${newEventId()}.wav');
      events = recorder.onStopped().listen((_) {
        if (!_finish.isCompleted) _finish.complete(false);
      });
      if (isCancelled) return null;
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: file.path,
      );
      if (!isCancelled) onRecording();
      timer = Timer(const Duration(seconds: 118), stop);
      if (!await _finish.future || isCancelled) {
        await recorder.cancel();
        if (!isCancelled) throw const FormatException('录音已中断，请重新录音');
        return null;
      }
      await recorder.stop();
      final length = await file.length();
      if (length <= 44 || length > 3840044) {
        throw const FormatException('录音为空或超过两分钟');
      }
      return await file.readAsBytes();
    } finally {
      timer?.cancel();
      await events?.cancel();
      try {
        await recorder.dispose();
      } finally {
        if (file != null && await file.exists()) await file.delete();
      }
    }
  }
}
