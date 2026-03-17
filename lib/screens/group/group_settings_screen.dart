import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/message_model.dart';
import '../../providers/chat_providers.dart';
import '../../providers/user_providers.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/theme.dart';
import '../../widgets/glass_dropdown.dart';
import 'group_permissions_screen.dart';

class GroupSettingsScreen extends ConsumerStatefulWidget {
  static const routeName = '/group-settings';
  final String chatId;

  const GroupSettingsScreen({super.key, required this.chatId});

  @override
  ConsumerState<GroupSettingsScreen> createState() =>
      _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _memberSearchCtrl = TextEditingController();
  bool _rotatingInvite = false;

  Map<String, bool> _permissionsFrom(Map<String, dynamic> groupData) {
    final settings = Map<String, dynamic>.from(
      (groupData['settings'] as Map?) ?? const {},
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

  Future<bool> _canManageInvites(Map<String, dynamic> groupData) async {
    final role = await _myRole();
    final perms = _permissionsFrom(groupData);
    return role == 'owner' || role == 'admin'
        ? true
        : (perms['membersCanInvite'] == true);
  }

  Future<void> _copyInviteLink({
    required Map<String, dynamic> groupData,
    required String? inviteLink,
  }) async {
    if (inviteLink == null || inviteLink.trim().isEmpty) return;
    final canInvite = await _canManageInvites(groupData);
    if (!mounted) return;
    if (!canInvite) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to manage invites'),
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: inviteLink));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invite link copied')));
  }

  Future<void> _showInviteQr({
    required Map<String, dynamic> groupData,
    required String? inviteLink,
  }) async {
    if (inviteLink == null || inviteLink.trim().isEmpty) return;
    final canInvite = await _canManageInvites(groupData);
    if (!mounted) return;
    if (!canInvite) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to manage invites'),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Invite via QR Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.navy.withValues(alpha: 0.18),
                  ),
                ),
                child: QrImageView(
                  data: inviteLink,
                  size: 220,
                  eyeStyle: const QrEyeStyle(
                    color: AppColors.navy,
                    eyeShape: QrEyeShape.square,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    color: AppColors.navy,
                    dataModuleShape: QrDataModuleShape.square,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                inviteLink,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: inviteLink));
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite link copied')),
                );
              },
              child: const Text('Copy link'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _memberSearchCtrl.dispose();
    super.dispose();
  }

  String _randomToken(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(
      length,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  Future<void> _editTextField({
    required String title,
    required TextEditingController controller,
    int maxLines = 1,
    required Map<String, dynamic> groupData,
  }) async {
    final role = await _myRole();
    if (!mounted) return;
    final perms = _permissionsFrom(groupData);
    final canEdit = role == 'owner' || role == 'admin'
        ? true
        : (perms['membersCanEditSettings'] == true);
    if (!canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to edit settings'),
        ),
      );
      return;
    }

    final next = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: maxLines,
            minLines: 1,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (next == null) return;
    try {
      await FirestoreService().dmChats.doc(widget.chatId).set({
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<ImageProvider?> _resolveGroupAvatar(String? url) async {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('sb://')) {
      final s = raw.substring(5);
      final i = s.indexOf('/');
      if (i <= 0) return null;
      final bucket = s.substring(0, i);
      final path = s.substring(i + 1);
      final signed = await SupabaseService.instance.getSignedUrl(
        bucket,
        path,
        expiresInSeconds: 86400,
      );
      return NetworkImage(signed);
    }
    if (!raw.contains('://')) {
      final signed = await SupabaseService.instance.resolveUrl(
        bucket: StorageService().profileBucket,
        path: raw,
      );
      return NetworkImage(signed);
    }
    return NetworkImage(raw);
  }

  Future<void> _rotateInvite({required Map<String, dynamic> groupData}) async {
    setState(() => _rotatingInvite = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final role = await _myRole();
      final perms = _permissionsFrom(groupData);
      final canInvite = role == 'owner' || role == 'admin'
          ? true
          : (perms['membersCanInvite'] == true);
      if (!canInvite) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You do not have permission to manage invites'),
          ),
        );
        return;
      }

      final token = _randomToken(12);
      await FirestoreService().dmChats.doc(widget.chatId).set({
        'invite': {
          'token': token,
          'createdAt': FieldValue.serverTimestamp(),
          'revokedBy': uid,
          'expiresAt': null,
          'memberLimit': null,
        },
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite update failed: $e')));
    } finally {
      if (mounted) setState(() => _rotatingInvite = false);
    }
  }

  Future<String?> _myRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
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

  Future<void> _setMute(Duration? duration) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final until = duration == null
        ? null
        : Timestamp.fromDate(DateTime.now().add(duration));
    try {
      await FirestoreService().dmChats
          .doc(widget.chatId)
          .collection('members')
          .doc(uid)
          .set({'muteUntil': until}, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Mute failed: $e')));
    }
  }

  Future<void> _leaveGroup() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final role = await _myRole();
    if (role == 'owner') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Creator cannot leave the group')),
      );
      return;
    }

    try {
      final chatRef = FirestoreService().dmChats.doc(widget.chatId);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        tx.update(chatRef, {
          'members': FieldValue.arrayRemove([uid]),
          'memberCount': FieldValue.increment(-1),
        });
        tx.delete(chatRef.collection('members').doc(uid));
      });
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Leave failed: $e')));
    }
  }

  Future<void> _deleteGroup() async {
    final role = await _myRole();
    if (!mounted) return;
    if (role != 'owner') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only creator can delete the group')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group permanently?'),
        content: const Text('All messages will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (ok != true) return;

    try {
      final chatRef = FirestoreService().dmChats.doc(widget.chatId);
      const batchSize = 300;
      while (true) {
        final snap = await chatRef
            .collection('messages')
            .limit(batchSize)
            .get();
        if (snap.docs.isEmpty) break;
        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        if (snap.docs.length < batchSize) break;
      }
      final memSnap = await chatRef
          .collection('members')
          .limit(batchSize)
          .get();
      if (memSnap.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final d in memSnap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
      await chatRef.delete();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _openAddPeople(List<String> existing) async {
    final myRole = await _myRole();
    if (!mounted) return;
    final chatSnap = await FirestoreService().dmChats.doc(widget.chatId).get();
    final groupData = chatSnap.data() ?? const <String, dynamic>{};
    final perms = _permissionsFrom(groupData);
    final canAdd = myRole == 'owner' || myRole == 'admin'
        ? true
        : (perms['membersCanAddMembers'] == true);
    if (!canAdd) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to add members'),
        ),
      );
      return;
    }

    final fs = FirestoreService();
    final snap = await fs.users.get();
    if (!mounted) return;
    final me = FirebaseAuth.instance.currentUser?.uid;
    final candidates = snap.docs
        .map((d) => d.data())
        .where((u) => (u['userId'] as String?) != null)
        .toList();

    final Set<String> selected = <String>{};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add people'),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: ListView.builder(
              itemCount: candidates.length,
              itemBuilder: (context, index) {
                final u = candidates[index];
                final uid = u['userId'] as String;
                if (uid == me) return const SizedBox.shrink();
                if (existing.contains(uid)) return const SizedBox.shrink();
                final name = (u['name'] as String?) ?? uid;
                return StatefulBuilder(
                  builder: (context, setState2) {
                    final checked = selected.contains(uid);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (v) {
                        setState2(() {
                          if (v == true) {
                            selected.add(uid);
                          } else {
                            selected.remove(uid);
                          }
                        });
                      },
                      title: Text(name),
                      subtitle: Text((u['email'] as String?) ?? ''),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (ok != true || selected.isEmpty) return;

    try {
      final chatRef = FirestoreService().dmChats.doc(widget.chatId);
      final requireApproval = perms['adminsCanApproveMembers'] == true;
      if (requireApproval) {
        final batch = FirebaseFirestore.instance.batch();
        for (final uid in selected) {
          batch.set(chatRef.collection('pendingMembers').doc(uid), {
            'userId': uid,
            'requestedBy': FirebaseAuth.instance.currentUser?.uid,
            'requestedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request sent for admin approval')),
        );
      } else {
        await FirebaseFirestore.instance.runTransaction((tx) async {
          tx.update(chatRef, {
            'members': FieldValue.arrayUnion(selected.toList()),
            'memberCount': FieldValue.increment(selected.length),
          });
          for (final uid in selected) {
            tx.set(chatRef.collection('members').doc(uid), {
              'userId': uid,
              'role': 'member',
              'joinedAt': FieldValue.serverTimestamp(),
              'muteUntil': null,
              'lastSentAt': null,
              'isBanned': false,
            });
          }
        });
      }
    } on FirebaseException catch (e) {
      if (!mounted) return;
      if (e.code == 'permission-denied') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing permissions to add members')),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Add members failed: $e')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Add members failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final fs = FirestoreService();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: fs.dmChats.doc(widget.chatId).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};
        final name = ((data['name'] as String?) ?? 'Group').trim();
        final description = ((data['description'] as String?) ?? '').trim();
        final photoUrl = (data['photoUrl'] as String?)?.trim();
        final members = List<String>.from(
          (data['members'] as List?) ?? const [],
        );
        final invite = Map<String, dynamic>.from(
          (data['invite'] as Map?) ?? const {},
        );
        final token = (invite['token'] as String?)?.trim();

        if (_nameCtrl.text.isEmpty) _nameCtrl.text = name;
        if (_descCtrl.text.isEmpty) _descCtrl.text = description;

        final inviteLink = token == null || token.isEmpty
            ? null
            : 'https://appchat.com/invite/$token';

        Future<void> handleMenu(String v) async {
          if (v == 'edit_name') {
            await _editTextField(
              title: 'Group name',
              controller: _nameCtrl,
              maxLines: 1,
              groupData: data,
            );
          } else if (v == 'edit_desc') {
            await _editTextField(
              title: 'Group description',
              controller: _descCtrl,
              maxLines: 3,
              groupData: data,
            );
          } else if (v == 'invite') {
            await _rotateInvite(groupData: data);
          } else if (v == 'leave') {
            await _leaveGroup();
          } else if (v == 'delete') {
            await _deleteGroup();
          }
        }

        return Scaffold(
          backgroundColor: const Color(0xFF000000),
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: AppBar(
              toolbarHeight: 52,
              backgroundColor: const Color(0xFF000000),
              elevation: 0,
              centerTitle: true,
              title: const Text(
                'Group Info',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              iconTheme: const IconThemeData(
                size: 20,
                color: Color(0xFFA0A0A0),
              ),
              actions: [
                IconButton(
                  tooltip: 'Search members',
                  onPressed: () {
                    FocusScope.of(context).requestFocus(FocusNode());
                    _memberSearchCtrl.selection = TextSelection.fromPosition(
                      TextPosition(offset: _memberSearchCtrl.text.length),
                    );
                  },
                  icon: const Icon(Icons.search_rounded),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GlassDropdown(
                    items: [
                      const GlassDropdownItem(
                        value: 'edit_name',
                        label: 'Edit name',
                        icon: Icons.edit,
                      ),
                      const GlassDropdownItem(
                        value: 'edit_desc',
                        label: 'Edit description',
                        icon: Icons.description,
                      ),
                      const GlassDropdownItem(
                        value: 'invite',
                        label: 'Invite link',
                        icon: Icons.link,
                      ),
                      const GlassDropdownItem(
                        value: 'leave',
                        label: 'Leave group',
                        icon: Icons.logout,
                        isDestructive: true,
                      ),
                      const GlassDropdownItem(
                        value: 'delete',
                        label: 'Delete group',
                        icon: Icons.delete_forever,
                        isDestructive: true,
                      ),
                    ],
                    onSelected: (v) async => handleMenu(v),
                    child: const Icon(Icons.more_vert_rounded),
                  ),
                ),
              ],
            ),
          ),
          body: FutureBuilder<String?>(
            future: _myRole(),
            builder: (context, roleSnap) {
              final role = roleSnap.data;
              final perms = _permissionsFrom(data);
              final canEditInfo = role == 'owner' || role == 'admin'
                  ? true
                  : (perms['membersCanEditSettings'] == true);
              final canAddMembers = role == 'owner' || role == 'admin'
                  ? true
                  : (perms['membersCanAddMembers'] == true);

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 14),
                      child: Column(
                        children: [
                          FutureBuilder<ImageProvider?>(
                            future: _resolveGroupAvatar(photoUrl),
                            builder: (context, imgSnap) {
                              final img = imgSnap.data;
                              return _GroupAvatar84(image: img, name: name);
                            },
                          ),
                          const SizedBox(height: 10),
                          _EditableTitle(
                            text: name,
                            enabled: canEditInfo,
                            onEdit: () => _editTextField(
                              title: 'Group name',
                              controller: _nameCtrl,
                              maxLines: 1,
                              groupData: data,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _EditableDescription(
                            text: description.isEmpty
                                ? 'Add a group description'
                                : description,
                            enabled: canEditInfo,
                            isPlaceholder: description.isEmpty,
                            onEdit: () => _editTextField(
                              title: 'Group description',
                              controller: _descCtrl,
                              maxLines: 3,
                              groupData: data,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${members.length} members',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8A8A8A),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _QuickActionsRow(
                            onCall: () {},
                            onSearchMessages: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Search coming soon'),
                                ),
                              );
                            },
                            onMute: () async {
                              final chosen =
                                  await showModalBottomSheet<Duration?>(
                                    context: context,
                                    builder: (ctx) => SafeArea(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ListTile(
                                            leading: const Icon(
                                              Icons.volume_off_outlined,
                                            ),
                                            title: const Text('Mute 8 hours'),
                                            onTap: () => Navigator.pop(
                                              ctx,
                                              const Duration(hours: 8),
                                            ),
                                          ),
                                          ListTile(
                                            leading: const Icon(
                                              Icons.volume_off_outlined,
                                            ),
                                            title: const Text('Mute 1 week'),
                                            onTap: () => Navigator.pop(
                                              ctx,
                                              const Duration(days: 7),
                                            ),
                                          ),
                                          ListTile(
                                            leading: const Icon(
                                              Icons.volume_off_outlined,
                                            ),
                                            title: const Text('Mute forever'),
                                            onTap: () => Navigator.pop(
                                              ctx,
                                              const Duration(days: 3650),
                                            ),
                                          ),
                                          ListTile(
                                            leading: const Icon(
                                              Icons.volume_up_outlined,
                                            ),
                                            title: const Text('Unmute'),
                                            onTap: () =>
                                                Navigator.pop(ctx, null),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                              await _setMute(chosen);
                            },
                            onAddMember: canAddMembers
                                ? () => _openAddPeople(members)
                                : () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'You do not have permission to add members',
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          const _SectionHeader(title: 'Pinned Messages'),
                          const SizedBox(height: 10),
                          const _EmptyCard(text: 'No pinned messages'),
                          const SizedBox(height: 18),
                          _MediaAndFilesPreview(chatId: widget.chatId),
                          const SizedBox(height: 18),
                          _MembersSection(
                            chatId: widget.chatId,
                            memberIds: members,
                            canManage: role == 'owner' || role == 'admin',
                            onAdd: canAddMembers
                                ? () => _openAddPeople(members)
                                : null,
                            controller: _memberSearchCtrl,
                          ),
                          const SizedBox(height: 18),
                          const _SectionHeader(title: 'Group Settings'),
                          const SizedBox(height: 10),
                          _SettingsTile(
                            icon: Icons.edit,
                            title: 'Edit group name',
                            onTap: canEditInfo
                                ? () => _editTextField(
                                    title: 'Group name',
                                    controller: _nameCtrl,
                                    maxLines: 1,
                                    groupData: data,
                                  )
                                : null,
                          ),
                          _SettingsTile(
                            icon: Icons.description_outlined,
                            title: 'Edit description',
                            onTap: canEditInfo
                                ? () => _editTextField(
                                    title: 'Group description',
                                    controller: _descCtrl,
                                    maxLines: 3,
                                    groupData: data,
                                  )
                                : null,
                          ),
                          _SettingsTile(
                            icon: Icons.admin_panel_settings_outlined,
                            title: 'Manage admins',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Manage admins coming soon'),
                                ),
                              );
                            },
                          ),
                          _SettingsTile(
                            icon: Icons.link,
                            title: 'Invite link',
                            onTap: () => _rotateInvite(groupData: data),
                          ),
                          _SettingsTile(
                            icon: Icons.tune,
                            title: 'Group permissions',
                            onTap: () => Navigator.pushNamed(
                              context,
                              GroupPermissionsScreen.routeName,
                              arguments: {'chatId': widget.chatId},
                            ),
                          ),
                          const SizedBox(height: 18),
                          _InviteLinkCard(
                            inviteLink: inviteLink,
                            isBusy: _rotatingInvite,
                            onShowQr: inviteLink == null
                                ? null
                                : () => _showInviteQr(
                                    groupData: data,
                                    inviteLink: inviteLink,
                                  ),
                            onCopy: inviteLink == null
                                ? null
                                : () => _copyInviteLink(
                                    groupData: data,
                                    inviteLink: inviteLink,
                                  ),
                            onRotate: () => _rotateInvite(groupData: data),
                          ),
                          const SizedBox(height: 22),
                          const _SectionHeader(title: 'Danger Zone'),
                          const SizedBox(height: 10),
                          _DangerButton(
                            text: 'Leave group',
                            onTap: () => _leaveGroup(),
                          ),
                          const SizedBox(height: 10),
                          _DangerButton(
                            text: 'Delete group',
                            onTap: () => _deleteGroup(),
                          ),
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const _SectionHeader({required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        if (action != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                action!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFC74B6C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;
  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Color(0xFFA5A5A5)),
      ),
    );
  }
}

class _GroupAvatar84 extends StatelessWidget {
  final ImageProvider? image;
  final String name;
  const _GroupAvatar84({required this.image, required this.name});

  String _initials(String t) {
    final parts = t.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final list = parts.toList();
    if (list.isEmpty) return 'G';
    final a = list.first.characters.isNotEmpty
        ? list.first.characters.first
        : 'G';
    final b = list.length > 1 && list[1].characters.isNotEmpty
        ? list[1].characters.first
        : '';
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF141414),
        image: image == null
            ? null
            : DecorationImage(image: image!, fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: image != null
          ? null
          : Text(
              _initials(name),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
    );
  }
}

class _EditableTitle extends StatelessWidget {
  final String text;
  final bool enabled;
  final VoidCallback onEdit;
  const _EditableTitle({
    required this.text,
    required this.enabled,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onEdit : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            if (enabled) ...[
              const SizedBox(width: 8),
              const Icon(Icons.edit, size: 16, color: Color(0xFFA0A0A0)),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditableDescription extends StatelessWidget {
  final String text;
  final bool enabled;
  final bool isPlaceholder;
  final VoidCallback onEdit;
  const _EditableDescription({
    required this.text,
    required this.enabled,
    required this.isPlaceholder,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onEdit : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isPlaceholder
                      ? const Color(0xFF6F6F6F)
                      : const Color(0xFFA5A5A5),
                  height: 1.25,
                ),
              ),
            ),
            if (enabled) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.edit_outlined,
                size: 16,
                color: Color(0xFFA0A0A0),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  final VoidCallback onCall;
  final VoidCallback onSearchMessages;
  final VoidCallback onMute;
  final VoidCallback onAddMember;
  const _QuickActionsRow({
    required this.onCall,
    required this.onSearchMessages,
    required this.onMute,
    required this.onAddMember,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _QuickActionItem(
            icon: Icons.call_outlined,
            label: 'Call',
            onTap: onCall,
          ),
          _QuickActionItem(
            icon: Icons.search_rounded,
            label: 'Search',
            onTap: onSearchMessages,
          ),
          _QuickActionItem(
            icon: Icons.notifications_off_outlined,
            label: 'Mute',
            onTap: onMute,
          ),
          _QuickActionItem(
            icon: Icons.person_add_alt_1_outlined,
            label: 'Add',
            onTap: onAddMember,
          ),
        ],
      ),
    );
  }
}

class _QuickActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: const Color(0xFFA0A0A0)),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFFA5A5A5)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaAndFilesPreview extends ConsumerWidget {
  final String chatId;
  const _MediaAndFilesPreview({required this.chatId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(messagesProvider(chatId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Media & Files',
          action: 'See all',
          onAction: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Media gallery coming soon')),
            );
          },
        ),
        const SizedBox(height: 10),
        messages.when(
          data: (list) {
            final items = list
                .where(
                  (m) =>
                      (m.messageType == MessageType.image ||
                          m.messageType == MessageType.video ||
                          m.messageType == MessageType.file) &&
                      (m.mediaUrl ?? '').isNotEmpty,
                )
                .toList()
                .reversed
                .take(6)
                .toList();
            if (items.isEmpty) {
              return const _EmptyCard(text: 'No media shared yet');
            }
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final m = items[index];
                return _MediaTile(message: m);
              },
            );
          },
          loading: () => _SkeletonGrid(count: 6),
          error: (_, __) => const _EmptyCard(text: 'Failed to load media'),
        ),
      ],
    );
  }
}

class _MediaTile extends StatelessWidget {
  final MessageModel message;
  const _MediaTile({required this.message});

  Future<String?> _resolve(String? raw) async {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    if (s.startsWith('sb://')) {
      final no = s.substring(5);
      final i = no.indexOf('/');
      if (i <= 0) return null;
      return SupabaseService.instance.getSignedUrl(
        no.substring(0, i),
        no.substring(i + 1),
        expiresInSeconds: 86400,
      );
    }
    if (!s.contains('://')) {
      return SupabaseService.instance.resolveUrl(
        bucket: StorageService().mediaBucket,
        path: s,
      );
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: const Color(0xFF151515),
        child: FutureBuilder<String?>(
          future: _resolve(message.mediaUrl),
          builder: (context, snap) {
            final url = snap.data;
            final isVideo = message.messageType == MessageType.video;
            final isDoc = message.messageType == MessageType.file;

            Widget base;
            if (url == null || isDoc) {
              base = Container(
                color: const Color(0xFF101010),
                alignment: Alignment.center,
                child: Icon(
                  isDoc
                      ? Icons.insert_drive_file_outlined
                      : Icons.image_outlined,
                  color: const Color(0xFFA0A0A0),
                  size: 22,
                ),
              );
            } else {
              base = CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (context, _) =>
                    Container(color: const Color(0xFF151515)),
                errorWidget: (context, _, __) => Container(
                  color: const Color(0xFF101010),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    size: 22,
                    color: Color(0xFFA0A0A0),
                  ),
                ),
              );
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                base,
                if (isVideo)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      size: 28,
                      color: Color(0xE6FFFFFF),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SkeletonGrid extends StatelessWidget {
  final int count;
  const _SkeletonGrid({required this.count});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(color: const Color(0xFF151515)),
        );
      },
    );
  }
}

class _MembersSection extends ConsumerStatefulWidget {
  final String chatId;
  final List<String> memberIds;
  final bool canManage;
  final VoidCallback? onAdd;
  final TextEditingController controller;
  const _MembersSection({
    required this.chatId,
    required this.memberIds,
    required this.canManage,
    required this.onAdd,
    required this.controller,
  });

  @override
  ConsumerState<_MembersSection> createState() => _MembersSectionState();
}

class _MembersSectionState extends ConsumerState<_MembersSection> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSearch);
  }

  @override
  void didUpdateWidget(covariant _MembersSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onSearch);
      widget.controller.addListener(_onSearch);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSearch);
    super.dispose();
  }

  void _onSearch() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.controller.text.trim().toLowerCase();

    final visible = <String>[];
    for (final id in widget.memberIds) {
      final u = ref
          .watch(userDocProvider(id))
          .maybeWhen(data: (x) => x, orElse: () => null);
      final name = ((u?.name ?? id)).trim().toLowerCase();
      if (q.isEmpty || name.contains(q)) visible.add(id);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Members',
          action: widget.onAdd == null ? null : 'Add',
          onAction: widget.onAdd,
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF101010),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
          ),
          child: TextField(
            controller: widget.controller,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Search members',
              hintStyle: TextStyle(color: Color(0xFF6F6F6F)),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (visible.isEmpty)
          const _EmptyCard(text: 'No members found')
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final id = visible[index];
              return _MemberRow(
                chatId: widget.chatId,
                userId: id,
                canManage: widget.canManage,
              );
            },
          ),
      ],
    );
  }
}

class _MemberRow extends ConsumerWidget {
  final String chatId;
  final String userId;
  final bool canManage;
  const _MemberRow({
    required this.chatId,
    required this.userId,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userDocProvider(userId));
    final fs = FirestoreService();

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
      ),
      child: Row(
        children: [
          user.when(
            data: (u) {
              final name = (u?.name ?? userId).trim();
              final pfp = (u?.profileImageUrl ?? '').trim();
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF141414),
                    child: pfp.isEmpty
                        ? Text(
                            name.characters.isNotEmpty
                                ? name.characters.first.toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  const Positioned(
                    right: -1,
                    bottom: -1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFF2ECC71),
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(width: 8, height: 8),
                    ),
                  ),
                ],
              );
            },
            loading: () => const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFF151515),
            ),
            error: (_, __) => const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFF151515),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                user.when(
                  data: (u) {
                    final display = ((u?.name ?? userId)).trim();
                    return Text(
                      display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    );
                  },
                  loading: () => Container(
                    width: 120,
                    height: 12,
                    color: const Color(0xFF151515),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 6),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: fs.dmChats
                      .doc(chatId)
                      .collection('members')
                      .doc(userId)
                      .snapshots(),
                  builder: (context, snap) {
                    final role = (snap.data?.data()?['role'] as String?) ?? '';
                    if (role != 'admin' && role != 'owner') {
                      return const SizedBox.shrink();
                    }
                    return _RoleBadge(role: role);
                  },
                ),
              ],
            ),
          ),
          if (canManage)
            IconButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: const Color(0xFF0F0F0F),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (ctx) {
                  return SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.person_outline,
                            color: Color(0xFFA0A0A0),
                          ),
                          title: const Text(
                            'View profile',
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: () => Navigator.pop(ctx),
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.admin_panel_settings_outlined,
                            color: Color(0xFFA0A0A0),
                          ),
                          title: const Text(
                            'Make admin',
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: () => Navigator.pop(ctx),
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.remove_circle_outline,
                            color: Color(0xFFE24C4C),
                          ),
                          title: const Text(
                            'Remove from group',
                            style: TextStyle(color: Color(0xFFE24C4C)),
                          ),
                          onTap: () => Navigator.pop(ctx),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  );
                },
              ),
              icon: const Icon(
                Icons.more_vert_rounded,
                color: Color(0xFFA0A0A0),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isOwner = role == 'owner';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isOwner ? const Color(0xFFC74B6C) : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isOwner ? 'OWNER' : 'ADMIN',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.0,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 52,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF101010),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFFA0A0A0)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: onTap == null ? const Color(0xFF6F6F6F) : Colors.white,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFA0A0A0), size: 20),
          ],
        ),
      ),
    );
  }
}

class _InviteLinkCard extends StatelessWidget {
  final String? inviteLink;
  final bool isBusy;
  final VoidCallback? onShowQr;
  final VoidCallback? onCopy;
  final VoidCallback onRotate;
  const _InviteLinkCard({
    required this.inviteLink,
    required this.isBusy,
    required this.onShowQr,
    required this.onCopy,
    required this.onRotate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Invite Link',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  inviteLink ?? 'No invite link generated',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFA5A5A5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: onCopy,
            icon: const Icon(Icons.copy, size: 18, color: Color(0xFFA0A0A0)),
            tooltip: 'Copy',
          ),
          IconButton(
            onPressed: onShowQr,
            icon: const Icon(
              Icons.qr_code_2,
              size: 18,
              color: Color(0xFFA0A0A0),
            ),
            tooltip: 'QR',
          ),
          const SizedBox(width: 2),
          OutlinedButton(
            onPressed: isBusy ? null : onRotate,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF1A1A1A)),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              isBusy
                  ? 'Generating...'
                  : (inviteLink == null ? 'Generate' : 'Revoke'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _DangerButton({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF3A1F1F), width: 1),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFFE24C4C),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
