import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../providers/user_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _bioCtrl = TextEditingController();
  bool _editingBio = false;
  bool _saving = false;

  String _languagePref = 'English';
  String _bubbleSizePref = 'Medium';
  String _fontSizePref = 'Default';
  String _lastSeenPref = 'Everyone';
  bool _readReceipts = true;

  String _themeValueFromMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

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
          'theme': _themeValueFromMode(ref.read(themeModeProvider)),
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
    final theme = Theme.of(context);
    final val = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
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
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 10),
              ...options.map((o) {
                final isOn = o == selected;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    o,
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 14,
                    ),
                  ),
                  trailing: isOn
                      ? Icon(
                          Icons.check,
                          color: theme.colorScheme.primary,
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

  Future<void> _logout(BuildContext context) async {
    try {
      await ref.read(firebaseAuthServiceProvider).signOut();

      if (!context.mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      debugPrint('Logout error: $e');
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
    final themeMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    final me = FirebaseAuth.instance.currentUser;
    final email = me?.email ?? '';
    final phone = me?.phoneNumber;

    return Scaffold(
      backgroundColor: isLight
          ? theme.colorScheme.background
          : const Color(0xFF000000),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: isLight
              ? theme.colorScheme.background
              : const Color(0xFF000000),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleSpacing: 0,
          title: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: isLight ? Color(0xFF667085) : Color(0xFFA0A0A0),
                ),
              ),
              const SizedBox(width: 2),
              Text(
                'Settings',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: isLight
                      ? theme.colorScheme.onBackground
                      : Colors.white,
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
              icon: Icon(
                Icons.edit_outlined,
                size: 20,
                color: isLight ? const Color(0xFF667085) : const Color(0xFFA0A0A0),
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
                              backgroundColor: isLight
                                  ? theme.colorScheme.surface
                                  : const Color(0xFF151515),
                              backgroundImage: hasImage
                                  ? NetworkImage(url!)
                                  : null,
                              child: hasImage
                                  ? null
                                  : Text(
                                      _initialsFrom(displayName),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: isLight
                                            ? theme.colorScheme.onSurface
                                            : Colors.white,
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
                                    color: theme.colorScheme.primary,
                                    border: Border.all(
                                      color: isLight
                                          ? theme.colorScheme.background
                                          : const Color(0xFF000000),
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isLight
                                ? theme.colorScheme.onBackground
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      username,
                      style: TextStyle(
                        fontSize: 13,
                        color: isLight
                            ? theme.colorScheme.onBackground.withOpacity(0.62)
                            : const Color(0xFF9A9A9A),
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
                                style: TextStyle(
                                  color: isLight
                                      ? theme.colorScheme.onSurface
                                      : Colors.white,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: isLight
                                      ? theme.colorScheme.surface
                                      : const Color(0xFF101010),
                                  hintText: 'Your bio',
                                  hintStyle: TextStyle(
                                    color: isLight
                                        ? theme.colorScheme.onSurface
                                              .withOpacity(0.55)
                                        : const Color(0xFF6B6B6B),
                                    fontSize: 13,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: isLight
                                          ? theme.dividerColor.withOpacity(0.6)
                                          : const Color(0xFF1A1A1A),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: isLight
                                          ? theme.colorScheme.primary
                                          : const Color(0xFF2A2A2A),
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
                                side: BorderSide(
                                  color: isLight
                                      ? theme.dividerColor.withOpacity(0.65)
                                      : const Color(0xFF1A1A1A),
                                ),
                                foregroundColor: isLight
                                    ? theme.colorScheme.onSurface
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _saving
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: isLight
                                            ? theme.colorScheme.primary
                                            : Colors.white,
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
                            style: TextStyle(
                              fontSize: 13,
                              color: isLight
                                  ? Color(0xFF667085)
                                  : Color(0xFFA5A5A5),
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
                  color: isLight
                      ? theme.colorScheme.surface
                      : const Color(0xFF101010),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isLight
                        ? theme.dividerColor.withOpacity(0.65)
                        : const Color(0xFF1A1A1A),
                    width: 1,
                  ),
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
                        final sheetTheme = Theme.of(context);
                        final sheetIsLight =
                            sheetTheme.brightness == Brightness.light;
                        showModalBottomSheet<void>(
                          context: context,
                          backgroundColor: sheetIsLight
                              ? sheetTheme.colorScheme.surface
                              : const Color(0xFF101010),
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
                                  Text(
                                    'Your QR Code',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: sheetIsLight
                                          ? sheetTheme.colorScheme.onSurface
                                          : Colors.white,
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
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: sheetIsLight
                                          ? sheetTheme.colorScheme.onSurface
                                                .withOpacity(0.62)
                                          : const Color(0xFF8A8A8A),
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

              const _SectionTitle('Appearance'),
              _AppearanceModeCard(
                selectedMode: themeMode,
                onSystem: () async {
                  await ref.read(themeModeProvider.notifier).setSystem();
                  if (!mounted) return;
                  _persistPrefs(uid);
                },
                onLight: () async {
                  await ref.read(themeModeProvider.notifier).setLight();
                  if (!mounted) return;
                  _persistPrefs(uid);
                },
                onDark: () async {
                  await ref.read(themeModeProvider.notifier).setDark();
                  if (!mounted) return;
                  _persistPrefs(uid);
                },
              ),

              const SizedBox(height: 14),

              const _SectionTitle('Preferences'),
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
                  final sheetTheme = Theme.of(context);
                  final sheetIsLight = sheetTheme.brightness == Brightness.light;
                  showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: sheetIsLight
                        ? sheetTheme.colorScheme.surface
                        : const Color(0xFF101010),
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
                            Text(
                              'Blocked users',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: sheetIsLight
                                    ? sheetTheme.colorScheme.onSurface
                                    : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (blocked.isEmpty)
                              Padding(
                                padding: EdgeInsets.only(bottom: 16),
                                child: Text(
                                  'No blocked users',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: sheetIsLight
                                        ? sheetTheme.colorScheme.onSurface
                                              .withOpacity(0.62)
                                        : const Color(0xFF8A8A8A),
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
                                        style: TextStyle(
                                          color: sheetIsLight
                                              ? sheetTheme.colorScheme.onSurface
                                              : Colors.white,
                                        ),
                                      ),
                                      trailing: TextButton(
                                        onPressed: () async {
                                          final messenger =
                                              ScaffoldMessenger.of(context);
                                          final confirm = await showDialog<bool>(
                                            context: ctx,
                                            builder: (dCtx) => AlertDialog(
                                              title: const Text(
                                                'Unblock user?',
                                              ),
                                              content: Text(
                                                'Unblock $id and allow messages again.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(dCtx),
                                                  child: const Text('Cancel'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(dCtx, true),
                                                  child: const Text('Unblock'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (!mounted) return;
                                          if (confirm != true) return;

                                          ref
                                              .read(blockServiceProvider)
                                              .unblockUser(peerId: id)
                                              .catchError((e) {
                                                messenger.showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Unblock failed: $e',
                                                    ),
                                                  ),
                                                );
                                              });
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: sheetIsLight
                                              ? sheetTheme.colorScheme.primary
                                              : Colors.white,
                                        ),
                                        child: const Text('Unblock'),
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
                  onTap: () {
                    _logout(context);
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
                        color: isLight
                            ? const Color(0xFFF1C5C5)
                            : const Color(0xFF3A1F1F),
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
          child: Text(
            'Error: $e',
            style: TextStyle(
              color: isLight ? theme.colorScheme.onBackground : Colors.white,
            ),
          ),
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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isLight ? theme.colorScheme.onBackground : Colors.white,
        ),
      ),
    );
  }
}

class _AppearanceModeCard extends StatelessWidget {
  final ThemeMode selectedMode;
  final VoidCallback onSystem;
  final VoidCallback onLight;
  final VoidCallback onDark;

  const _AppearanceModeCard({
    required this.selectedMode,
    required this.onSystem,
    required this.onLight,
    required this.onDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
        color: isLight ? theme.colorScheme.surface : const Color(0xFF101010),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLight
              ? theme.dividerColor.withOpacity(0.65)
              : const Color(0xFF1A1A1A),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          _AppearanceOptionTile(
            icon: Icons.phone_android,
            title: 'System Default',
            selected: selectedMode == ThemeMode.system,
            onTap: onSystem,
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: isLight
                ? theme.dividerColor.withOpacity(0.55)
                : const Color(0xFF1E1E1E),
          ),
          _AppearanceOptionTile(
            icon: Icons.light_mode,
            title: 'Light',
            selected: selectedMode == ThemeMode.light,
            onTap: onLight,
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: isLight
                ? theme.dividerColor.withOpacity(0.55)
                : const Color(0xFF1E1E1E),
          ),
          _AppearanceOptionTile(
            icon: Icons.dark_mode,
            title: 'Dark',
            selected: selectedMode == ThemeMode.dark,
            onTap: onDark,
          ),
        ],
      ),
    );
  }
}

class _AppearanceOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _AppearanceOptionTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return SizedBox(
      height: 52,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Icon(
                  icon,
                  size: 20,
                  color: isLight ? const Color(0xFF667085) : const Color(0xFFA0A0A0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isLight
                        ? theme.colorScheme.onSurface
                        : Colors.white,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check, size: 20, color: AppColors.primary),
            ],
          ),
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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isLight ? const Color(0xFF667085) : const Color(0xFFA0A0A0),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isLight
                    ? theme.colorScheme.onSurface.withOpacity(0.64)
                    : const Color(0xFF9A9A9A),
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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
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
                        color: isLight
                            ? const Color(0xFF667085)
                            : const Color(0xFFA0A0A0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isLight
                              ? theme.colorScheme.onBackground
                              : Colors.white,
                        ),
                      ),
                    ),
                    if ((value ?? '').trim().isNotEmpty)
                      Text(
                        value!,
                        style: TextStyle(
                          fontSize: 13,
                          color: isLight
                              ? theme.colorScheme.onBackground.withOpacity(0.62)
                              : const Color(0xFF9A9A9A),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: isLight
                          ? const Color(0xFF98A2B3)
                          : const Color(0xFFA0A0A0),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: isLight
                    ? theme.dividerColor.withOpacity(0.55)
                    : const Color(0xFF1E1E1E),
              ),
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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
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
                    child: Icon(
                      icon,
                      size: 20,
                      color: isLight
                          ? const Color(0xFF667085)
                          : const Color(0xFFA0A0A0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isLight
                            ? theme.colorScheme.onBackground
                            : Colors.white,
                      ),
                    ),
                  ),
                  Switch(
                    value: value,
                    onChanged: onChanged,
                    activeColor: isLight ? Colors.white : Colors.white,
                    activeTrackColor: theme.colorScheme.primary,
                    inactiveTrackColor: isLight
                        ? const Color(0xFFD5D9E1)
                        : const Color(0xFF1E1E1E),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: isLight
                  ? theme.dividerColor.withOpacity(0.55)
                  : const Color(0xFF1E1E1E),
            ),
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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final total = (imagesMb + videosMb + docsMb).toDouble();
    final used = total == 0 ? 0.0 : 1.0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLight ? theme.colorScheme.surface : const Color(0xFF101010),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLight
              ? theme.dividerColor.withOpacity(0.65)
              : const Color(0xFF1A1A1A),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(context, 'Images', '${imagesMb}MB'),
          const SizedBox(height: 6),
          _row(context, 'Videos', '${videosMb}MB'),
          const SizedBox(height: 6),
          _row(context, 'Documents', '${docsMb}MB'),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: used,
              minHeight: 6,
              backgroundColor: isLight
                  ? const Color(0xFFE4E7EC)
                  : const Color(0xFF1E1E1E),
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: TextStyle(
              fontSize: 13,
              color: isLight
                  ? theme.colorScheme.onSurface.withOpacity(0.64)
                  : const Color(0xFFA5A5A5),
            ),
          ),
        ),
        Text(
          v,
          style: TextStyle(
            fontSize: 13,
            color: isLight ? theme.colorScheme.onSurface : Colors.white,
          ),
        ),
      ],
    );
  }
}

class _SettingsSkeleton extends StatelessWidget {
  const _SettingsSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    Widget bar({double w = double.infinity, double h = 12}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFE9ECF2) : const Color(0xFF151515),
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
                    color: isLight
                        ? const Color(0xFFE9ECF2)
                        : const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: bar(h: 12)),
                const SizedBox(width: 60),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: isLight
                ? theme.dividerColor.withOpacity(0.55)
                : const Color(0xFF1E1E1E),
          ),
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
                decoration: BoxDecoration(
                  color: isLight ? Color(0xFFE9ECF2) : Color(0xFF151515),
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
            color: isLight ? theme.colorScheme.surface : const Color(0xFF101010),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isLight
                  ? theme.dividerColor.withOpacity(0.65)
                  : const Color(0xFF1A1A1A),
              width: 1,
            ),
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
            color: isLight ? theme.colorScheme.surface : const Color(0xFF101010),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isLight
                  ? theme.dividerColor.withOpacity(0.65)
                  : const Color(0xFF1A1A1A),
              width: 1,
            ),
          ),
        ),
        tile(),
        const SizedBox(height: 18),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isLight ? const Color(0xFFF1C5C5) : const Color(0xFF3A1F1F),
              width: 1,
            ),
          ),
        ),
      ],
    );
  }
}

