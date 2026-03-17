import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/message_model.dart';
import '../../providers/chat_providers.dart';
import '../../providers/user_providers.dart';

class ForwardSelectScreen extends ConsumerStatefulWidget {
  final MessageModel source;
  const ForwardSelectScreen({super.key, required this.source});

  @override
  ConsumerState<ForwardSelectScreen> createState() =>
      _ForwardSelectScreenState();
}

class _ForwardSelectScreenState extends ConsumerState<ForwardSelectScreen> {
  final _search = TextEditingController();
  final Set<String> _selected = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatListProvider);
    final q = _search.text.trim().toLowerCase();

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        title: const Text('Forward to', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final service = ref.read(chatServiceProvider);
                    final ids = _selected.toList();
                    Navigator.pop(context);
                    try {
                      for (final id in ids) {
                        await service.forwardExistingMessageToChat(
                          source: widget.source,
                          targetChatId: id,
                        );
                      }
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Message forwarded')),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Forward failed: $e')),
                      );
                    }
                  },
            child: Text(
              'Send',
              style: TextStyle(
                color: _selected.isEmpty
                    ? const Color(0xFF666666)
                    : const Color(0xFFC74B6C),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search chats',
                hintStyle: const TextStyle(color: Color(0xFF8A8A8A)),
                filled: true,
                fillColor: const Color(0xFF0F0F0F),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF8A8A8A),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
              ),
            ),
          ),
          Expanded(
            child: chats.when(
              data: (docs) {
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No chats found',
                      style: TextStyle(color: Color(0xFF8A8A8A)),
                    ),
                  );
                }

                final me = FirebaseAuth.instance.currentUser!.uid;
                final filtered = docs.where((d) {
                  final data = d.data();
                  final type = (data['type'] as String?) ?? 'dm';
                  final title = type == 'group'
                      ? ((data['name'] as String?) ?? 'Group')
                      : _dmTitle(data, me);
                  if (q.isEmpty) return true;
                  final last = (data['lastMessage'] as String?) ?? '';
                  return title.toLowerCase().contains(q) ||
                      last.toLowerCase().contains(q);
                }).toList();

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final d = filtered[i];
                    final data = d.data();
                    final type = (data['type'] as String?) ?? 'dm';
                    final title = type == 'group'
                        ? ((data['name'] as String?) ?? 'Group')
                        : _dmTitle(data, me);
                    final last = (data['lastMessage'] as String?) ?? '';
                    final checked = _selected.contains(d.id);

                    final peerId = type == 'group' ? null : title;
                    final peerName = peerId == null
                        ? null
                        : ref
                              .watch(userDocProvider(peerId))
                              .maybeWhen(
                                data: (u) => (u?.name ?? '').trim(),
                                orElse: () => '',
                              );
                    final displayTitle = type == 'group'
                        ? title
                        : ((peerName != null && peerName.isNotEmpty)
                              ? peerName
                              : title);

                    return ListTile(
                      onTap: () {
                        setState(() {
                          if (checked) {
                            _selected.remove(d.id);
                          } else {
                            _selected.add(d.id);
                          }
                        });
                      },
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF1A1A1A),
                        child: Icon(
                          type == 'group' ? Icons.group : Icons.person,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF8A8A8A)),
                      ),
                      trailing: Checkbox(
                        value: checked,
                        onChanged: (_) {
                          setState(() {
                            if (checked) {
                              _selected.remove(d.id);
                            } else {
                              _selected.add(d.id);
                            }
                          });
                        },
                        activeColor: const Color(0xFFC74B6C),
                        checkColor: Colors.black,
                        side: const BorderSide(color: Color(0xFF444444)),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Error: $e',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _dmTitle(Map<String, dynamic> data, String me) {
    final members = List<String>.from((data['members'] as List?) ?? const []);
    final peer = members.firstWhere((m) => m != me, orElse: () => '');
    return peer.isEmpty ? 'Chat' : peer;
  }
}
