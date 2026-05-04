import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class AudioCacheService {
  static final CacheManager _cache = DefaultCacheManager();

  static Future<File?> getAudio(String url) async {
    try {
      final file = await _cache.getSingleFile(url);
      return file;
    } catch (_) {
      return null;
    }
  }
}
