import 'dart:typed_data';

import 'webrtc_service_impl_io.dart'
    if (dart.library.html) 'webrtc_service_impl_web.dart';

class RecordingResult {
  final Uint8List bytes;
  final String mimeType;
  RecordingResult({required this.bytes, required this.mimeType});
}

abstract class WebRTCService {
  Future<void> startRecording();
  Future<RecordingResult> stopRecording();
  Future<void> dispose();
}

WebRTCService createWebRTCService() => WebRTCServiceImpl();
