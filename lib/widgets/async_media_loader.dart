import 'dart:async';
import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../services/media_resolver.dart';
import '../theme/theme.dart';

class AsyncMediaLoader {
  /// Resolves a media reference to a stable public URL.
  /// Supports:
  /// - Full HTTP(S) URLs (returned as-is)
  /// - sb://bucket/path format
  /// - bucket/path format (e.g., chatMedia/chatId/...)
  /// - Uses explicit bucket from MessageModel if available
  static Future<String?> resolveUrl(
    String? rawUrl,
    MessageType type, {
    String? bucket,
  }) async {
    if (rawUrl == null || rawUrl.isEmpty) return null;

    try {
      final resolved = MediaResolver.resolve(rawUrl, bucket: bucket);
      if (resolved == null || resolved.isEmpty) return null;
      if (!resolved.contains('/storage/v1/object/public/')) return null;
      return resolved;
    } catch (e) {
      return null;
    }
  }

  @Deprecated('Use resolveUrl instead')
  static Future<String?> getSignedUrl(String? rawUrl, MessageType type) async {
    return resolveUrl(rawUrl, type);
  }

  static void clearCache() {
    // no-op: public urls are stable
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
  bool _failed = false;
  Timer? _timeoutTimer;

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startLoadWithTimeout();
    });
  }

  void _startLoadWithTimeout() {
    // Start the actual load
    _loadMedia();
    _startLoadingTimer();
  }

  void _startLoadingTimer() {
    // Set a 8-second max timeout to prevent infinite loading
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
          _failed = true;
          _resolvedUrl = null;
        });
      }
    });
  }

  Future<void> _loadMedia() async {
    if (!mounted) return;

    // Avoid resolving/painting a URL while the upload is still in progress.
    // This prevents transient 400s when the object isn't available yet.
    if (widget.message.uploadStatus == 'uploading') {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _resolvedUrl = null;
        });
      }
      return;
    }

    // Check both mediaUrl and mediaPath (mediaPath stores bucket/path)
    final rawUrl = (widget.message.storagePath?.isNotEmpty == true)
        ? widget.message.storagePath!
        : (widget.message.mediaPath?.isNotEmpty == true)
        ? widget.message.mediaPath!
        : (widget.message.mediaUrl?.isNotEmpty == true)
        ? widget.message.mediaUrl!
        : '';

    if (rawUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _resolvedUrl = null;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isLoading = true);
    }

    String? resolved;
    for (var attempt = 0; attempt < 3; attempt++) {
      resolved = await AsyncMediaLoader.resolveUrl(
        rawUrl,
        widget.message.messageType,
        bucket: widget.message.bucket,
      );
      if (resolved != null && resolved.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _resolvedUrl = resolved;
      _failed = resolved == null || resolved.isEmpty;
    });

    if (resolved != null &&
        resolved.isNotEmpty &&
        resolved.startsWith('https://') &&
        widget.message.messageType == MessageType.image) {
      try {
        await precacheImage(NetworkImage(resolved), context);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.placeholder;
    }

    if (_failed) {
      return widget.child ?? widget.placeholder;
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Grey placeholder background
          Container(color: Colors.grey.shade300),
          // Actual image with loading and fade-in
          Image.network(
            _resolvedUrl!,
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              // Fade in when frame is ready
              if (wasSynchronouslyLoaded || frame != null) {
                return AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: child,
                );
              }
              // Still loading - show placeholder
              return const SizedBox.shrink();
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey.shade300,
                child: const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.grey,
                    size: 32,
                  ),
                ),
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              // Show progress indicator on top of grey background
              return Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                      : null,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.highlight,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVideoWidget() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Dark background placeholder
            Container(color: Colors.black),
            // Video thumbnail preview
            if (_resolvedUrl != null && _resolvedUrl!.isNotEmpty)
              Image.network(
                _resolvedUrl!,
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) {
                    return AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: child,
                    );
                  }
                  return const SizedBox.shrink();
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey.shade900,
                    child: const Center(
                      child: Icon(
                        Icons.videocam_off_outlined,
                        color: Colors.grey,
                        size: 32,
                      ),
                    ),
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                          : null,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.highlight,
                      ),
                    ),
                  );
                },
              ),
            // Play button overlay (centered)
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioWidget() {
    final hasUrl = _resolvedUrl != null && _resolvedUrl!.isNotEmpty;
    final isUploading = widget.message.uploadStatus == 'uploading';
    final isLoading = _isLoading || (isUploading && hasUrl == false);
    final isReady = hasUrl && !isLoading && !isUploading;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isMe ? AppColors.navy : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Mic icon
          Icon(
            Icons.mic,
            color: isReady
                ? (widget.isMe ? Colors.white : Colors.black)
                : (widget.isMe ? Colors.white70 : Colors.black54),
            size: 20,
          ),
          const SizedBox(width: 10),
          // Waveform or progress area
          Expanded(
            child: Container(
              height: 32,
              child: isUploading
                  ? // Uploading state - show progress bar
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: widget.message.uploadProgress > 0
                              ? widget.message.uploadProgress
                              : null,
                          backgroundColor: widget.isMe
                              ? Colors.white.withOpacity(0.2)
                              : Colors.black.withOpacity(0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            widget.isMe ? Colors.white : AppColors.highlight,
                          ),
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Uploading...',
                          style: TextStyle(
                            color: widget.isMe
                                ? Colors.white70
                                : Colors.black54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    )
                  : isLoading
                  ? // Loading state - shimmer effect
                    Container(
                      decoration: BoxDecoration(
                        color: widget.isMe
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const _AudioWaveformPlaceholder(),
                    )
                  : // Ready state - waveform placeholder
                    Container(
                      decoration: BoxDecoration(
                        color: widget.isMe
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const _AudioWaveformPlaceholder(),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          // Play button (only when ready)
          isReady
              ? IconButton(
                  icon: Icon(
                    Icons.play_arrow,
                    color: widget.isMe ? Colors.white : Colors.black,
                  ),
                  onPressed: () {
                    // Play audio - actual implementation handled elsewhere
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                )
              : isUploading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: widget.message.uploadProgress > 0
                        ? widget.message.uploadProgress
                        : null,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      widget.isMe ? Colors.white70 : Colors.black54,
                    ),
                  ),
                )
              : const SizedBox(width: 32),
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

/// Audio waveform placeholder widget (WhatsApp-style bars)
class _AudioWaveformPlaceholder extends StatelessWidget {
  const _AudioWaveformPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(12, (index) {
        final heights = [
          8.0,
          16.0,
          12.0,
          20.0,
          14.0,
          18.0,
          10.0,
          22.0,
          16.0,
          12.0,
          20.0,
          14.0,
        ];
        return Container(
          width: 2,
          height: heights[index],
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
