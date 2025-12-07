import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import '../models/message_model.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';

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
        return _ImagePreview(url: url, type: message.messageType, isMe: isMe);
      case MessageType.video:
        return _VideoPreview(url: url, type: message.messageType, isMe: isMe);
      case MessageType.audio:
        return _AudioInline(url: url, type: message.messageType, isMe: isMe);
      case MessageType.file:
      default:
        return _FileTile(url: url, type: message.messageType);
    }
  }
}

class _ImagePreview extends StatelessWidget {
  final String url;
  final MessageType type;
  final bool isMe;
  const _ImagePreview({
    required this.url,
    required this.type,
    required this.isMe,
  });
  Future<String> _resolve(String u) async {
    if (u.contains('://')) {
      return SupabaseService.instance.resolveUrl(directUrl: u);
    }
    final bucket = type == MessageType.audio
        ? StorageService().audioBucket
        : StorageService().mediaBucket;
    return SupabaseService.instance.resolveUrl(bucket: bucket, path: u);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _resolve(url),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            height: 180,
            width: 260,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final resolved = snap.data!;
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
                            Uri.parse(resolved),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                      ),
                    ],
                  ),
                  body: PhotoView(imageProvider: NetworkImage(resolved)),
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              resolved,
              fit: BoxFit.cover,
              height: 180,
              width: 260,
            ),
          ),
        );
      },
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
        return SizedBox(
          width: 260,
          height: 180,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AspectRatio(
                  aspectRatio: controller.value.aspectRatio == 0
                      ? 16 / 9
                      : controller.value.aspectRatio,
                  child: VideoPlayer(controller),
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
    final mainColor = widget.isMe ? Colors.white : const Color(0xFF0A1A3A);
    final playedColor = widget.isMe ? Colors.white : const Color(0xFF0A1A3A);
    final unplayedColor = widget.isMe ? Colors.white24 : Colors.grey.shade300;
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

class _FileTile extends StatelessWidget {
  final String url;
  final MessageType type;
  const _FileTile({required this.url, required this.type});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: () async {
        if (url.contains('://')) {
          return SupabaseService.instance.resolveUrl(directUrl: url);
        }
        final bucket = type == MessageType.audio
            ? StorageService().audioBucket
            : StorageService().mediaBucket;
        return SupabaseService.instance.resolveUrl(bucket: bucket, path: url);
      }(),
      builder: (context, snap) {
        final name = url.split('/').last;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          leading: const Icon(Icons.insert_drive_file, color: Colors.white70),
          trailing: const Icon(Icons.open_in_new, color: Colors.white70),
          onTap: () {
            if (!snap.hasData) return;
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => _PdfMaybe(url: snap.data!)),
            );
          },
        );
      },
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
    if (mounted)
      setState(() {
        _ready = true;
        _resolved = u;
      });
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
