import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/message_model.dart';
import '../theme/theme.dart';
import 'file_preview_widget.dart';
import '../services/firestore_service.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final double zoom; // 1.0 = normal, >1 scales only text bubbles

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.zoom = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final isImage = message.messageType == MessageType.image;
    final bubbleColor = isImage
        ? Colors.transparent
        : (isMe ? AppColors.navy : AppColors.surface);
    final textColor = isMe ? AppColors.white : Colors.black;
    // Apply zoom only for text messages; others remain at 1.0
    final z = message.messageType == MessageType.text
        ? zoom.clamp(1.0, 1.6)
        : 1.0;

    return Column(
      crossAxisAlignment: align,
      children: [
        AnimatedContainer(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
            boxShadow: isImage
                ? []
                : [
                    BoxShadow(
                      color: AppColors.highlight.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          padding: isImage
              ? EdgeInsets.zero
              : EdgeInsets.symmetric(horizontal: 12 * z, vertical: 8 * z),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _content(context, textColor, z),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _content(BuildContext context, Color textColor, double z) {
    if (message.isDeletedForAll) {
      // Keep deleted label subtle and not scaled aggressively
      final style = TextStyle(
        fontSize: 12 * (message.messageType == MessageType.text ? z : 1.0),
        color: textColor.withValues(alpha: 0.6),
        fontStyle: FontStyle.italic,
      );
      return AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        style: style,
        child: const Text('This message was deleted.'),
      );
    }
    switch (message.messageType) {
      case MessageType.text:
        final t = (message.text ?? '');
        final url = _firstUrl(t);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (url != null) ...[
              _LinkPreview(
                chatId: message.chatId,
                messageId: message.id,
                url: url,
                isMe: isMe,
              ),
              const SizedBox(height: 6),
            ],
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                fontSize: 15 * z,
                height: 1.25,
                color: textColor,
              ),
              child: _linkifiedText(t, textColor),
            ),
            const SizedBox(height: 6),
            _metaRow(textColor),
          ],
        );
      case MessageType.image:
        // Image messages show their own overlay timestamp/ticks; no meta row below.
        return FilePreviewWidget(message: message, isMe: isMe);
      case MessageType.video:
      case MessageType.file:
      case MessageType.audio:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FilePreviewWidget(message: message, isMe: isMe),
            const SizedBox(height: 6),
            _metaRow(textColor),
          ],
        );
    }
  }

  Widget _metaRow(Color baseColor) {
    final timeColor = isMe
        ? AppColors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.7);
    final List<Widget> children = [
      Text(_formatTime(), style: TextStyle(fontSize: 10, color: timeColor)),
    ];
    if (isMe) {
      children.add(const SizedBox(width: 6));
      final isPending = message.hasPendingWrites;
      final iconData = isPending
          ? Icons.watch_later_outlined
          : _statusIconData();
      final iconColor = (!isPending && message.status == 3)
          ? (isMe ? AppColors.white : Colors.black)
          : timeColor;
      children.add(Icon(iconData, size: 12, color: iconColor));
    }
    if (message.edited) {
      children.add(const SizedBox(width: 6));
      children.add(
        Text('Edited', style: TextStyle(fontSize: 10, color: timeColor)),
      );
    }
    // Return a minimal-width row so the bubble shrinks to content width
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  IconData _statusIconData() {
    switch (message.status) {
      case 1:
        return Icons.done;
      case 2:
        return Icons.done; // keep single tick for delivered
      case 3:
        return Icons.done_all_rounded;
      default:
        return Icons.watch_later_outlined;
    }
  }

  String _formatTime() {
    final dt = message.timestamp.toDate();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // Extract first URL in text
  String? _firstUrl(String t) {
    final exp = RegExp(r'(https?:\/\/[^\s]+)', caseSensitive: false);
    final m = exp.firstMatch(t);
    return m?.group(0);
  }

  Widget _linkifiedText(String t, Color color) {
    final url = _firstUrl(t);
    if (url == null) return Text(t);
    final parts = t.split(url);
    return Wrap(
      children: [
        Text(parts.first, style: TextStyle(color: color)),
        InkWell(
          onTap: () => _open(url),
          child: Text(
            url,
            style: TextStyle(
              color: color,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        if (parts.length > 1)
          Text(parts.sublist(1).join(url), style: TextStyle(color: color)),
      ],
    );
  }

  void _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

class _LinkPreview extends StatefulWidget {
  final String chatId;
  final String messageId;
  final String url;
  final bool isMe;
  const _LinkPreview({
    required this.chatId,
    required this.messageId,
    required this.url,
    required this.isMe,
  });
  @override
  State<_LinkPreview> createState() => _LinkPreviewState();
}

class _LinkPreviewState extends State<_LinkPreview> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await FirestoreService()
          .messages(widget.chatId)
          .doc(widget.messageId)
          .get();
      final existing = doc.data()?['linkPreview'] as Map<String, dynamic>?;
      if (existing != null && existing['title'] != null) {
        setState(() {
          _data = existing;
          _loading = false;
        });
        return;
      }
      final meta = await _fetchMeta(widget.url);
      _data = meta;
      await FirestoreService()
          .messages(widget.chatId)
          .doc(widget.messageId)
          .set({'linkPreview': meta}, SetOptions(merge: true));
    } catch (_) {
      // swallow errors; fallback to no preview
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>> _fetchMeta(String url) async {
    final resp = await http.get(Uri.parse(url));
    final html = resp.body;
    String pick(RegExp re) => re.firstMatch(html)?.group(1) ?? '';
    String og(String p) => pick(
      RegExp(
        '<meta[^>]*property=["\']$p["\'][^>]*content=["\']([^"\']+)["\']',
        caseSensitive: false,
      ),
    );
    String metaName(String n) => pick(
      RegExp(
        '<meta[^>]*name=["\']$n["\'][^>]*content=["\']([^"\']+)["\']',
        caseSensitive: false,
      ),
    );
    final title = og('og:title').isNotEmpty
        ? og('og:title')
        : pick(RegExp('<title>([^<]+)</title>', caseSensitive: false));
    final desc = og('og:description').isNotEmpty
        ? og('og:description')
        : metaName('description');
    final image = og('og:image');
    final host = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? '';
    return {
      'title': title,
      'description': desc,
      'image': image,
      'domain': host,
      'url': url,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _data == null) {
      return const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final tColor = widget.isMe ? AppColors.white : Colors.black;
    final img = (_data!['image'] as String?) ?? '';
    return InkWell(
      onTap: () => _launch(_data!['url'] as String),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (img.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(imageUrl: img, fit: BoxFit.cover),
              ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((_data!['title'] as String).isNotEmpty)
                    Text(
                      _data!['title'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if ((_data!['description'] as String).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        _data!['description'] as String,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tColor.withOpacity(0.8)),
                      ),
                    ),
                  if ((_data!['domain'] as String).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        _data!['domain'] as String,
                        style: TextStyle(
                          color: tColor.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _launch(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
