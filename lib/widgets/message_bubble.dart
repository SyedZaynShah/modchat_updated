import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../theme/theme.dart';
import 'file_preview_widget.dart';

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
    final bubbleColor = isMe ? AppColors.navy : AppColors.surface;
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
            boxShadow: [
              BoxShadow(
                color: AppColors.highlight.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(horizontal: 12 * z, vertical: 8 * z),
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                fontSize: 15 * z,
                height: 1.25,
                color: textColor,
              ),
              child: Text(t),
            ),
            const SizedBox(height: 6),
            _metaRow(textColor),
          ],
        );
      case MessageType.image:
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
}
