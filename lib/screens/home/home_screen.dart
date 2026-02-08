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
import '../../services/supabase_service.dart';
import '../../theme/theme.dart';
import '../../widgets/glass_button.dart';
import '../../widgets/spotlight_nav_bar.dart';
import '../chat/chat_detail_screen.dart';
import 'new_chat_screen.dart';
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
    this.radius = 20,
    this.emptyIcon = Icons.person,
  });

  @override
  Widget build(BuildContext context) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.sinopia.withValues(alpha: 0.25),
        child: Icon(emptyIcon, color: AppColors.white.withOpacity(0.7)),
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
        return CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.sinopia.withValues(alpha: 0.25),
          foregroundImage: (resolved != null && resolved.isNotEmpty)
              ? NetworkImage(resolved)
              : null,
          onForegroundImageError: (_, __) {},
          child: (resolved != null && resolved.isNotEmpty)
              ? null
              : Icon(emptyIcon, color: AppColors.white.withOpacity(0.7)),
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
    _chatSearchController.dispose();
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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        centerTitle: false,
        title: Text(
          _currentIndex == 0 ? 'ModChat' : _titles[_currentIndex],
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.highlight,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.camera_alt_outlined,
              color: AppColors.iconMuted,
            ),
            onPressed: _openCamera,
            tooltip: 'Camera',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.iconMuted),
            onSelected: _onMenuSelected,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'new_group', child: Text('New group')),
              PopupMenuItem(
                value: 'new_community',
                child: Text('New community'),
              ),
              PopupMenuItem(
                value: 'broadcast_lists',
                child: Text('Broadcast lists'),
              ),
              PopupMenuItem(value: 'starred', child: Text('Starred messages')),
              PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
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
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.cardTop, AppColors.cardBottom],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.outline.withOpacity(0.8),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  child: TextField(
                    controller: _chatSearchController,
                    onChanged: (_) => setState(() {}),
                    textAlignVertical: TextAlignVertical.center,
                    style: const TextStyle(color: AppColors.highlight),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.iconMuted,
                        size: 20,
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      filled: true,
                      fillColor: Colors.transparent,
                      hintText: 'Search chats',
                      hintStyle: const TextStyle(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: chatList.when(
                  data: (docs) {
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text(
                          'No chats yet',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      );
                    }
                    final q = _chatSearchController.text.trim().toLowerCase();
                    return ListView.builder(
                      itemCount: docs.length,
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
                          query: q,
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text(
                      'Error: $e',
                      style: const TextStyle(color: AppColors.textSecondary),
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.highlight,
        child: const Icon(Icons.add),
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
  final String? last;
  final DateTime? time;
  final String? query;
  const _ChatListTile({
    required this.chatId,
    required this.peerId,
    this.last,
    this.time,
    this.query,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userDocProvider(peerId));
    return user.when(
      data: (u) {
        final q = (query ?? '').trim().toLowerCase();
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              title: Text(
                u?.name.isNotEmpty == true ? u!.name : peerId,
                style: const TextStyle(
                  color: AppColors.highlight,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                last ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              trailing: time != null
                  ? Text(
                      _formatTime(time!),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
              leading: _ResolvedAvatar(url: u?.profileImageUrl),
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
                      child: _ResolvedAvatar(
                        url: user?.profileImageUrl,
                        radius: 36,
                        emptyIcon: Icons.camera_alt,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.cardTop, AppColors.cardBottom],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.outline.withOpacity(0.9),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
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
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.cardTop, AppColors.cardBottom],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.outline.withOpacity(0.9),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
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
