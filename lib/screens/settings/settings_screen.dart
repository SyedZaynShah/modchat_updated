import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/user_providers.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
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

  @override
  void dispose() {
    _bioCtrl.dispose();
    super.dispose();
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
              'Settings',
              style: TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 6.0),
            child: Icon(Icons.search, color: AppColors.navy),
          ),
        ],
      ),
      body: userDoc.when(
        data: (user) {
          if (!_editingBio) {
            _bioCtrl.text = user?.about ?? '';
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Profile row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: AppColors.sinopia.withOpacity(0.25),
                        backgroundImage:
                            (user?.profileImageUrl?.isNotEmpty == true)
                            ? NetworkImage(user!.profileImageUrl!)
                            : null,
                        child: (user?.profileImageUrl?.isNotEmpty == true)
                            ? null
                            : const Icon(
                                Icons.person,
                                color: Colors.white70,
                                size: 28,
                              ),
                      ),
                      Positioned(
                        bottom: -6,
                        right: -6,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _pickAndUploadAvatar(uid),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                border: Border.all(
                                  color: AppColors.sinopia,
                                  width: 1.2,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt_outlined,
                                size: 16,
                                color: AppColors.navy,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (user?.name?.isNotEmpty == true) ? user!.name : uid,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _editingBio
                            ? Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: AppColors.navy,
                                          width: 1.5,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      child: TextField(
                                        controller: _bioCtrl,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          border: InputBorder.none,
                                          labelText: 'Bio',
                                          hintText: 'Write something about you',
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _saving
                                        ? null
                                        : () => _saveBio(uid),
                                    child: _saving
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text('Save'),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      (user?.about?.isNotEmpty == true)
                                          ? user!.about!
                                          : 'Add a bio',
                                      style: TextStyle(
                                        color: AppColors.navy.withOpacity(0.6),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: () => setState(() {
                                      _bioCtrl.text = user?.about ?? '';
                                      _editingBio = true;
                                    }),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.navy,
                                      side: const BorderSide(
                                        color: AppColors.navy,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Edit bio'),
                                  ),
                                ],
                              ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Settings tiles
              _settingTile(
                icon: Icons.person_outline,
                title: 'Account',
                subtitle: 'Privacy, security, change number',
                onTap: () {},
              ),
              _settingTile(
                icon: Icons.lock_outline,
                title: 'Privacy',
                subtitle: 'Manage privacy and safety',
                onTap: () {},
              ),
              _settingTile(
                icon: Icons.shield_outlined,
                title: 'Moderation Controls',
                subtitle: 'Block, report, filters',
                onTap: () {},
              ),
              _settingTile(
                icon: Icons.face_outlined,
                title: 'Avatar',
                subtitle: 'Profile photo, visibility',
                onTap: () {},
              ),
              _settingTile(
                icon: Icons.list_alt_outlined,
                title: 'Lists',
                subtitle: 'Broadcasts, labels',
                onTap: () {},
              ),
              _settingTile(
                icon: Icons.chat_bubble_outline,
                title: 'Chats',
                subtitle: 'Theme, wallpaper, chat backup',
                onTap: () {},
              ),
              _settingTile(
                icon: Icons.campaign_outlined,
                title: 'Broadcasts',
                subtitle: 'Create and manage lists',
                onTap: () {},
              ),
              _settingTile(
                icon: Icons.notifications_none,
                title: 'Notifications',
                subtitle: 'Message, group & call tones',
                onTap: () {},
              ),
              _settingTile(
                icon: Icons.storage_outlined,
                title: 'Storage and data',
                subtitle: 'Manage storage, network usage',
                onTap: () {},
              ),
              _settingTile(
                icon: Icons.accessibility_new_outlined,
                title: 'Accessibility',
                subtitle: 'Screen reader, text size',
                onTap: () {},
              ),
              _settingTile(
                icon: Icons.language_outlined,
                title: 'App Language',
                subtitle: 'Select your preferred language',
                onTap: () {},
              ),
              _settingTile(
                icon: Icons.help_outline,
                title: 'Help and feedback',
                subtitle: 'FAQ, contact us',
                onTap: () {},
              ),
              _settingTile(
                icon: Icons.share_outlined,
                title: 'Invite a friend',
                subtitle: 'Share ModChat with friends',
                onTap: () {},
              ),
              _settingTile(
                icon: Icons.system_update_alt_outlined,
                title: 'App updates',
                subtitle: 'Version, what\'s new',
                onTap: () {},
              ),

              const SizedBox(height: 12),

              // Logout
              const Divider(height: 24),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    Navigator.of(context).pop();
                  },
                  splashColor: AppColors.navy.withOpacity(0.08),
                  highlightColor: AppColors.navy.withOpacity(0.06),
                  child: const ListTile(
                    leading: Icon(Icons.logout, color: Colors.redAccent),
                    title: Text(
                      'Logout',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
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
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.navy.withOpacity(0.08),
        highlightColor: AppColors.navy.withOpacity(0.06),
        child: ListTile(
          leading: Icon(icon, color: AppColors.navy),
          title: Text(
            title,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(color: AppColors.navy.withOpacity(0.6)),
          ),
          trailing: const Icon(Icons.chevron_right, color: AppColors.navy),
        ),
      ),
    );
  }
}
