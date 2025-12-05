import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../theme/theme.dart';
import '../models/message_model.dart';

typedef SendText = Future<void> Function(String text);
typedef SendMedia =
    Future<void> Function(
      Uint8List bytes,
      String fileName,
      String contentType,
      MessageType type, {
      int? durationMs,
    });

class InputField extends StatefulWidget {
  final SendText onSend;
  final SendMedia onSendMedia;
  final ValueChanged<bool>? onTypingChanged;

  const InputField({
    super.key,
    required this.onSend,
    required this.onSendMedia,
    this.onTypingChanged,
  });

  @override
  State<InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<InputField> {
  final _controller = TextEditingController();
  bool _sending = false;
  bool _hasText = false;

  // Voice note state
  final AudioRecorder _rec = AudioRecorder();
  bool _recording = false;
  bool _locked = false;
  bool _cancelHint = false;
  DateTime? _recStart;
  String? _recPath;
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _tick;
  double _amp = 0.0; // 0..1
  final List<double> _wave = <double>[]; // recent amps
  Offset? _gestureStart;

  @override
  void dispose() {
    _controller.dispose();
    _ampSub?.cancel();
    _tick?.cancel();
    _rec.dispose();
    super.dispose();
  }

  Future<void> _pickImageAndSend() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final name = x.name;
    final mime =
        lookupMimeType(
          name,
          headerBytes: bytes.sublist(0, bytes.length > 32 ? 32 : bytes.length),
        ) ??
        'image/*';
    await widget.onSendMedia(bytes, name, mime, MessageType.image);
  }

  Future<void> _pickFile() async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickImageAndSend();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndSend(type: FileType.video);
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('Document'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndSend(
                  type: FileType.custom,
                  exts: const [
                    'pdf',
                    'ppt',
                    'pptx',
                    'doc',
                    'docx',
                    'xls',
                    'xlsx',
                    'rar',
                    'zip',
                  ],
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.audiotrack),
              title: const Text('Audio'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndSend(type: FileType.audio);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Other files'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAndSend(type: FileType.any);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSend({
    required FileType type,
    List<String>? exts,
  }) async {
    final res = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: exts,
      allowMultiple: false,
      allowCompression: false,
      withData: false,
      withReadStream: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final name = f.name;

    Uint8List? bytes = f.bytes;
    if (bytes == null) {
      final stream = f.readStream;
      if (stream != null) {
        final chunks = <int>[];
        await for (final chunk in stream) {
          chunks.addAll(chunk);
        }
        bytes = Uint8List.fromList(chunks);
      } else if (f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
    }
    if (bytes == null) return;

    String? mime = lookupMimeType(
      name,
      headerBytes: bytes.isNotEmpty
          ? bytes.sublist(0, bytes.length > 32 ? 32 : bytes.length)
          : null,
    );
    mime ??= _inferMime(name);
    final typeOut = _typeFromMime(mime);
    await widget.onSendMedia(bytes, name, mime, typeOut);
  }

  String _inferMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.rar')) return 'application/vnd.rar';
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
      return 'application/vnd.ms-powerpoint';
    }
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.webm')) return 'audio/webm';
    return 'application/octet-stream';
  }

  MessageType _typeFromMime(String mime) {
    if (mime.startsWith('image/')) return MessageType.image;
    if (mime.startsWith('video/')) return MessageType.video;
    if (mime.startsWith('audio/')) return MessageType.audio;
    return MessageType.file;
  }

  // ===== Voice note logic =====
  Future<void> _startRec() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice recording is not supported on Web'),
        ),
      );
      return;
    }
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      _recStart = DateTime.now();
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      _recPath = path;
      _wave.clear();
      _amp = 0;
      _ampSub?.cancel();
      _ampSub = _rec
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((a) {
            final cur = a.current; // dB [-160..0]
            final norm = ((cur + 60.0) / 60.0).clamp(0.0, 1.0).toDouble();
            if (!mounted) return;
            setState(() {
              _amp = norm;
              _wave.add(norm);
              if (_wave.length > 32) _wave.removeAt(0);
            });
          });
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() {});
      });
      setState(() {
        _recording = true;
        _cancelHint = false;
        if (!_locked) _locked = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to start recording: $e')));
    }
  }

  Future<void> _cancelRec() async {
    try {
      await _rec.stop();
    } catch (_) {}
    _ampSub?.cancel();
    _tick?.cancel();
    if (_recPath != null) {
      try {
        File(_recPath!).deleteSync();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _locked = false;
      _cancelHint = false;
      _recPath = null;
    });
  }

  Future<void> _finishRecSend() async {
    final path = await _rec.stop();
    _ampSub?.cancel();
    _tick?.cancel();
    final duration = DateTime.now()
        .difference(_recStart ?? DateTime.now())
        .inMilliseconds;
    if (!mounted) return;
    setState(() {
      _recording = false;
      _locked = false;
      _cancelHint = false;
    });
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    await widget.onSendMedia(
      bytes,
      'voice_${DateTime.now().millisecondsSinceEpoch}.wav',
      'audio/wav',
      MessageType.audio,
      durationMs: duration,
    );
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  void _onLongPressStart(LongPressStartDetails d) {
    _gestureStart = d.globalPosition;
    _locked = false;
    _cancelHint = false;
    _startRec();
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    if (_gestureStart == null) return;
    final dx = d.globalPosition.dx - _gestureStart!.dx;
    final dy = d.globalPosition.dy - _gestureStart!.dy;
    bool changed = false;
    if (dx < -60 && !_cancelHint) {
      _cancelHint = true;
      changed = true;
    }
    if (dy < -60 && !_locked) {
      _locked = true;
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    if (_locked) {
      // keep recording; user will tap send/delete
      return;
    }
    if (_cancelHint) {
      _cancelRec();
    } else {
      _finishRecSend();
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      _controller.clear();
      if (_hasText) {
        setState(() => _hasText = false);
        widget.onTypingChanged?.call(false);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final composer = !_recording
        ? Row(
            children: [
              IconButton(
                onPressed: _pickFile,
                icon: const Icon(Icons.attach_file, color: Color(0xFF1E1E1E)),
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 5,
                  onChanged: (v) {
                    final has = v.trim().isNotEmpty;
                    if (has != _hasText) {
                      setState(() => _hasText = has);
                      widget.onTypingChanged?.call(has);
                    }
                  },
                  decoration: const InputDecoration(
                    hintText: 'Type a message',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: _sending
                    ? const SizedBox(
                        key: ValueKey('sending'),
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : (_hasText
                          ? IconButton(
                              key: const ValueKey('send'),
                              onPressed: _send,
                              icon: const Icon(
                                Icons.send,
                                color: AppColors.sinopia,
                                size: 26,
                              ),
                            )
                          : GestureDetector(
                              key: const ValueKey('mic'),
                              onTap: () async {
                                // single tap => free-hand locked recording
                                await _startRec();
                                if (mounted) setState(() => _locked = true);
                              },
                              onLongPressStart: _onLongPressStart,
                              onLongPressMoveUpdate: _onLongPressMove,
                              onLongPressEnd: _onLongPressEnd,
                              child: const Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Icon(
                                  Icons.mic,
                                  color: AppColors.sinopia,
                                  size: 26,
                                ),
                              ),
                            )),
              ),
            ],
          )
        : Row(
            children: [
              // Recording UI
              Expanded(
                child: Row(
                  children: [
                    if (!_locked) ...[
                      const Icon(
                        Icons.arrow_back_ios_new,
                        size: 16,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _cancelHint
                            ? 'Release to cancel'
                            : 'Slide left to cancel • Slide up to lock',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _Waveform(values: _wave),
                    const SizedBox(width: 8),
                    Text(
                      _fmtElapsed(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              if (_locked) ...[
                IconButton(
                  onPressed: _cancelRec,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                ),
                IconButton(
                  onPressed: _finishRecSend,
                  icon: const Icon(Icons.send, color: AppColors.sinopia),
                ),
              ],
            ],
          );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: AppTheme.glassDecoration(radius: 28),
      child: composer,
    );
  }

  String _fmtElapsed() {
    final d = _recStart == null
        ? Duration.zero
        : DateTime.now().difference(_recStart!);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _Waveform extends StatelessWidget {
  final List<double> values; // 0..1
  const _Waveform({required this.values});

  @override
  Widget build(BuildContext context) {
    final v = values.isEmpty
        ? List<double>.filled(16, 0.1)
        : values.takeLast(24);
    return SizedBox(
      height: 26,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: v.map((e) {
          final h = 6 + (e * 20);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Container(
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: AppColors.sinopia,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

extension on List<double> {
  List<double> takeLast(int n) {
    if (length <= n) return List<double>.from(this);
    return sublist(length - n);
  }
}
