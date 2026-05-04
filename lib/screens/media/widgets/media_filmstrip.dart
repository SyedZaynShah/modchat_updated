import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../../models/message_model.dart';
import '../../../services/media_picker_service.dart';

class MediaFilmstrip extends StatelessWidget {
  final List<SelectedMedia> items;
  final int currentIndex;
  final ValueChanged<int> onTapIndex;

  const MediaFilmstrip({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTapIndex,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final m = items[i];
          final selected = i == currentIndex;
          return GestureDetector(
            onTap: () => onTapIndex(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? const Color(0xFF5865F2) : Colors.white12,
                  width: selected ? 2 : 1,
                ),
                color: Colors.white10,
              ),
              clipBehavior: Clip.antiAlias,
              child: _Thumb(media: m),
            ),
          );
        },
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final SelectedMedia media;
  const _Thumb({required this.media});

  @override
  Widget build(BuildContext context) {
    final p = media.path;
    if (p == null || p.isEmpty) {
      return const ColoredBox(color: Colors.black54);
    }

    if (media.type == MessageType.image) {
      return Image.file(
        File(p),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black54),
      );
    }

    if (media.type == MessageType.video) {
      return FutureBuilder<String?>(
        future: VideoThumbnail.thumbnailFile(
          video: p,
          imageFormat: ImageFormat.JPEG,
          quality: 60,
        ).catchError((_) => null),
        builder: (context, snap) {
          final thumb = snap.data;
          if (thumb == null || thumb.isEmpty) {
            return const ColoredBox(color: Colors.black54);
          }
          return Image.file(
            File(thumb),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: Colors.black54),
          );
        },
      );
    }

    return const Center(
      child: Icon(Icons.insert_drive_file, color: Colors.white54, size: 20),
    );
  }
}
