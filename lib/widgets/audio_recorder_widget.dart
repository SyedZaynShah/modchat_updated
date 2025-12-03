import 'dart:async';
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
  StreamSubscription<Amplitude>? _ampSub;
  double _amp = 0.0; // normalized 0..1
  Timer? _ticker;
  String? _lastPath;

  Future<void> _startRec() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;
    try {
      final dir = await getTemporaryDirectory();
      _lastPath =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _start = DateTime.now();
      await _rec.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _lastPath!,
      );
      _amp = 0;
      _ampSub?.cancel();
      _ampSub = _rec
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((a) {
            // Normalize roughly: current amplitude around -50..0 dB
            final cur = a.current; // dB
            final norm = ((cur + 60.0) / 60.0).clamp(0.0, 1.0).toDouble();
            if (mounted) setState(() => _amp = norm);
          });
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() {});
      });
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to start recording: $e')));
    }
  }

  Future<void> _stopRecAndConfirm() async {
    final path = await _rec.stop();
    final duration = DateTime.now()
        .difference(_start ?? DateTime.now())
        .inMilliseconds;
    _ampSub?.cancel();
    _ticker?.cancel();
    if (!mounted) return;
    setState(() => _recording = false);
    if (path == null) return;

    // Confirm send or cancel
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.send),
              title: const Text('Send voice note'),
              onTap: () => Navigator.pop(ctx, 'send'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx, 'cancel'),
            ),
          ],
        ),
      ),
    );
    if (action == 'send') {
      final bytes = await File(path).readAsBytes();
      await widget.onSendAudio(
        bytes,
        'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        'audio/m4a',
        MessageType.audio,
        durationMs: duration,
      );
    } else {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _ampSub?.cancel();
    _ticker?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = _start == null
        ? Duration.zero
        : DateTime.now().difference(_start!);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onLongPressStart: (_) => _startRec(),
          onLongPressEnd: (_) => _stopRecAndConfirm(),
          child: Icon(
            _recording ? Icons.mic : Icons.mic,
            color: _recording ? Colors.redAccent : Colors.white70,
            size: 24,
          ),
        ),
        if (_recording) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 80,
            height: 18,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Container(color: Colors.white24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: 0.2 + 0.8 * _amp,
                      child: Container(
                        color: Colors.redAccent.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _fmt(elapsed),
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ],
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
