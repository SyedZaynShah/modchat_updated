import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';
import '../theme/theme.dart';

class SimpleAsyncMedia extends StatefulWidget {
  final MessageModel message;
  final bool isMe;

  const SimpleAsyncMedia({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  State<SimpleAsyncMedia> createState() => _SimpleAsyncMediaState();
}

class _SimpleAsyncMediaState extends State<SimpleAsyncMedia> {
  String? _resolvedUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    if (!mounted) return;

    final rawUrl = widget.message.mediaUrl ?? '';
    if (rawUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _resolvedUrl = null;
        });
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      String resolved;
      if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
        resolved = rawUrl;
      } else {
        var path = rawUrl;
        if (rawUrl.startsWith('sb://')) {
          final s = rawUrl.substring(5);
          final i = s.indexOf('/');
          if (i > 0) {
            path = s.substring(i + 1);
          }
        } else if (rawUrl.startsWith('chatMedia/')) {
          path = rawUrl.substring('chatMedia/'.length);
        }
        resolved = await Supabase.instance.client.storage
            .from('chatMedia')
            .createSignedUrl(
              path,
              3600,
            );
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _resolvedUrl = resolved;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _resolvedUrl = rawUrl; // fallback to original URL
        });
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildPlaceholder();
    }

    if (_resolvedUrl == null || _resolvedUrl!.isEmpty) {
      return _buildPlaceholder();
    }

    return _buildMediaContent();
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: widget.isMe ? AppColors.navy : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image,
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

  Widget _buildMediaContent() {
    switch (widget.message.messageType) {
      case MessageType.text:
        return const SizedBox.shrink(); // Text handled elsewhere
      case MessageType.image:
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            _resolvedUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildPlaceholder();
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                decoration: BoxDecoration(
                  color: widget.isMe ? AppColors.navy : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              );
            },
          ),
        );

      case MessageType.video:
      case MessageType.audio:
      case MessageType.file:
        return Container(
          decoration: BoxDecoration(
            color: widget.isMe ? AppColors.navy : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_getIcon(), color: Colors.white, size: 24),
                const SizedBox(height: 8),
                Text(
                  _getLabel(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  IconData _getIcon() {
    switch (widget.message.messageType) {
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

  String _getLabel() {
    switch (widget.message.messageType) {
      case MessageType.video:
        return 'Video';
      case MessageType.audio:
        return 'Audio Message';
      case MessageType.file:
        return 'File';
      default:
        return 'Image';
    }
  }
}
