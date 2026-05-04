import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../../providers/user_providers.dart';
import '../../providers/chat_providers.dart';
import '../../models/message_model.dart';
import '../../widgets/glass_dropdown.dart';
import '../../services/supabase_service.dart';
import '../../services/storage_service.dart';
import 'package:url_launcher/url_launcher.dart';

final Map<String, ImageProvider> _viewerProviders = <String, ImageProvider>{};
final Set<String> _viewerPrecache = <String>{};

ImageProvider _viewerProvider(String url) {
  return _viewerProviders.putIfAbsent(
    url,
    () => CachedNetworkImageProvider(url),
  );
}

class _BlurredImage extends StatelessWidget {
  final ImageProvider provider;
  final bool blurred;
  final BoxFit fit;
  const _BlurredImage({
    required this.provider,
    required this.blurred,
    required this.fit,
  });

  @override
  Widget build(BuildContext context) {
    final image = Image(
      image: provider,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black54),
    );
    if (!blurred) return image;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: image,
    );
  }
}

class _ViewerRetryOverlay extends StatelessWidget {
  final VoidCallback onRetry;
  const _ViewerRetryOverlay({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.refresh, color: Colors.white70, size: 40),
          const SizedBox(height: 10),
          const Text('Tap to retry', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white12,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _ViewerImage extends StatefulWidget {
  final String url;
  final String heroTag;
  const _ViewerImage({required this.url, required this.heroTag});

  @override
  State<_ViewerImage> createState() => _ViewerImageState();
}

class _ViewerImageState extends State<_ViewerImage> {
  bool _ready = false;
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final provider = _viewerProvider(widget.url);
    return Stack(
      fit: StackFit.expand,
      children: [
        _BlurredImage(provider: provider, blurred: true, fit: BoxFit.contain),
        AnimatedOpacity(
          opacity: _ready ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: Hero(
            tag: widget.heroTag,
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image(
                image: provider,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                frameBuilder: (context, child, frame, wasSync) {
                  if (frame != null && !_ready) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _ready = true);
                    });
                  }
                  return child;
                },
                errorBuilder: (_, __, ___) {
                  if (!_failed) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _failed = true);
                    });
                  }
                  return const ColoredBox(color: Colors.black54);
                },
              ),
            ),
          ),
        ),
        if (_failed)
          _ViewerRetryOverlay(
            onRetry: () => setState(() {
              _failed = false;
              _ready = false;
            }),
          ),
      ],
    );
  }
}

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
  int _tabIndex = 0; // 0 media, 1 documents, 2 links, 3 voice
  bool _showAllMedia = false;

  Future<void> _confirmAndBlock() async {
    final service = ref.read(blockServiceProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block this user?'),
        content: const Text("You won't receive messages or calls from them."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirm != true) return;

    service.blockUser(peerId: widget.peerId).catchError((e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Block failed: $e')));
    });
  }

  Future<void> _unblock() async {
    final service = ref.read(blockServiceProvider);
    service.unblockUser(peerId: widget.peerId).catchError((e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unblock failed: $e')));
    });
  }

  Future<ImageProvider?> _resolve(String? url) async {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('sb://')) {
      final s = raw.substring(5);
      final i = s.indexOf('/');
      if (i <= 0) return null;
      final bucket = s.substring(0, i);
      final path = s.substring(i + 1);
      final signed = await SupabaseService.instance.getSignedUrl(
        bucket,
        path,
        expiresInSeconds: 86400,
      );
      return NetworkImage(signed);
    }
    if (!raw.contains('://')) {
      final signed = await SupabaseService.instance.resolveUrl(
        bucket: StorageService().profileBucket,
        path: raw,
      );
      return NetworkImage(signed);
    }
    return NetworkImage(raw);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userDocProvider(widget.peerId));
    final messages = ref.watch(messagesProvider(widget.chatId));
    final bubbleZoom = bubbleZoomStore[widget.chatId] ?? 1.0;
    final status = ref.watch(dmBlockStatusProvider(widget.peerId));
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Scaffold(
      backgroundColor: isLight
          ? theme.colorScheme.background
          : theme.scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    color: theme.textTheme.bodyLarge?.color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Contact info',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GlassDropdown(
                  tooltip: 'More',
                  items: [
                    GlassDropdownItem(
                      value: status.iBlocked ? 'unblock' : 'block',
                      label: status.iBlocked ? 'Unblock' : 'Block',
                      icon: Icons.block,
                      isDestructive: !status.iBlocked,
                    ),
                    const GlassDropdownItem(
                      value: 'report',
                      label: 'Report',
                      icon: Icons.flag,
                      isDestructive: true,
                    ),
                  ],
                  onSelected: (v) {
                    if (v == 'block') {
                      _confirmAndBlock();
                      return;
                    }
                    if (v == 'unblock') {
                      _unblock();
                    }
                  },
                  child: Icon(
                    Icons.more_vert,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: user.when(
        data: (u) {
          final name = (u?.name.isNotEmpty == true) ? u!.name : widget.peerId;
          final about = (u?.about ?? '').trim();
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      FutureBuilder<ImageProvider?>(
                        future: _resolve(u?.profileImageUrl),
                        builder: (context, snap) {
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 40,
                                backgroundColor: isLight
                                    ? theme.colorScheme.surface
                                    : const Color(0xFF1A1A1A),
                                backgroundImage: snap.data,
                                child: snap.data == null
                                    ? Icon(
                                        Icons.person,
                                        size: 28,
                                        color: isLight
                                            ? theme.colorScheme.onBackground
                                                  .withOpacity(0.6)
                                            : Colors.white54,
                                      )
                                    : null,
                              ),
                              Positioned(
                                right: -1,
                                bottom: -1,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF5865F2),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isLight
                                          ? theme.colorScheme.background
                                          : Colors.black,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onBackground,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (about.isNotEmpty)
                        Text(
                          about,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.onBackground.withOpacity(
                              0.6,
                            ),
                            fontSize: 13,
                          ),
                        ),
                      const SizedBox(height: 14),
                      _QuickActionBar(
                        onCall: () {},
                        onVideo: () {},
                        onSearch: () {},
                        onMute: () {},
                      ),
                      const SizedBox(height: 18),
                      _MediaTabs(
                        index: _tabIndex,
                        onChanged: (i) {
                          setState(() {
                            _tabIndex = i;
                            if (i != 0) _showAllMedia = false;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: messages.when(
                    data: (list) => _buildTabContent(context, list),
                    loading: () => _TabSkeleton(index: _tabIndex),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        '$e',
                        style: const TextStyle(
                          color: Color(0xFF9A9A9A),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 6),
                      Text(
                        'Chat Settings',
                        style: TextStyle(
                          color: theme.colorScheme.onBackground,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SettingsTile(
                        icon: Icons.text_fields,
                        title: 'Chat bubble size',
                        onTap: () {},
                      ),
                      const SizedBox(height: 10),
                      _BubbleSizeSlider(
                        value: bubbleZoom,
                        onChanged: (v) => setState(() {
                          bubbleZoomStore[widget.chatId] = v;
                        }),
                      ),
                      const SizedBox(height: 12),
                      _SettingsTile(
                        icon: Icons.notifications_off_outlined,
                        title: 'Mute notifications',
                        onTap: () {},
                      ),
                      _SettingsTile(
                        icon: Icons.block,
                        title: status.iBlocked
                            ? 'Unblock contact'
                            : 'Block contact',
                        danger: true,
                        onTap: status.iBlocked ? _unblock : _confirmAndBlock,
                      ),
                      _SettingsTile(
                        icon: Icons.delete_outline,
                        title: 'Delete chat',
                        danger: true,
                        onTap: () async {
                          final nav = Navigator.of(context);
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete chat?'),
                              content: const Text(
                                'This will permanently delete the conversation and all its messages.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (!mounted) return;
                          if (confirm == true) {
                            await ref
                                .read(chatServiceProvider)
                                .deleteChatPermanently(widget.chatId);
                            nav.pushNamedAndRemoveUntil(
                              '/home',
                              (route) => false,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, List<MessageModel> list) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    if (_tabIndex == 0) {
      final media = list
          .where(
            (m) =>
                (m.messageType == MessageType.image ||
                    m.messageType == MessageType.video) &&
                (m.mediaUrl ?? '').isNotEmpty,
          )
          .toList()
          .reversed
          .toList();
      if (media.isEmpty) {
        return const _EmptyState(text: 'No media shared yet');
      }
      final shown = _showAllMedia ? media : media.take(9).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MediaGrid(
            items: shown,
            resolveUrl: (raw, type) => _resolveMediaTileUrl(raw, type),
            onOpen: (items, start) => _openMediaViewer(context, items, start),
          ),
          if (media.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextButton(
                onPressed: () => setState(() => _showAllMedia = true),
                style: TextButton.styleFrom(
                  foregroundColor: isLight
                      ? theme.colorScheme.primary
                      : Colors.white,
                ),
                child: const Text('Show more'),
              ),
            ),
        ],
      );
    }

    if (_tabIndex == 1) {
      final docs = list
          .where(
            (m) =>
                m.messageType == MessageType.file &&
                (m.mediaUrl ?? '').isNotEmpty,
          )
          .toList()
          .reversed
          .toList();
      if (docs.isEmpty) {
        return const _EmptyState(text: 'No documents in this chat');
      }
      return Column(
        children: [
          for (final m in docs) ...[
            _DocumentRow(
              message: m,
              resolveUrl: (raw) => _resolveMediaTileUrl(raw, m.messageType),
            ),
            Divider(
              height: 1,
              thickness: 0.5,
              color: Colors.black.withOpacity(0.05),
            ),
          ],
        ],
      );
    }

    if (_tabIndex == 2) {
      final links = list
          .where(
            (m) =>
                m.messageType == MessageType.text &&
                (m.text ?? '').toLowerCase().contains('http'),
          )
          .map((m) => m.text!.trim())
          .where((t) => t.isNotEmpty)
          .toList()
          .reversed
          .toList();
      if (links.isEmpty) {
        return const _EmptyState(text: 'No links shared');
      }
      return Column(
        children: [
          for (final t in links) ...[
            _LinkCard(urlText: t),
            const SizedBox(height: 10),
          ],
        ],
      );
    }

    final voices = list
        .where(
          (m) =>
              m.messageType == MessageType.audio &&
              (m.mediaUrl ?? '').isNotEmpty,
        )
        .toList()
        .reversed
        .toList();
    if (voices.isEmpty) {
      return const _EmptyState(text: 'No voice messages');
    }
    return Column(
      children: [
        for (final m in voices) ...[
          _VoiceCard(
            message: m,
            resolveUrl: (raw) => _resolveMediaTileUrl(raw, m.messageType),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Future<String> _resolveMediaTileUrl(String raw, MessageType type) async {
    if (raw.contains('://')) {
      return SupabaseService.instance.resolveUrl(directUrl: raw);
    }
    final bucket = (type == MessageType.audio)
        ? StorageService().audioBucket
        : StorageService().mediaBucket;
    return SupabaseService.instance.resolveUrl(bucket: bucket, path: raw);
  }

  void _openMediaViewer(
    BuildContext context,
    List<MessageModel> items,
    int start,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MediaViewer(
          items: items,
          initialIndex: start,
          resolveUrl: (raw, type) => _resolveMediaTileUrl(raw, type),
        ),
      ),
    );
  }
}

class _QuickActionBar extends StatelessWidget {
  final VoidCallback onCall;
  final VoidCallback onVideo;
  final VoidCallback onSearch;
  final VoidCallback onMute;
  const _QuickActionBar({
    required this.onCall,
    required this.onVideo,
    required this.onSearch,
    required this.onMute,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isLight ? theme.colorScheme.surface : const Color(0xFF111111),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLight
              ? Colors.black.withOpacity(0.05)
              : const Color(0xFF1A1A1A),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _QuickAction(icon: Icons.call_outlined, label: 'Call', onTap: onCall),
          _QuickAction(
            icon: Icons.videocam_outlined,
            label: 'Video',
            onTap: onVideo,
          ),
          _QuickAction(
            icon: Icons.search_rounded,
            label: 'Search',
            onTap: onSearch,
          ),
          _QuickAction(
            icon: Icons.notifications_off_outlined,
            label: 'Mute',
            onTap: onMute,
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isLight
                  ? theme.colorScheme.onSurface.withOpacity(0.7)
                  : Colors.white,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isLight
                    ? theme.colorScheme.onSurface.withOpacity(0.7)
                    : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaTabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _MediaTabs({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _IconTab(
          icon: Icons.photo_library_outlined,
          active: index == 0,
          onTap: () => onChanged(0),
        ),
        _IconTab(
          icon: Icons.description_outlined,
          active: index == 1,
          onTap: () => onChanged(1),
        ),
        _IconTab(
          icon: Icons.link_outlined,
          active: index == 2,
          onTap: () => onChanged(2),
        ),
        _IconTab(
          icon: Icons.mic_none_outlined,
          active: index == 3,
          onTap: () => onChanged(3),
        ),
      ],
    );
  }
}

class _IconTab extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _IconTab({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final c = active
        ? (isLight ? theme.colorScheme.primary : Colors.white)
        : (isLight
              ? theme.colorScheme.onSurface.withOpacity(0.5)
              : const Color(0xFF7A7A7A));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 2,
              width: 28,
              decoration: BoxDecoration(
                color: active ? theme.colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  final List<MessageModel> items;
  final Future<String> Function(String raw, MessageType type) resolveUrl;
  final void Function(List<MessageModel> items, int start) onOpen;
  const _MediaGrid({
    required this.items,
    required this.resolveUrl,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final theme = Theme.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final m = items[i];
        final raw = m.mediaUrl ?? '';
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Material(
            color: isLight
                ? theme.colorScheme.surface
                : const Color(0xFF151515),
            child: InkWell(
              onTap: () => onOpen(items, i),
              child: FutureBuilder<String>(
                future: resolveUrl(raw, m.messageType),
                builder: (context, snap) {
                  final resolved = snap.data;
                  if (resolved == null || resolved.isEmpty) {
                    return ColoredBox(
                      color: isLight
                          ? theme.colorScheme.surface
                          : const Color(0xFF151515),
                    );
                  }
                  if (m.messageType == MessageType.video) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        _VideoFrameThumb(url: resolved),
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ],
                    );
                  }
                  return CachedNetworkImage(
                    imageUrl: resolved,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (context, _) => ColoredBox(
                      color: isLight
                          ? theme.colorScheme.surface
                          : const Color(0xFF151515),
                    ),
                    errorWidget: (context, _, __) => ColoredBox(
                      color: isLight
                          ? theme.colorScheme.surface
                          : const Color(0xFF151515),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VideoFrameThumb extends StatefulWidget {
  final String url;
  const _VideoFrameThumb({required this.url});

  @override
  State<_VideoFrameThumb> createState() => _VideoFrameThumbState();
}

class _VideoFrameThumbState extends State<_VideoFrameThumb> {
  VideoPlayerController? _c;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant _VideoFrameThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _dispose();
      _init();
    }
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c = c;
    try {
      await c.initialize();
      await c.pause();
      if (mounted) setState(() {});
    } catch (_) {
      // ignore
    }
  }

  void _dispose() {
    final c = _c;
    _c = null;
    c?.dispose();
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_c != null && _c!.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: _c!.value.size.width,
          height: _c!.value.size.height,
          child: VideoPlayer(_c!),
        ),
      );
    }
    return const ColoredBox(color: Color(0xFF151515));
  }
}

class _MediaViewer extends StatefulWidget {
  final List<MessageModel> items;
  final int initialIndex;
  final Future<String> Function(String raw, MessageType type) resolveUrl;
  const _MediaViewer({
    required this.items,
    required this.initialIndex,
    required this.resolveUrl,
  });

  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  late final PageController _pc;
  int _currentIndex = 0;
  bool _showUi = true;
  double _dragDy = 0;
  int _retryNonce = 0;

  @override
  void initState() {
    super.initState();
    _pc = PageController(initialPage: widget.initialIndex);
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheAround(_currentIndex);
    });
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _precacheAround(int index) {
    for (final i in [index - 1, index, index + 1]) {
      if (i < 0 || i >= widget.items.length) continue;
      final m = widget.items[i];
      if (m.messageType != MessageType.image) continue;
      final raw = m.mediaUrl ?? '';
      if (raw.isEmpty) continue;
      widget
          .resolveUrl(raw, m.messageType)
          .then((u) {
            if (u.isEmpty || !mounted || !_viewerPrecache.add(u)) return;
            unawaited(
              precacheImage(_viewerProvider(u), context).catchError((_) {}),
            );
          })
          .catchError((_) {});
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    setState(() => _dragDy += d.delta.dy);
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy.abs();
    final dy = _dragDy.abs();
    if (dy > 120 || v > 900) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _dragDy = 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showUi = !_showUi),
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              color: Colors.black.withOpacity(
                (1.0 - (_dragDy.abs() / 280).clamp(0.0, 0.6)),
              ),
            ),
            Transform.translate(
              offset: Offset(0, _dragDy),
              child: PageView.builder(
                controller: _pc,
                itemCount: widget.items.length,
                onPageChanged: (i) {
                  setState(() => _currentIndex = i);
                  _precacheAround(i);
                },
                itemBuilder: (context, i) {
                  final m = widget.items[i];
                  final raw = m.mediaUrl ?? '';
                  final heroTag = raw.isNotEmpty ? raw : 'media_${m.id}';
                  return FutureBuilder<String>(
                    key: ValueKey('${m.id}_$_retryNonce'),
                    future: widget.resolveUrl(raw, m.messageType),
                    builder: (context, snap) {
                      final resolved = snap.data ?? '';
                      if (resolved.isEmpty) {
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            const ColoredBox(color: Colors.black54),
                            _ViewerRetryOverlay(
                              onRetry: () => setState(() => _retryNonce++),
                            ),
                          ],
                        );
                      }
                      if (m.messageType == MessageType.video) {
                        return Center(
                          child: _VideoFullscreenViewer(url: resolved),
                        );
                      }
                      return Center(
                        child: _ViewerImage(url: resolved, heroTag: heroTag),
                      );
                    },
                  );
                },
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _showUi ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Text(
                          '${_currentIndex + 1} / ${widget.items.length}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.download,
                                color: Colors.white,
                              ),
                              onPressed: () {},
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.share,
                                color: Colors.white,
                              ),
                              onPressed: () {},
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoFullscreenViewer extends StatefulWidget {
  final String url;
  const _VideoFullscreenViewer({required this.url});

  @override
  State<_VideoFullscreenViewer> createState() => _VideoFullscreenViewerState();
}

class _VideoFullscreenViewerState extends State<_VideoFullscreenViewer> {
  VideoPlayerController? _c;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c));
  }
}

class _DocumentRow extends StatelessWidget {
  final MessageModel message;
  final Future<String> Function(String raw) resolveUrl;
  const _DocumentRow({required this.message, required this.resolveUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final raw = message.mediaUrl ?? '';
    final name = raw.split('/').last;
    final ext = name.contains('.')
        ? name.split('.').last.toUpperCase()
        : 'FILE';
    final size = (message.mediaSize != null && message.mediaSize! > 0)
        ? _fmtSize(message.mediaSize!)
        : '';
    final meta = size.isEmpty ? ext : '$ext - $size';
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isLight
                  ? theme.colorScheme.surface
                  : const Color(0xFF151515),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.description_outlined,
              color: isLight
                  ? theme.colorScheme.onSurface.withOpacity(0.7)
                  : Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () async {
              final resolved = await resolveUrl(raw);
              await launchUrl(
                Uri.parse(resolved),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: Icon(
              Icons.download_rounded,
              color: isLight ? theme.colorScheme.primary : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtSize(int bytes) {
    const kb = 1024;
    const mb = 1024 * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}

class _LinkCard extends StatelessWidget {
  final String urlText;
  const _LinkCard({required this.urlText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final uri = Uri.tryParse(urlText);
    final domain = uri?.host.isNotEmpty == true ? uri!.host : urlText;
    return InkWell(
      onTap: () async {
        final u = Uri.tryParse(urlText);
        if (u == null) return;
        await launchUrl(u, mode: LaunchMode.externalApplication);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isLight ? theme.colorScheme.surface : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isLight
                ? Colors.black.withOpacity(0.05)
                : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              urlText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              domain,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  final MessageModel message;
  final Future<String> Function(String raw) resolveUrl;
  const _VoiceCard({required this.message, required this.resolveUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isLight ? theme.colorScheme.surface : const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLight ? Colors.black.withOpacity(0.05) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: Color(0xFF5865F2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            '0:00',
            style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool danger;
  final VoidCallback onTap;
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final c = danger
        ? Colors.redAccent
        : (isLight ? theme.colorScheme.onSurface : Colors.white);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: c.withValues(alpha: 0.9)),
          ],
        ),
      ),
    );
  }
}

class _BubbleSizeSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _BubbleSizeSlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: theme.colorScheme.primary,
        inactiveTrackColor: Theme.of(context).brightness == Brightness.light
            ? theme.colorScheme.onSurface.withOpacity(0.2)
            : const Color(0xFF1E1E1E),
        thumbColor: theme.colorScheme.primary,
        overlayColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      ),
      child: Slider(
        min: 1.0,
        max: 1.6,
        divisions: 12,
        value: value.clamp(1.0, 1.6),
        onChanged: onChanged,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: theme.colorScheme.onBackground.withOpacity(0.6),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _TabSkeleton extends StatelessWidget {
  final int index;
  const _TabSkeleton({required this.index});

  @override
  Widget build(BuildContext context) {
    if (index == 0) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: 9,
        itemBuilder: (_, __) => ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: const ColoredBox(color: Color(0xFF151515)),
        ),
      );
    }
    if (index == 1) {
      return Column(
        children: List.generate(
          4,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF151515),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF151515),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}
