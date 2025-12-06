import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/chat_providers.dart';
import '../../providers/user_providers.dart';
import '../../theme/theme.dart';
import '../chat/chat_detail_screen.dart';
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        centerTitle: false,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.navy),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 4),
            const Text(
              'New Chat',
              style: TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('New group coming soon'),
                          ),
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FractionallySizedBox(
                        widthFactor: 0.68,
                        child: Container(
                          height: 0.75,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.sinopia.withOpacity(0.28),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                    // Existing chats list below options
                    ...docs.map((d) {
                      final data = d.data();
                      final members = List<String>.from(
                        data['members'] as List,
                      );
                      final peerId = members.firstWhere(
                        (m) => m != me,
                        orElse: () => me,
                      );
                      final last = data['lastMessage'] as String?;
                      return _ChatRow(
                        peerId: peerId,
                        chatId: d.id,
                        last: last,
                        query: _search.text.trim(),
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
                  style: const TextStyle(color: Colors.redAccent),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.navy, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Text(
            'To:',
            style: TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search name or email',
                hintStyle: TextStyle(color: Colors.black54),
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
  const _ChatRow({
    required this.chatId,
    required this.peerId,
    required this.last,
    required this.query,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
              subtitle: Text(
                last ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              leading: CircleAvatar(
                backgroundColor: AppColors.sinopia.withOpacity(0.25),
                backgroundImage: (u?.profileImageUrl?.isNotEmpty == true)
                    ? NetworkImage(u!.profileImageUrl!)
                    : null,
                child: (u?.profileImageUrl?.isNotEmpty == true)
                    ? null
                    : const Icon(Icons.person, color: Colors.white70),
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
            child: Icon(icon, color: AppColors.navy),
          ),
          title: Text(
            label,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }
}
