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
    final bg = isMe ? AppColors.sinopia.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.06);
    final border = isMe ? Border.all(color: AppColors.sinopia.withValues(alpha: 0.6), width: 1.2) : Border.all(color: Colors.white.withValues(alpha: 0.2));

    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
            border: border,
            boxShadow: [
              BoxShadow(color: AppColors.sinopia.withValues(alpha: isMe ? 0.25 : 0.05), blurRadius: 12, spreadRadius: 1),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: _content(context),
        ),
        const SizedBox(height: 6),
        _statusRow(context),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _content(BuildContext context) {
    switch (message.messageType) {
      case MessageType.text:
        return Text(message.text ?? '', style: const TextStyle(fontSize: 16));
      case MessageType.image:
      case MessageType.video:
      case MessageType.file:
      case MessageType.audio:
        return FilePreviewWidget(message: message);
    }
  }

  Widget _statusRow(BuildContext context) {
    IconData icon;
    Color color = Colors.white70;
    switch (message.status) {
      case 1:
        icon = Icons.check;
        color = Colors.white70;
        break;
      case 2:
        icon = Icons.done_all;
        color = Colors.white70;
        break;
      case 3:
        icon = Icons.done_all;
        color = AppColors.sinopia;
        break;
      default:
        icon = Icons.more_horiz;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
      ],
    );
  }
}
