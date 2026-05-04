import 'dart:io';
import 'package:video_player/video_player.dart';

/// LRU cache entry with timestamp for eviction tracking
class _ControllerEntry {
  final VideoPlayerController controller;
  DateTime lastAccessed;
  bool isInitializing;

  _ControllerEntry({
    required this.controller,
    required this.lastAccessed,
    this.isInitializing = false,
  });
}

/// Shared pool for VideoPlayerController instances to prevent
/// re-initialization lag and memory leaks across the app.
///
/// Usage:
/// ```dart
/// final controller = await VideoControllerPool.instance.getController(url);
/// // use controller...
/// VideoControllerPool.instance.releaseController(url);
/// ```
class VideoControllerPool {
  static final VideoControllerPool _instance = VideoControllerPool._internal();
  static VideoControllerPool get instance => _instance;

  VideoControllerPool._internal();

  final Map<String, _ControllerEntry> _pool = {};
  final int _maxSize = 5;

  /// Get or create a controller for the given URL.
  /// Returns an initialized controller ready for playback.
  Future<VideoPlayerController> getController(String url) async {
    final now = DateTime.now();

    // Return existing controller if available
    if (_pool.containsKey(url)) {
      final entry = _pool[url]!;
      entry.lastAccessed = now;

      // Wait for initialization if in progress
      if (entry.isInitializing) {
        while (entry.isInitializing) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      // Ensure controller is playable
      if (entry.controller.value.isInitialized) {
        return entry.controller;
      }

      // Re-initialize if needed
      await _initializeController(entry);
      return entry.controller;
    }

    // Evict oldest if at capacity
    if (_pool.length >= _maxSize) {
      _evictLRU();
    }

    // Create new controller
    final isRemote = url.startsWith('http://') || url.startsWith('https://');
    final controller = isRemote
        ? VideoPlayerController.networkUrl(Uri.parse(url))
        : VideoPlayerController.file(File(url));

    final entry = _ControllerEntry(
      controller: controller,
      lastAccessed: now,
      isInitializing: true,
    );
    _pool[url] = entry;

    // Initialize asynchronously
    await _initializeController(entry);
    return controller;
  }

  Future<void> _initializeController(_ControllerEntry entry) async {
    try {
      entry.isInitializing = true;
      await entry.controller.initialize();
      await entry.controller.setLooping(false);
    } catch (e) {
      // Mark as failed but keep in pool to avoid retries
      entry.isInitializing = false;
      rethrow;
    } finally {
      entry.isInitializing = false;
    }
  }

  /// Mark a controller as recently used without creating it.
  /// Call this when opening the viewer to prioritize this video.
  void touch(String url) {
    if (_pool.containsKey(url)) {
      _pool[url]!.lastAccessed = DateTime.now();
    }
  }

  /// Pause a specific video without removing from pool.
  Future<void> pause(String url) async {
    if (_pool.containsKey(url)) {
      final controller = _pool[url]!.controller;
      if (controller.value.isInitialized && controller.value.isPlaying) {
        await controller.pause();
      }
    }
  }

  /// Play a specific video.
  Future<void> play(String url) async {
    if (_pool.containsKey(url)) {
      final controller = _pool[url]!.controller;
      if (controller.value.isInitialized) {
        await controller.play();
      }
    }
  }

  /// Release reference to a controller. Actual disposal happens
  /// via LRU eviction or disposeAll().
  void releaseController(String url) {
    // Just mark as unused - actual disposal is LRU-managed
    // This allows quick re-opening of same video
  }

  /// Pause all controllers (useful when viewer closes).
  Future<void> pauseAll() async {
    for (final entry in _pool.values) {
      final controller = entry.controller;
      if (controller.value.isInitialized && controller.value.isPlaying) {
        await controller.pause();
      }
    }
  }

  /// Dispose all controllers. Call on app exit or memory pressure.
  Future<void> disposeAll() async {
    for (final entry in _pool.values) {
      await entry.controller.dispose();
    }
    _pool.clear();
  }

  void _evictLRU() {
    if (_pool.isEmpty) return;

    // Find oldest entry
    String? oldestKey;
    DateTime? oldestTime;

    for (final entry in _pool.entries) {
      if (oldestTime == null || entry.value.lastAccessed.isBefore(oldestTime)) {
        oldestTime = entry.value.lastAccessed;
        oldestKey = entry.key;
      }
    }

    if (oldestKey != null) {
      final entry = _pool.remove(oldestKey)!;
      entry.controller.dispose();
    }
  }

  /// Pre-warm a controller without returning it.
  /// Useful for preloading adjacent videos in viewer.
  Future<void> prewarm(String url) async {
    if (!_pool.containsKey(url)) {
      try {
        await getController(url);
        await pause(url);
      } catch (_) {
        // Ignore prewarm failures
      }
    }
  }
}
