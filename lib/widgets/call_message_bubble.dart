import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'package:intl/intl.dart';

class CallMessageBubble extends StatelessWidget {
  final Map<String, dynamic> meta;
  final DateTime timestamp;
  final VoidCallback? onTap;

  const CallMessageBubble({
    super.key,
    required this.meta,
    required this.timestamp,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final callType = meta['callType'] as String? ?? 'voice';
    final callStatus = meta['callStatus'] as String? ?? 'completed';
    final callDuration = meta['callDuration'] as int? ?? 0;
    final isIncoming = meta['isIncoming'] as bool? ?? false;
    
    final isVideo = callType == 'video';
    final isMissed = callStatus == 'missed';
    final isCompleted = callStatus == 'completed';
    
    final icon = isVideo ? Icons.videocam : Icons.phone;
    final directionIcon = isIncoming ? Icons.call_received : Icons.call_made;
    
    final color = isMissed ? Colors.red : (isCompleted ? Colors.green : Colors.grey);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMissed 
              ? Colors.red.withOpacity(0.05) 
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMissed 
                ? Colors.red.withOpacity(0.2) 
                : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Call icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Call info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        directionIcon,
                        size: 14,
                        color: color,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _getCallText(isVideo, callStatus, isMissed, isCompleted),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isMissed ? Colors.red : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isCompleted && callDuration > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Duration: ${_formatDuration(callDuration)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    _formatTimestamp(timestamp),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            // Info icon
            Icon(
              Icons.info_outline,
              size: 18,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(time);
    }
  }

  String _getCallText(bool isVideo, String status, bool isMissed, bool isCompleted) {
    if (isMissed) {
      return 'Missed ${isVideo ? 'video' : 'voice'} call';
    } else if (status == 'declined') {
      return '${isVideo ? 'Video' : 'Voice'} call declined';
    } else if (status == 'cancelled') {
      return '${isVideo ? 'Video' : 'Voice'} call cancelled';
    } else if (isCompleted) {
      return '${isVideo ? 'Video' : 'Voice'} call';
    } else {
      return '${isVideo ? 'Video' : 'Voice'} call failed';
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    }
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (secs == 0) {
      return '${minutes}m';
    }
    return '${minutes}m ${secs}s';
  }
}
