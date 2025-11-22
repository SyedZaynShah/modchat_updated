import 'dart:io';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'webrtc_service.dart';

class WebRTCServiceImpl implements WebRTCService {
  MediaStream? _stream;
  MediaRecorder? _recorder;
  String? _filePath;

  Future<void> _ensureStream() async {
    _stream ??= await navigator.mediaDevices.getUserMedia({'audio': true});
  }

  @override
  Future<void> startRecording() async {
    await _ensureStream();
    _recorder = MediaRecorder();
    final dir = await getTemporaryDirectory();
    _filePath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.webm';
    await _recorder!.start(
      _filePath!,
      audioChannel: RecorderAudioChannel.INPUT,
    );
  }

  @override
  Future<RecordingResult> stopRecording() async {
    await _recorder?.stop();
    if (_filePath == null) {
      throw Exception('Recording file missing');
    }
    final file = File(_filePath!);
    final bytes = await file.readAsBytes();
    return RecordingResult(bytes: bytes, mimeType: 'audio/webm');
  }

  @override
  Future<void> dispose() async {
    await _recorder?.stop();
    await _stream?.dispose();
    _recorder = null;
    _stream = null;
  }
}
