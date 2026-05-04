import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import '../models/message_model.dart';

class SelectedMedia {
  final XFile? xfile;
  final File? file;
  final MessageType type;

  String caption;
  bool viewOnce;

  // Video-only metadata (placeholders)
  Duration? trimStart;
  Duration? trimEnd;
  bool muted;

  SelectedMedia({
    required this.type,
    this.xfile,
    this.file,
    this.caption = '',
    this.viewOnce = false,
    this.trimStart,
    this.trimEnd,
    this.muted = false,
  });

  String get name {
    final n = xfile?.name;
    if (n != null && n.isNotEmpty) return n;
    final p = path;
    if (p != null && p.isNotEmpty) {
      final parts = p.split(Platform.pathSeparator);
      return parts.isNotEmpty ? parts.last : p;
    }
    return 'file';
  }

  String? get path {
    if (kIsWeb) return null;
    return xfile?.path ?? file?.path;
  }
}

class MediaPickerService {
  MediaPickerService._();

  static final MediaPickerService instance = MediaPickerService._();

  final ImagePicker _picker = ImagePicker();

  Future<List<SelectedMedia>> pickGalleryMulti({int limit = 30}) async {
    // Uses native multi-select where available.
    final items = await _picker.pickMultipleMedia(
      limit: limit,
      imageQuality: 95,
    );
    if (items.isEmpty) return <SelectedMedia>[];

    return items
        .map((x) {
          final lower = x.name.toLowerCase();
          final isVideo =
              lower.endsWith('.mp4') ||
              lower.endsWith('.mov') ||
              lower.endsWith('.mkv') ||
              lower.endsWith('.webm');
          return SelectedMedia(
            type: isVideo ? MessageType.video : MessageType.image,
            xfile: x,
          );
        })
        .toList(growable: false);
  }

  Future<List<SelectedMedia>> captureCamera({required bool video}) async {
    final XFile? x = video
        ? await _picker.pickVideo(source: ImageSource.camera)
        : await _picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 85,
            preferredCameraDevice: CameraDevice.rear,
          );
    if (x == null) return <SelectedMedia>[];
    return <SelectedMedia>[
      SelectedMedia(
        type: video ? MessageType.video : MessageType.image,
        xfile: x,
      ),
    ];
  }

  Future<List<SelectedMedia>> pickDocuments({bool allowMultiple = true}) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf',
        'doc',
        'docx',
        'ppt',
        'pptx',
        'xls',
        'xlsx',
        'txt',
        'zip',
        'rar',
      ],
      allowMultiple: allowMultiple,
      withData: false,
      withReadStream: false,
    );
    if (res == null || res.files.isEmpty) return <SelectedMedia>[];

    // Extra safety filter: reject media file extensions
    final allowed = <String>{
      '.pdf',
      '.doc',
      '.docx',
      '.ppt',
      '.pptx',
      '.xls',
      '.xlsx',
      '.txt',
      '.zip',
      '.rar',
    };

    return res.files
        .where((f) {
          final p = f.path;
          if (p == null || p.isEmpty) return false;
          final lower = p.toLowerCase();
          // Must end with allowed extension
          return allowed.any((ext) => lower.endsWith(ext));
        })
        .map((f) => SelectedMedia(type: MessageType.file, file: File(f.path!)))
        .toList(growable: false);
  }

  Future<List<SelectedMedia>> pickAudio({bool allowMultiple = true}) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: allowMultiple,
      withData: false,
      withReadStream: false,
    );
    if (res == null || res.files.isEmpty) return <SelectedMedia>[];

    return res.files
        .where((f) => f.path != null && f.path!.isNotEmpty)
        .map((f) => SelectedMedia(type: MessageType.audio, file: File(f.path!)))
        .toList(growable: false);
  }
}
