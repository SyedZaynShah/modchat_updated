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
  late final PageController _pageController;
  int _currentIndex = 0;
  final List<String> _titles = const [
    'Chats',
    'Updates',
    'Communities',
    'Calls',
  ];

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
    _pageController.dispose();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User not found')));
        return;
      }
      final peerId = (qs.docs.first.data())['userId'] as String;
      if (peerId == me) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('That is you')));
        return;
      }
      final chatId = await ref
          .read(chatServiceProvider)
          .startOrOpenChat(peerId);
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        ChatDetailScreen.routeName,
        arguments: {'chatId': chatId, 'peerId': peerId},
      );
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
        title: Text(
          _titles[_currentIndex],
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _openProfile,
            icon: const Icon(Icons.person_outline),
          ),
          IconButton(
            onPressed: () => ref.read(firebaseAuthServiceProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (i) => setState(() => _currentIndex = i),
        children: [
          // Chats
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          hintText: 'Start chat by email',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GlassButton(
                      onPressed: _starting ? null : _startChat,
                      child: _starting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chat_bubble_outline),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: chatList.when(
                  data: (docs) {
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text(
                          'No chats yet',
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (context, index) => Center(
                        child: FractionallySizedBox(
                          widthFactor: 0.68,
                          child: Container(
                            height: 0.5,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.sinopia.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ),
                      itemBuilder: (context, index) {
                        final d = docs[index];
                        final data = d.data();
                        final members = List<String>.from(
                          data['members'] as List,
                        );
                        final me = FirebaseAuth.instance.currentUser!.uid;
                        final peerId = members.firstWhere(
                          (m) => m != me,
                          orElse: () => me,
                        );
                        final last = data['lastMessage'] as String?;
                        final ts = (data['lastTimestamp'] as Timestamp?)
                            ?.toDate();
                        return _ChatListTile(
                          chatId: d.id,
                          peerId: peerId,
                          last: last,
                          time: ts,
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
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
      bottomNavigationBar: _buildBottomNav(),
    );
  }
}

extension on _HomeScreenState {
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        border: const Border(
          top: BorderSide(color: AppColors.sinopia, width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _navItem(icon: Icons.chat_bubble_rounded, label: 'Chats', index: 0),
            _navItem(icon: Icons.update, label: 'Updates', index: 1),
            _navItem(
              icon: Icons.groups_rounded,
              label: 'Communities',
              index: 2,
            ),
            _navItem(icon: Icons.call_rounded, label: 'Calls', index: 3),
          ],
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final selected = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _currentIndex = index);
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.navy, size: 22),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 2,
                width: 24,
                decoration: BoxDecoration(
                  color: selected ? AppColors.sinopia : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder({required IconData icon, required String text}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppColors.navy.withOpacity(0.6)),
          const SizedBox(height: 12),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.navy,
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
  final String? last;
  final DateTime? time;
  const _ChatListTile({
    required this.chatId,
    required this.peerId,
    this.last,
    this.time,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userDocProvider(peerId));
    return user.when(
      data: (u) {
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
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              subtitle: Text(
                last ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: time != null
                  ? Text(
                      _formatTime(time!),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    )
                  : null,
              leading: CircleAvatar(
                backgroundColor: AppColors.sinopia.withValues(alpha: 0.25),
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
      decoration: AppTheme.glassDecoration(radius: 24, glow: true),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _pickAvatar,
                      child: CircleAvatar(
                        radius: 36,
                        backgroundImage:
                            (user?.profileImageUrl?.isNotEmpty == true)
                            ? NetworkImage(user!.profileImageUrl!)
                            : null,
                        child: (user?.profileImageUrl?.isNotEmpty == true)
                            ? null
                            : const Icon(
                                Icons.camera_alt,
                                color: Colors.white70,
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _about,
                  decoration: const InputDecoration(labelText: 'About'),
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
