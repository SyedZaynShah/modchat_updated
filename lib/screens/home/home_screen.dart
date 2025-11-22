import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/user_providers.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../theme/theme.dart';
import '../../widgets/glass_button.dart';
import '../chat/chat_detail_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _aboutController = TextEditingController();
  bool _starting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  Future<void> _startChat() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _starting = true);
    try {
      final fs = ref.read(firestoreServiceProvider);
      final me = FirebaseAuth.instance.currentUser!.uid;
      final qs = await fs.users.where('email', isEqualTo: email).limit(1).get();
      if (qs.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not found')));
        return;
      }
      final peerId = (qs.docs.first.data())['userId'] as String;
      if (peerId == me) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That is you')));
        return;
      }
      final chatId = await ref.read(chatServiceProvider).startOrOpenChat(peerId);
      if (!mounted) return;
      Navigator.pushNamed(context, ChatDetailScreen.routeName, arguments: {'chatId': chatId, 'peerId': peerId});
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _openProfile() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ProfileSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatList = ref.watch(chatListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('ModChat'),
        actions: [
          IconButton(onPressed: _openProfile, icon: const Icon(Icons.person_outline)),
          IconButton(onPressed: () => ref.read(firebaseAuthServiceProvider).signOut(), icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(hintText: 'Start chat by email'),
                  ),
                ),
                const SizedBox(width: 8),
                GlassButton(
                  onPressed: _starting ? null : _startChat,
                  child: _starting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chat_bubble_outline),
                ),
              ],
            ),
          ),
          Expanded(
            child: chatList.when(
              data: (docs) {
                if (docs.isEmpty) {
                  return const Center(child: Text('No chats yet', style: TextStyle(color: Colors.white70)));
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final d = docs[index];
                    final data = d.data();
                    final members = List<String>.from(data['members'] as List);
                    final me = FirebaseAuth.instance.currentUser!.uid;
                    final peerId = members.firstWhere((m) => m != me, orElse: () => me);
                    final last = data['lastMessage'] as String?;
                    final ts = (data['lastTimestamp'] as Timestamp?)?.toDate();
                    return _ChatListTile(chatId: d.id, peerId: peerId, last: last, time: ts);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.redAccent))),
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
  final String? last;
  final DateTime? time;
  const _ChatListTile({required this.chatId, required this.peerId, this.last, this.time});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userDocProvider(peerId));
    return user.when(
      data: (u) {
        return ListTile(
          onTap: () => Navigator.pushNamed(context, ChatDetailScreen.routeName, arguments: {'chatId': chatId, 'peerId': peerId}),
          title: Text(u?.name.isNotEmpty == true ? u!.name : peerId),
          subtitle: Text(last ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: time != null ? Text(_formatTime(time!), style: const TextStyle(color: Colors.white54, fontSize: 12)) : null,
          leading: CircleAvatar(
            backgroundColor: AppColors.sinopia.withValues(alpha: 0.25),
            backgroundImage: (u?.profilePicUrl?.isNotEmpty == true) ? NetworkImage(u!.profilePicUrl!) : null,
            child: (u?.profilePicUrl?.isNotEmpty == true) ? null : const Icon(Icons.person, color: Colors.white70),
          ),
        );
      },
      loading: () => const ListTile(title: Text('...'), subtitle: Text('...')),
      error: (e, _) => ListTile(title: Text(peerId), subtitle: Text(last ?? '')),
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
    final res = await FilePicker.platform.pickFiles(withData: true, type: FileType.image);
    if (res != null && res.files.isNotEmpty) {
      setState(() => _avatar = res.files.first.bytes);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final u = FirebaseAuth.instance.currentUser!;
      String? url;
      if (_avatar != null) {
        final path = 'avatars/${u.uid}_${DateTime.now().millisecondsSinceEpoch}.png';
        final uploaded = await StorageService().uploadBytes(
          data: _avatar!,
          bucket: StorageService().profileBucket,
          path: path,
          contentType: 'image/png',
        );
        url = uploaded.signedUrl;
      }
      final fs = FirestoreService();
      await fs.users.doc(u.uid).set({
        'userId': u.uid,
        'name': _name.text.trim().isNotEmpty ? _name.text.trim() : (u.displayName ?? ''),
        'email': u.email,
        'about': _about.text.trim(),
        if (url != null) 'profilePicUrl': url,
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
      decoration: AppTheme.glassDecoration(radius: 24, glow: true),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom) + const EdgeInsets.all(16),
      child: SafeArea(
        child: userDoc.when(
          data: (user) {
            _about.text = user?.about ?? '';
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _pickAvatar,
                      child: CircleAvatar(
                        radius: 36,
                        backgroundImage: (user?.profilePicUrl?.isNotEmpty == true)
                            ? NetworkImage(user!.profilePicUrl!)
                            : null,
                        child: (user?.profilePicUrl?.isNotEmpty == true)
                            ? null
                            : const Icon(Icons.camera_alt, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 8),
                TextField(controller: _about, decoration: const InputDecoration(labelText: 'About')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: GlassButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'))),
                ]),
                const SizedBox(height: 8),
              ],
            );
          },
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text('Error: $e')),
        ),
      ),
    );
  }
}
