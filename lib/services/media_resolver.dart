import 'package:flutter/foundation.dart';

class MediaResolver {
  MediaResolver._();

  static const base =
      'https://gtkswyrmucdzpkjfbfty.supabase.co/storage/v1/object/public/';

  static final Set<String> _logged = <String>{};

  static void logOnceFailure(String path) {
    final k = path.trim();
    if (k.isEmpty) return;
    if (_logged.add(k)) {
      debugPrint('❌ MEDIA FAILED: $k');
    }
  }

  static String? resolve(String? rawPath, {String? bucket}) {
    if (rawPath == null) return null;
    final input = rawPath.trim();
    if (input.isEmpty) return null;

    // already full URL
    if (input.startsWith('http')) {
      return Uri.encodeFull(input.replaceAll('\\', '/'));
    }

    final cleaned = _clean(input);
    if (cleaned.isEmpty) return null;

    // Handle scaled_ files: try original
    if (cleaned.contains('scaled_')) {
      final fixed = cleaned.replaceFirst('scaled_', '');
      return resolve(fixed, bucket: bucket);
    }

    // STRICT: Never guess bucket from file extension
    // Use explicit bucket parameter, or infer from path structure only
    String resolvedBucket;
    if (bucket != null && bucket.trim().isNotEmpty) {
      resolvedBucket = bucket.trim();
    } else if (cleaned.contains('avatars')) {
      resolvedBucket = 'profilePictures';
    } else if (cleaned.contains('group_avatars')) {
      resolvedBucket = 'groupImages';
    } else if (cleaned.contains('voice_')) {
      // DEMO FIX: Voice notes always go to dmMedia
      resolvedBucket = 'dmMedia';
    } else {
      // Default to chatMedia - caller SHOULD provide explicit bucket
      resolvedBucket = 'chatMedia';
    }

    var cleanPath = cleaned.replaceAll(RegExp(r'^/+'), '');
    if (cleanPath.isEmpty) return null;

    // CRITICAL: Strip ANY known bucket prefix from path to avoid double bucket
    // This handles voice notes that were stored with wrong bucket prefix
    final knownBuckets = [
      'chatMedia',
      'dmMedia',
      'profilePictures',
      'groupImages',
    ];
    for (final b in knownBuckets) {
      if (cleanPath.startsWith('$b/')) {
        cleanPath = cleanPath.substring(b.length + 1);
        break;
      }
    }

    return Uri.encodeFull('$base$resolvedBucket/$cleanPath');
  }

  static String _clean(String path) {
    return path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+'), '')
        .replaceAll(RegExp(r'/+'), '/')
        .trim();
  }
}
