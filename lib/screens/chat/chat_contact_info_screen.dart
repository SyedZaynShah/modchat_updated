import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/user_providers.dart';
import '../../providers/chat_providers.dart';
import '../../models/message_model.dart';
import '../../services/supabase_service.dart';
import '../../services/storage_service.dart';
import '../../theme/theme.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatContactInfoScreen extends ConsumerStatefulWidget {
  static const routeName = '/chat-contact-info';
  final String peerId;
  final String chatId;
  const ChatContactInfoScreen({
    super.key,
    required this.peerId,
    required this.chatId,
  });

  @override
  ConsumerState<ChatContactInfoScreen> createState() =>
      _ChatContactInfoScreenState();
}

class _ChatContactInfoScreenState extends ConsumerState<ChatContactInfoScreen> {
  int _tabIndex = 0; // 0 media, 1 documents, 2 links
  bool _showAllMedia = false;

  Future<ImageProvider?> _resolve(String? url) async {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('sb://')) {
      final s = url.substring(5);
      final i = s.indexOf('/');
      final bucket = s.substring(0, i);
      final path = s.substring(i + 1);
      final signed = await SupabaseService.instance.getSignedUrl(
        bucket,
        path,
        expiresInSeconds: 86400,
      );
      return NetworkImage(signed);
    }
    if (!url.contains('://')) {
      final signed = await SupabaseService.instance.resolveUrl(
        bucket: StorageService().profileBucket,
        path: url,
      );
      return NetworkImage(signed);
    }
    return NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userDocProvider(widget.peerId));
    final messages = ref.watch(messagesProvider(widget.chatId));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Contact info',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.navy),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(3),
          child: SizedBox(
            height: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(color: AppColors.sinopia),
            ),
          ),
        ),
      ),
      body: user.when(
        data: (u) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FutureBuilder<ImageProvider?>(
                  future: _resolve(u?.profileImageUrl),
                  builder: (context, snap) => CircleAvatar(
                    radius: 44,
                    backgroundImage: snap.data,
                    child: snap.data == null
                        ? const Icon(Icons.person, size: 44)
                        : null,
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -44),
                  child: _NotchedActionsBar(
                    avatarRadius: 44,
                    gap: 10,
                    height: 214,
                    title: (u?.name.isNotEmpty == true
                        ? u!.name
                        : widget.peerId),
                    subtitle: (u?.about ?? ''),
                    onCall: () {},
                    onVideo: () {},
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Media',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Tabs icons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _tabIcon(0, Icons.photo_library_outlined),
                    _tabIcon(1, Icons.description_outlined),
                    _tabIcon(2, Icons.link_outlined),
                  ],
                ),
                const SizedBox(height: 10),
                messages.when(
                  data: (list) {
                    if (_tabIndex == 0) {
                      final media = list
                          .where(
                            (m) =>
                                m.messageType == MessageType.image &&
                                (m.mediaUrl ?? '').isNotEmpty,
                          )
                          .toList()
                          .reversed
                          .toList();
                      if (media.isEmpty) return _empty('No media');
                      final shown = _showAllMedia
                          ? media
                          : media.take(9).toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 6,
                                  crossAxisSpacing: 6,
                                ),
                            itemCount: shown.length,
                            itemBuilder: (context, i) {
                              final m = shown[i];
                              final raw = m.mediaUrl!;
                              return FutureBuilder<String>(
                                future: () async {
                                  if (raw.contains('://')) {
                                    return SupabaseService.instance.resolveUrl(
                                      directUrl: raw,
                                    );
                                  }
                                  final bucket = StorageService().mediaBucket;
                                  return SupabaseService.instance.resolveUrl(
                                    bucket: bucket,
                                    path: raw,
                                  );
                                }(),
                                builder: (context, snap) {
                                  final resolved = snap.data;
                                  return GestureDetector(
                                    onTap: resolved == null
                                        ? null
                                        : () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => Scaffold(
                                                  backgroundColor: Colors.black,
                                                  appBar: AppBar(
                                                    actions: [
                                                      IconButton(
                                                        icon: const Icon(
                                                          Icons
                                                              .download_rounded,
                                                        ),
                                                        onPressed: () async {
                                                          await launchUrl(
                                                            Uri.parse(resolved),
                                                            mode: LaunchMode
                                                                .externalApplication,
                                                          );
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                  body: PhotoView(
                                                    imageProvider: NetworkImage(
                                                      resolved,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: resolved == null
                                          ? const Center(
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Image.network(
                                              resolved,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          if (media.length > shown.length)
                            TextButton(
                              onPressed: () =>
                                  setState(() => _showAllMedia = true),
                              child: const Text('Show more'),
                            ),
                        ],
                      );
                    } else if (_tabIndex == 1) {
                      final docs = list
                          .where(
                            (m) =>
                                m.messageType == MessageType.file &&
                                (m.mediaUrl ?? '').isNotEmpty,
                          )
                          .toList()
                          .reversed
                          .toList();
                      if (docs.isEmpty) return _empty('No documents');
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final m = docs[i];
                          final name = (m.mediaUrl ?? '').split('/').last;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.insert_drive_file,
                              color: AppColors.navy,
                            ),
                            title: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(
                              Icons.open_in_new,
                              color: AppColors.navy,
                            ),
                          );
                        },
                      );
                    } else {
                      final links = list
                          .where(
                            (m) =>
                                m.messageType == MessageType.text &&
                                (m.text ?? '').toLowerCase().contains('http'),
                          )
                          .map((m) => m.text!)
                          .toList()
                          .reversed
                          .toList();
                      if (links.isEmpty) return _empty('No links');
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: links.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final t = links[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.link,
                              color: AppColors.navy,
                            ),
                            title: Text(
                              t,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      );
                    }
                  },
                  loading: () => const SizedBox(
                    height: 40,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (e, _) => SizedBox(
                    height: 40,
                    child: Center(
                      child: Text(
                        '$e',
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                const Divider(height: 24),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete chat?'),
                          content: const Text(
                            'This will permanently delete the conversation and all its messages.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await ref
                            .read(chatServiceProvider)
                            .deleteChatPermanently(widget.chatId);
                        if (!mounted) return;
                        // Ensure we land on the chat list reliably
                        Navigator.of(
                          context,
                        ).pushNamedAndRemoveUntil('/home', (route) => false);
                      }
                    },
                    splashColor: AppColors.navy.withOpacity(0.08),
                    highlightColor: AppColors.navy.withOpacity(0.06),
                    child: const ListTile(
                      leading: Icon(
                        Icons.delete_forever,
                        color: Colors.redAccent,
                      ),
                      title: Text(
                        'Delete chat',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _tabIcon(int i, IconData icon) {
    final selected = _tabIndex == i;
    return InkWell(
      onTap: () => setState(() {
        _tabIndex = i;
        if (i != 0) _showAllMedia = false;
      }),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.navy),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 2,
            width: 26,
            decoration: BoxDecoration(
              color: selected ? AppColors.sinopia : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(String text) => SizedBox(
    height: 40,
    child: Center(
      child: Text(
        text,
        style: const TextStyle(color: Colors.black45, fontSize: 12),
      ),
    ),
  );
}

class _NotchedActionsBar extends StatelessWidget {
  final double avatarRadius;
  final double gap;
  final double height;
  final String title;
  final String subtitle;
  final VoidCallback onCall;
  final VoidCallback onVideo;

  const _NotchedActionsBar({
    required this.avatarRadius,
    required this.gap,
    required this.height,
    required this.title,
    required this.subtitle,
    required this.onCall,
    required this.onVideo,
  });

  @override
  Widget build(BuildContext context) {
    final notch = avatarRadius + gap;
    // Place content ~1.5 lines below the bottom of the circular notch
    final topInset = notch + 28;
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _ActionsBarPainter(
          color: AppColors.navy,
          cornerRadius: 18,
          notchRadius: notch,
          shadowColor: Colors.black.withOpacity(0.14),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, topInset, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Name
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
              const SizedBox(height: 32),
              // Icons centered with decent spacing
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _iconBtn(Icons.videocam_rounded, onVideo),
                  const SizedBox(width: 26),
                  _iconBtn(Icons.call_rounded, onCall),
                  const SizedBox(width: 26),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    color: Colors.white,
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'block', child: Text('Block')),
                      PopupMenuItem(value: 'report', child: Text('Report')),
                    ],
                    onSelected: (v) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(v == 'block' ? 'Blocked' : 'Reported'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) => InkResponse(
    onTap: onTap,
    radius: 28,
    splashColor: AppColors.white.withOpacity(0.12),
    highlightColor: Colors.transparent,
    child: Icon(icon, color: Colors.white, size: 24),
  );
}

class _ActionsBarPainter extends CustomPainter {
  final Color color;
  final double cornerRadius;
  final double notchRadius;
  final Color shadowColor;

  _ActionsBarPainter({
    required this.color,
    required this.cornerRadius,
    required this.notchRadius,
    required this.shadowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(cornerRadius),
    );

    final rectPath = Path()..addRRect(rrect);

    final notchPath = Path()
      ..addOval(Rect.fromCircle(center: Offset(w / 2, 0), radius: notchRadius));

    final path = Path.combine(ui.PathOperation.difference, rectPath, notchPath);

    canvas.drawShadow(path, shadowColor, 12, false);
    final paint = Paint()..color = color;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ActionsBarPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.cornerRadius != cornerRadius ||
        oldDelegate.notchRadius != notchRadius ||
        oldDelegate.shadowColor != shadowColor;
  }
}
