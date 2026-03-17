import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../theme/theme.dart';

class WorkingAsyncMedia extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  
  const WorkingAsyncMedia({
    super.key,
    required this.message,
    required this.isMe,
  });
  
  @override
  Widget build(BuildContext context) {
    // For now, just return a placeholder for media messages
    // Text messages are handled elsewhere and render instantly
    
    if (message.messageType == MessageType.text) {
      return const SizedBox.shrink(); // Text handled elsewhere
    }
    
    // For media messages, show a simple placeholder
    return Container(
      decoration: BoxDecoration(
        color: isMe ? AppColors.navy : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getIcon(),
              color: Colors.white.withValues(alpha: 0.6),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              'Loading...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  IconData _getIcon() {
    switch (message.messageType) {
      case MessageType.video:
        return Icons.videocam;
      case MessageType.audio:
        return Icons.audiotrack;
      case MessageType.file:
        return Icons.insert_drive_file;
      default:
        return Icons.image;
    }
  }
}
