import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../theme/theme.dart';
import '../models/message_model.dart';

typedef SendText = Future<void> Function(String text);
typedef SendMedia = Future<void> Function(Uint8List bytes, String fileName, String contentType, MessageType type);

class InputField extends StatefulWidget {
  final SendText onSend;
  final SendMedia onSendMedia;

  const InputField({super.key, required this.onSend, required this.onSendMedia});

  @override
  State<InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<InputField> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
    if (res == null) return;
    final f = res.files.first;
    final bytes = f.bytes;
    final name = f.name;
    final mime = _inferMime(name);
    if (bytes == null) return;

    final type = _typeFromMime(mime);
    await widget.onSendMedia(bytes, name, mime, type);
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
              decoration: const InputDecoration(
                hintText: 'Type a message',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _sending
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  onPressed: _send,
                  icon: const Icon(Icons.send, color: AppColors.sinopia),
                ),
        ],
      ),
    );
  }
}
