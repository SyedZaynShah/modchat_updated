import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageUploadResult {
  final String path;
  final String signedUrl;
  final String contentType;
  final int size;
  StorageUploadResult({required this.path, required this.signedUrl, required this.contentType, required this.size});
}

class StorageService {
  

  Future<StorageUploadResult> uploadBytes({
    required Uint8List data,
    required String bucket,
    required String path,
    required String contentType,
    int expireInSeconds = 604800, // 7 days
  }) async {
    final client = Supabase.instance.client;
    final storage = client.storage.from(bucket);
    await storage.uploadBinary(path, data, fileOptions: FileOptions(contentType: contentType, cacheControl: '3600'));
    final signed = await storage.createSignedUrl(path, expireInSeconds);
    return StorageUploadResult(path: path, signedUrl: signed, contentType: contentType, size: data.length);
  }

  String get profileBucket => dotenv.env['SUPABASE_STORAGE_BUCKET_PROFILE'] ?? 'profile_pics';
  String get mediaBucket => dotenv.env['SUPABASE_STORAGE_BUCKET_MEDIA'] ?? 'chat_media';
  String get audioBucket => dotenv.env['SUPABASE_STORAGE_BUCKET_AUDIO'] ?? 'chat_audio';
}
