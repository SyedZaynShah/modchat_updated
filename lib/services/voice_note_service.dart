import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:just_audio/just_audio.dart';
import 'media_resolver.dart';

/// Comprehensive voice note service handling:
/// - URL resolution
/// - Background downloading with exponential backoff
/// - Pre-warming for instant playback
/// - Cache management
class VoiceNoteService {
  VoiceNoteService._();

  static final CacheManager _cache = DefaultCacheManager();

  /// Maximum attempts for background download
  static const int _maxDownloadAttempts = 5;

  /// Exponential backoff delays (2s, 4s, 8s, 16s, 32s)
  static Duration _backoffDelay(int attempt) {
    return Duration(seconds: pow(2, attempt + 1).toInt());
  }

  /// Resolves any audio URL to a stable public URL
  /// For voice notes, bucket should be 'dmMedia'
  static String resolveUrl(String? rawUrl, {String? bucket}) {
    return MediaResolver.resolve(rawUrl ?? '', bucket: bucket) ?? '';
  }

  /// Gets cached file if available, null otherwise
  static Future<File?> getCachedFile(String url) async {
    try {
      final fileInfo = await _cache.getFileFromCache(url);
      if (fileInfo != null && fileInfo.file.existsSync()) {
        return fileInfo.file;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Downloads and caches audio file with exponential backoff retry
  /// Returns cached file path on success, null on failure
  static Future<File?> downloadWithRetry(
    String url, {
    required void Function(File file) onComplete,
    void Function(int attempt, Object error)? onRetry,
  }) async {
    for (int attempt = 0; attempt < _maxDownloadAttempts; attempt++) {
      try {
        final file = await _cache.getSingleFile(url);
        if (file.existsSync()) {
          onComplete(file);
          return file;
        }
      } catch (e) {
        if (onRetry != null) {
          onRetry(attempt, e);
        }
        if (attempt < _maxDownloadAttempts - 1) {
          await Future.delayed(_backoffDelay(attempt));
        }
      }
    }
    return null;
  }

  /// Pre-warms a player for instant playback
  /// Sets up audio source and loads it in background
  static Future<bool> prewarmPlayer(
    AudioPlayer player,
    String url, {
    File? localFile,
  }) async {
    try {
      if (localFile != null && localFile.existsSync()) {
        await player.setAudioSource(AudioSource.file(localFile.path));
        await player.load();
        return true;
      }

      await player.setAudioSource(
        AudioSource.uri(Uri.parse(url)),
        preload: true,
      );
      await player.load();
      return true;
    } catch (e) {
      debugPrint('❌ VoiceNoteService.prewarmPlayer failed: $e');
      return false;
    }
  }

  /// Starts background download without blocking
  /// Perfect for calling in initState
  static void startBackgroundDownload(
    String url, {
    required void Function(File file) onComplete,
    void Function(Object error)? onError,
  }) {
    unawaited(() async {
      final file = await downloadWithRetry(
        url,
        onComplete: onComplete,
        onRetry: (attempt, error) {
          if (kDebugMode) {
            debugPrint('🔄 Voice note download retry #$attempt: $error');
          }
        },
      );
      if (file == null && onError != null) {
        onError(
          Exception('Failed to download after $_maxDownloadAttempts attempts'),
        );
      }
    }());
  }

  /// Preloads multiple voice notes for a chat view
  /// Only processes the last N messages to avoid overwhelming the system
  static void preloadVisibleVoiceNotes(
    List<String> urls, {
    int limit = 5,
    void Function(String url, File file)? onEachComplete,
  }) {
    final toProcess = urls.take(limit).toList();

    for (final url in toProcess) {
      if (url.isEmpty) continue;

      startBackgroundDownload(
        url,
        onComplete: (file) {
          if (onEachComplete != null) {
            onEachComplete(url, file);
          }
        },
        onError: (_) {
          // Silent - will retry when user taps
        },
      );
    }
  }
}
