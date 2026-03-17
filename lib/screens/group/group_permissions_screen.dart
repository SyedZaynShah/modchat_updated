import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_service.dart';
import '../../theme/theme.dart';

class GroupPermissionsScreen extends StatefulWidget {
  static const routeName = '/group-permissions';
  final String chatId;

  const GroupPermissionsScreen({super.key, required this.chatId});

  @override
  State<GroupPermissionsScreen> createState() => _GroupPermissionsScreenState();
}

class _GroupPermissionsScreenState extends State<GroupPermissionsScreen> {
  final _auth = FirebaseAuth.instance;

  Future<String?> _myRole() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final snap = await FirestoreService().dmChats
        .doc(widget.chatId)
        .collection('members')
        .doc(uid)
        .get();
    if (!snap.exists) return null;
    final data = snap.data();
    return (data?['role'] as String?) ?? 'member';
  }

  Map<String, bool> _permissionsFrom(Map<String, dynamic> chatData) {
    final settings = Map<String, dynamic>.from(
      (chatData['settings'] as Map?) ?? const {},
    );
    final perms = Map<String, dynamic>.from(
      (settings['permissions'] as Map?) ?? const {},
    );

    bool readBool(String k, bool fallback) {
      final v = perms[k];
      if (v is bool) return v;
      return fallback;
    }

    return {
      'membersCanEditSettings': readBool('membersCanEditSettings', false),
      'membersCanSendMessages': readBool('membersCanSendMessages', true),
      'membersCanAddMembers': readBool('membersCanAddMembers', false),
      'membersCanInvite': readBool('membersCanInvite', false),
      'adminsCanApproveMembers': readBool('adminsCanApproveMembers', false),
      'adminsCanEditAdmins': readBool('adminsCanEditAdmins', true),
    };
  }

  Future<void> _setPermission(String key, bool value) async {
    await FirestoreService().dmChats.doc(widget.chatId).set({
      'settings': {
        'permissions': {key: value},
      },
    }, SetOptions(merge: true));
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.highlight,
        ),
      ),
    );
  }

  Widget _glassTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    final on = value;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline, width: 1),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: enabled ? onChanged : null,
        activeColor: AppColors.highlight,
        activeTrackColor: AppColors.outlineStrong,
        inactiveThumbColor: AppColors.textSecondary,
        inactiveTrackColor: AppColors.outline,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.outline, width: 1),
              ),
              child: Icon(
                icon,
                color: on ? AppColors.highlight : AppColors.textSecondary,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.highlight,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(left: 48),
          child: Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
              fontSize: 12,
            ),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Scaffold(body: SizedBox.shrink());

    final fs = FirestoreService();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Group permissions',
          style: TextStyle(
            color: AppColors.highlight,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.highlight, size: 18),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: fs.dmChats.doc(widget.chatId).snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? const <String, dynamic>{};
          final perms = _permissionsFrom(data);

          return FutureBuilder<String?>(
            future: _myRole(),
            builder: (context, roleSnap) {
              final role = roleSnap.data;
              final canEdit = role == 'owner';

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  if (!canEdit)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.outline, width: 1),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            color: AppColors.textSecondary,
                            size: 18,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Only the group creator can change permissions.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  _sectionTitle('Members can'),
                  _glassTile(
                    icon: Icons.tune,
                    title: 'Edit group settings',
                    subtitle:
                        'Allow members to edit name, description and group settings.',
                    value: perms['membersCanEditSettings']!,
                    enabled: canEdit,
                    onChanged: (v) =>
                        _setPermission('membersCanEditSettings', v),
                  ),
                  const SizedBox(height: 12),
                  _glassTile(
                    icon: Icons.chat_bubble_outline,
                    title: 'Send new messages',
                    subtitle:
                        'Allow members to send new messages in this group.',
                    value: perms['membersCanSendMessages']!,
                    enabled: canEdit,
                    onChanged: (v) =>
                        _setPermission('membersCanSendMessages', v),
                  ),
                  const SizedBox(height: 12),
                  _glassTile(
                    icon: Icons.person_add_alt_1,
                    title: 'Add other members',
                    subtitle:
                        'Allow members to add people directly to the group.',
                    value: perms['membersCanAddMembers']!,
                    enabled: canEdit,
                    onChanged: (v) => _setPermission('membersCanAddMembers', v),
                  ),
                  const SizedBox(height: 12),
                  _glassTile(
                    icon: Icons.qr_code_rounded,
                    title: 'Invite via link or QR Code',
                    subtitle:
                        'Allow members to generate invite links and QR codes.',
                    value: perms['membersCanInvite']!,
                    enabled: canEdit,
                    onChanged: (v) => _setPermission('membersCanInvite', v),
                  ),
                  _sectionTitle('Admins can'),
                  _glassTile(
                    icon: Icons.verified_user_outlined,
                    title: 'Approve new members',
                    subtitle: 'Require admin approval for new join requests.',
                    value: perms['adminsCanApproveMembers']!,
                    enabled: canEdit,
                    onChanged: (v) =>
                        _setPermission('adminsCanApproveMembers', v),
                  ),
                  const SizedBox(height: 12),
                  _glassTile(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Edit group admins',
                    subtitle: 'Allow admins to promote/demote other members.',
                    value: perms['adminsCanEditAdmins']!,
                    enabled: canEdit,
                    onChanged: (v) => _setPermission('adminsCanEditAdmins', v),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
