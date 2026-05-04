import 'package:flutter/foundation.dart';

import 'storage_service.dart';

/// Single source of truth for media URL resolution.
/// Converts various input formats to stable public Supabase Storage URLs.
class MediaUrlResolver {
  MediaUrlResolver._();

  static const String _projectPublicPrefix =
      'https://gtkswyrmucdzpkjfbfty.supabase.co/storage/v1/object/public/';

  static String _mediaBucket() => StorageService().mediaBucket;
  static String _audioBucket() => StorageService().audioBucket;

  static bool _isSupportedBucket(String bucket) {
    return bucket == _mediaBucket() ||
        bucket == _audioBucket() ||
        bucket == 'chatMedia';
  }

  static String _publicPrefixForBucket(String bucket) {
    return '$_projectPublicPrefix$bucket/';
  }

  /// Normalizes any legacy/malformed media reference into the single DB format:
  ///
  /// ONLY: `path/to/file.ext`
  ///
  /// Accepts (backwards compatible):
  /// - Full Supabase public URL
  /// - chatMedia/path
  /// - bucket/path (bucket must be chatMedia)
  /// - sb://chatMedia/path
  /// - Random concatenations that still contain `/chatMedia/`
  static String normalizeToChatMediaPath(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return '';

    // Explicitly reject legacy scaled_* variants. These frequently point to
    // non-existent objects and cause persistent 400s.
    if (raw.contains('scaled_')) return '';

    var v = raw.replaceAll('\\', '/');

    // If it's a full Supabase public URL, extract everything after /chatMedia/.
    // This also fixes cases like: https://.../public/chatMedia/scaled_.../file
    final idxChatMedia = v.indexOf('/chatMedia/');
    if (idxChatMedia >= 0) {
      v = v.substring(idxChatMedia + '/chatMedia/'.length);
    }

    if (v.contains('scaled_')) return '';

    // If it still starts with a scheme, we don't know how to normalize safely.
    if (v.startsWith('http://') || v.startsWith('https://')) {
      return '';
    }

    // sb://bucket/path
    if (v.startsWith('sb://')) {
      final s = v.substring(5);
      final i = s.indexOf('/');
      if (i <= 0) return '';
      final bucket = s.substring(0, i);
      final path = s.substring(i + 1);
      if (!_isSupportedBucket(bucket)) return '';
      // only keep the path portion; caller decides which bucket prefix to use.
      v = path;
    }

    // bucket/path
    if (v.contains('/')) {
      // Allow legacy strings that still prefix the bucket.
      final i = v.indexOf('/');
      final bucket = v.substring(0, i);
      if (_isSupportedBucket(bucket)) {
        v = v.substring(i + 1);
      }
    }

    // Clean and strictly de-prefix.
    v = v.replaceAll(RegExp(r'^/+'), '');
    v = v.replaceAll(RegExp(r'/+'), '/');
    v = v.replaceAll(RegExp(r'^/|/$'), '');

    // Very common corruption: duplicated prefixes.
    // Example: chatMedia/chatMedia/user/file
    if (v.startsWith('chatMedia/')) {
      v = v.substring('chatMedia/'.length);
      v = v.replaceAll(RegExp(r'^/+'), '');
    }

    return v;
  }

  static bool isValidChatMediaPath(String path) {
    final p = path.trim();
    if (p.isEmpty) return false;
    if (p.contains('http://') || p.contains('https://')) return false;
    if (p.contains('supabase.co/storage')) return false;
    return true;
  }

  static bool isValidChatMediaUrl(String url) {
    final u = url.trim();
    return u.startsWith('https://') && u.contains('/storage/v1/object/public/');
  }

  /// Resolves any media reference to a public URL.
  ///
  /// STRICT:
  /// - If input already contains `supabase.co/storage`, returns it as-is.
  /// - Otherwise normalizes to a `bucket` relative path and builds a stable
  /// - Otherwise normalizes to a `chatMedia` relative path and builds a stable
  ///   public URL.
  /// - Never uses signed URLs.
  static String resolve(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return '';

    // Reject scaled_* references early to avoid 400s and infinite loading.
    if (raw.contains('scaled_')) {
      debugPrint('❌ BAD MEDIA PATH: $raw');
      return '';
    }

    // Already full URL (including legacy public URLs)
    if (raw.contains('supabase.co/storage')) {
      return raw.replaceAll('\\', '/');
    }

    final cleanPath = normalizeToChatMediaPath(raw);
    if (!isValidChatMediaPath(cleanPath)) {
      debugPrint('❌ BAD MEDIA PATH: $raw');
      return '';
    }

    // Default to media bucket; callers that need audio can pass bucket/path
    // explicitly or store audio in the audio bucket.
    final url = '${_publicPrefixForBucket(_mediaBucket())}$cleanPath';
    if (kDebugMode) debugPrint('🖼️ MEDIA URL => $url');
    return url;
  }

  /// Async wrapper for consistency with existing APIs
  static Future<String> resolveAsync(String input) async {
    return resolve(input);
  }
}
