import 'dart:async';
import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../theme/theme.dart';

class AsyncMediaLoader {
  static final Map<String, String> _cache = {};

  static Future<String?> getSignedUrl(String? rawUrl, MessageType type) async {
    if (rawUrl == null || rawUrl.isEmpty) return null;

    // Check cache first
    if (_cache.containsKey(rawUrl)) {
      return _cache[rawUrl];
    }

    String? signedUrl;
    try {
      if (rawUrl.contains('://')) {
        final s = rawUrl.substring(5);
        final i = s.indexOf('/');
        final bucket = s.substring(0, i);
        final path = s.substring(i + 1);
        signedUrl = await SupabaseService.instance.getSignedUrl(
          bucket,
          path,
          expiresInSeconds: 86400,
        );
      } else {
        final bucket = type == MessageType.audio
            ? StorageService().audioBucket
            : StorageService().mediaBucket;
        signedUrl = await SupabaseService.instance.resolveUrl(
          bucket: bucket,
          path: rawUrl,
        );
      }

      // Cache the result
      _cache[rawUrl] = signedUrl;
      return signedUrl;
    } catch (e) {
      // Return original URL on error to prevent blocking
      return rawUrl;
    }
  }

  static void clearCache() {
    _cache.clear();
  }
}

class AsyncMediaWidget extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final Widget placeholder;
  final Widget? child;

  const AsyncMediaWidget({
    super.key,
    required this.message,
    required this.isMe,
    required this.placeholder,
    this.child,
  });

  @override
  State<AsyncMediaWidget> createState() => _AsyncMediaWidgetState();
}

class _AsyncMediaWidgetState extends State<AsyncMediaWidget> {
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

    final resolved = await AsyncMediaLoader.getSignedUrl(
      rawUrl,
      widget.message.messageType,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        _resolvedUrl = resolved;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.placeholder;
    }

    if (_resolvedUrl == null || _resolvedUrl!.isEmpty) {
      return widget.child ?? widget.placeholder;
    }

    return widget.child ?? _buildMediaContent();
  }

  Widget _buildMediaContent() {
    switch (widget.message.messageType) {
      case MessageType.image:
        return _buildImageWidget();
      case MessageType.video:
        return _buildVideoWidget();
      case MessageType.audio:
        return _buildAudioWidget();
      case MessageType.file:
        return _buildFileWidget();
      default:
        return widget.placeholder;
    }
  }

  Widget _buildImageWidget() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        _resolvedUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return widget.placeholder;
        },
        loadingBuilder: (context, child, loadingProgress) {
          return Container(
            decoration: BoxDecoration(
              color: widget.isMe ? AppColors.navy : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child:
                  child ??
                  const CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.highlight,
                    ),
                  ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideoWidget() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video thumbnail placeholder
            if (_resolvedUrl != null && _resolvedUrl!.isNotEmpty)
              Image.network(
                _resolvedUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return widget.placeholder;
                },
              ),
            // Loading overlay
            if (_isLoading)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.highlight,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioWidget() {
    return Container(
      decoration: BoxDecoration(
        color: widget.isMe ? AppColors.navy : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.audiotrack,
            color: widget.isMe ? Colors.white : Colors.black,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Audio Message',
              style: TextStyle(
                color: widget.isMe ? Colors.white : Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileWidget() {
    final fileName = (widget.message.mediaUrl ?? '').split('/').last.isNotEmpty
        ? (widget.message.mediaUrl ?? '').split('/').last
        : 'File';
    return Container(
      decoration: BoxDecoration(
        color: widget.isMe ? AppColors.navy : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file,
            color: widget.isMe ? Colors.white : Colors.black,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              fileName,
              style: TextStyle(
                color: widget.isMe ? Colors.white : Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
