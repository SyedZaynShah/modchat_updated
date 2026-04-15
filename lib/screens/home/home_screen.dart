import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/chat_providers.dart';
import '../../providers/user_providers.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/theme.dart';
import '../../widgets/glass_dropdown.dart';
import '../../widgets/glass_button.dart';
import '../../widgets/spotlight_nav_bar.dart';
import '../chat/chat_detail_screen.dart';
import '../chat/group_chat_detail_screen.dart';
import '../home/new_chat_screen.dart';
import '../group/create_group_screen.dart';
import '../settings/settings_screen.dart';
import 'package:image_picker/image_picker.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _ResolvedAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  final IconData emptyIcon;

  const _ResolvedAvatar({
    required this.url,
    this.radius = 18,
    this.emptyIcon = Icons.person,
  });

  @override
  Widget build(BuildContext context) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.sinopia.withValues(alpha: 0.25),
        child: Icon(emptyIcon, color: AppColors.white.withValues(alpha: 0.7)),
      );
    }

    final fut = raw.contains('://')
        ? Future.value(raw)
        : SupabaseService.instance.resolveUrl(
            bucket: StorageService().profileBucket,
            path: raw,
          );

    return FutureBuilder<String>(
      future: fut,
      builder: (context, snap) {
        final resolved = snap.data;
        final hasImage = resolved != null && resolved.isNotEmpty;
        return CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.sinopia.withValues(alpha: 0.25),
          backgroundImage: hasImage ? NetworkImage(resolved) : null,
          onBackgroundImageError: hasImage ? (_, __) {} : null,
          child: hasImage
              ? null
              : Icon(emptyIcon, color: AppColors.white.withValues(alpha: 0.7)),
        );
      },
    );
  }
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _aboutController = TextEditingController();
  final _chatSearchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _aboutController.dispose();
    _chatSearchController.dispose();
    _searchFocus.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _openCamera() async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (!mounted) return;
      if (photo == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Camera cancelled')));
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Photo captured')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Camera error: $e')));
    }
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'settings':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        break;
      case 'new_group':
        Navigator.pushNamed(context, CreateGroupScreen.routeName);
        break;
      case 'new_community':
      case 'broadcast_lists':
      case 'starred':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Coming soon: ${value.replaceAll('_', ' ')}')),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatList = ref.watch(chatListProvider);
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Scaffold(
      backgroundColor: isLight
          ? theme.colorScheme.background
          : AppColors.background,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const BouncingScrollPhysics(),
          onPageChanged: (i) => setState(() => _currentIndex = i),
          children: [
            // Chats Hub
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _HomeHeader(
                    onCamera: _openCamera,
                    onMenuSelected: _onMenuSelected,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _SmartSearchBar(
                    controller: _chatSearchController,
                    focusNode: _searchFocus,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _QuickActionsRow(
                    onNewChat: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NewChatScreen()),
                    ),
                    onNewGroup: () => Navigator.pushNamed(
                      context,
                      CreateGroupScreen.routeName,
                    ),
                    onCamera: _openCamera,
                    onSaved: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Saved messages soon')),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: chatList.when(
                    data: (docs) {
                      if (docs.isEmpty) {
                        return const _EmptyChatsState();
                      }

                      final q = _chatSearchController.text.trim().toLowerCase();

                      final pinned =
                          <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                      final rest =
                          <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                      for (final d in docs) {
                        final data = d.data();
                        final isPinned = (data['pinned'] as bool?) ?? false;
                        if (isPinned) {
                          pinned.add(d);
                        } else {
                          rest.add(d);
                        }
                      }

                      return ListView(
                        padding: const EdgeInsets.only(top: 2, bottom: 88),
                        children: [
                          if (pinned.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                              child: Text(
                                'Pinned',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isLight
                                      ? theme.colorScheme.onBackground
                                            .withOpacity(0.7)
                                      : AppColors.textTertiary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            isLight
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surface,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: theme.dividerColor.withOpacity(
                                            0.1,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: _PinnedChatsRow(
                                        pinned: pinned,
                                        query: q,
                                      ),
                                    ),
                                  )
                                : _PinnedChatsRow(pinned: pinned, query: q),
                            const SizedBox(height: 10),
                          ],
                          ...rest.map((d) {
                            final data = d.data();
                            final type = (data['type'] as String?) ?? 'dm';
                            final groupName = data['name'] as String?;
                            final members = List<String>.from(
                              data['members'] as List,
                            );
                            final me = FirebaseAuth.instance.currentUser!.uid;
                            final peerId = members.firstWhere(
                              (m) => m != me,
                              orElse: () => me,
                            );
                            final last = data['lastMessage'] as String?;
                            final lastType =
                                (data['lastMessageType'] as String?)
                                    ?.trim()
                                    .toLowerCase();
                            final unread = (data['unreadCount'] as int?) ?? 0;
                            final ts = (data['lastTimestamp'] as Timestamp?)
                                ?.toDate();
                            final typingMap = Map<String, dynamic>.from(
                              (data['typing'] as Map?) ?? const <String, dynamic>{},
                            );
                            return _ChatListTile(
                              chatId: d.id,
                              peerId: peerId,
                              myUid: me,
                              typingMap: typingMap,
                              last: last,
                              lastType: lastType,
                              time: ts,
                              unreadCount: unread,
                              query: q,
                              chatType: type,
                              groupName: groupName,
                            );
                          }),
                        ],
                      );
                    },
                    loading: () => const _ChatListSkeleton(),
                    error: (e, _) => Center(
                      child: Text(
                        'Error: $e',
                        style: TextStyle(
                          color: theme.colorScheme.onBackground.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Updates placeholder
            _buildPlaceholder(icon: Icons.update, text: 'No updates yet'),
            // Communities placeholder
            _buildPlaceholder(
              icon: Icons.groups_rounded,
              text: 'No communities yet',
            ),
            // Calls placeholder
            _buildPlaceholder(icon: Icons.call_rounded, text: 'No calls yet'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: isLight
          ? theme.colorScheme.primary
          : AppColors.highlight,
        foregroundColor: isLight ? Colors.white : Colors.black,
        elevation: isLight ? 3 : null,
        shape: isLight
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
          : null,
        child: const Icon(Icons.chat_bubble_outline),
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const NewChatScreen()));
        },
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return SpotlightNavBar(
      items: [
        const SpotlightNavItem(icon: Icons.chat_bubble_outline),
        const SpotlightNavItem(icon: Icons.update_outlined),
        const SpotlightNavItem(icon: Icons.groups_outlined),
        const SpotlightNavItem(icon: Icons.call_outlined),
      ],
      currentIndex: _currentIndex,
      onTap: (index) {
        setState(() => _currentIndex = index);
        _pageController.animateToPage(
          index,
          duration: const Duration(
            milliseconds: 1,
          ), // Instant page change, nav handles animation
          curve: Curves.linear,
        );
      },
    );
  }
}

extension on _HomeScreenState {
  Widget _buildPlaceholder({required IconData icon, required String text}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppColors.iconMuted),
          const SizedBox(height: 12),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatListTile extends ConsumerWidget {
  final String chatId;
  final String peerId;
  final String myUid;
  final Map<String, dynamic>? typingMap;
  final String? last;
  final String? lastType;
  final DateTime? time;
  final int unreadCount;
  final String? query;
  final String chatType;
  final String? groupName;
  const _ChatListTile({
    required this.chatId,
    required this.peerId,
    required this.myUid,
    this.typingMap,
    this.last,
    this.lastType,
    this.time,
    this.unreadCount = 0,
    this.query,
    this.chatType = 'dm',
    this.groupName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = (query ?? '').trim().toLowerCase();
    final typingState = getTypingState(typingMap, myUid);

    if (chatType == 'group') {
      final title = (groupName ?? '').trim().isNotEmpty ? groupName! : 'Group';
      if (q.isNotEmpty) {
        final matched =
            title.toLowerCase().contains(q) ||
            (last ?? '').toLowerCase().contains(q);
        if (!matched) return const SizedBox.shrink();
      }

      return _ChatTile(
        title: title,
        subtitle: _subtitle(
          typingState: typingState,
          last: last,
          lastType: lastType,
        ),
        leading: _AvatarWithDot(
          avatar: CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF1A1A1A),
            child: const Icon(Icons.group, color: AppColors.white, size: 18),
          ),
          showDot: _isFresh(time),
        ),
        trailing: _TrailingMeta(time: time, unreadCount: unreadCount),
        onTap: () => Navigator.pushNamed(
          context,
          GroupChatDetailScreen.routeName,
          arguments: {'chatId': chatId},
        ),
      );
    }

    final user = ref.watch(userDocProvider(peerId));
    return user.when(
      data: (u) {
        if (q.isNotEmpty) {
          final name = (u?.name ?? '').toLowerCase();
          final email = (u?.email ?? '').toLowerCase();
          final id = peerId.toLowerCase();
          final lastMsg = (last ?? '').toLowerCase();
          final matched =
              name.contains(q) ||
              email.contains(q) ||
              id.contains(q) ||
              lastMsg.contains(q);
          if (!matched) return const SizedBox.shrink();
        }

        final title = u?.name.isNotEmpty == true ? u!.name : peerId;
        return _ChatTile(
          title: title,
          subtitle: _subtitle(
            typingState: typingState,
            last: last,
            lastType: lastType,
          ),
          leading: _AvatarWithDot(
            avatar: _ResolvedAvatar(url: u?.profileImageUrl, radius: 20),
            showDot: _isFresh(time),
          ),
          trailing: _TrailingMeta(time: time, unreadCount: unreadCount),
          onTap: () => Navigator.pushNamed(
            context,
            ChatDetailScreen.routeName,
            arguments: {'chatId': chatId, 'peerId': peerId},
          ),
        );
      },
      loading: () => const ListTile(title: Text('...'), subtitle: Text('...')),
      error: (e, _) =>
          ListTile(title: Text(peerId), subtitle: Text(last ?? '')),
    );
  }

  bool _isFresh(DateTime? date) {
    if (date == null) return false;
    final d = DateTime.now().difference(date);
    return d.inMinutes >= 0 && d.inMinutes <= 5;
  }

  _Preview _previewLabel({required String? last, required String? lastType}) {
    final t = (lastType ?? '').trim().toLowerCase();
    if (t == 'image' || t == 'photo') {
      return const _Preview(icon: Icons.photo_outlined, label: 'Photo');
    }
    if (t == 'video') {
      return const _Preview(icon: Icons.videocam_outlined, label: 'Video');
    }
    if (t == 'audio' || t == 'voice') {
      return const _Preview(icon: Icons.mic_none, label: 'Voice message');
    }
    if (t == 'file' || t == 'document' || t == 'pdf') {
      return const _Preview(
        icon: Icons.insert_drive_file_outlined,
        label: 'Document',
      );
    }
    final txt = (last ?? '').trim();
    if (txt.isEmpty) {
      return const _Preview(label: '');
    }
    return _Preview(label: txt);
  }

  Widget _subtitle({
    required Map<String, dynamic>? typingState,
    required String? last,
    required String? lastType,
  }) {
    if (typingState != null) {
      return _TypingPreview(
        isTyping: typingState['isTyping'] == true,
        isRecording: typingState['isRecording'] == true,
      );
    }
    return _SubtitlePreview(preview: _previewLabel(last: last, lastType: lastType));
  }
}

Map<String, dynamic>? getTypingState(
  Map<String, dynamic>? typingMap,
  String myUid,
) {
  if (typingMap == null || typingMap.isEmpty) return null;

  Map<String, dynamic>? recordingCandidate;
  final now = DateTime.now();
  const staleAfter = Duration(seconds: 5);

  for (final entry in typingMap.entries) {
    final uid = entry.key;
    if (uid == myUid) continue;

    final raw = entry.value;
    if (raw is! Map) continue;
    final data = Map<String, dynamic>.from(raw as Map);

    final active = (data['active'] as bool?) ?? false;
    final type = ((data['type'] as String?) ?? '').trim().toLowerCase();
    final isTyping =
        (data['isTyping'] as bool?) ?? (active && type != 'voice');
    final isRecording =
        (data['isRecording'] as bool?) ?? (active && type == 'voice');

    final tsRaw = data['updatedAt'] ?? data['timestamp'];
    DateTime? ts;
    if (tsRaw is Timestamp) ts = tsRaw.toDate();
    if (tsRaw is DateTime) ts = tsRaw;
    if (ts != null && now.difference(ts) > staleAfter) {
      continue;
    }

    if (isTyping) {
      return {
        'uid': uid,
        'isTyping': true,
        'isRecording': false,
      };
    }

    if (isRecording && recordingCandidate == null) {
      recordingCandidate = {
        'uid': uid,
        'isTyping': false,
        'isRecording': true,
      };
    }
  }

  return recordingCandidate;
}

class _Preview {
  final IconData? icon;
  final String label;
  const _Preview({this.icon, required this.label});
}

class _ChatTile extends StatelessWidget {
  final String title;
  final Widget subtitle;
  final Widget leading;
  final Widget trailing;
  final VoidCallback onTap;

  const _ChatTile({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    if (!isLight) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.highlight.withValues(alpha: 0.04),
          highlightColor: const Color(0xFF101010),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.highlight,
                          ),
                        ),
                        const SizedBox(height: 4),
                        subtitle,
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  trailing,
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.highlight.withValues(alpha: 0.04),
        highlightColor: Colors.transparent,
        child: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    leading,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onBackground,
                            ),
                          ),
                          const SizedBox(height: 4),
                          subtitle,
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    trailing,
                  ],
                ),
              ),
            ),
            Divider(
              height: 0.5,
              thickness: 0.5,
              color: Colors.black.withOpacity(0.05),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubtitlePreview extends StatelessWidget {
  final _Preview preview;
  const _SubtitlePreview({required this.preview});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final darkColor = AppColors.iconMuted;
    final color = Theme.of(context).colorScheme.onBackground.withOpacity(0.6);
    if (preview.icon == null) {
      return Text(
        preview.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: isLight ? color : darkColor),
      );
    }
    return Row(
      children: [
        Icon(preview.icon, size: 14, color: isLight ? color : darkColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            preview.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: isLight ? color : darkColor),
          ),
        ),
      ],
    );
  }
}

class _TypingPreview extends StatelessWidget {
  final bool isTyping;
  final bool isRecording;

  const _TypingPreview({required this.isTyping, required this.isRecording});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.blueAccent : Colors.blue;
    final showTyping = isTyping;

    return Row(
      children: [
        if (showTyping)
          _TypingDots(color: color)
        else if (isRecording)
          Icon(Icons.mic, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            showTyping ? 'typing...' : 'recording...',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _TypingDots extends StatefulWidget {
  final Color color;

  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final t = _controller.value;
        final op1 = (t < 0.33) ? 1.0 : 0.3;
        final op2 = (t >= 0.33 && t < 0.66) ? 1.0 : 0.3;
        final op3 = (t >= 0.66) ? 1.0 : 0.3;

        return Row(
          children: [
            _dot(op1),
            const SizedBox(width: 2),
            _dot(op2),
            const SizedBox(width: 2),
            _dot(op3),
          ],
        );
      },
    );
  }

  Widget _dot(double opacity) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

class _TrailingMeta extends StatelessWidget {
  final DateTime? time;
  final int unreadCount;
  const _TrailingMeta({required this.time, required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (time != null)
          Text(
            _formatTime(time!),
            style: TextStyle(
              fontSize: 11,
              color: isLight
                  ? theme.colorScheme.onBackground.withOpacity(0.5)
                  : const Color(0xFF7A7A7A),
              fontWeight: FontWeight.w500,
            ),
          )
        else
          const SizedBox.shrink(),
        if (time != null && unreadCount > 0) const SizedBox(height: 6),
        if (unreadCount > 0)
          Container(
            constraints: const BoxConstraints(minWidth: 20),
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isLight ? theme.colorScheme.primary : AppColors.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              unreadCount > 99 ? '99+' : unreadCount.toString(),
              style: TextStyle(
                fontSize: 11,
                color: isLight ? Colors.white : AppColors.highlight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    if (now.difference(date).inDays == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _AvatarWithDot extends StatelessWidget {
  final Widget avatar;
  final bool showDot;
  const _AvatarWithDot({required this.avatar, required this.showDot});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        if (showDot)
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _HomeHeader extends StatelessWidget {
  final VoidCallback onCamera;
  final void Function(String) onMenuSelected;
  const _HomeHeader({required this.onCamera, required this.onMenuSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Row(
      children: [
        Expanded(
          child: Text(
            'ModChat',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: isLight
                  ? theme.colorScheme.onBackground
                  : AppColors.highlight,
              letterSpacing: 0.3,
            ),
          ),
        ),
        _HeaderIcon(icon: Icons.camera_alt_outlined, onTap: onCamera),
        const SizedBox(width: 12),
        GlassDropdown(
          tooltip: 'Menu',
          items: const [
            GlassDropdownItem(
              value: 'new_group',
              label: 'New group',
              icon: Icons.group_add,
            ),
            GlassDropdownItem(
              value: 'new_community',
              label: 'New community',
              icon: Icons.diversity_3,
            ),
            GlassDropdownItem(
              value: 'broadcast_lists',
              label: 'Broadcast lists',
              icon: Icons.broadcast_on_personal_outlined,
            ),
            GlassDropdownItem(
              value: 'starred',
              label: 'Starred messages',
              icon: Icons.star,
            ),
            GlassDropdownItem(
              value: 'settings',
              label: 'Settings',
              icon: Icons.settings,
            ),
          ],
          onSelected: onMenuSelected,
          child: Icon(
            Icons.more_vert,
            color: isLight
                ? theme.colorScheme.onBackground
                : AppColors.iconMuted,
            size: 20,
          ),
        ),
      ],
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return InkResponse(
      onTap: onTap,
      radius: 22,
      splashColor: AppColors.highlight.withValues(alpha: 0.06),
      highlightColor: AppColors.highlight.withValues(alpha: 0.04),
      child: Icon(
        icon,
        color: isLight ? theme.colorScheme.onBackground : AppColors.iconMuted,
        size: 20,
      ),
    );
  }
}

class _SmartSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onChanged;
  const _SmartSearchBar({
    required this.controller,
    required this.focusNode,
    this.onChanged,
  });

  @override
  State<_SmartSearchBar> createState() => _SmartSearchBarState();
}

class _SmartSearchBarState extends State<_SmartSearchBar> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    if (!isLight) {
      final focused = widget.focusNode.hasFocus;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: focused
                ? AppColors.outlineStrong
                : const Color(0xFF1A1A1A),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Icon(Icons.search, size: 18, color: Color(0xFF8A8A8A)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                onChanged: widget.onChanged,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.highlight,
                  height: 1.2,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  hintText: 'Search conversations',
                  hintStyle: TextStyle(color: Color(0xFF7A7A7A), fontSize: 14),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final focused = widget.focusNode.hasFocus;
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: focused
              ? theme.colorScheme.primary.withOpacity(0.3)
              : Colors.black.withOpacity(0.05),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: 18,
            color: theme.colorScheme.onSurface.withOpacity(0.55),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              onChanged: widget.onChanged,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: theme.colorScheme.onSurface,
                height: 1.2,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: 'Search chats...',
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                  fontSize: 14,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  final VoidCallback onNewChat;
  final VoidCallback onNewGroup;
  final VoidCallback onCamera;
  final VoidCallback onSaved;
  const _QuickActionsRow({
    required this.onNewChat,
    required this.onNewGroup,
    required this.onCamera,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    if (!isLight) {
      return SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          children: [
            _DarkActionCapsule(
              icon: Icons.chat_bubble_outline,
              label: 'New Chat',
              onTap: onNewChat,
            ),
            const SizedBox(width: 8),
            _DarkActionCapsule(
              icon: Icons.group_add_outlined,
              label: 'New Group',
              onTap: onNewGroup,
            ),
            const SizedBox(width: 8),
            _DarkActionCapsule(
              icon: Icons.camera_alt_outlined,
              label: 'Camera',
              onTap: onCamera,
            ),
            const SizedBox(width: 8),
            _DarkActionCapsule(
              icon: Icons.bookmark_border,
              label: 'Saved',
              onTap: onSaved,
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ActionCapsule(
          icon: Icons.chat_bubble_outline,
          label: 'New Chat',
          onTap: onNewChat,
        ),
        _ActionCapsule(
          icon: Icons.group_add_outlined,
          label: 'New Group',
          onTap: onNewGroup,
        ),
        _ActionCapsule(
          icon: Icons.camera_alt_outlined,
          label: 'Camera',
          onTap: onCamera,
        ),
        _ActionCapsule(
          icon: Icons.bookmark_border,
          label: 'Saved',
          onTap: onSaved,
        ),
      ],
    );
  }
}

class _DarkActionCapsule extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DarkActionCapsule({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: AppColors.highlight.withValues(alpha: 0.04),
        highlightColor: AppColors.highlight.withValues(alpha: 0.03),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppColors.highlight),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.highlight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCapsule extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionCapsule({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ActionCapsule> createState() => _ActionCapsuleState();
}

class _ActionCapsuleState extends State<_ActionCapsule> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: 74,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.dividerColor.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  widget.icon,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onBackground.withOpacity(0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinnedChatsRow extends ConsumerWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> pinned;
  final String query;
  const _PinnedChatsRow({required this.pinned, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 74,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          final d = pinned[index];
          final data = d.data();
          final type = (data['type'] as String?) ?? 'dm';
          final groupName = (data['name'] as String?)?.trim();
          final members = List<String>.from(data['members'] as List);
          final me = FirebaseAuth.instance.currentUser!.uid;
          final peerId = members.firstWhere((m) => m != me, orElse: () => me);

          if (query.isNotEmpty) {
            final last = (data['lastMessage'] as String?) ?? '';
            final title = type == 'group'
                ? (groupName?.isNotEmpty == true ? groupName! : 'Group')
                : peerId;
            final matched =
                title.toLowerCase().contains(query) ||
                last.toLowerCase().contains(query);
            if (!matched) return const SizedBox.shrink();
          }

          if (type == 'group') {
            final title = (groupName?.isNotEmpty == true)
                ? groupName!
                : 'Group';
            return _PinnedChip(
              title: title,
              avatar: const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFF1A1A1A),
                child: Icon(Icons.group, size: 18, color: Colors.white),
              ),
              onTap: () => Navigator.pushNamed(
                context,
                GroupChatDetailScreen.routeName,
                arguments: {'chatId': d.id},
              ),
            );
          }

          final user = ref.watch(userDocProvider(peerId));
          return user.when(
            data: (u) {
              final title = (u?.name ?? '').trim().isNotEmpty
                  ? u!.name
                  : peerId;
              return _PinnedChip(
                title: title,
                avatar: _ResolvedAvatar(url: u?.profileImageUrl, radius: 18),
                onTap: () => Navigator.pushNamed(
                  context,
                  ChatDetailScreen.routeName,
                  arguments: {'chatId': d.id, 'peerId': peerId},
                ),
              );
            },
            loading: () => const _PinnedChip(
              title: '…',
              avatar: CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFF1A1A1A),
              ),
            ),
            error: (_, __) => _PinnedChip(
              title: peerId,
              avatar: const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFF1A1A1A),
                child: Icon(Icons.person, size: 18, color: Colors.white),
              ),
              onTap: () => Navigator.pushNamed(
                context,
                ChatDetailScreen.routeName,
                arguments: {'chatId': d.id, 'peerId': peerId},
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemCount: pinned.length,
      ),
    );
  }
}

class _PinnedChip extends StatelessWidget {
  final Widget avatar;
  final String title;
  final VoidCallback? onTap;
  const _PinnedChip({required this.avatar, required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              avatar,
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isLight
                      ? theme.colorScheme.onBackground.withOpacity(0.6)
                      : const Color(0xFF7A7A7A),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatListSkeleton extends StatelessWidget {
  const _ChatListSkeleton();

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return ListView.separated(
      padding: const EdgeInsets.only(top: 6, bottom: 88),
      itemCount: 10,
      separatorBuilder: (_, __) => Divider(
        height: 0.5,
        thickness: 0.5,
        color: isLight ? Colors.grey.shade300 : AppColors.outline,
      ),
      itemBuilder: (context, index) {
        return SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.iconContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _SkeletonBar(width: 160, height: 12),
                      SizedBox(height: 8),
                      _SkeletonBar(width: 220, height: 10),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: const [
                    _SkeletonBar(width: 44, height: 10),
                    SizedBox(height: 10),
                    _SkeletonBadge(),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  final double width;
  final double height;
  const _SkeletonBar({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isLight ? Colors.grey.shade200 : AppColors.iconContainer,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _SkeletonBadge extends StatelessWidget {
  const _SkeletonBadge();

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: isLight ? Colors.grey.shade300 : AppColors.iconContainer,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}

class _EmptyChatsState extends StatelessWidget {
  const _EmptyChatsState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 54,
              color: AppColors.iconMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'No conversations yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isLight
                    ? theme.colorScheme.onBackground.withOpacity(0.6)
                    : AppColors.highlight,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start a new chat to begin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSheet extends ConsumerStatefulWidget {
  const _ProfileSheet();
  @override
  ConsumerState<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends ConsumerState<_ProfileSheet> {
  final _name = TextEditingController();
  final _about = TextEditingController();
  Uint8List? _avatar;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    _name.text = u?.displayName ?? '';
  }

  Future<void> _pickAvatar() async {
    final res = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.image,
    );
    if (res != null && res.files.isNotEmpty) {
      setState(() => _avatar = res.files.first.bytes);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final u = FirebaseAuth.instance.currentUser!;
      String? url;
      String? bucket;
      String? path;
      if (_avatar != null) {
        path = 'avatars/${u.uid}_${DateTime.now().millisecondsSinceEpoch}.png';
        bucket = StorageService().profileBucket;
        await StorageService().uploadBytes(
          data: _avatar!,
          bucket: bucket,
          path: path,
          contentType: 'image/png',
        );
        // Store only storage path (no scheme)
        url = path;
      }
      final fs = FirestoreService();
      await fs.users.doc(u.uid).set({
        'userId': u.uid,
        'name': _name.text.trim().isNotEmpty
            ? _name.text.trim()
            : (u.displayName ?? ''),
        'email': u.email,
        'about': _about.text.trim(),
        if (url != null) 'profileImageUrl': url,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    final userDoc = ref.watch(userDocProvider(u!.uid));
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outline, width: 1),
      ),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom) +
          const EdgeInsets.all(16),
      child: SafeArea(
        child: userDoc.when(
          data: (user) {
            _about.text = user?.about ?? '';
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outlineStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _pickAvatar,
                      child: _ResolvedAvatar(
                        url: user?.profileImageUrl,
                        radius: 40,
                        emptyIcon: Icons.camera_alt,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.input,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.outline, width: 1),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      labelText: 'Name',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.input,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.outline, width: 1),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _about,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      labelText: 'About',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GlassButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Error: $e'),
          ),
        ),
      ),
    );
  }
}
