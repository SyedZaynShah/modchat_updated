import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class _SignedUrlCacheEntry {
  final String url;
  final DateTime expiresAt;
  _SignedUrlCacheEntry(this.url, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  final Map<String, _SignedUrlCacheEntry> _cache = {};

  SupabaseClient get _client => Supabase.instance.client;

  ({String bucket, String path})? _parseSupabasePathFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final idx = segments.indexOf('object');
      if (idx != -1 && idx + 1 < segments.length) {
        // Handles both .../object/public/<bucket>/<path> and .../object/sign/<bucket>/<path>
        if (segments[idx + 1] == 'public' || segments[idx + 1] == 'sign') {
          if (idx + 3 <= segments.length) {
            final bucket = segments[idx + 2];
            final path = segments.sublist(idx + 3).join('/');
            return (bucket: bucket, path: path);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final from = _client.storage.from(bucket);
    await from.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        contentType: contentType,
        upsert: true,
        cacheControl: '3600',
      ),
    );
  }

  Future<String> getPublicUrl(String bucket, String path) {
    final from = _client.storage.from(bucket);
    return Future.value(from.getPublicUrl(path));
  }

  Future<String> getSignedUrl(
    String bucket,
    String path, {
    int expiresInSeconds = 86400,
  }) async {
    final key = '$bucket/$path';
    final cached = _cache[key];
    if (cached != null && !cached.isExpired) {
      return cached.url;
    }
    final from = _client.storage.from(bucket);
    // createSignedUrl returns a String in supabase_flutter 2.x
    final signedUrl = await from.createSignedUrl(path, expiresInSeconds);
    final entry = _SignedUrlCacheEntry(
      signedUrl,
      DateTime.now().add(Duration(seconds: expiresInSeconds - 5)),
    );
    _cache[key] = entry;
    return signedUrl;
  }

  Future<String> resolveUrl({
    String? directUrl,
    String? bucket,
    String? path,
    int expiresInSeconds = 86400,
  }) async {
    if (directUrl != null && directUrl.isNotEmpty) {
      // sb://bucket/path
      if (directUrl.startsWith('sb://')) {
        final s = directUrl.substring(5);
        final i = s.indexOf('/');
        if (i > 0) {
          final b = s.substring(0, i);
          final p = s.substring(i + 1);
          return getSignedUrl(b, p, expiresInSeconds: expiresInSeconds);
        }
      }
      // http(s) Supabase storage URL (public or expired signed) -> re-sign
      final parsed = _parseSupabasePathFromUrl(directUrl);
      if (parsed != null) {
        return getSignedUrl(
          parsed.bucket,
          parsed.path,
          expiresInSeconds: expiresInSeconds,
        );
      }
      // Any other URL: return as-is
      return directUrl;
    }
    if (bucket != null &&
        bucket.isNotEmpty &&
        path != null &&
        path.isNotEmpty) {
      return getSignedUrl(bucket, path, expiresInSeconds: expiresInSeconds);
    }
    throw StateError('No media URL or storage path provided');
  }
}
