import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../models/message_model.dart';
import '../../services/media_picker_service.dart';
import 'widgets/caption_bar.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/media_filmstrip.dart';

typedef SendMediaWithMeta = Future<void> Function(
  Uint8List bytes,
  String fileName,
  String contentType,
  MessageType type, {
  String? localPath,
  String? thumbnailPath,
  int? durationMs,
  String? caption,
  bool? viewOnce,
  Map<String, dynamic>? meta,
});

typedef SendText = Future<void> Function(String text);

class MediaPreviewScreen extends StatefulWidget {
  static const routeName = '/media-preview';

  final List<SelectedMedia> items;
  final SendMediaWithMeta onSendMedia;
  final SendText? onSendText;

  const MediaPreviewScreen({
    super.key,
    required this.items,
    required this.onSendMedia,
    this.onSendText,
  });

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  late final PageController _pageController;
  int _currentIndex = 0;

  final Map<int, TextEditingController> _captionControllers =
      <int, TextEditingController>{};

  bool _sending = false;

  VideoPlayerController? _videoController;
  String? _videoPath;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _ensureCaptionController(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareVideoIfNeeded();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _captionControllers.values) {
      c.dispose();
    }
    _disposeVideo();
    super.dispose();
  }

  SelectedMedia get _current => widget.items[_currentIndex];

  TextEditingController _ensureCaptionController(int index) {
    return _captionControllers.putIfAbsent(
      index,
      () => TextEditingController(text: widget.items[index].caption),
    );
  }

  void _disposeVideo() {
    final c = _videoController;
    _videoController = null;
    _videoPath = null;
    unawaited(c?.dispose());
  }

  Future<void> _prepareVideoIfNeeded() async {
    final m = _current;
    if (m.type != MessageType.video) {
      _disposeVideo();
      if (mounted) setState(() {});
      return;
    }

    final p = m.path;
    if (p == null || p.isEmpty) {
      _disposeVideo();
      if (mounted) setState(() {});
      return;
    }

    if (_videoController != null && _videoPath == p) {
      return;
    }

    _disposeVideo();
    _videoPath = p;

    try {
      final controller = VideoPlayerController.file(File(p));
      _videoController = controller;
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      _disposeVideo();
      if (mounted) setState(() {});
    }
  }

  Future<String?> _thumbFor(SelectedMedia m) async {
    final p = m.path;
    if (p == null || p.isEmpty) return null;
    if (m.type != MessageType.video) return null;
    return VideoThumbnail.thumbnailFile(
      video: p,
      imageFormat: ImageFormat.JPEG,
      quality: 75,
    ).catchError((_) => null);
  }

  Future<void> _sendAll() async {
    if (_sending) return;
    setState(() => _sending = true);

    try {
      for (var i = 0; i < widget.items.length; i++) {
        final m = widget.items[i];
        final caption = m.caption.trim().isEmpty ? null : m.caption.trim();
        final viewOnce = m.viewOnce;

        Uint8List bytes;
        String name;
        String? localPath;

        if (m.xfile != null) {
          name = m.xfile!.name;
          bytes = await m.xfile!.readAsBytes();
          localPath = kIsWeb ? null : m.xfile!.path;
        } else if (m.file != null) {
          name = m.name;
          bytes = await m.file!.readAsBytes();
          localPath = kIsWeb ? null : m.file!.path;
        } else {
          continue;
        }

        final mime =
            lookupMimeType(name, headerBytes: bytes.isNotEmpty ? bytes.sublist(0, bytes.length > 32 ? 32 : bytes.length) : null) ??
                _inferMime(name, m.type);

        String? thumbnailPath;
        if (!kIsWeb && m.type == MessageType.video && localPath != null) {
          thumbnailPath = await _thumbFor(m);
        }

        await widget.onSendMedia(
          bytes,
          name,
          mime,
          m.type,
          localPath: localPath,
          thumbnailPath: thumbnailPath,
          caption: caption,
          viewOnce: viewOnce,
          meta: <String, dynamic>{
            if (m.type == MessageType.video && m.trimStart != null)
              'trimStartMs': m.trimStart!.inMilliseconds,
            if (m.type == MessageType.video && m.trimEnd != null)
              'trimEndMs': m.trimEnd!.inMilliseconds,
            if (m.type == MessageType.video) 'muted': m.muted,
          },
        );
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $e')),
      );
      setState(() => _sending = false);
    }
  }

  String _inferMime(String name, MessageType type) {
    if (type == MessageType.image) return 'image/*';
    if (type == MessageType.video) return 'video/*';
    if (type == MessageType.audio) return 'audio/*';
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  @override
  Widget build(BuildContext context) {
    final captionController = _ensureCaptionController(_currentIndex);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (i) {
              setState(() {
                _currentIndex = i;
                widget.items[i].caption = _ensureCaptionController(i).text;
              });
              unawaited(_prepareVideoIfNeeded());
            },
            itemBuilder: (context, i) {
              final m = widget.items[i];
              return _PreviewPage(
                media: m,
                heroTag: 'media_preview_$i',
                videoController: i == _currentIndex ? _videoController : null,
              );
            },
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _current.viewOnce = !_current.viewOnce;
                            });
                          },
                          icon: Icon(
                            _current.viewOnce
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: _current.viewOnce
                                ? const Color(0xFF5865F2)
                                : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                EditorToolbar(
                  onDraw: () => _stub('Draw (coming soon)'),
                  onText: () => _stub('Text overlay (coming soon)'),
                  onEmoji: () => _stub('Emoji (coming soon)'),
                  onCrop: () => _stub('Crop (coming soon)'),
                ),
              ],
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 82,
            child: MediaFilmstrip(
              items: widget.items,
              currentIndex: _currentIndex,
              onTapIndex: (i) {
                _pageController.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                );
              },
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CaptionBar(
              controller: captionController,
              onChanged: (v) {
                _current.caption = v;
              },
              onSend: _sending ? () {} : _sendAll,
            ),
          ),

          if (_sending)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withOpacity(0.25),
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _stub(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _PreviewPage extends StatelessWidget {
  final SelectedMedia media;
  final String heroTag;
  final VideoPlayerController? videoController;

  const _PreviewPage({
    required this.media,
    required this.heroTag,
    required this.videoController,
  });

  @override
  Widget build(BuildContext context) {
    final p = media.path;

    Widget body;

    if (media.type == MessageType.image && p != null && p.isNotEmpty) {
      body = Hero(
        tag: heroTag,
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Image.file(
            File(p),
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black54),
          ),
        ),
      );
    } else if (media.type == MessageType.video && p != null && p.isNotEmpty) {
      final c = videoController;
      body = Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            )
          else
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
            ),
          Positioned(
            bottom: 130,
            left: 0,
            right: 0,
            child: _VideoStubBar(media: media),
          ),
        ],
      );
    } else {
      body = const Center(
        child: Icon(Icons.insert_drive_file, color: Colors.white54, size: 52),
      );
    }

    return ColoredBox(color: Colors.black, child: body);
  }
}

class _VideoStubBar extends StatelessWidget {
  final SelectedMedia media;
  const _VideoStubBar({required this.media});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Chip(
            icon: Icons.content_cut,
            label: 'Trim',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Trim UI (coming soon)')),
              );
            },
          ),
          const SizedBox(width: 10),
          _Chip(
            icon: media.muted ? Icons.volume_off : Icons.volume_up,
            label: media.muted ? 'Muted' : 'Sound',
            onTap: () {
              media.muted = !media.muted;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(media.muted ? 'Muted' : 'Sound on'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Chip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
