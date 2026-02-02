import 'package:flutter/material.dart';
import 'dart:async';
import 'package:video_player/video_player.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/message_model.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../theme/theme.dart';

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
        return _VideoPreview(url: url, type: message.messageType, isMe: isMe);
      case MessageType.audio:
        return _AudioInline(url: url, type: message.messageType, isMe: isMe);
      case MessageType.file:
      default:
        return _FileTile(message: message, isMe: isMe);
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
  bool _portrait = false;
  bool _ready = false;
  late final String _heroTag;

  @override
  void initState() {
    super.initState();
    _heroTag = 'img_${widget.message.id}';
    _init();
  }

  Future<void> _init() async {
    final v = widget.message.mediaUrl ?? '';
    final resolved = v.contains('://')
        ? await SupabaseService.instance.resolveUrl(directUrl: v)
        : await SupabaseService.instance.resolveUrl(
            bucket: widget.message.messageType == MessageType.audio
                ? StorageService().audioBucket
                : StorageService().mediaBucket,
            path: v,
          );
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
      final info = await c.future;
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (mounted) {
        setState(() {
          _resolved = resolved;
          _portrait = h >= w;
          _ready = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _resolved = resolved;
          _portrait = false;
          _ready = true;
        });
      }
    } finally {
      stream.removeListener(l);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _resolved == null) {
      return const SizedBox(
        height: 180,
        width: 260,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final screenW = MediaQuery.of(context).size.width;
    final maxBubbleW = screenW * 0.70; // WhatsApp-like ~70%
    const portraitSizeW = 220.0;
    const portraitSizeH = 320.0;
    const landscapeSizeW = 300.0;
    const landscapeSizeH = 180.0;
    final targetW = (_portrait ? portraitSizeW : landscapeSizeW).clamp(
      0.0,
      maxBubbleW,
    );
    final targetH = _portrait ? portraitSizeH : landscapeSizeH;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _ImageFullscreen(
              heroTag: _heroTag,
              url: _resolved!,
              fileName: _suggestedFileName(widget.message.mediaUrl ?? ''),
            ),
          ),
        );
      },
      child: Hero(
        tag: _heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
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
                  placeholder: (context, _) => Container(
                    color: Colors.black26,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                // Bottom gradient for readability
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 40,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ),
                // Timestamp + ticks (sender only)
                Positioned(
                  right: 8,
                  bottom: 6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(widget.message.timestamp.toDate()),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.isMe) ...[
                        const SizedBox(width: 6),
                        Icon(
                          _statusIconData(widget.message),
                          size: 14,
                          color: Colors.white,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _suggestedFileName(String raw) {
    final base = raw.split('/').last;
    if (base.isNotEmpty) return base;
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'image_$ts.jpg';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  IconData _statusIconData(MessageModel m) {
    if (m.hasPendingWrites) return Icons.watch_later_outlined;
    switch (m.status) {
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
}

class _ImageFullscreen extends StatelessWidget {
  final String heroTag;
  final String url;
  final String fileName;
  const _ImageFullscreen({
    required this.heroTag,
    required this.url,
    required this.fileName,
  });
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: AppColors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: () async {
              try {
                final res = await http.get(Uri.parse(url));
                if (res.statusCode == 200) {
                  // Save to app documents
                  // ignore: deprecated_member_use
                  final dir = await getApplicationDocumentsDirectory();
                  final file = File('${dir.path}/$fileName');
                  await file.writeAsBytes(res.bodyBytes);
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Saved to ${file.path}')),
                  );
                } else {
                  await launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  );
                }
              } catch (_) {
                await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Hero(
          tag: heroTag,
          child: PhotoView(imageProvider: NetworkImage(url)),
        ),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final String url;
  final MessageType type;
  final bool isMe;
  const _VideoPreview({
    required this.url,
    required this.type,
    required this.isMe,
  });
  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _init();
  }

  Future<void> _init() async {
    final u = await (() async {
      final v = widget.url;
      if (v.contains('://')) {
        return SupabaseService.instance.resolveUrl(directUrl: v);
      }
      final bucket = widget.type == MessageType.audio
          ? StorageService().audioBucket
          : StorageService().mediaBucket;
      return SupabaseService.instance.resolveUrl(bucket: bucket, path: v);
    })();
    final ctl = VideoPlayerController.networkUrl(Uri.parse(u));
    await ctl.initialize();
    _controller = ctl;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done ||
            _controller == null) {
          return const SizedBox(
            width: 260,
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final controller = _controller!;
        final ar = controller.value.aspectRatio == 0
            ? (16 / 9)
            : controller.value.aspectRatio;
        final isPortrait = ar < 1.0;
        final screenW = MediaQuery.of(context).size.width;
        final maxBubbleW = screenW * 0.78;
        const portraitW = 220.0;
        const portraitH = 320.0;
        const landscapeW = 300.0;
        const landscapeH = 180.0;
        final targetW = (isPortrait ? portraitW : landscapeW).clamp(
          0.0,
          maxBubbleW,
        );
        final targetH = isPortrait ? portraitH : landscapeH;
        return SizedBox(
          width: targetW,
          height: targetH,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: targetW,
                    height: targetW / ar,
                    child: VideoPlayer(controller),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _VideoFullscreen(
                            url: widget.url,
                            type: widget.type,
                          ),
                        ),
                      );
                    },
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
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late final List<double> _bars;

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
      final u = v.contains('://')
          ? await SupabaseService.instance.resolveUrl(directUrl: v)
          : await SupabaseService.instance.resolveUrl(
              bucket: widget.type == MessageType.audio
                  ? StorageService().audioBucket
                  : StorageService().mediaBucket,
              path: v,
            );
      await _player.setUrl(u);
      _duration = _player.duration ?? Duration.zero;
      _player.positionStream.listen((p) => setState(() => _position = p));
      _player.durationStream.listen(
        (d) => setState(() => _duration = d ?? Duration.zero),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
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
    final playing = _player.playing;
    final mainColor = widget.isMe ? Colors.white : Colors.black;
    final playedColor = widget.isMe ? Colors.white : Colors.black;
    final unplayedColor = widget.isMe
        ? Colors.white24
        : Colors.black.withOpacity(0.2);
    return SizedBox(
      width: 260,
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
                onPressed: () => playing ? _player.pause() : _player.play(),
              ),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final progress = _duration.inMilliseconds == 0
                          ? 0.0
                          : _position.inMilliseconds / _duration.inMilliseconds;
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
                            top:
                                12, // center vertically for 34px height with 10px dot
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
                                final dx = d.localPosition.dx.clamp(0.0, w);
                                final ratio = dx / w;
                                final ms = (_duration.inMilliseconds * ratio)
                                    .toInt();
                                _player.seek(Duration(milliseconds: ms));
                              },
                              onTapDown: (d) {
                                final dx = d.localPosition.dx.clamp(0.0, w);
                                final ratio = dx / w;
                                final ms = (_duration.inMilliseconds * ratio)
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
                style: TextStyle(
                  fontSize: 11,
                  color: mainColor.withOpacity(0.7),
                ),
              ),
            ),
          ),
        ],
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

class _FileTile extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  const _FileTile({required this.message, required this.isMe});
  @override
  State<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<_FileTile> {
  bool _downloading = false;
  double _progress = 0.0;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _checkIfDownloaded();
  }

  Future<void> _checkIfDownloaded() async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = _suggestedName(widget.message);
    final path = '${dir.path}/$fileName';
    final exists = await File(path).exists();
    if (exists) setState(() => _localPath = path);
  }

  Color _iconColorFor(String name) {
    final l = name.toLowerCase();
    if (l.endsWith('.pdf')) return Colors.red;
    if (l.endsWith('.ppt') || l.endsWith('.pptx')) return Colors.orange;
    if (l.endsWith('.doc') || l.endsWith('.docx')) return Colors.blue;
    if (l.endsWith('.zip') || l.endsWith('.rar')) return Colors.grey;
    return widget.isMe ? Colors.white70 : Colors.black;
  }

  String _sizeLabel() {
    final bytes = widget.message.mediaSize ?? 0;
    if (bytes <= 0) return '';
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes >= mb) {
      return (bytes / mb).toStringAsFixed(2) + ' MB';
    }
    return (bytes / kb).toStringAsFixed(1) + ' KB';
  }

  String _suggestedName(MessageModel m) {
    final url = (m.mediaUrl ?? '').trim();
    final last = url.split('/').last;
    if (last.isNotEmpty) return last;
    final ts = m.timestamp.millisecondsSinceEpoch;
    return 'file_$ts';
  }

  Future<void> _handleTap() async {
    if (_localPath != null) {
      // Try open with external app
      final uri = Uri.file(_localPath!);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0.0;
    });
    try {
      final resolved = await _resolve(widget.message);
      final req = await http.Client().send(
        http.Request('GET', Uri.parse(resolved)),
      );
      final dir = await getApplicationDocumentsDirectory();
      final fileName = _suggestedName(widget.message);
      final file = File('${dir.path}/$fileName');
      final sink = file.openWrite();
      final contentLen = req.contentLength ?? 0;
      int received = 0;
      await for (final chunk in req.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (contentLen > 0) {
          setState(() => _progress = received / contentLen);
        }
      }
      await sink.flush();
      await sink.close();
      setState(() => _localPath = file.path);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<String> _resolve(MessageModel m) async {
    final url = m.mediaUrl ?? '';
    if (url.contains('://')) {
      return SupabaseService.instance.resolveUrl(directUrl: url);
    }
    final bucket = m.messageType == MessageType.audio
        ? StorageService().audioBucket
        : StorageService().mediaBucket;
    return SupabaseService.instance.resolveUrl(bucket: bucket, path: url);
  }

  @override
  Widget build(BuildContext context) {
    final name = _suggestedName(widget.message);
    final tc = widget.isMe ? Colors.white : Colors.black;
    final ic = _iconColorFor(name);
    return InkWell(
      onTap: _handleTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: Icon(Icons.insert_drive_file, color: ic, size: 28),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tc, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                if (_sizeLabel().isNotEmpty)
                  Text(
                    _sizeLabel(),
                    style: TextStyle(color: tc.withOpacity(0.7), fontSize: 12),
                  ),
                if (_downloading)
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0, right: 12),
                    child: LinearProgressIndicator(
                      value: _progress == 0.0 ? null : _progress,
                      minHeight: 3,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (_downloading)
            const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (_localPath != null)
            IconButton(
              icon: Icon(Icons.open_in_new, color: tc),
              onPressed: _handleTap,
            )
          else
            IconButton(
              icon: Icon(Icons.download_rounded, color: tc),
              onPressed: _handleTap,
            ),
        ],
      ),
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
    final u = v.contains('://')
        ? await SupabaseService.instance.resolveUrl(directUrl: v)
        : await SupabaseService.instance.resolveUrl(
            bucket: widget.type == MessageType.audio
                ? StorageService().audioBucket
                : StorageService().mediaBucket,
            path: v,
          );
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
