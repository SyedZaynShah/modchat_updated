import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/chat_providers.dart';
import '../../services/firestore_service.dart';
import '../../theme/theme.dart';
import '../chat/group_chat_detail_screen.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  static const routeName = '/create-group';
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final Set<String> _selected = <String>{};
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;

    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter group name')));
      return;
    }

    final members = <String>{..._selected, me}.toList();
    if (members.length < 2) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select at least 1 member')));
      return;
    }

    setState(() => _creating = true);
    try {
      final chatId = await ref
          .read(chatServiceProvider)
          .createGroup(
            name: name,
            memberIds: members,
            description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
            photoUrl: null,
          );
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        GroupChatDetailScreen.routeName,
        arguments: {'chatId': chatId},
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Create failed: $e')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final fs = FirestoreService();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('New group'),
        actions: [
          TextButton(
            onPressed: _creating ? null : _create,
            child: _creating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Group name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _desc,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: fs.users.orderBy('name').snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                final filtered = docs.where((d) {
                  final data = d.data();
                  final uid = (data['userId'] as String?) ?? d.id;
                  return me == null ? true : uid != me;
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('No users found'));
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final d = filtered[i];
                    final data = d.data();
                    final uid = (data['userId'] as String?) ?? d.id;
                    final name = (data['name'] as String?) ?? uid;
                    final email = (data['email'] as String?) ?? '';
                    final selected = _selected.contains(uid);

                    return CheckboxListTile(
                      value: selected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(uid);
                          } else {
                            _selected.remove(uid);
                          }
                        });
                      },
                      title: Text(name),
                      subtitle: email.isEmpty ? null : Text(email),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
