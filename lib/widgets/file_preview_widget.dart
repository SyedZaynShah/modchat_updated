import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:pdfx/pdfx.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:photo_view/photo_view.dart';
import '../models/message_model.dart';
import '../services/supabase_service.dart';

class FilePreviewWidget extends StatelessWidget {
  final MessageModel message;
  const FilePreviewWidget({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final url = message.mediaUrl ?? '';
    switch (message.messageType) {
      case MessageType.image:
        return _ImagePreview(url: url);
      case MessageType.video:
        return _VideoPreview(url: url);
      case MessageType.audio:
        return _AudioInline(url: url);
      case MessageType.file:
      default:
        return _FileTile(url: url);
    }
  }
}

class _ImagePreview extends StatelessWidget {
  final String url;
  const _ImagePreview({required this.url});
  Future<String> _resolve(String u) async {
    if (u.startsWith('sb://')) {
      final s = u.substring(5);
      final i = s.indexOf('/');
      final bucket = s.substring(0, i);
      final path = s.substring(i + 1);
      return SupabaseService.instance.getSignedUrl(
        bucket,
        path,
        expiresInSeconds: 600,
      );
    }
    return u;
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
                  appBar: AppBar(),
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
  const _VideoPreview({required this.url});
  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  Future<VideoPlayerController> _initController() async {
    String u = widget.url;
    if (u.startsWith('sb://')) {
      final s = u.substring(5);
      final i = s.indexOf('/');
      final bucket = s.substring(0, i);
      final path = s.substring(i + 1);
      u = await SupabaseService.instance.getSignedUrl(
        bucket,
        path,
        expiresInSeconds: 600,
      );
    }
    final ctl = VideoPlayerController.networkUrl(Uri.parse(u));
    await ctl.initialize();
    return ctl;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VideoPlayerController>(
      future: _initController(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            width: 260,
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final controller = snap.data!;
        return GestureDetector(
          onTap: () => controller.value.isPlaying
              ? controller.pause()
              : controller.play(),
          child: SizedBox(
            width: 260,
            height: 180,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: VideoPlayer(controller),
                ),
                const Align(
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.play_circle,
                    size: 48,
                    color: Colors.white70,
                  ),
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _VideoFullscreen(url: widget.url),
                        ),
                      );
                    },
                    child: const Icon(
                      Icons.open_in_full,
                      color: Colors.white70,
                      size: 18,
                    ),
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
  const _AudioInline({required this.url});
  @override
  State<_AudioInline> createState() => _AudioInlineState();
}

class _AudioInlineState extends State<_AudioInline> {
  late final AudioPlayer _player;
  bool _loading = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _init();
  }

  Future<void> _init() async {
    try {
      var u = widget.url;
      if (u.startsWith('sb://')) {
        final s = u.substring(5);
        final i = s.indexOf('/');
        final bucket = s.substring(0, i);
        final path = s.substring(i + 1);
        u = await SupabaseService.instance.getSignedUrl(
          bucket,
          path,
          expiresInSeconds: 600,
        );
      }
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
    return SizedBox(
      width: 260,
      child: Row(
        children: [
          IconButton(
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            onPressed: () => playing ? _player.pause() : _player.play(),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  value: _position.inMilliseconds
                      .clamp(0, _duration.inMilliseconds)
                      .toDouble(),
                  max: _duration.inMilliseconds.toDouble().clamp(
                    1,
                    double.infinity,
                  ),
                  onChanged: (v) =>
                      _player.seek(Duration(milliseconds: v.toInt())),
                ),
                Text(
                  '${_format(_position)} / ${_format(_duration)}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
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

class _FileTile extends StatelessWidget {
  final String url;
  const _FileTile({required this.url});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: () async {
        if (url.startsWith('sb://')) {
          final s = url.substring(5);
          final i = s.indexOf('/');
          final bucket = s.substring(0, i);
          final path = s.substring(i + 1);
          return SupabaseService.instance.getSignedUrl(
            bucket,
            path,
            expiresInSeconds: 600,
          );
        }
        return url;
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
  const _VideoFullscreen({required this.url});
  @override
  State<_VideoFullscreen> createState() => _VideoFullscreenState();
}

class _VideoFullscreenState extends State<_VideoFullscreen> {
  late VideoPlayerController _ctl;
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    String u = widget.url;
    if (u.startsWith('sb://')) {
      final s = u.substring(5);
      final i = s.indexOf('/');
      final bucket = s.substring(0, i);
      final path = s.substring(i + 1);
      u = await SupabaseService.instance.getSignedUrl(
        bucket,
        path,
        expiresInSeconds: 600,
      );
    }
    _ctl = VideoPlayerController.networkUrl(Uri.parse(u));
    await _ctl.initialize();
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(),
      body: Center(
        child: _ready
            ? AspectRatio(
                aspectRatio: _ctl.value.aspectRatio,
                child: Stack(
                  children: [
                    VideoPlayer(_ctl),
                    Align(
                      alignment: Alignment.center,
                      child: IconButton(
                        iconSize: 64,
                        color: Colors.white70,
                        icon: Icon(
                          _ctl.value.isPlaying
                              ? Icons.pause_circle
                              : Icons.play_circle,
                        ),
                        onPressed: () => setState(
                          () =>
                              _ctl.value.isPlaying ? _ctl.pause() : _ctl.play(),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
