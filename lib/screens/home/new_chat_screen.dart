import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/chat_providers.dart';
import '../../providers/user_providers.dart';
import '../../theme/theme.dart';
import '../chat/chat_detail_screen.dart';
import '../chat/group_chat_detail_screen.dart';
import '../group/create_group_screen.dart';
import 'new_contact_screen.dart';

class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      appBar: AppBar(
        backgroundColor: isLight
            ? theme.colorScheme.background
            : null,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: isLight
                    ? theme.colorScheme.onBackground
                    : AppColors.navy,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 4),
            Text(
              'New Chat',
              style: TextStyle(
                color: isLight
                    ? theme.colorScheme.onBackground
                    : AppColors.navy,
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _ToSearchBar(
              controller: _search,
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: chatList.when(
              data: (docs) {
                final me = FirebaseAuth.instance.currentUser!.uid;
                return ListView(
                  children: [
                    // Options at the top
                    _OptionRow(
                      icon: Icons.person_add_alt,
                      label: 'New contact',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NewContactScreen(),
                          ),
                        );
                      },
                    ),
                    _OptionRow(
                      icon: Icons.groups_2_rounded,
                      label: 'New community',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('New community coming soon'),
                          ),
                        );
                      },
                    ),
                    _OptionRow(
                      icon: Icons.group,
                      label: 'New group',
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          CreateGroupScreen.routeName,
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FractionallySizedBox(
                        widthFactor: 0.68,
                        child: Divider(
                          height: 12,
                          thickness: 0.5,
                          color: Colors.black.withOpacity(0.05),
                        ),
                      ),
                    ),
                    // Existing chats list below options
                    ...docs.map((d) {
                      final data = d.data();
                      final type = (data['type'] as String?) ?? 'dm';
                      final members = List<String>.from(
                        data['members'] as List,
                      );
                      final peerId = members.firstWhere(
                        (m) => m != me,
                        orElse: () => me,
                      );
                      final last = data['lastMessage'] as String?;
                      final groupName = data['name'] as String?;
                      return _ChatRow(
                        peerId: peerId,
                        chatId: d.id,
                        last: last,
                        query: _search.text.trim(),
                        chatType: type,
                        groupName: groupName,
                      );
                    }),
                    const SizedBox(height: 24),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Error: $e',
                  style: TextStyle(
                    color: isLight
                        ? theme.colorScheme.onBackground
                        : Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  const _ToSearchBar({required this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: isLight ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          Text(
            'To:',
            style: TextStyle(
              color: isLight
                  ? theme.colorScheme.onSurface
                  : Colors.black,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                color: isLight
                    ? theme.colorScheme.onSurface
                    : Colors.black,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                filled: true,
                fillColor: isLight
                    ? theme.colorScheme.surface
                    : Colors.transparent,
                hintText: 'Search name or email',
                hintStyle: TextStyle(
                  color: isLight
                      ? theme.colorScheme.onSurface.withOpacity(0.5)
                      : Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatRow extends ConsumerWidget {
  final String chatId;
  final String peerId;
  final String? last;
  final String query;
  final String chatType;
  final String? groupName;
  const _ChatRow({
    required this.chatId,
    required this.peerId,
    required this.last,
    required this.query,
    this.chatType = 'dm',
    this.groupName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    if (chatType == 'group') {
      final title = (groupName ?? '').trim().isNotEmpty ? groupName! : 'Group';
      final q = query.trim().toLowerCase();
      if (q.isNotEmpty) {
        final matched =
            title.toLowerCase().contains(q) ||
            (last ?? '').toLowerCase().contains(q);
        if (!matched) return const SizedBox.shrink();
      }

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pushNamed(
            context,
            GroupChatDetailScreen.routeName,
            arguments: {'chatId': chatId},
          ),
          splashColor: AppColors.navy.withOpacity(0.08),
          highlightColor: AppColors.navy.withOpacity(0.06),
          child: ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -2),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 2,
            ),
            title: Text(
              title,
              style: TextStyle(
                color: isLight
                    ? theme.colorScheme.onBackground
                    : AppColors.navy,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
            subtitle: Text(
              last ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isLight
                    ? theme.colorScheme.onBackground.withOpacity(0.6)
                    : null,
              ),
            ),
            leading: CircleAvatar(
              backgroundColor: AppColors.sinopia.withOpacity(0.25),
              child: Icon(
                Icons.group,
                color: isLight
                    ? theme.colorScheme.onBackground
                    : AppColors.navy,
              ),
            ),
          ),
        ),
      );
    }

    final user = ref.watch(userDocProvider(peerId));
    return user.when(
      data: (u) {
        final q = query.trim().toLowerCase();
        if (q.isNotEmpty) {
          final name = (u?.name ?? '').toLowerCase();
          final email = (u?.email ?? '').toLowerCase();
          final lastMsg = (last ?? '').toLowerCase();
          final id = peerId.toLowerCase();
          final match =
              name.contains(q) ||
              email.contains(q) ||
              lastMsg.contains(q) ||
              id.contains(q);
          if (!match) return const SizedBox.shrink();
        }
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.pushNamed(
              context,
              ChatDetailScreen.routeName,
              arguments: {'chatId': chatId, 'peerId': peerId},
            ),
            splashColor: AppColors.navy.withOpacity(0.08),
            highlightColor: AppColors.navy.withOpacity(0.06),
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(vertical: -2),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              title: Text(
                u?.name.isNotEmpty == true ? u!.name : peerId,
                style: TextStyle(
                  color: isLight
                      ? theme.colorScheme.onBackground
                      : AppColors.navy,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              subtitle: Text(
                last ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isLight
                      ? theme.colorScheme.onBackground.withOpacity(0.6)
                      : null,
                ),
              ),
              leading: CircleAvatar(
                backgroundColor: AppColors.sinopia.withOpacity(0.25),
                backgroundImage: (u?.profileImageUrl?.isNotEmpty == true)
                    ? NetworkImage(u!.profileImageUrl!)
                    : null,
                onBackgroundImageError: (u?.profileImageUrl?.isNotEmpty == true)
                    ? (_, __) {}
                    : null,
                child: (u?.profileImageUrl?.isNotEmpty == true)
                    ? null
                    : Icon(
                        Icons.person,
                        color: isLight
                            ? theme.colorScheme.onSurface.withOpacity(0.7)
                            : Colors.white70,
                      ),
              ),
            ),
          ),
        );
      },
      loading: () => const ListTile(title: Text('...'), subtitle: Text('...')),
      error: (e, _) =>
          ListTile(title: Text(peerId), subtitle: Text(last ?? '')),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _OptionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.navy.withOpacity(0.08),
        highlightColor: AppColors.navy.withOpacity(0.06),
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -2),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 2,
          ),
          leading: CircleAvatar(
            backgroundColor: AppColors.sinopia.withOpacity(0.25),
            child: Icon(
              icon,
              color: isLight
                  ? theme.colorScheme.onBackground
                  : AppColors.navy,
            ),
          ),
          title: Text(
            label,
            style: TextStyle(
              color: isLight
                  ? theme.colorScheme.onBackground
                  : AppColors.navy,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }
}
