import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../models/message_model.dart';
import 'package:permission_handler/permission_handler.dart';

typedef SendAudio =
    Future<void> Function(
      Uint8List bytes,
      String fileName,
      String contentType,
      MessageType type, {
      int? durationMs,
    });

class AudioRecorderWidget extends StatefulWidget {
  final SendAudio onSendAudio;
  const AudioRecorderWidget({super.key, required this.onSendAudio});

  @override
  State<AudioRecorderWidget> createState() => _AudioRecorderWidgetState();
}

class _AudioRecorderWidgetState extends State<AudioRecorderWidget> {
  final AudioRecorder _rec = AudioRecorder();
  bool _recording = false;
  DateTime? _start;

  Future<void> _toggle() async {
    if (_recording) {
      final path = await _rec.stop();
      final duration = DateTime.now()
          .difference(_start ?? DateTime.now())
          .inMilliseconds;
      if (path != null) {
        final bytes = await File(path).readAsBytes();
        await widget.onSendAudio(
          bytes,
          'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
          'audio/m4a',
          MessageType.audio,
          durationMs: duration,
        );
      }
      setState(() => _recording = false);
    } else {
      final status = await Permission.microphone.request();
      if (!status.isGranted) return;
      try {
        final dir = await getTemporaryDirectory();
        final p =
            '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        _start = DateTime.now();
        await _rec.start(
          RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: p,
        );
        setState(() => _recording = true);
      } on UnsupportedError catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message ?? 'Voice recording not supported on this platform',
            ),
          ),
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
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _recording ? Icons.stop_circle : Icons.mic,
        color: _recording ? Colors.redAccent : Colors.white70,
      ),
      onPressed: _toggle,
      tooltip: _recording ? 'Stop recording' : 'Record voice note',
    );
  }
}
