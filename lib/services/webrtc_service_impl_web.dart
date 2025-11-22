import 'webrtc_service.dart';

class WebRTCServiceImpl implements WebRTCService {
  @override
  Future<void> startRecording() async {
    throw UnsupportedError('Voice recording on Web is not available in this build.');
  }

  @override
  Future<RecordingResult> stopRecording() async {
    throw UnsupportedError('Voice recording on Web is not available in this build.');
  }

  @override
  Future<void> dispose() async {}
}
