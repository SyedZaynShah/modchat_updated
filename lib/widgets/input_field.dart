import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import '../theme/theme.dart';
import '../models/message_model.dart';

typedef SendText = Future<void> Function(String text);
typedef SendMedia =
    Future<void> Function(
      Uint8List bytes,
      String fileName,
      String contentType,
      MessageType type,
    );

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

  @override
  void dispose() {
    _controller.dispose();
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
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: AppTheme.glassDecoration(radius: 28),
      child: Row(
        children: [
          IconButton(
            onPressed: _pickFile,
            icon: const Icon(Icons.attach_file, color: Colors.white70),
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
          const SizedBox(width: 8),
          _sending
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : (_hasText
                    ? IconButton(
                        onPressed: _send,
                        icon: const Icon(Icons.send, color: AppColors.sinopia),
                      )
                    : const SizedBox(width: 48, height: 48)),
        ],
      ),
    );
  }
}
