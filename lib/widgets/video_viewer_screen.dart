import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../services/video_controller_pool.dart';

/// WhatsApp-style full-screen video viewer with swipe navigation.
///
/// Features:
/// - Shared controller pool for instant playback
/// - Horizontal swipe between videos
/// - Vertical swipe to dismiss
/// - Tap to toggle controls
/// - Auto-play/pause on navigation
class VideoViewerScreen extends StatefulWidget {
  final List<String> videoUrls;
  final List<String?>? thumbnailUrls;
  final int initialIndex;
  final String heroTag;
  final Future<String> Function(String) resolveUrl;

  const VideoViewerScreen({
    super.key,
    required this.videoUrls,
    this.thumbnailUrls,
    required this.initialIndex,
    required this.heroTag,
    required this.resolveUrl,
  });

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  bool _showControls = true;
  bool _isDragging = false;
  double _dragOffset = 0;
  double _opacity = 1.0;

  final Map<int, VideoPlayerController?> _controllers = {};
  final Map<int, bool> _isInitialized = {};
  final Map<int, int> _retryCount = {};
  final Map<int, Timer?> _retryTimers = {};

  late AnimationController _controlsAnimationController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    _controlsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _controlsAnimationController.value = 1.0;

    // Initialize current video
    _initializeVideo(_currentIndex);
    _prewarmAdjacent();

    // Auto-hide controls after delay
    _scheduleControlsHide();

    // Set immersive mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  Future<void> _initializeVideo(int index) async {
    if (index < 0 || index >= widget.videoUrls.length) return;
    if (_isInitialized[index] == true) return;
    if (_retryTimers[index]?.isActive == true) return;

    final url = widget.videoUrls[index];
    _retryCount[index] = (_retryCount[index] ?? 0);

    Future<void> attempt() async {
      try {
        final resolved = await widget.resolveUrl(url);
        final controller = await VideoControllerPool.instance.getController(
          resolved,
        );

        if (!mounted) return;

        setState(() {
          _controllers[index] = controller;
          _isInitialized[index] = true;
        });

        // Auto-play current video
        if (index == _currentIndex) {
          unawaited(controller.setLooping(false));
          unawaited(controller.play());
        }
      } catch (_) {
        // Max 3 retries then fail fast - show error state instead of infinite loading
        final next = (_retryCount[index] ?? 0) + 1;
        if (next > 3) {
          // Give up after 3 attempts - show error state
          if (mounted) {
            setState(() {
              _isInitialized[index] = false;
              _controllers[index] = null;
            });
          }
          return;
        }
        _retryCount[index] = next;

        // Retry with increasing delay: 500ms, 1s, 2s
        final delay = Duration(milliseconds: 500 * (1 << (next - 1)));

        _retryTimers[index]?.cancel();
        _retryTimers[index] = Timer(delay, () {
          if (!mounted) return;
          _initializeVideo(index);
        });
      }
    }

    await attempt();
  }

  void _prewarmAdjacent() {
    // Prewarm previous and next videos
    if (_currentIndex > 0) {
      _initializeVideo(_currentIndex - 1);
    }
    if (_currentIndex < widget.videoUrls.length - 1) {
      _initializeVideo(_currentIndex + 1);
    }
  }

  void _onPageChanged(int index) {
    // Pause previous video
    final prevController = _controllers[_currentIndex];
    if (prevController != null && prevController.value.isInitialized) {
      prevController.pause();
    }

    setState(() => _currentIndex = index);

    // Play new video
    _initializeVideo(index).then((_) {
      final newController = _controllers[index];
      if (newController != null && newController.value.isInitialized) {
        newController.play();
      }
    });

    _prewarmAdjacent();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _controlsAnimationController.forward();
      _scheduleControlsHide();
    } else {
      _controlsAnimationController.reverse();
    }
  }

  Timer? _controlsTimer;
  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _showControls) {
        setState(() {
          _showControls = false;
          _controlsAnimationController.reverse();
        });
      }
    });
  }

  void _togglePlayPause(int index) {
    final controller = _controllers[index];
    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    setState(() {}); // Update UI
    _scheduleControlsHide();
  }

  void _toggleMute(int index) {
    final controller = _controllers[index];
    if (controller == null || !controller.value.isInitialized) return;

    final newVolume = controller.value.volume > 0 ? 0.0 : 1.0;
    controller.setVolume(newVolume);
    setState(() {});
  }

  void _close() {
    // Pause all before exiting
    for (final controller in _controllers.values) {
      if (controller != null && controller.value.isInitialized) {
        controller.pause();
      }
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _controlsAnimationController.dispose();
    _pageController.dispose();

    for (final t in _retryTimers.values) {
      t?.cancel();
    }

    // Pause all videos but don't dispose (pool manages lifecycle)
    for (final controller in _controllers.values) {
      if (controller != null && controller.value.isInitialized) {
        controller.pause();
      }
    }

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onVerticalDragStart: (_) => setState(() => _isDragging = true),
        onVerticalDragUpdate: (details) {
          setState(() {
            _dragOffset += details.delta.dy;
            _opacity = 1 - (_dragOffset.abs() / 400).clamp(0.0, 1.0);
          });
        },
        onVerticalDragEnd: (details) {
          if (_dragOffset.abs() > 150 ||
              details.velocity.pixelsPerSecond.dy.abs() > 500) {
            _close();
          } else {
            setState(() {
              _isDragging = false;
              _dragOffset = 0;
              _opacity = 1.0;
            });
          }
        },
        child: AnimatedOpacity(
          opacity: _opacity,
          duration: const Duration(milliseconds: 100),
          child: Transform.translate(
            offset: Offset(0, _isDragging ? _dragOffset : 0),
            child: Stack(
              children: [
                // Video PageView
                PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  itemCount: widget.videoUrls.length,
                  itemBuilder: (context, index) {
                    return _VideoPage(
                      url: widget.videoUrls[index],
                      thumbnailUrl:
                          widget.thumbnailUrls != null &&
                              index < widget.thumbnailUrls!.length
                          ? widget.thumbnailUrls![index]
                          : null,
                      resolveUrl: widget.resolveUrl,
                      controller: _controllers[index],
                      isInitialized: _isInitialized[index] == true,
                      isCurrent: index == _currentIndex,
                      heroTag: index == widget.initialIndex
                          ? widget.heroTag
                          : null,
                      onPlayPause: () => _togglePlayPause(index),
                      onToggleMute: () => _toggleMute(index),
                    );
                  },
                ),

                // Top controls
                AnimatedBuilder(
                  animation: _controlsAnimationController,
                  builder: (context, child) {
                    return Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: FadeTransition(
                        opacity: _controlsAnimationController,
                        child: Container(
                          padding: EdgeInsets.only(
                            top: MediaQuery.of(context).padding.top + 8,
                            left: 8,
                            right: 8,
                            bottom: 16,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.7),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.arrow_back,
                                  color: Colors.white,
                                ),
                                onPressed: _close,
                              ),
                              const Spacer(),
                              Text(
                                '${_currentIndex + 1} / ${widget.videoUrls.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              const SizedBox(width: 48), // Balance
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final String url;
  final String? thumbnailUrl;
  final Future<String> Function(String) resolveUrl;
  final VideoPlayerController? controller;
  final bool isInitialized;
  final bool isCurrent;
  final String? heroTag;
  final VoidCallback onPlayPause;
  final VoidCallback onToggleMute;

  const _VideoPage({
    required this.url,
    required this.thumbnailUrl,
    required this.resolveUrl,
    required this.controller,
    required this.isInitialized,
    required this.isCurrent,
    required this.onPlayPause,
    required this.onToggleMute,
    this.heroTag,
  });

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  bool _showThumbnail = true;

  @override
  void didUpdateWidget(_VideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isInitialized && !oldWidget.isInitialized) {
      // Fade from thumbnail to video
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) setState(() => _showThumbnail = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    Widget thumbnailLayer;
    final thumb = (widget.thumbnailUrl ?? '').trim();
    if (thumb.isNotEmpty) {
      final ImageProvider provider =
          (thumb.startsWith('http://') || thumb.startsWith('https://'))
          ? NetworkImage(thumb)
          : FileImage(File(thumb));
      thumbnailLayer = Image(
        image: provider,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => Container(color: Colors.grey[900]),
      );
    } else {
      thumbnailLayer = Container(color: Colors.grey[900]);
    }

    Widget videoContent;

    if (!widget.isInitialized || controller == null) {
      // Loading state with thumbnail placeholder
      videoContent = Stack(
        fit: StackFit.expand,
        children: [
          thumbnailLayer,
          Container(color: Colors.black.withOpacity(0.25)),
          const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Colors.white54,
                strokeWidth: 2,
              ),
            ),
          ),
        ],
      );
    } else {
      // Video is ready
      videoContent = Stack(
        fit: StackFit.expand,
        children: [
          // Always keep thumbnail behind video to avoid black frames.
          thumbnailLayer,

          // Fade from thumbnail to video
          AnimatedOpacity(
            opacity: _showThumbnail ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Container(color: Colors.black.withOpacity(0.12)),
          ),

          // Actual video player
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),

          // Buffering indicator (while playing)
          if (controller.value.isBuffering)
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white54,
                strokeWidth: 2,
              ),
            ),

          // Center play/pause button
          _CenterPlayButton(
            isPlaying: controller.value.isPlaying,
            onTap: widget.onPlayPause,
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _VideoControls(
              controller: controller,
              onPlayPause: widget.onPlayPause,
              onToggleMute: widget.onToggleMute,
            ),
          ),
        ],
      );
    }

    // Wrap with Hero if this is the initial video
    if (widget.heroTag != null) {
      return Hero(
        tag: widget.heroTag!,
        child: Material(color: Colors.transparent, child: videoContent),
      );
    }

    return videoContent;
  }
}

class _CenterPlayButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _CenterPlayButton({required this.isPlaying, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: AnimatedOpacity(
            opacity: isPlaying ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoControls extends StatefulWidget {
  final VideoPlayerController controller;
  final VoidCallback onPlayPause;
  final VoidCallback onToggleMute;

  const _VideoControls({
    required this.controller,
    required this.onPlayPause,
    required this.onToggleMute,
  });

  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls> {
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, child) {
        final position = value.position;
        final duration = value.duration;
        final isMuted = value.volume == 0;

        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black.withOpacity(0.8), Colors.transparent],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress bar
              if (duration > Duration.zero)
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                  ),
                  child: Slider(
                    value: position.inMilliseconds.toDouble().clamp(
                      0,
                      duration.inMilliseconds.toDouble(),
                    ),
                    min: 0,
                    max: math.max(1, duration.inMilliseconds.toDouble()),
                    onChanged: (value) {
                      final newPosition = Duration(milliseconds: value.toInt());
                      widget.controller.seekTo(newPosition);
                    },
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                  ),
                ),

              // Time and controls row
              Row(
                children: [
                  // Play/Pause
                  IconButton(
                    icon: Icon(
                      value.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    onPressed: widget.onPlayPause,
                  ),

                  // Time
                  Text(
                    '${_formatDuration(position)} / ${_formatDuration(duration)}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),

                  const Spacer(),

                  // Mute toggle
                  IconButton(
                    icon: Icon(
                      isMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                    ),
                    onPressed: widget.onToggleMute,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
