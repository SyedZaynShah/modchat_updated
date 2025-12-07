import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../theme/theme.dart';
import 'file_preview_widget.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;

  const MessageBubble({super.key, required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final navy = AppColors.navy;
    final offWhite = const Color(0xFFF5F7FA);
    final bubbleColor = isMe ? navy : offWhite;
    final textColor = isMe ? offWhite : navy;

    return Column(
      crossAxisAlignment: align,
      children: [
        if (message.edited)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Text(
              'Edited',
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Container(
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
            border: const Border(
              top: BorderSide(color: AppColors.sinopia, width: 2),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _content(context, textColor),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _content(BuildContext context, Color textColor) {
    if (message.isDeletedForAll) {
      return Text(
        'This message was deleted.',
        style: TextStyle(
          fontSize: 12,
          color: textColor.withValues(alpha: 0.6),
          fontStyle: FontStyle.italic,
        ),
      );
    }
    switch (message.messageType) {
      case MessageType.text:
        final t = (message.text ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t,
              style: TextStyle(fontSize: 13, height: 1.25, color: textColor),
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
        ? Colors.white70
        : AppColors.navy.withValues(alpha: 0.6);
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
          ? AppColors.sinopia
          : timeColor;
      children.add(Icon(iconData, size: 12, color: iconColor));
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
