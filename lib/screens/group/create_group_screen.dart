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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Scaffold(
      backgroundColor: isLight
          ? theme.colorScheme.background
          : AppColors.background,
      appBar: AppBar(
        backgroundColor: isLight ? theme.colorScheme.background : null,
        elevation: 0,
        iconTheme: IconThemeData(
          color: isLight ? theme.colorScheme.onBackground : null,
        ),
        title: Text(
          'New group',
          style: TextStyle(
            color: isLight ? theme.colorScheme.onBackground : null,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _creating ? null : _create,
            style: TextButton.styleFrom(
              foregroundColor: isLight
                  ? theme.colorScheme.primary
                  : null,
            ),
            child: _creating
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                      backgroundColor: theme.colorScheme.surface,
                    ),
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
                  style: TextStyle(
                    color: isLight
                        ? theme.colorScheme.onSurface
                        : null,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Group name',
                    filled: isLight,
                    fillColor: theme.colorScheme.surface,
                    labelStyle: TextStyle(
                      color: isLight
                          ? theme.colorScheme.onSurface.withOpacity(0.7)
                          : null,
                    ),
                    hintStyle: TextStyle(
                      color: isLight
                          ? theme.colorScheme.onSurface.withOpacity(0.5)
                          : null,
                    ),
                    prefixIconColor: isLight
                        ? theme.colorScheme.onSurface.withOpacity(0.7)
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _desc,
                  style: TextStyle(
                    color: isLight
                        ? theme.colorScheme.onSurface
                        : null,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    filled: isLight,
                    fillColor: theme.colorScheme.surface,
                    labelStyle: TextStyle(
                      color: isLight
                          ? theme.colorScheme.onSurface.withOpacity(0.7)
                          : null,
                    ),
                    hintStyle: TextStyle(
                      color: isLight
                          ? theme.colorScheme.onSurface.withOpacity(0.5)
                          : null,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: Colors.black.withOpacity(0.05),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: fs.users.orderBy('name').snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                      backgroundColor: theme.colorScheme.surface,
                    ),
                  );
                }
                final docs = snap.data!.docs;
                final filtered = docs.where((d) {
                  final data = d.data();
                  final uid = (data['userId'] as String?) ?? d.id;
                  return me == null ? true : uid != me;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      'No users found',
                      style: TextStyle(
                        color: isLight
                            ? theme.colorScheme.onBackground.withOpacity(0.6)
                            : null,
                      ),
                    ),
                  );
                }

                return Container(
                  margin: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isLight ? theme.colorScheme.surface : null,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.black.withOpacity(0.05),
                    ),
                  ),
                  child: ListView.builder(
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
                        activeColor: theme.colorScheme.primary,
                        checkColor: Colors.white,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(uid);
                            } else {
                              _selected.remove(uid);
                            }
                          });
                        },
                        title: Text(
                          name,
                          style: TextStyle(
                            color: isLight
                                ? theme.colorScheme.onBackground
                                : null,
                          ),
                        ),
                        subtitle: email.isEmpty
                            ? null
                            : Text(
                                email,
                                style: TextStyle(
                                  color: isLight
                                      ? theme.colorScheme.onBackground
                                            .withOpacity(0.6)
                                      : null,
                                ),
                              ),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
