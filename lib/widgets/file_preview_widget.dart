import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import '../models/message_model.dart';
import '../providers/chat_providers.dart';
import '../services/media_resolver.dart';
import '../services/voice_note_service.dart';
import '../theme/theme.dart';

String? _resolveMediaUrlOrNull(String raw, {String? bucket}) {
  final url = MediaResolver.resolve(raw, bucket: bucket);
  if (url == null || url.isEmpty) {
    MediaResolver.logOnceFailure(raw);
    return null;
  }
  return url;
}

final Set<String> _precacheRequested = <String>{};
final Map<String, ImageProvider> _sharedNetworkProviders =
    <String, ImageProvider>{};

String? _bestExistingLocalPath(MessageModel message) {
  final cached = message.cachedPath;
  if (cached != null && cached.isNotEmpty && File(cached).existsSync()) {
    return cached;
  }
  final local = message.localPath;
  if (local != null && local.isNotEmpty && File(local).existsSync()) {
    return local;
  }
  return null;
}

ImageProvider? _mediaPlaceholderProvider({
  required String? localPath,
  required String? thumbUrl,
}) {
  if (localPath != null && localPath.isNotEmpty) {
    final f = File(localPath);
    if (f.existsSync()) return FileImage(f);
  }
  if (thumbUrl != null && thumbUrl.isNotEmpty) {
    if (thumbUrl.startsWith('http://') || thumbUrl.startsWith('https://')) {
      return _sharedNetworkProvider(thumbUrl);
    }
    final f = File(thumbUrl);
    if (f.existsSync()) return FileImage(f);
  }
  return null;
}

ImageProvider _sharedNetworkProvider(String url) {
  return _sharedNetworkProviders.putIfAbsent(
    url,
    () => CachedNetworkImageProvider(url),
  );
}

Size _mediaBoxSize({
  required double maxW,
  required double maxH,
  required double minSize,
  required double aspectRatio,
}) {
  final ar = aspectRatio <= 0 ? 1.0 : aspectRatio;
  double width = maxW;
  double height = width / ar;

  if (height > maxH) {
    height = maxH;
    width = height * ar;
  }

  if (width < minSize) {
    width = minSize;
    height = width / ar;
  }

  if (height < minSize) {
    height = minSize;
    width = height * ar;
  }

  if (width > maxW) {
    width = maxW;
    height = width / ar;
  }

  if (height > maxH) {
    height = maxH;
    width = height * ar;
  }

  return Size(width, height);
}

class _UploadStatusOverlay extends StatelessWidget {
  final String status;
  final double progress;
  final RetryUpload onRetry;
  const _UploadStatusOverlay({
    required this.status,
    required this.progress,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (status != 'failed') return const SizedBox.shrink();
    // No retry UI (WhatsApp-like): keep showing placeholder.
    return const SizedBox.shrink();
  }
}

class _AudioPendingInline extends StatelessWidget {
  final bool isMe;
  final String status; // uploading | failed
  final double progress;
  const _AudioPendingInline({
    super.key,
    required this.isMe,
    required this.status,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isMe ? const Color(0xFF4752C4) : const Color(0xFF0F0F0F);
    final border = isMe
        ? null
        : Border.all(color: const Color(0xFF1A1A1A), width: 1);

    final label = status == 'failed' ? 'Failed to send' : 'Sending...';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status == 'failed'
                ? Icons.error_outline
                : Icons.watch_later_outlined,
            size: 18,
            color: Colors.white,
          ),
          const SizedBox(width: 10),
          Container(
            width: 110,
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: status == 'failed'
                    ? 1.0
                    : progress.clamp(0.0, 1.0),
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5865F2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            status == 'uploading'
                ? '${(progress.clamp(0.0, 1.0) * 100).round()}%'
                : label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class FilePreviewWidget extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final VoidCallback? onOpenOverride;
  final String? heroTag;
  const FilePreviewWidget({
    super.key,
    required this.message,
    required this.isMe,
    this.onOpenOverride,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return _FilePreviewContent(
      message: message,
      isMe: isMe,
      onOpenOverride: onOpenOverride,
      heroTag: heroTag,
    );
  }
}

typedef RetryUpload = Future<void> Function();

class _FilePreviewContent extends ConsumerWidget {
  final MessageModel message;
  final bool isMe;
  final VoidCallback? onOpenOverride;
  final String? heroTag;
  const _FilePreviewContent({
    required this.message,
    required this.isMe,
    this.onOpenOverride,
    this.heroTag,
  });

  Future<void> _retryUpload(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(chatServiceProvider).retryMediaUpload(message: message);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Retry failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> retry() => _retryUpload(context, ref);
    final rawUrl =
        (message.storagePath != null && message.storagePath!.isNotEmpty)
        ? message.storagePath
        : message.mediaUrl;
    if (message.messageType == MessageType.image &&
        rawUrl != null &&
        rawUrl.isNotEmpty &&
        _precacheRequested.add(rawUrl)) {
      final resolvedUrl = _resolveMediaUrlOrNull(
        rawUrl,
        bucket: message.bucket,
      );
      if (resolvedUrl != null && context.mounted) {
        final provider = _sharedNetworkProvider(resolvedUrl);
        unawaited(precacheImage(provider, context).catchError((_) {}));
      }
    }
    switch (message.messageType) {
      case MessageType.image:
        return _ImagePreview(
          message: message,
          isMe: isMe,
          onRetry: retry,
          onOpenOverride: onOpenOverride,
          heroTag: heroTag,
        );
      case MessageType.video:
        return _VideoPreview(
          message: message,
          isMe: isMe,
          onRetry: retry,
          onOpenOverride: onOpenOverride,
          heroTag: heroTag,
        );
      case MessageType.audio:
        return _AudioInline(message: message, isMe: isMe, onRetry: retry);
      case MessageType.file:
      default:
        return _FileTile(message: message, isMe: isMe, onRetry: retry);
    }
  }
}

class _ImagePreview extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final RetryUpload onRetry;
  final VoidCallback? onOpenOverride;
  final String? heroTag;
  const _ImagePreview({
    required this.message,
    required this.isMe,
    required this.onRetry,
    this.onOpenOverride,
    this.heroTag,
  });
  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  String? _resolved;
  double? _aspectRatio;
  bool _ready = false;
  bool _failed = false;
  bool _loaded = false;
  Timer? _failFastTimer;

  @override
  void initState() {
    super.initState();
    _failFastTimer?.cancel();
    _failFastTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_loaded) {
        setState(() => _failed = true);
      }
    });
    _init();
  }

  @override
  void didUpdateWidget(covariant _ImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUrl = oldWidget.message.mediaUrl;
    final newUrl = widget.message.mediaUrl;
    final oldLocal = _bestExistingLocalPath(oldWidget.message);
    final newLocal = _bestExistingLocalPath(widget.message);
    if (oldUrl != newUrl || oldLocal != newLocal) {
      setState(() {
        _resolved = null;
        _aspectRatio = null;
        _ready = false;
        _failed = false;
        _loaded = false;
      });
      _failFastTimer?.cancel();
      _failFastTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && !_loaded) {
          setState(() => _failed = true);
        }
      });
      _init();
    }
  }

  @override
  void dispose() {
    _failFastTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final local = _bestExistingLocalPath(widget.message);
    if (local != null) {
      if (!mounted) return;
      setState(() {
        _resolved = null;
        _ready = true;
      });
      return;
    }

    final v = (widget.message.storagePath ?? '').isNotEmpty
        ? (widget.message.storagePath ?? '')
        : (widget.message.mediaUrl ?? '');
    if (v.isEmpty) {
      if (!mounted) return;
      setState(() {
        _resolved = null;
        _aspectRatio = null;
        _ready = true;
      });
      return;
    }
    String? resolved;
    for (var attempt = 0; attempt < 3; attempt++) {
      resolved = _resolveMediaUrlOrNull(v, bucket: widget.message.bucket);
      if (resolved != null && resolved.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) return;
    setState(() {
      _ready = true;
      _resolved = resolved;
      _loaded = resolved != null && resolved.isNotEmpty;
      _failed = !_loaded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final local = _bestExistingLocalPath(widget.message);

    final placeholderProvider = _mediaPlaceholderProvider(
      localPath: local,
      thumbUrl: widget.message.thumbnailUrl,
    );
    final fallback = AppColors.highlight.withOpacity(0.65);

    final maxW = MediaQuery.of(context).size.width * 0.65;
    const minSize = 140.0;
    const maxH = 280.0;

    final ar = (_aspectRatio == null || _aspectRatio! <= 0)
        ? 1.0
        : _aspectRatio!.clamp(0.6, 1.4);

    final boxSize = _mediaBoxSize(
      maxW: maxW,
      maxH: maxH,
      minSize: minSize,
      aspectRatio: ar,
    );

    if (_failed && local == null) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxW,
          maxHeight: maxH,
          minWidth: minSize,
          minHeight: minSize,
        ),
        child: SizedBox(
          width: boxSize.width,
          height: boxSize.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _BlurredPlaceholder(
              image: placeholderProvider,
              blurred: true,
              fallback: fallback,
            ),
          ),
        ),
      );
    }

    if (!_ready) {
      final loadingChild = placeholderProvider != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                _BlurredPlaceholder(
                  image: placeholderProvider,
                  blurred: true,
                  fallback: fallback,
                ),
                const Opacity(opacity: 0.22, child: _ShimmerBox(radius: 14)),
              ],
            )
          : const _ShimmerBox(radius: 14);

      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxW,
          maxHeight: maxH,
          minWidth: minSize,
          minHeight: minSize,
        ),
        child: SizedBox(
          width: boxSize.width,
          height: boxSize.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: loadingChild,
          ),
        ),
      );
    }

    ImageProvider? actualProvider;
    String? actualKey;
    if (local != null && local.isNotEmpty) {
      actualProvider = FileImage(File(local));
      actualKey = 'local_${widget.message.id}';
    } else if (_resolved != null) {
      actualProvider = _sharedNetworkProvider(_resolved!);
      actualKey = 'network_${widget.message.id}';
    }

    if (_resolved == null) {
      final unresolvedPreview = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxW,
          maxHeight: maxH,
          minWidth: minSize,
          minHeight: minSize,
        ),
        child: SizedBox(
          width: boxSize.width,
          height: boxSize.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _BlurredPlaceholder(
                  image: placeholderProvider,
                  blurred: true,
                  fallback: fallback,
                ),
                if (actualProvider != null)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: Image(
                      key: ValueKey(actualKey),
                      image: actualProvider,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (_, __, ___) => _MediaErrorFallback(
                        placeholder: placeholderProvider,
                        onRetry: widget.onRetry,
                        fallback: fallback,
                      ),
                    ),
                  )
                else
                  // Loading state - show shimmer only, no retry UI
                  Container(
                    color: fallback,
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ),
                _UploadStatusOverlay(
                  status: widget.message.uploadStatus,
                  progress: widget.message.uploadProgress,
                  onRetry: widget.onRetry,
                ),
              ],
            ),
          ),
        ),
      );

      final heroWrapped = (widget.heroTag != null)
          ? Hero(tag: widget.heroTag!, child: unresolvedPreview)
          : unresolvedPreview;

      if (widget.onOpenOverride == null) return heroWrapped;

      return GestureDetector(onTap: widget.onOpenOverride, child: heroWrapped);
    }

    final preview = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxW,
        maxHeight: maxH,
        minWidth: minSize,
        minHeight: minSize,
      ),
      child: SizedBox(
        width: boxSize.width,
        height: boxSize.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _BlurredPlaceholder(
                image: placeholderProvider,
                blurred: true,
                fallback: fallback,
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: actualProvider != null
                    ? Image(
                        key: ValueKey(actualKey),
                        image: actualProvider,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => _MediaErrorFallback(
                          placeholder: placeholderProvider,
                          onRetry: widget.onRetry,
                          fallback: fallback,
                        ),
                      )
                    : const SizedBox.expand(),
              ),
              _UploadStatusOverlay(
                status: widget.message.uploadStatus,
                progress: widget.message.uploadProgress,
                onRetry: widget.onRetry,
              ),
              Positioned(
                right: 6,
                bottom: 6,
                child: _MediaMetaOverlay(
                  timestamp: widget.message.timestamp,
                  isMe: widget.isMe,
                  status: widget.message.status,
                  isPending: widget.message.hasPendingWrites,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final heroWrapped = (widget.heroTag != null)
        ? Hero(tag: widget.heroTag!, child: preview)
        : preview;

    return GestureDetector(
      onTap: () {
        final override = widget.onOpenOverride;
        if (override != null) {
          override();
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _SingleImageViewer(
              url: _resolved!,
              heroTag: widget.heroTag ?? _resolved!,
            ),
          ),
        );
      },
      child: heroWrapped,
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double radius;
  const _ShimmerBox({required this.radius});

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _BlurredPlaceholder extends StatelessWidget {
  final ImageProvider? image;
  final bool blurred;
  final Color fallback;
  const _BlurredPlaceholder({
    super.key,
    required this.image,
    required this.blurred,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    Widget base;
    if (image != null) {
      base = Image(
        image: image!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => ColoredBox(color: fallback),
      );
    } else {
      base = ColoredBox(color: fallback);
    }

    if (!blurred) return base;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: base,
    );
  }
}

class _MediaErrorFallback extends StatefulWidget {
  final ImageProvider? placeholder;
  final RetryUpload onRetry;
  final Color fallback;
  const _MediaErrorFallback({
    required this.placeholder,
    required this.onRetry,
    required this.fallback,
  });

  @override
  State<_MediaErrorFallback> createState() => _MediaErrorFallbackState();
}

class _MediaErrorFallbackState extends State<_MediaErrorFallback> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _BlurredPlaceholder(
          image: widget.placeholder,
          blurred: false,
          fallback: widget.fallback,
        ),
      ],
    );
  }
}

class _AudioSkeleton extends StatelessWidget {
  final bool isMe;
  final List<double> bars;
  const _AudioSkeleton({super.key, required this.isMe, required this.bars});

  @override
  Widget build(BuildContext context) {
    final bg = isMe ? const Color(0xFF4752C4) : const Color(0xFF0F0F0F);
    final unplayed = Colors.white.withOpacity(0.24);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: bg,
        child: SizedBox(
          width: 260,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.play_arrow,
                            color: Colors.white54,
                          ),
                          onPressed: null,
                        ),
                        Expanded(
                          child: SizedBox(
                            height: 34,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return CustomPaint(
                                  size: Size(constraints.maxWidth, 34),
                                  painter: _WaveformPainter(
                                    bars: bars,
                                    progress: 0.0,
                                    playedColor: Colors.white54,
                                    unplayedColor: unplayed,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 2),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(opacity: 0.18, child: _ShimmerBox(radius: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final a = Alignment(-1.0 + 2.0 * t, -0.2);
          final b = Alignment(-0.2 + 2.0 * t, 0.2);
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: a,
                end: b,
                colors: [
                  AppColors.highlight.withOpacity(0.55),
                  Colors.white,
                  AppColors.highlight.withOpacity(0.55),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final RetryUpload onRetry;
  final VoidCallback? onOpenOverride;
  final String? heroTag;
  const _VideoPreview({
    required this.message,
    required this.isMe,
    required this.onRetry,
    this.onOpenOverride,
    this.heroTag,
  });
  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late Future<String> _resolvedFuture;
  bool _cacheWriteStarted = false;
  VideoPlayerController? _warmController;
  String? _warmUrl;
  bool _prewarmRequested = false;
  Timer? _resolveRetryTimer;
  bool _failed = false;
  bool _loaded = false;
  Timer? _failFastTimer;

  @override
  void initState() {
    super.initState();
    _failFastTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_loaded) setState(() => _failed = true);
    });
    _resolvedFuture = _resolve();
  }

  @override
  void didUpdateWidget(covariant _VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUrl = oldWidget.message.mediaUrl;
    final newUrl = widget.message.mediaUrl;
    final oldLocal = _bestExistingLocalPath(oldWidget.message);
    final newLocal = _bestExistingLocalPath(widget.message);
    if (oldUrl != newUrl || oldLocal != newLocal) {
      setState(() {
        _resolvedFuture = _resolve();
        _cacheWriteStarted = false;
        _prewarmRequested = false;
      });
      _resolveRetryTimer?.cancel();
      _disposeWarmController();
    }
  }

  void _scheduleResolveRetry() {
    // No retry UI / no infinite loops.
  }

  Future<String> _resolve() async {
    final local = _bestExistingLocalPath(widget.message);
    if (local != null) {
      _loaded = true;
      return local;
    }
    final v = (widget.message.storagePath ?? '').isNotEmpty
        ? (widget.message.storagePath ?? '')
        : (widget.message.mediaUrl ?? '');
    if (v.isEmpty) {
      throw StateError('Empty video url');
    }
    String? resolved;
    for (var attempt = 0; attempt < 3; attempt++) {
      resolved = _resolveMediaUrlOrNull(v, bucket: widget.message.bucket);
      if (resolved != null && resolved.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (resolved == null || resolved.isEmpty) {
      _failed = true;
      throw StateError('Failed to resolve video url');
    }
    _loaded = true;
    return resolved;
  }

  Future<void> _cacheRemoteIfNeeded(String resolved) async {
    if (_cacheWriteStarted) return;
    final local = _bestExistingLocalPath(widget.message);
    if (local != null) return;
    if (!(resolved.startsWith('http://') || resolved.startsWith('https://'))) {
      return;
    }
    _cacheWriteStarted = true;
    try {
      final file = await DefaultCacheManager().getSingleFile(resolved);
      if (!file.existsSync()) return;
      await FirebaseFirestore.instance
          .collection('dmChats')
          .doc(widget.message.chatId)
          .collection('messages')
          .doc(widget.message.id)
          .set({'cachedPath': file.path}, SetOptions(merge: true));
    } catch (_) {
      _cacheWriteStarted = false;
    }
  }

  void _disposeWarmController() {
    final c = _warmController;
    _warmController = null;
    _warmUrl = null;
    c?.dispose();
  }

  Future<void> _ensureWarmController(String resolvedUrl) async {
    if (_warmUrl == resolvedUrl && _warmController != null) return;
    _disposeWarmController();
    _warmUrl = resolvedUrl;
    final isRemote =
        resolvedUrl.startsWith('http://') || resolvedUrl.startsWith('https://');
    final c = isRemote
        ? VideoPlayerController.networkUrl(Uri.parse(resolvedUrl))
        : VideoPlayerController.file(File(resolvedUrl));
    _warmController = c;
    try {
      await c.initialize();
      await c.pause();
    } catch (_) {
      _disposeWarmController();
    }
  }

  void _schedulePrewarm(String resolved) {
    if (_prewarmRequested) return;
    _prewarmRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final offset = box.localToGlobal(Offset.zero);
      final rect = offset & box.size;
      final screen = Offset.zero & MediaQuery.of(context).size;
      final intersection = rect.intersect(screen);
      if (intersection.isEmpty) return;
      final visibleFraction =
          (intersection.width * intersection.height) /
          (rect.width * rect.height);
      if (visibleFraction >= 0.2) {
        unawaited(_ensureWarmController(resolved));
      }
    });
  }

  @override
  void dispose() {
    _resolveRetryTimer?.cancel();
    _failFastTimer?.cancel();
    _disposeWarmController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thumb = widget.message.thumbnailUrl;
    final placeholderProvider = _mediaPlaceholderProvider(
      localPath: null,
      thumbUrl: thumb,
    );
    final fallback = AppColors.highlight.withOpacity(0.65);

    final maxW = MediaQuery.of(context).size.width * 0.65;
    const minSize = 140.0;
    const maxH = 280.0;
    const aspect = 16 / 9;
    final boxSize = _mediaBoxSize(
      maxW: maxW,
      maxH: maxH,
      minSize: minSize,
      aspectRatio: aspect,
    );

    if (_failed) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxW,
          maxHeight: maxH,
          minWidth: minSize,
          minHeight: minSize,
        ),
        child: SizedBox(
          width: boxSize.width,
          height: boxSize.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _BlurredPlaceholder(
              image: placeholderProvider,
              blurred: true,
              fallback: fallback,
            ),
          ),
        ),
      );
    }

    return FutureBuilder<String>(
      future: _resolvedFuture,
      builder: (context, snap) {
        if ((widget.message.mediaUrl ?? '').isEmpty &&
            thumb != null &&
            thumb.isNotEmpty) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxW,
              maxHeight: maxH,
              minWidth: minSize,
              minHeight: minSize,
            ),
            child: SizedBox(
              width: boxSize.width,
              height: boxSize.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(
                      image: FileImage(File(thumb)),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: AppColors.highlight.withOpacity(0.65),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                    _UploadStatusOverlay(
                      status: widget.message.uploadStatus,
                      progress: widget.message.uploadProgress,
                      onRetry: widget.onRetry,
                    ),
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: _MediaMetaOverlay(
                        timestamp: widget.message.timestamp,
                        isMe: widget.isMe,
                        status: widget.message.status,
                        isPending: widget.message.hasPendingWrites,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snap.connectionState != ConnectionState.done) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxW,
              maxHeight: maxH,
              minWidth: minSize,
              minHeight: minSize,
            ),
            child: SizedBox(
              width: boxSize.width,
              height: boxSize.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _BlurredPlaceholder(
                      image: placeholderProvider,
                      blurred: true,
                      fallback: fallback,
                    ),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                    const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snap.hasError || snap.data == null || (snap.data ?? '').isEmpty) {
          _scheduleResolveRetry();
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxW,
              maxHeight: maxH,
              minWidth: minSize,
              minHeight: minSize,
            ),
            child: SizedBox(
              width: boxSize.width,
              height: boxSize.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _BlurredPlaceholder(
                      image: placeholderProvider,
                      blurred: true,
                      fallback: fallback,
                    ),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                    const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: _MediaMetaOverlay(
                        timestamp: widget.message.timestamp,
                        isMe: widget.isMe,
                        status: widget.message.status,
                        isPending: widget.message.hasPendingWrites,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final resolved = snap.data;

        if (resolved != null && resolved.isNotEmpty) {
          unawaited(_cacheRemoteIfNeeded(resolved));
          _schedulePrewarm(resolved);
        }

        // Duration badge requires duration metadata; keep null for now.
        final String? durationLabel = null;

        Widget content = ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxW,
            maxHeight: maxH,
            minWidth: minSize,
            minHeight: minSize,
          ),
          child: SizedBox(
            width: boxSize.width,
            height: boxSize.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: _BlurredPlaceholder(
                      key: ValueKey(resolved == null ? 'blur' : 'sharp'),
                      image: placeholderProvider,
                      blurred: resolved == null,
                      fallback: fallback,
                    ),
                  ),
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 44,
                      color: Colors.white,
                    ),
                  ),
                  if (durationLabel != null)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Text(
                        durationLabel,
                        style: const TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              offset: Offset(0, 1),
                              blurRadius: 2,
                              color: Colors.black54,
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: _MediaMetaOverlay(
                      timestamp: widget.message.timestamp,
                      isMe: widget.isMe,
                      status: widget.message.status,
                      isPending: widget.message.hasPendingWrites,
                    ),
                  ),
                  _UploadStatusOverlay(
                    status: widget.message.uploadStatus,
                    progress: widget.message.uploadProgress,
                    onRetry: widget.onRetry,
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        final override = widget.onOpenOverride;
                        if (override != null) {
                          override();
                          return;
                        }
                        // Fallback to legacy fullscreen
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _VideoFullscreen(
                              url: widget.message.mediaUrl ?? '',
                              type: widget.message.messageType,
                              bucket: widget.message.bucket,
                            ),
                          ),
                        );
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        // Wrap with Hero if heroTag is provided
        if (widget.heroTag != null) {
          content = Hero(
            tag: widget.heroTag!,
            child: Material(color: Colors.transparent, child: content),
          );
        }

        return content;
      },
    );
  }
}

class _AudioInline extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final RetryUpload onRetry;
  const _AudioInline({
    required this.message,
    required this.isMe,
    required this.onRetry,
  });
  @override
  State<_AudioInline> createState() => _AudioInlineState();
}

class _AudioInlineState extends State<_AudioInline> {
  late final AudioPlayer _player;
  bool _loading = true;
  bool _failed = false;
  bool _loaded = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late final List<double> _bars;
  bool _cacheWriteStarted = false;
  bool _downloadLoopStarted = false;
  bool _sourceSet = false;
  bool _usingLocal = false;
  String? _resolvedStreamingUrl;
  bool _isPrewarmed = false;
  bool _optimisticPlaying = false;
  int _downloadAttempts = 0;
  Timer? _failFastTimer;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _bars = _generateBars(widget.message.mediaUrl ?? widget.message.id);
    _failFastTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_loaded) {
        setState(() => _failed = true);
      }
    });
    unawaited(_resolveAndWarm());
    _startAutoDownload();
  }

  @override
  void didUpdateWidget(covariant _AudioInline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldLocal = _bestExistingLocalPath(oldWidget.message);
    final newLocal = _bestExistingLocalPath(widget.message);
    final oldUrl = oldWidget.message.mediaUrl;
    final newUrl = widget.message.mediaUrl;
    if (oldLocal != newLocal || oldUrl != newUrl) {
      _cacheWriteStarted = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _loading = true;
      _downloadLoopStarted = false;
      _downloadAttempts = 0;
      _sourceSet = false;
      _usingLocal = false;
      _resolvedStreamingUrl = null;
      _isPrewarmed = false;
      _optimisticPlaying = false;
      unawaited(_resolveAndWarm());
      unawaited(_startAutoDownload());
    }
  }

  Future<void> _resolveAndWarm() async {
    try {
      if (_isPrewarmed || _sourceSet) {
        unawaited(_player.play());
        return;
      }
      // Check for existing local file first (offline playback)
      final existing = _bestExistingLocalPath(widget.message);
      if (existing != null && existing.isNotEmpty) {
        await _player.setAudioSource(AudioSource.file(existing));
        await _player.load();
        _duration = _player.duration ?? Duration.zero;
        await _wirePlayerStreams();
        _sourceSet = true;
        _usingLocal = true;
        _isPrewarmed = true;
        if (mounted) {
          setState(() => _loading = false);
        }
        _loaded = true;
        return;
      }

      // Resolve URL from the strict single-format field first.
      // Fall back to legacy fields for backwards compatibility.
      final raw = ((widget.message.storagePath ?? '').trim().isNotEmpty)
          ? (widget.message.storagePath ?? '').trim()
          : ((widget.message.mediaUrl ?? '').trim().isNotEmpty)
          ? (widget.message.mediaUrl ?? '').trim()
          : (widget.message.mediaPath ?? '').trim();
      if (raw.isEmpty) return;

      final resolved = VoiceNoteService.resolveUrl(
        raw,
        bucket: widget.message.bucket,
      );
      if (resolved.isEmpty) return;

      _resolvedStreamingUrl = resolved;

      // Prewarm for instant playback - stream while downloading
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(resolved)),
        preload: true,
      );
      await _player.load();
      _duration = _player.duration ?? Duration.zero;
      await _wirePlayerStreams();
      _sourceSet = true;
      _usingLocal = false;
      _isPrewarmed = true;
      if (mounted) {
        setState(() => _loading = false);
      }
      _loaded = true;
    } catch (_) {
      // Silent fail - background download will retry
    }
  }

  Future<void> _playWhenReady() async {
    try {
      if (_isPrewarmed || _sourceSet) {
        unawaited(_player.play());
        return;
      }

      await _resolveAndWarm();
      if (_sourceSet) unawaited(_player.play());
    } catch (_) {
      // silent
    }
  }

  Future<void> _persistCachedPathIfNeeded(String filePath) async {
    if (_cacheWriteStarted) return;
    if (_bestExistingLocalPath(widget.message) != null) return;
    _cacheWriteStarted = true;
    try {
      await FirebaseFirestore.instance
          .collection('dmChats')
          .doc(widget.message.chatId)
          .collection('messages')
          .doc(widget.message.id)
          .set({'cachedPath': filePath}, SetOptions(merge: true));
    } catch (_) {
      _cacheWriteStarted = false;
    }
  }

  Future<void> _wirePlayerStreams() async {
    await _posSub?.cancel();
    _posSub = _player.positionStream.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });

    await _durSub?.cancel();
    _durSub = _player.durationStream.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d ?? Duration.zero);
    });

    await _stateSub?.cancel();
    _stateSub = _player.playerStateStream.listen((s) {
      if (!mounted) return;
      final nowPlaying = _player.playing;
      if (_optimisticPlaying != nowPlaying) {
        setState(() => _optimisticPlaying = nowPlaying);
      }
      if (s.processingState == ProcessingState.completed) {
        unawaited(_player.seek(Duration.zero));
        unawaited(_player.pause());
        setState(() => _position = Duration.zero);
      }
    });
  }

  Future<void> _startAutoDownload() async {
    if (_downloadLoopStarted) return;
    _downloadLoopStarted = true;
    if (!_sourceSet && mounted) setState(() => _loading = true);

    // Silent retry (max 3 attempts) - never infinite.
    while (mounted && _downloadAttempts < 3) {
      try {
        // Check for existing local file first
        final existing = _bestExistingLocalPath(widget.message);
        if (existing != null && existing.isNotEmpty) {
          if (!_sourceSet) {
            await _player.setAudioSource(AudioSource.file(existing));
            await _player.load();
            _duration = _player.duration ?? Duration.zero;
            await _wirePlayerStreams();
            _sourceSet = true;
            _usingLocal = true;
            _isPrewarmed = true;
            if (mounted) {
              setState(() => _loading = false);
            }
          }
          return; // Successfully using local file
        }

        final raw = ((widget.message.storagePath ?? '').trim().isNotEmpty)
            ? (widget.message.storagePath ?? '').trim()
            : ((widget.message.mediaUrl ?? '').trim().isNotEmpty)
            ? (widget.message.mediaUrl ?? '').trim()
            : (widget.message.mediaPath ?? '').trim();
        if (raw.isEmpty) {
          await Future.delayed(const Duration(seconds: 2));
          _downloadAttempts++;
          continue;
        }

        // Resolve URL if not already done
        final resolved =
            _resolvedStreamingUrl ??
            VoiceNoteService.resolveUrl(raw, bucket: widget.message.bucket);
        if (resolved.isEmpty) {
          await Future.delayed(const Duration(seconds: 2));
          _downloadAttempts++;
          continue;
        }
        _resolvedStreamingUrl ??= resolved;

        // Start streaming immediately if not already set
        if (!_sourceSet) {
          unawaited(_resolveAndWarm());
        }

        // Try to download and cache
        final file = await VoiceNoteService.downloadWithRetry(
          resolved,
          onComplete: (f) {},
          onRetry: (attempt, error) {
            if (kDebugMode) {
              debugPrint('🔄 Voice note download retry #$attempt: $error');
            }
          },
        );

        if (file != null && file.existsSync()) {
          await _persistCachedPathIfNeeded(file.path);

          // Switch to local file for better playback
          if (!_usingLocal) {
            final wasPlaying = _player.playing;
            final pos = _player.position;
            await _player.setAudioSource(AudioSource.file(file.path));
            await _player.load();
            _duration = _player.duration ?? Duration.zero;
            await _wirePlayerStreams();
            _usingLocal = true;
            _sourceSet = true;
            _isPrewarmed = true;
            await _player.seek(pos);
            if (wasPlaying) {
              unawaited(_player.play());
            }
            if (mounted) {
              setState(() => _loading = false);
            }
          }
          return; // Successfully downloaded and cached
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Voice note download error: $e');
        }
      }

      _downloadAttempts++;
      if (_downloadAttempts < 3) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    // After max attempts, stop trying but keep showing skeleton
    // User can still play via streaming if that worked
  }

  @override
  void dispose() {
    _failFastTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_failed && _bestExistingLocalPath(widget.message) == null) {
      content = _AudioSkeleton(
        key: const ValueKey('failed'),
        isMe: widget.isMe,
        bars: _bars,
      );
    } else if (widget.message.uploadStatus == 'failed') {
      content = _AudioPendingInline(
        key: const ValueKey('upload_failed'),
        isMe: widget.isMe,
        status: widget.message.uploadStatus,
        progress: widget.message.uploadProgress,
      );
    } else if (widget.message.uploadStatus == 'uploading' &&
        _bestExistingLocalPath(widget.message) == null) {
      content = _AudioPendingInline(
        key: const ValueKey('uploading'),
        isMe: widget.isMe,
        status: widget.message.uploadStatus,
        progress: widget.message.uploadProgress,
      );
    } else if (_loading) {
      content = _AudioSkeleton(
        key: const ValueKey('loading'),
        isMe: widget.isMe,
        bars: _bars,
      );
    } else {
      final playing = _player.playing || _optimisticPlaying;
      const mainColor = Color(0xFFFFFFFF);
      const playedColor = Color(0xFFFFFFFF);
      final unplayedColor = Colors.white.withOpacity(0.24);
      final bg = widget.isMe
          ? const Color(0xFF4752C4)
          : const Color(0xFF0F0F0F);
      content = ClipRRect(
        key: const ValueKey('ready'),
        borderRadius: BorderRadius.circular(14),
        child: ColoredBox(
          color: bg,
          child: SizedBox(
            width: 260,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                          color: mainColor,
                        ),
                        onPressed: () {
                          if (playing) {
                            setState(() => _optimisticPlaying = false);
                            unawaited(_player.pause());
                            return;
                          }
                          setState(() => _optimisticPlaying = true);
                          unawaited(_playWhenReady());
                        },
                      ),
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final w = constraints.maxWidth;
                              final progress = _duration.inMilliseconds == 0
                                  ? 0.0
                                  : _position.inMilliseconds /
                                        _duration.inMilliseconds;
                              return Stack(
                                children: [
                                  CustomPaint(
                                    size: Size(w, 34),
                                    painter: _WaveformPainter(
                                      bars: _bars,
                                      progress: progress,
                                      playedColor: playedColor,
                                      unplayedColor: unplayedColor,
                                    ),
                                  ),
                                  Positioned(
                                    left: (w * progress).clamp(0.0, w - 10.0),
                                    top: 12,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: mainColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onHorizontalDragUpdate: (d) {
                                        final dx = d.localPosition.dx.clamp(
                                          0.0,
                                          w,
                                        );
                                        final ratio = dx / w;
                                        final ms =
                                            (_duration.inMilliseconds * ratio)
                                                .toInt();
                                        _player.seek(
                                          Duration(milliseconds: ms),
                                        );
                                      },
                                      onTapDown: (d) {
                                        final dx = d.localPosition.dx.clamp(
                                          0.0,
                                          w,
                                        );
                                        final ratio = dx / w;
                                        final ms =
                                            (_duration.inMilliseconds * ratio)
                                                .toInt();
                                        _player.seek(
                                          Duration(milliseconds: ms),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8.0, top: 2),
                      child: Text(
                        '${_format(_position)} / ${_format(_duration)}',
                        style: TextStyle(fontSize: 11, color: mainColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: content,
    );
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress; // 0..1
  final Color playedColor;
  final Color unplayedColor;
  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = bars.length;
    final spacing = 2.0;
    final barWidth = (size.width - (barCount - 1) * spacing) / barCount;
    final playedBars = (barCount * progress)
        .clamp(0, barCount.toDouble())
        .toInt();
    final paint = Paint()..strokeCap = StrokeCap.round;

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + spacing);
      final h = (bars[i] * (size.height - 6)).clamp(6.0, size.height - 2);
      final y = (size.height - h) / 2;
      paint.color = i <= playedBars ? playedColor : unplayedColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.bars != bars ||
        oldDelegate.playedColor != playedColor ||
        oldDelegate.unplayedColor != unplayedColor;
  }
}

List<double> _generateBars(String seed) {
  final r = math.Random(seed.hashCode);
  return List.generate(48, (i) => 0.3 + r.nextDouble() * 0.7);
}

class _FileTile extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final RetryUpload onRetry;
  const _FileTile({
    required this.message,
    required this.isMe,
    required this.onRetry,
  });

  String _ext(String name) {
    final i = name.lastIndexOf('.');
    if (i == -1) return '';
    return name.substring(i + 1).toUpperCase();
  }

  String _fmtSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    const kb = 1024;
    const mb = 1024 * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  IconData _iconForExt(String ext) {
    switch (ext) {
      case 'PDF':
        return Icons.picture_as_pdf_rounded;
      case 'PPT':
      case 'PPTX':
        return Icons.slideshow_rounded;
      case 'DOC':
      case 'DOCX':
        return Icons.description_rounded;
      case 'XLS':
      case 'XLSX':
        return Icons.grid_on_rounded;
      case 'ZIP':
      case 'RAR':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = _bestExistingLocalPath(message);
    final rawUrl = (message.storagePath ?? '').isNotEmpty
        ? (message.storagePath ?? '')
        : (message.mediaUrl ?? '');
    return FutureBuilder<String?>(
      future: () async {
        if (local != null) return local;
        if (rawUrl.isEmpty) {
          return null;
        }
        String? resolved;
        for (var attempt = 0; attempt < 3; attempt++) {
          resolved = _resolveMediaUrlOrNull(rawUrl, bucket: message.bucket);
          if (resolved != null && resolved.isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (resolved == null || resolved.isEmpty) {
          return null;
        }
        if ((resolved.startsWith('http://') ||
                resolved.startsWith('https://')) &&
            message.cachedPath == null) {
          try {
            final file = await DefaultCacheManager().getSingleFile(resolved);
            if (file.existsSync()) {
              await FirebaseFirestore.instance
                  .collection('dmChats')
                  .doc(message.chatId)
                  .collection('messages')
                  .doc(message.id)
                  .set({'cachedPath': file.path}, SetOptions(merge: true));
            }
          } catch (_) {}
        }
        return resolved;
      }(),
      builder: (context, snap) {
        final nameSource = local ?? rawUrl;
        final name = nameSource.split('/').last;
        const tc = Color(0xFFFFFFFF);
        final ext = _ext(name);
        final sizeLabel = _fmtSize(message.mediaSize);
        final bg = isMe ? AppColors.navy : AppColors.surface;
        final uploading = message.uploadStatus == 'uploading';
        final failed = message.uploadStatus == 'failed';
        return GestureDetector(
          onTap: () {
            final u = snap.data;
            if (u == null || u.isEmpty) return;
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => _PdfMaybe(url: u)));
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                ColoredBox(
                  color: bg,
                  child: SizedBox(
                    width: 260,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: Icon(
                                _iconForExt(ext),
                                color: tc,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: tc,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    if (ext.isNotEmpty) ext,
                                    if (sizeLabel.isNotEmpty) sizeLabel,
                                  ].join(' - '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: tc,
                                    fontSize: 11,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.open_in_new, color: tc, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                if (uploading || failed)
                  Positioned.fill(child: ColoredBox(color: Colors.black26)),
                _UploadStatusOverlay(
                  status: message.uploadStatus,
                  progress: message.uploadProgress,
                  onRetry: onRetry,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MediaMetaOverlay extends StatelessWidget {
  final Timestamp timestamp;
  final bool isMe;
  final int status;
  final bool isPending;
  const _MediaMetaOverlay({
    required this.timestamp,
    required this.isMe,
    required this.status,
    required this.isPending,
  });

  String _formatTime() {
    final dt = timestamp.toDate();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  IconData _tickIcon() {
    if (isPending) return Icons.watch_later_outlined;
    switch (status) {
      case 1:
        return Icons.done;
      case 2:
        return Icons.done;
      case 3:
        return Icons.done_all_rounded;
      default:
        return Icons.watch_later_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatTime(),
          style: const TextStyle(
            fontSize: 10,
            height: 1.1,
            color: Color(0xFFFFFFFF),
            shadows: [
              Shadow(
                offset: Offset(0, 1),
                blurRadius: 2,
                color: Colors.black54,
              ),
            ],
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          Icon(
            _tickIcon(),
            size: 12,
            color: const Color(0xFFFFFFFF),
            shadows: const [
              Shadow(
                offset: Offset(0, 1),
                blurRadius: 2,
                color: Colors.black54,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PdfMaybe extends StatelessWidget {
  final String url;
  const _PdfMaybe({required this.url});
  @override
  Widget build(BuildContext context) {
    if (url.toLowerCase().endsWith('.pdf')) {
      return FutureBuilder<http.Response>(
        future: http.get(Uri.parse(url)),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Scaffold(
              backgroundColor: Colors.black,
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError || snap.data!.statusCode != 200) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: Text('Failed to load PDF (${snap.data?.statusCode})'),
              ),
            );
          }
          final bytes = snap.data!.bodyBytes;
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(),
            body: PdfViewPinch(
              controller: PdfControllerPinch(
                document: PdfDocument.openData(bytes),
              ),
            ),
          );
        },
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(),
      body: Center(
        child: SelectableText(url, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _SingleImageViewer extends StatefulWidget {
  final String url;
  final String heroTag;
  const _SingleImageViewer({required this.url, required this.heroTag});

  @override
  State<_SingleImageViewer> createState() => _SingleImageViewerState();
}

class _SingleImageViewerState extends State<_SingleImageViewer> {
  bool _showUi = true;
  bool _ready = false;
  bool _failed = false;
  double _dragDy = 0;

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    setState(() => _dragDy += d.delta.dy);
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy.abs();
    final dy = _dragDy.abs();
    if (dy > 120 || v > 900) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _dragDy = 0);
  }

  @override
  Widget build(BuildContext context) {
    final provider = _sharedNetworkProvider(widget.url);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showUi = !_showUi),
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              color: Colors.black.withOpacity(
                (1.0 - (_dragDy.abs() / 280).clamp(0.0, 0.6)),
              ),
            ),
            Transform.translate(
              offset: Offset(0, _dragDy),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _BlurredPlaceholder(
                    image: provider,
                    blurred: true,
                    fallback: Colors.black54,
                  ),
                  AnimatedOpacity(
                    opacity: _ready ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Hero(
                      tag: widget.heroTag,
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: Image(
                          image: provider,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                          frameBuilder: (context, child, frame, wasSync) {
                            if (frame != null && !_ready) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) setState(() => _ready = true);
                              });
                            }
                            return child;
                          },
                          errorBuilder: (_, __, ___) {
                            if (!_failed) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) setState(() => _failed = true);
                              });
                            }
                            return const ColoredBox(color: Colors.black54);
                          },
                        ),
                      ),
                    ),
                  ),
                  if (_failed)
                    Center(
                      child: Material(
                        color: Colors.black45,
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () => setState(() {
                            _failed = false;
                            _ready = false;
                          }),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _showUi ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Text(
                          '1 / 1',
                          style: TextStyle(color: Colors.white),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.download,
                                color: Colors.white,
                              ),
                              onPressed: () async {
                                await launchUrl(
                                  Uri.parse(widget.url),
                                  mode: LaunchMode.externalApplication,
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.share,
                                color: Colors.white,
                              ),
                              onPressed: () {},
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoFullscreen extends StatefulWidget {
  final String url;
  final MessageType type;
  final String? bucket;
  const _VideoFullscreen({required this.url, required this.type, this.bucket});
  @override
  State<_VideoFullscreen> createState() => _VideoFullscreenState();
}

class _VideoFullscreenState extends State<_VideoFullscreen> {
  late VideoPlayerController _ctl;
  bool _ready = false;
  String? _resolved;
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final v = widget.url;
    String? u;
    for (var attempt = 0; attempt < 3; attempt++) {
      u = _resolveMediaUrlOrNull(v, bucket: widget.bucket);
      if (u != null && u.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (u == null || u.isEmpty) {
      if (mounted) setState(() => _ready = true);
      return;
    }
    _ctl = VideoPlayerController.networkUrl(Uri.parse(u));
    await _ctl.initialize();
    _ctl.play();
    if (mounted) {
      setState(() {
        _ready = true;
        _resolved = u;
      });
    }
  }

  @override
  void dispose() {
    // ensure playback stops when leaving fullscreen
    if (_ctl.value.isPlaying) {
      _ctl.pause();
    }
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        actions: [
          if (_resolved != null)
            IconButton(
              icon: const Icon(Icons.download_rounded),
              onPressed: () async {
                await launchUrl(
                  Uri.parse(_resolved!),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
        ],
      ),
      body: Center(
        child: _ready
            ? AspectRatio(
                aspectRatio: _ctl.value.aspectRatio,
                child: _FullscreenVideoControls(controller: _ctl),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class _FullscreenVideoControls extends StatefulWidget {
  final VideoPlayerController controller;
  const _FullscreenVideoControls({required this.controller});
  @override
  State<_FullscreenVideoControls> createState() =>
      _FullscreenVideoControlsState();
}

class _FullscreenVideoControlsState extends State<_FullscreenVideoControls> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ctl = widget.controller;
    final v = ctl.value;
    final pos = v.position;
    final dur = v.duration;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // toggle play/pause on tap
        ctl.value.isPlaying ? ctl.pause() : ctl.play();
      },
      child: Stack(
        children: [
          VideoPlayer(ctl),
          // Center overlay play button only when paused
          if (!v.isPlaying)
            const Align(
              alignment: Alignment.center,
              child: Icon(Icons.play_circle, size: 72, color: Colors.white70),
            ),
          // Bottom controls: play/pause + slider + time
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      v.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    onPressed: () => v.isPlaying ? ctl.pause() : ctl.play(),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                      ),
                      child: Slider(
                        value: pos.inMilliseconds
                            .clamp(0, dur.inMilliseconds)
                            .toDouble(),
                        min: 0,
                        max: dur.inMilliseconds == 0
                            ? 1
                            : dur.inMilliseconds.toDouble(),
                        activeColor: Colors.white,
                        inactiveColor: Colors.white38,
                        onChanged: (v) =>
                            ctl.seekTo(Duration(milliseconds: v.toInt())),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6.0, right: 4.0),
                    child: Text(
                      '${_fmt(pos)} / ${_fmt(dur)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
