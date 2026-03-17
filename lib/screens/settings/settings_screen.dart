import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../providers/user_providers.dart';
import '../../providers/auth_providers.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../services/supabase_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _bioCtrl = TextEditingController();
  bool _editingBio = false;
  bool _saving = false;

  String _themePref = 'dark';
  String _languagePref = 'English';
  String _bubbleSizePref = 'Medium';
  String _fontSizePref = 'Default';
  String _lastSeenPref = 'Everyone';
  bool _readReceipts = true;

  @override
  void dispose() {
    _bioCtrl.dispose();
    super.dispose();
  }

  String _initialsFrom(String nameOrId) {
    final parts = nameOrId
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'MC';
    final a = parts.first.isNotEmpty ? parts.first[0] : 'M';
    final b = parts.length > 1 && parts[1].isNotEmpty
        ? parts[1][0]
        : (parts.first.length > 1 ? parts.first[1] : 'C');
    return (a + b).toUpperCase();
  }

  Future<String?> _resolveAvatarUrl(String? raw) async {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return null;
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    if (v.startsWith('sb://')) {
      return SupabaseService.instance.resolveUrl(directUrl: v);
    }
    final bucket = StorageService().profileBucket;
    return SupabaseService.instance.getSignedUrl(bucket, v);
  }

  Future<void> _saveName(String uid, String name) async {
    final text = name.trim();
    if (text.isEmpty) return;
    try {
      await FirestoreService().users.doc(uid).set({
        'name': text,
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update name: $e')));
    }
  }

  Future<void> _openEditName({
    required String uid,
    required String initial,
  }) async {
    final ctrl = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Your name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _saveName(uid, ctrl.text);
    }
  }

  Future<void> _persistPrefs(String uid) async {
    try {
      await FirestoreService().users.doc(uid).set({
        'settings': {
          'theme': _themePref,
          'language': _languagePref,
          'bubbleSize': _bubbleSizePref,
          'fontSize': _fontSizePref,
          'lastSeen': _lastSeenPref,
          'readReceipts': _readReceipts,
        },
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _openSelectorSheet({
    required String title,
    required String selected,
    required List<String> options,
    required ValueChanged<String> onSelected,
  }) async {
    final val = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF101010),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              ...options.map((o) {
                final isOn = o == selected;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    o,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  trailing: isOn
                      ? const Icon(
                          Icons.check,
                          color: Color(0xFFC74B6C),
                          size: 20,
                        )
                      : null,
                  onTap: () => Navigator.pop(ctx, o),
                );
              }),
            ],
          ),
        ),
      ),
    );

    if (val != null) onSelected(val);
  }

  Future<void> _saveBio(String uid) async {
    final text = _bioCtrl.text.trim();
    setState(() => _saving = true);
    try {
      await FirestoreService().users.doc(uid).set({
        'about': text,
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _editingBio = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Bio updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update bio: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadAvatar(String uid) async {
    try {
      final picker = ImagePicker();
      final XFile? x = await picker.pickImage(source: ImageSource.camera);
      if (x == null) return;
      final data = await x.readAsBytes();
      final path =
          'avatars/${uid}_${DateTime.now().millisecondsSinceEpoch}.png';
      final bucket = StorageService().profileBucket;
      await StorageService().uploadBytes(
        data: Uint8List.fromList(data),
        bucket: bucket,
        path: path,
        contentType: 'image/png',
      );
      // Store only storage path to keep behavior consistent with existing UI
      await FirestoreService().users.doc(uid).set({
        'profileImageUrl': path,
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Avatar update failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDoc = ref.watch(userDocProvider(uid));

    final me = FirebaseAuth.instance.currentUser;
    final email = me?.email ?? '';
    final phone = me?.phoneNumber;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: const Color(0xFF000000),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 0,
          title: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: Color(0xFFA0A0A0),
                ),
              ),
              const SizedBox(width: 2),
              const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Edit profile',
              onPressed: () async {
                final u = ref.read(userDocProvider(uid)).value;
                await _openEditName(
                  uid: uid,
                  initial: (u?.name ?? '').trim().isEmpty ? uid : u!.name,
                );
              },
              icon: const Icon(
                Icons.edit_outlined,
                size: 20,
                color: Color(0xFFA0A0A0),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
      body: userDoc.when(
        data: (user) {
          final displayName = (user?.name ?? '').trim().isNotEmpty
              ? user!.name
              : uid;
          final usernameSeed = email.trim().isNotEmpty
              ? email.trim().split('@').first
              : displayName.toLowerCase().replaceAll(' ', '');
          final username =
              '@${usernameSeed.isEmpty ? uid.substring(0, uid.length.clamp(0, 6)) : usernameSeed}';
          final bio = (user?.about ?? '').trim();

          return ListView(
            padding: const EdgeInsets.only(bottom: 18),
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 26),
                child: Column(
                  children: [
                    FutureBuilder<String?>(
                      future: _resolveAvatarUrl(user?.profileImageUrl),
                      builder: (context, snap) {
                        final url = snap.data;
                        final hasImage = (url ?? '').trim().isNotEmpty;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 43,
                              backgroundColor: const Color(0xFF151515),
                              backgroundImage: hasImage
                                  ? NetworkImage(url!)
                                  : null,
                              child: hasImage
                                  ? null
                                  : Text(
                                      _initialsFrom(displayName),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                            Positioned(
                              bottom: -2,
                              right: -2,
                              child: InkWell(
                                onTap: () => _pickAndUploadAvatar(uid),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFC74B6C),
                                    border: Border.all(
                                      color: const Color(0xFF000000),
                                      width: 2,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_outlined,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () =>
                          _openEditName(uid: uid, initial: displayName),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      username,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9A9A9A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_editingBio) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _bioCtrl,
                                maxLines: 2,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFF101010),
                                  hintText: 'Your bio',
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF6B6B6B),
                                    fontSize: 13,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF2A2A2A),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: _saving ? null : () => _saveBio(uid),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                side: const BorderSide(
                                  color: Color(0xFF1A1A1A),
                                ),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Save',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      InkWell(
                        onTap: () {
                          _bioCtrl.text = bio;
                          setState(() => _editingBio = true);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 6,
                          ),
                          child: Text(
                            bio.isEmpty ? 'Tap to add a bio' : bio,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFA5A5A5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF101010),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _QuickAction(
                      icon: Icons.edit_outlined,
                      label: 'Edit Profile',
                      onTap: () =>
                          _openEditName(uid: uid, initial: displayName),
                    ),
                    _QuickAction(
                      icon: Icons.qr_code_2,
                      label: 'QR Code',
                      onTap: () {
                        showModalBottomSheet<void>(
                          context: context,
                          backgroundColor: const Color(0xFF101010),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(22),
                            ),
                          ),
                          builder: (ctx) => SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                24,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Your QR Code',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: QrImageView(
                                      data: uid,
                                      size: 170,
                                      backgroundColor: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    username,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF8A8A8A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    _QuickAction(
                      icon: Icons.share_outlined,
                      label: 'Share',
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Share profile')),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              const _SectionTitle('Account'),
              _SettingsTile(
                icon: Icons.phone_outlined,
                title: 'Phone number',
                value: phone ?? 'Not set',
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.alternate_email,
                title: 'Email',
                value: email.isEmpty ? 'Not set' : email,
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.lock_outline,
                title: 'Change password',
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Change password')),
                ),
              ),
              _SettingsTile(
                icon: Icons.verified_user_outlined,
                title: 'Two-factor authentication',
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('2FA coming soon')),
                ),
              ),

              const SizedBox(height: 14),

              const _SectionTitle('Preferences'),
              _SettingsTile(
                icon: Icons.dark_mode_outlined,
                title: 'Theme',
                value: _themePref == 'system' ? 'System' : 'Dark',
                onTap: () => _openSelectorSheet(
                  title: 'Theme',
                  selected: _themePref,
                  options: const ['dark', 'system'],
                  onSelected: (v) {
                    setState(() => _themePref = v);
                    _persistPrefs(uid);
                  },
                ),
              ),
              _SettingsTile(
                icon: Icons.language_outlined,
                title: 'Language',
                value: _languagePref,
                onTap: () => _openSelectorSheet(
                  title: 'Language',
                  selected: _languagePref,
                  options: const ['English', 'Urdu'],
                  onSelected: (v) {
                    setState(() => _languagePref = v);
                    _persistPrefs(uid);
                  },
                ),
              ),
              _SettingsTile(
                icon: Icons.chat_bubble_outline,
                title: 'Chat bubble size',
                value: _bubbleSizePref,
                onTap: () => _openSelectorSheet(
                  title: 'Chat bubble size',
                  selected: _bubbleSizePref,
                  options: const ['Small', 'Medium', 'Large'],
                  onSelected: (v) {
                    setState(() => _bubbleSizePref = v);
                    _persistPrefs(uid);
                  },
                ),
              ),
              _SettingsTile(
                icon: Icons.text_fields,
                title: 'Font size',
                value: _fontSizePref,
                onTap: () => _openSelectorSheet(
                  title: 'Font size',
                  selected: _fontSizePref,
                  options: const ['Small', 'Default', 'Large'],
                  onSelected: (v) {
                    setState(() => _fontSizePref = v);
                    _persistPrefs(uid);
                  },
                ),
              ),

              const SizedBox(height: 14),

              const _SectionTitle('Privacy'),
              _SettingsTile(
                icon: Icons.visibility_outlined,
                title: 'Last seen',
                value: _lastSeenPref,
                onTap: () => _openSelectorSheet(
                  title: 'Last seen',
                  selected: _lastSeenPref,
                  options: const ['Everyone', 'My contacts', 'Nobody'],
                  onSelected: (v) {
                    setState(() => _lastSeenPref = v);
                    _persistPrefs(uid);
                  },
                ),
              ),
              _SettingsTile(
                icon: Icons.photo_outlined,
                title: 'Profile photo visibility',
                value: 'Everyone',
                onTap: () => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Coming soon'))),
              ),
              _ToggleTile(
                icon: Icons.done_all,
                title: 'Read receipts',
                value: _readReceipts,
                onChanged: (v) {
                  setState(() => _readReceipts = v);
                  _persistPrefs(uid);
                },
              ),
              _SettingsTile(
                icon: Icons.block_outlined,
                title: 'Blocked users',
                value: (user?.blockedUsers.isNotEmpty == true)
                    ? '${user!.blockedUsers.length}'
                    : '0',
                onTap: () {
                  final blocked = user?.blockedUsers ?? const [];
                  showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: const Color(0xFF101010),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(22),
                      ),
                    ),
                    builder: (ctx) => SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Blocked users',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (blocked.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 16),
                                child: Text(
                                  'No blocked users',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF8A8A8A),
                                  ),
                                ),
                              )
                            else
                              ...blocked
                                  .take(8)
                                  .map(
                                    (id) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        id,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                      trailing: const Icon(
                                        Icons.chevron_right,
                                        color: Color(0xFFA0A0A0),
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 14),

              const _SectionTitle('Storage & Data'),
              _ToggleTile(
                icon: Icons.download_outlined,
                title: 'Media auto-download',
                value: true,
                onChanged: (_) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Coming soon')));
                },
              ),
              _SettingsTile(
                icon: Icons.pie_chart_outline,
                title: 'Storage usage',
                onTap: () => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Storage usage'))),
              ),
              const _StorageUsageCard(imagesMb: 120, videosMb: 430, docsMb: 60),
              _SettingsTile(
                icon: Icons.cleaning_services_outlined,
                title: 'Clear cache',
                onTap: () => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Cache cleared'))),
              ),

              const SizedBox(height: 18),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InkWell(
                  onTap: () async {
                    final nav = Navigator.of(context);
                    await ref.read(firebaseAuthServiceProvider).signOut();
                    if (!mounted) return;
                    nav.pop();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF3A1F1F),
                        width: 1,
                      ),
                    ),
                    child: const Text(
                      'Log out',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFE24C4C),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const _SettingsSkeleton(),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: const Color(0xFFA0A0A0)),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9A9A9A),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Icon(
                        icon,
                        size: 20,
                        color: const Color(0xFFA0A0A0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if ((value ?? '').trim().isNotEmpty)
                      Text(
                        value!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9A9A9A),
                        ),
                      ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Color(0xFFA0A0A0),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0xFF1E1E1E)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Icon(icon, size: 20, color: const Color(0xFFA0A0A0)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Switch(
                    value: value,
                    onChanged: onChanged,
                    activeColor: Colors.white,
                    activeTrackColor: const Color(0xFFC74B6C),
                    inactiveTrackColor: const Color(0xFF1E1E1E),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFF1E1E1E)),
          ],
        ),
      ),
    );
  }
}

class _StorageUsageCard extends StatelessWidget {
  final int imagesMb;
  final int videosMb;
  final int docsMb;
  const _StorageUsageCard({
    required this.imagesMb,
    required this.videosMb,
    required this.docsMb,
  });

  @override
  Widget build(BuildContext context) {
    final total = (imagesMb + videosMb + docsMb).toDouble();
    final used = total == 0 ? 0.0 : 1.0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Images', '${imagesMb}MB'),
          const SizedBox(height: 6),
          _row('Videos', '${videosMb}MB'),
          const SizedBox(height: 6),
          _row('Documents', '${docsMb}MB'),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: used,
              minHeight: 6,
              backgroundColor: const Color(0xFF1E1E1E),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFC74B6C)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Row(
    children: [
      Expanded(
        child: Text(
          k,
          style: const TextStyle(fontSize: 13, color: Color(0xFFA5A5A5)),
        ),
      ),
      Text(v, style: const TextStyle(fontSize: 13, color: Colors.white)),
    ],
  );
}

class _SettingsSkeleton extends StatelessWidget {
  const _SettingsSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar({double w = double.infinity, double h = 12}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(10),
      ),
    );

    Widget tile() => Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: bar(h: 12)),
                const SizedBox(width: 60),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFF1E1E1E)),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 18),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 26),
          child: Column(
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: const BoxDecoration(
                  color: Color(0xFF151515),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 80),
                child: bar(h: 14),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 120),
                child: bar(h: 12),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: bar(h: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 70,
          decoration: BoxDecoration(
            color: const Color(0xFF101010),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
          ),
        ),
        const SizedBox(height: 18),
        const _SectionTitle('Account'),
        tile(),
        tile(),
        tile(),
        tile(),
        const SizedBox(height: 14),
        const _SectionTitle('Preferences'),
        tile(),
        tile(),
        tile(),
        tile(),
        const SizedBox(height: 14),
        const _SectionTitle('Privacy'),
        tile(),
        tile(),
        tile(),
        tile(),
        const SizedBox(height: 14),
        const _SectionTitle('Storage & Data'),
        tile(),
        tile(),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          height: 92,
          decoration: BoxDecoration(
            color: const Color(0xFF101010),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
          ),
        ),
        tile(),
        const SizedBox(height: 18),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3A1F1F), width: 1),
          ),
        ),
      ],
    );
  }
}
