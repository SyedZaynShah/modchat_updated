import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math' as math;
import '../models/message_model.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../theme/theme.dart';

Future<String> _resolveMediaUrl(String raw, MessageType type) {
  if (raw.isEmpty) {
    return Future.error(StateError('Empty media url'));
  }
  // sb://bucket/path or https://... or any other url
  if (raw.startsWith('sb://') ||
      raw.startsWith('http://') ||
      raw.startsWith('https://')) {
    return SupabaseService.instance.resolveUrl(directUrl: raw);
  }
  // Raw storage path: sign using the right bucket.
  final bucket = type == MessageType.audio
      ? StorageService().audioBucket
      : StorageService().mediaBucket;
  return SupabaseService.instance.resolveUrl(bucket: bucket, path: raw);
}

class _AudioPendingInline extends StatelessWidget {
  final bool isMe;
  final String status; // uploading | failed
  const _AudioPendingInline({required this.isMe, required this.status});

  @override
  Widget build(BuildContext context) {
    final bg = isMe ? const Color(0xFF7A1F3D) : const Color(0xFF0F0F0F);
    final border = isMe
        ? null
        : Border.all(color: const Color(0xFF1A1A1A), width: 1);

    final label = status == 'failed' ? 'Failed to send' : 'Sending…';

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
                widthFactor: status == 'failed' ? 1.0 : 0.55,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC74B6C),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
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
  const FilePreviewWidget({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final url = message.mediaUrl ?? '';
    switch (message.messageType) {
      case MessageType.image:
        return _ImagePreview(message: message, isMe: isMe);
      case MessageType.video:
        return _VideoPreview(message: message, isMe: isMe);
      case MessageType.audio:
        if (message.uploadStatus != 'done') {
          return _AudioPendingInline(isMe: isMe, status: message.uploadStatus);
        }
        return _AudioInline(url: url, type: message.messageType, isMe: isMe);
      case MessageType.file:
      default:
        return _FileTile(
          url: url,
          type: message.messageType,
          isMe: isMe,
          sizeBytes: message.mediaSize,
        );
    }
  }
}

class _ImagePreview extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  const _ImagePreview({required this.message, required this.isMe});
  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  String? _resolved;
  double? _aspectRatio;
  bool _ready = false;

  static const Duration _resolveTimeout = Duration(seconds: 6);
  static const Duration _probeTimeout = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant _ImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUrl = oldWidget.message.mediaUrl;
    final newUrl = widget.message.mediaUrl;
    if (oldUrl != newUrl) {
      setState(() {
        _resolved = null;
        _aspectRatio = null;
        _ready = false;
      });
      _init();
    }
  }

  Future<void> _init() async {
    final v = widget.message.mediaUrl ?? '';
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
    try {
      resolved = await _resolveMediaUrl(
        v,
        widget.message.messageType,
      ).timeout(_resolveTimeout);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolved = null;
        _aspectRatio = null;
        _ready = true;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _resolved = resolved;
      _ready = true;
    });

    // Probe dimensions asynchronously to refine aspect ratio without blocking paint.
    final img = Image.network(resolved);
    final c = Completer<ImageInfo>();
    final stream = img.image.resolve(const ImageConfiguration());
    late final ImageStreamListener l;
    l = ImageStreamListener(
      (info, _) {
        if (!c.isCompleted) c.complete(info);
      },
      onError: (e, st) {
        if (!c.isCompleted) c.completeError(e, st);
      },
    );
    stream.addListener(l);
    try {
      final info = await c.future.timeout(_probeTimeout);
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (!mounted) return;
      final ar = (h == 0) ? null : (w / h);
      if (ar != null && ar > 0) {
        setState(() => _aspectRatio = ar);
      }
    } catch (_) {
      // ignore
    } finally {
      stream.removeListener(l);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      final screenW = MediaQuery.of(context).size.width;
      final maxBubbleW = screenW * 0.70;
      return SizedBox(
        width: maxBubbleW,
        height: maxBubbleW * 0.72,
        child: const _ShimmerBox(radius: 14),
      );
    }

    if (_resolved == null) {
      final screenW = MediaQuery.of(context).size.width;
      final maxBubbleW = screenW * 0.70;
      return SizedBox(
        width: maxBubbleW,
        height: maxBubbleW * 0.72,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: _MediaErrorBox(icon: Icons.broken_image_outlined),
        ),
      );
    }

    final screenW = MediaQuery.of(context).size.width;
    final maxBubbleW = screenW * 0.70;
    final ar = (_aspectRatio == null || _aspectRatio! <= 0)
        ? 1.0
        : _aspectRatio!;
    final targetW = maxBubbleW;
    final targetH = (targetW / ar).clamp(160.0, 360.0);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                actions: [
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
              body: PhotoView.customChild(
                child: Image.network(
                  _resolved!,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 48,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: targetW,
          height: targetH,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: _resolved!,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (context, _) => const _ShimmerBox(radius: 14),
                errorWidget: (context, _, __) => ColoredBox(
                  color: AppColors.highlight.withOpacity(0.65),
                  child: const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.black54,
                      size: 28,
                    ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double radius;
  const _ShimmerBox({required this.radius});

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
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
  const _VideoPreview({required this.message, required this.isMe});
  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late Future<String> _resolvedFuture;
  VideoPlayerController? _controller;
  String? _resolvedUrl;

  static const Duration _resolveTimeout = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _resolvedFuture = _resolve();
  }

  @override
  void didUpdateWidget(covariant _VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUrl = oldWidget.message.mediaUrl;
    final newUrl = widget.message.mediaUrl;
    if (oldUrl != newUrl) {
      setState(() {
        _resolvedFuture = _resolve();
      });
      _disposeController();
    }
  }

  Future<String> _resolve() async {
    final v = widget.message.mediaUrl ?? '';
    if (v.isEmpty) {
      throw StateError('Empty video url');
    }
    return _resolveMediaUrl(
      v,
      widget.message.messageType,
    ).timeout(_resolveTimeout);
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    final c = _controller;
    _controller = null;
    _resolvedUrl = null;
    c?.dispose();
  }

  Future<void> _ensureController(String resolvedUrl) async {
    if (_resolvedUrl == resolvedUrl && _controller != null) return;

    _disposeController();
    _resolvedUrl = resolvedUrl;
    final c = VideoPlayerController.networkUrl(Uri.parse(resolvedUrl));
    _controller = c;
    try {
      await c.initialize();
      await c.setLooping(false);
      await c.pause();
      if (mounted) setState(() {});
    } catch (_) {
      // If initialization fails, we'll fall back to the color placeholder.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _resolvedFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          final screenW = MediaQuery.of(context).size.width;
          final maxBubbleW = screenW * 0.70;
          return SizedBox(
            width: maxBubbleW,
            height: maxBubbleW * 0.62,
            child: const _ShimmerBox(radius: 14),
          );
        }

        if (snap.hasError || snap.data == null || (snap.data ?? '').isEmpty) {
          final screenW = MediaQuery.of(context).size.width;
          final maxBubbleW = screenW * 0.70;
          final targetW = maxBubbleW;
          final targetH = (targetW / (16 / 9)).clamp(160.0, 360.0);
          return SizedBox(
            width: targetW,
            height: targetH,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const _ShimmerBox(radius: 14),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 18,
                      color: Colors.white,
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
          );
        }

        final resolved = snap.data;
        final screenW = MediaQuery.of(context).size.width;
        final maxBubbleW = screenW * 0.70;
        final targetW = maxBubbleW;
        final targetH = (targetW / (16 / 9)).clamp(160.0, 360.0);

        if (resolved != null && resolved.isNotEmpty) {
          // Initialize controller to show first frame as a thumbnail.
          unawaited(_ensureController(resolved));
        }

        // Duration badge requires duration metadata; keep null for now.
        final String? durationLabel = null;

        return SizedBox(
          width: targetW,
          height: targetH,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (resolved == null)
                  const _ShimmerBox(radius: 14)
                else if (_controller != null &&
                    _controller!.value.isInitialized)
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: _controller!.value.size.width,
                      height: _controller!.value.size.height,
                      child: VideoPlayer(_controller!),
                    ),
                  )
                else
                  ColoredBox(
                    color: AppColors.highlight.withOpacity(0.65),
                    child: const SizedBox.expand(),
                  ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 18,
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
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _VideoFullscreen(
                            url: widget.message.mediaUrl ?? '',
                            type: widget.message.messageType,
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
        );
      },
    );
  }
}

class _AudioInline extends StatefulWidget {
  final String url;
  final MessageType type;
  final bool isMe;
  const _AudioInline({
    required this.url,
    required this.type,
    required this.isMe,
  });
  @override
  State<_AudioInline> createState() => _AudioInlineState();
}

class _AudioInlineState extends State<_AudioInline> {
  late final AudioPlayer _player;
  bool _loading = true;
  Object? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late final List<double> _bars;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _bars = _generateBars(widget.url);
    _init();
  }

  Future<void> _init() async {
    try {
      final v = widget.url;
      if (v.isEmpty) {
        _error = StateError('Empty audio url');
        return;
      }
      final u = await _resolveMediaUrl(v, widget.type);
      await _player.setUrl(u);
      _duration = _player.duration ?? Duration.zero;

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
        if (s.processingState == ProcessingState.completed) {
          // Reset to start and pause so next play starts from 0.
          unawaited(_player.seek(Duration.zero));
          unawaited(_player.pause());
          setState(() => _position = Duration.zero);
        }
      });
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 220,
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_error != null) {
      final bg = widget.isMe
          ? const Color(0xFF7A1F3D)
          : const Color(0xFF0F0F0F);
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ColoredBox(
          color: bg,
          child: const SizedBox(
            width: 260,
            height: 54,
            child: Row(
              children: [
                SizedBox(width: 12),
                Icon(Icons.volume_off, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Audio unavailable',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(width: 12),
              ],
            ),
          ),
        ),
      );
    }
    final playing = _player.playing;
    const mainColor = Color(0xFFFFFFFF);
    const playedColor = Color(0xFFFFFFFF);
    final unplayedColor = Colors.white.withOpacity(0.24);
    final bg = widget.isMe ? const Color(0xFF7A1F3D) : const Color(0xFF0F0F0F);
    return ClipRRect(
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
                      onPressed: () =>
                          playing ? _player.pause() : _player.play(),
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
                                      _player.seek(Duration(milliseconds: ms));
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
                                      _player.seek(Duration(milliseconds: ms));
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
  final String url;
  final MessageType type;
  final bool isMe;
  final int? sizeBytes;
  const _FileTile({
    required this.url,
    required this.type,
    required this.isMe,
    required this.sizeBytes,
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
    return FutureBuilder<String>(
      future: () async {
        return _resolveMediaUrl(url, type);
      }(),
      builder: (context, snap) {
        final name = url.split('/').last;
        const tc = Color(0xFFFFFFFF);
        final ext = _ext(name);
        final sizeLabel = _fmtSize(sizeBytes);
        final bg = isMe ? AppColors.navy : AppColors.surface;
        return GestureDetector(
          onTap: () {
            if (!snap.hasData) return;
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => _PdfMaybe(url: snap.data!)),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ColoredBox(
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
                          child: Icon(_iconForExt(ext), color: tc, size: 22),
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
                              ].join(' • '),
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

class _MediaErrorBox extends StatelessWidget {
  final IconData icon;
  const _MediaErrorBox({required this.icon});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.highlight.withOpacity(0.65),
      child: Center(child: Icon(icon, color: Colors.black54, size: 28)),
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

class _VideoFullscreen extends StatefulWidget {
  final String url;
  final MessageType type;
  const _VideoFullscreen({required this.url, required this.type});
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
    final u = await _resolveMediaUrl(v, widget.type);
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
