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
import '../services/firestore_service.dart';

typedef SendText = Future<void> Function(String text);
typedef SendMedia =
    Future<void> Function(
      Uint8List bytes,
      String fileName,
      String contentType,
      MessageType type, {
      String? localPath,
      String? thumbnailPath,
      int? durationMs,
    });

class InputField extends StatefulWidget {
  final SendText onSend;
  final SendMedia onSendMedia;
  final ValueChanged<bool>? onTypingChanged;
  final ValueChanged<String>? onTextChanged;
  final ValueChanged<bool>? onVoiceRecordingChanged;
  final bool sendDisabled;

  const InputField({
    super.key,
    required this.onSend,
    required this.onSendMedia,
    this.onTypingChanged,
    this.onTextChanged,
    this.onVoiceRecordingChanged,
    this.sendDisabled = false,
  });

  @override
  State<InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<InputField> {
  final _controller = TextEditingController();
  bool _hasText = false;

  Future<void> _sendQueue = Future<void>.value();

  bool _fsRecoveryInFlight = false;

  // Voice note state
  final AudioRecorder _rec = AudioRecorder();
  bool _recording = false;
  DateTime? _recStart;
  String? _recPath;
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _tick;
  final List<double> _wave = <double>[]; // recent amps

  @override
  void dispose() {
    if (_recording) {
      widget.onVoiceRecordingChanged?.call(false);
    }
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
    final localPath = kIsWeb ? null : x.path;
    final mime =
        lookupMimeType(
          name,
          headerBytes: bytes.sublist(0, bytes.length > 32 ? 32 : bytes.length),
        ) ??
        'image/*';
    await widget.onSendMedia(
      bytes,
      name,
      mime,
      MessageType.image,
      localPath: localPath,
    );
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

    final localPath = kIsWeb ? null : f.path;

    String? mime = lookupMimeType(
      name,
      headerBytes: bytes.isNotEmpty
          ? bytes.sublist(0, bytes.length > 32 ? 32 : bytes.length)
          : null,
    );
    mime ??= _inferMime(name);
    final typeOut = _typeFromMime(mime);
    await widget.onSendMedia(bytes, name, mime, typeOut, localPath: localPath);
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
      _ampSub?.cancel();
      _ampSub = _rec
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((a) {
            final cur = a.current; // dB [-160..0]
            final norm = ((cur + 60.0) / 60.0).clamp(0.0, 1.0).toDouble();
            if (!mounted) return;
            setState(() {
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
      });
      widget.onVoiceRecordingChanged?.call(true);
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
      _recPath = null;
    });
    widget.onVoiceRecordingChanged?.call(false);
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
    });
    widget.onVoiceRecordingChanged?.call(false);
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

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final draft = text;
    _controller.clear();
    if (_hasText) {
      setState(() => _hasText = false);
      widget.onTypingChanged?.call(false);
      widget.onTextChanged?.call('');
    }

    _sendQueue = _sendQueue.catchError((_) {}).then((_) async {
      try {
        await widget.onSend(text);
      } catch (e) {
        final msg = e.toString();

        if (kIsWeb &&
            !_fsRecoveryInFlight &&
            (msg.contains('INTERNAL ASSERTION FAILED') ||
                msg.contains('Unexpected state'))) {
          _fsRecoveryInFlight = true;
          try {
            await FirestoreService.resetPersistenceAndNetwork();
          } catch (_) {
            // ignore
          } finally {
            _fsRecoveryInFlight = false;
          }
        }

        if (!mounted) return;
        if (_controller.text.trim().isEmpty) {
          _controller.text = draft;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
          if (!_hasText) {
            setState(() => _hasText = true);
            widget.onTypingChanged?.call(true);
            widget.onTextChanged?.call(_controller.text);
          }
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Send failed: $e')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inputBg = isDark ? const Color(0xFF0F0F0F) : AppColors.inputBgLight;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      height: 48,
      decoration: BoxDecoration(
        color: inputBg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: _recording ? _buildRecordingUI() : _buildNormalUI(),
    );
  }

  Widget _buildNormalUI() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textLightPrimary;
    final hintColor = isDark ? const Color(0xFF8A8A8A) : AppColors.textLightSecondary;
    final iconColor = isDark ? const Color(0xFF9A9A9A) : AppColors.textLightSecondary;
    return Row(
      children: [
        IconButton(
          onPressed: _pickFile,
          icon: Icon(
            Icons.attach_file,
            color: iconColor,
            size: 20,
          ),
        ),
        Expanded(
          child: TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 4,
            onChanged: (v) {
              widget.onTextChanged?.call(v);
              final has = v.trim().isNotEmpty;
              if (has != _hasText) {
                setState(() => _hasText = has);
                widget.onTypingChanged?.call(has);
              }
            },
            style: TextStyle(color: textColor, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Message',
              hintStyle: TextStyle(color: hintColor, fontSize: 14),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildActionButton(),
      ],
    );
  }

  Widget _buildRecordingUI() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textLightPrimary;
    final actionBg = Theme.of(context).colorScheme.primary;
    final actionFg = Theme.of(context).colorScheme.onPrimary;
    return Row(
      children: [
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _Waveform(values: _wave),
              const SizedBox(width: 10),
              Text(
                _fmtElapsed(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _cancelRec,
          icon: const Icon(
            Icons.delete_outline,
            color: Color(0xFF5865F2),
            size: 20,
          ),
        ),
        const SizedBox(width: 2),
        GestureDetector(
          onTap: _finishRecSend,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: actionBg,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.send, color: actionFg, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    final actionBg = Theme.of(context).colorScheme.primary;
    final actionFg = Theme.of(context).colorScheme.onPrimary;
    return GestureDetector(
      onTap: () {
        if (widget.sendDisabled) return;
        if (_hasText) {
          _send();
          return;
        }
        if (!_recording) {
          _startRec();
        }
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: actionBg,
          shape: BoxShape.circle,
        ),
        child: Icon(
          _hasText ? Icons.send : Icons.mic,
          color: widget.sendDisabled ? const Color(0xFF5A5A5A) : actionFg,
          size: 20,
        ),
      ),
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
                color: AppColors.navy,
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

