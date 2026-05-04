import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MediaService {
  MediaService._();

  static Future<String?> resolvePublicUrl(String? rawUrl) async {
    final raw = (rawUrl ?? '').trim();
    if (raw.isEmpty) return null;

    try {
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        return raw;
      }

      String bucket;
      String path;

      // sb://bucket/path
      if (raw.startsWith('sb://')) {
        final s = raw.substring(5);
        final i = s.indexOf('/');
        if (i <= 0) return null;
        bucket = s.substring(0, i);
        path = s.substring(i + 1);
      } else if (raw.contains('/')) {
        // bucket/path
        final i = raw.indexOf('/');
        bucket = raw.substring(0, i);
        path = raw.substring(i + 1);
      } else {
        return null;
      }

      // Sanitize path: remove double slashes and leading/trailing slashes
      path = path
          .replaceAll(RegExp(r'/+'), '/')
          .replaceAll(RegExp(r'^/|/$'), '');

      // Encode each segment to avoid double-encoding '/' while still handling spaces
      final encodedPath = path
          .split('/')
          .map((s) => Uri.encodeComponent(s))
          .join('/');

      final client = Supabase.instance.client;
      final url = client.storage.from(bucket).getPublicUrl(encodedPath);

      // Validate URL format
      if (url.isEmpty || !url.startsWith('http')) {
        debugPrint('❌ Invalid media URL generated: $url for path: $path');
        return null;
      }

      return url;
    } catch (e) {
      debugPrint('❌ Invalid media URL: $raw - Error: $e');
      return null;
    }
  }
}
