import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/webrtc_service.dart';
import '../models/message_model.dart';
import 'package:permission_handler/permission_handler.dart';

typedef SendAudio = Future<void> Function(Uint8List bytes, String fileName, String contentType, MessageType type);

class AudioRecorderWidget extends StatefulWidget {
  final SendAudio onSendAudio;
  const AudioRecorderWidget({super.key, required this.onSendAudio});

  @override
  State<AudioRecorderWidget> createState() => _AudioRecorderWidgetState();
}

class _AudioRecorderWidgetState extends State<AudioRecorderWidget> {
  late final WebRTCService _rtc = createWebRTCService();
  bool _recording = false;

  Future<void> _toggle() async {
    if (_recording) {
      final result = await _rtc.stopRecording();
      await widget.onSendAudio(result.bytes, 'voice_${DateTime.now().millisecondsSinceEpoch}.webm', result.mimeType, MessageType.audio);
      setState(() => _recording = false);
    } else {
      final status = await Permission.microphone.request();
      if (!status.isGranted) return;
      try {
        await _rtc.startRecording();
        setState(() => _recording = true);
      } on UnsupportedError catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Voice recording not supported on this platform')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to start recording: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _rtc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_recording ? Icons.stop_circle : Icons.mic, color: _recording ? Colors.redAccent : Colors.white70),
      onPressed: _toggle,
      tooltip: _recording ? 'Stop recording' : 'Record voice note',
    );
  }
}
