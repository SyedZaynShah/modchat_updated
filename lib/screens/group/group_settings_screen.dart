import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/message_model.dart';
import '../../providers/chat_providers.dart';
import '../../providers/user_providers.dart';
import '../../services/firestore_service.dart';
import '../../services/group_moderation_service.dart';
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

class _JoinRequestsSection extends ConsumerWidget {
  final String chatId;
  const _JoinRequestsSection({required this.chatId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatRef = FirestoreService().dmChats.doc(chatId);
    final requestsStream = chatRef
        .collection('pendingMembers')
        .orderBy('requestedAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: requestsStream,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        Future<void> approve(String uid) async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            print('ADDING MEMBER $uid');
            final myUid = FirebaseAuth.instance.currentUser?.uid;
            if (myUid == null) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('You are not allowed to perform this action'),
                ),
              );
              return;
            }
            final myRoleSnap = await chatRef
                .collection('members')
                .doc(myUid)
                .get();
            final myRole = (myRoleSnap.data()?['role'] as String?) ?? 'member';
            final isAdmin = myRole == 'owner' || myRole == 'admin';
            if (!isAdmin) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('You are not allowed to perform this action'),
                ),
              );
              return;
            }

            // ✅ TRANSACTION: Atomic member addition
            print("ADDING MEMBER: $uid by $myUid");
            await FirebaseFirestore.instance.runTransaction((tx) async {
              final memberRef = chatRef.collection('members').doc(uid);
              final memberSnap = await tx.get(memberRef);

              // ✅ Prevent duplicate add
              if (memberSnap.exists) {
                print("User already a member, skipping");
                return;
              }

              // ✅ Create member doc
              tx.set(memberRef, {
                'userId': uid,
                'role': 'member',
                'joinedAt': FieldValue.serverTimestamp(),
                'removedAt': null,
                'removeType': null,
                'removedBy': null,
                'muteUntil': null,
                'lastSentAt': null,
                'isBanned': false,
                'bannedUntil': null,
                'banReason': null,
              });

              // ✅ Update members array
              tx.update(chatRef, {
                'members': FieldValue.arrayUnion([uid]),
                'memberCount': FieldValue.increment(1),
              });
            });

            // ✅ SECONDARY: Delete pending member request (silent)
            try {
              await chatRef.collection('pendingMembers').doc(uid).delete();
            } catch (e) {
              print("PENDING DELETE FAILED: $e");
            }

            // ✅ SECONDARY: Create system message (silent)
            try {
              final moderationService = GroupModerationService(
                FirestoreService(),
              );
              await moderationService.writeSystemMessageWithNames(
                chatId: chatId,
                action: 'member_added',
                actorId: myUid,
                targetId: uid,
                buildText: (actorName, targetName) {
                  final t = targetName ?? uid;
                  return '$t was added by $actorName';
                },
              );
            } catch (e) {
              print("SYSTEM MESSAGE FAILED: $e");
            }
          } on FirebaseException catch (e) {
            final isPermissionError =
                e.code == 'permission-denied' ||
                e.toString().toLowerCase().contains('permission');
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  isPermissionError
                      ? 'You are not allowed to perform this action'
                      : 'Approve failed: $e',
                ),
              ),
            );
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Approve failed: $e')),
            );
          }
        }

        Future<void> reject(String uid) async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await chatRef.collection('pendingMembers').doc(uid).delete();
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Reject failed: $e')),
            );
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: 'Join Requests', action: '${docs.length}'),
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final d = docs[index];
                final uid = (d.data()['userId'] as String?) ?? d.id;

                return Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  margin: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Theme.of(context).colorScheme.surface
                        : const Color(0xFF0F0F0F),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black.withOpacity(0.05)
                          : const Color(0xFF1A1A1A),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          uid,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                Theme.of(context).brightness == Brightness.light
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => reject(uid),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFE24C4C),
                        ),
                        child: const Text('Reject'),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: () => approve(uid),
                        style: TextButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).brightness == Brightness.light
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                        ),
                        child: const Text('Approve'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _memberSearchCtrl = TextEditingController();
  bool _rotatingInvite = false;
  bool _uploadingPhoto = false;
  String? _photoUrlOverride;
  Uint8List? _photoBytesOverride;
  String? _avatarFutureKey;
  Future<ImageProvider?>? _avatarFuture;
  bool? _slowModeEnabledOverride;
  int? _slowModeDurationOverride;
  bool _addingMembers = false;
  final Set<String> _optimisticallyRemovedMemberIds = <String>{};
  final Set<String> _removingMemberIds = <String>{};

  Future<ImageProvider?> _avatarFutureFor(String? url) {
    final key = (url ?? '').trim();
    if (_avatarFuture == null || _avatarFutureKey != key) {
      _avatarFutureKey = key;
      _avatarFuture = _resolveGroupAvatar(key);
    }
    return _avatarFuture!;
  }

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
    required String inviteLink,
  }) async {
    if (inviteLink.trim().isEmpty) return;
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

  Future<void> _shareInviteLink({
    required Map<String, dynamic> groupData,
    required String inviteLink,
  }) async {
    if (inviteLink.trim().isEmpty) return;
    final canInvite = await _canManageInvites(groupData);
    if (!canInvite) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Invite link'),
          content: const Text('You do not have permission to manage invites'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    await Share.share(inviteLink);
  }

  String _buildInviteLink(String code) {
    final c = code.trim();
    if (c.isEmpty) return '';
    return 'https://modchat.app/join?groupId=$c';
  }

  Future<void> _showInviteQr({
    required Map<String, dynamic> groupData,
    required String inviteLink,
  }) async {
    if (inviteLink.trim().isEmpty) return;
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

  Future<void> _revokeInvite({required Map<String, dynamic> groupData}) async {
    setState(() => _rotatingInvite = true);
    try {
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

      await ref
          .read(groupModerationServiceProvider)
          .revokeInvite(chatId: widget.chatId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite update failed: $e')));
    } finally {
      if (mounted) setState(() => _rotatingInvite = false);
    }
  }

  Future<void> _setSlowMode({
    required bool enabled,
    required int durationSec,
  }) async {
    final prevEnabled = _slowModeEnabledOverride;
    final prevDuration = _slowModeDurationOverride;

    setState(() {
      _slowModeEnabledOverride = enabled;
      _slowModeDurationOverride = enabled ? durationSec : 0;
    });

    // Fire-and-forget: UI is already updated optimistically.
    ref
        .read(groupModerationServiceProvider)
        .setSlowMode(
          chatId: widget.chatId,
          enabled: enabled,
          durationSec: durationSec,
        )
        .catchError((e) {
          if (!mounted) return;
          setState(() {
            _slowModeEnabledOverride = prevEnabled;
            _slowModeDurationOverride = prevDuration;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Slow mode update failed: $e')),
          );
        });
  }

  Future<void> _pickAndUploadGroupPhoto({required ImageSource source}) async {
    if (_uploadingPhoto) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      setState(() => _uploadingPhoto = true);
      final picker = ImagePicker();
      final XFile? x = await picker.pickImage(
        source: source,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 75,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() => _photoBytesOverride = Uint8List.fromList(bytes));
      final path =
          'group_avatars/${widget.chatId}_${DateTime.now().millisecondsSinceEpoch}.png';
      final bucket = StorageService().profileBucket;
      await StorageService().uploadBytes(
        data: Uint8List.fromList(bytes),
        bucket: bucket,
        path: path,
        contentType: 'image/png',
      );
      await FirestoreService().dmChats.doc(widget.chatId).set({
        'photoUrl': path,
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _photoBytesOverride = null;
        _photoUrlOverride = path;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Group photo updated')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update group photo: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _showGroupPhotoPicker(String? currentPhotoUrl) async {
    final current = (currentPhotoUrl ?? '').trim();
    final canRemove = current.isNotEmpty;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadGroupPhoto(source: ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadGroupPhoto(source: ImageSource.gallery);
              },
            ),
            if (canRemove) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeGroupPhoto();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _removeGroupPhoto() async {
    if (_uploadingPhoto) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      setState(() => _uploadingPhoto = true);
      await FirestoreService().dmChats.doc(widget.chatId).set({
        'photoUrl': null,
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _photoBytesOverride = null;
        _photoUrlOverride = null;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Group photo removed')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to remove group photo: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
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

      await ref
          .read(groupModerationServiceProvider)
          .generateNewInvite(chatId: widget.chatId);
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

  // ✅ Get active members (filtered by removedAt == null)
  Stream<List<String>> _getActiveMemberIds() {
    return FirestoreService().dmChats
        .doc(widget.chatId)
        .collection('members')
        .where('removedAt', isNull: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toList());
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
      await ref
          .read(groupModerationServiceProvider)
          .leaveGroup(chatId: widget.chatId);
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
    if (_addingMembers) return;
    final myRole = await _myRole();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null) {
      final roleDoc = await FirebaseFirestore.instance
          .collection('dmChats')
          .doc(widget.chatId)
          .collection('members')
          .doc(currentUserId)
          .get();
      debugPrint(
        'MY ROLE: ${roleDoc.data()?['"'
            "'role'"
            '"']}',
      );
    }
    if (!mounted) return;
    final canAdd = myRole == 'owner' || myRole == 'admin';
    if (!canAdd) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are not allowed to perform this action'),
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

    if (mounted) {
      setState(() => _addingMembers = true);
    }
    try {
      final chatRef = FirestoreService().dmChats.doc(widget.chatId);
      final isAdmin = myRole == 'owner' || myRole == 'admin';
      if (!isAdmin) {
        throw Exception('Not authorized');
      }

      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (myUid == null) throw Exception('Not authenticated');

      // ✅ TRANSACTIONS: Atomic member additions (one per user)
      for (final uid in selected) {
        print("ADDING MEMBER: $uid by $myUid");
        await FirebaseFirestore.instance.runTransaction((tx) async {
          final memberRef = chatRef.collection('members').doc(uid);
          final memberSnap = await tx.get(memberRef);

          // ✅ Prevent duplicate add
          if (memberSnap.exists) {
            print("User $uid already a member, skipping");
            return;
          }

          // ✅ Create member doc
          tx.set(memberRef, {
            'userId': uid,
            'role': 'member',
            'joinedAt': FieldValue.serverTimestamp(),
            'removedAt': null,
            'removeType': null,
            'removedBy': null,
            'muteUntil': null,
            'lastSentAt': null,
            'isBanned': false,
            'bannedUntil': null,
            'banReason': null,
          });

          // ✅ Update members array
          tx.update(chatRef, {
            'members': FieldValue.arrayUnion([uid]),
            'memberCount': FieldValue.increment(1),
          });
        });
      }

      // ✅ SECONDARY: Delete pending member requests (silent)
      for (final uid in selected) {
        try {
          await chatRef.collection('pendingMembers').doc(uid).delete();
        } catch (e) {
          print("PENDING DELETE FAILED for $uid: $e");
        }
      }

      // ✅ SECONDARY: Create system messages (silent)
      final moderationService = GroupModerationService(FirestoreService());
      for (final uid in selected) {
        try {
          await moderationService.writeSystemMessageWithNames(
            chatId: widget.chatId,
            action: 'member_added',
            actorId: myUid,
            targetId: uid,
            buildText: (actorName, targetName) {
              final t = targetName ?? uid;
              return '$t was added by $actorName';
            },
          );
        } catch (e) {
          print("SYSTEM MESSAGE FAILED for $uid: $e");
        }
      }
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final isPermissionError =
          e.code == 'permission-denied' ||
          e.toString().toLowerCase().contains('permission');
      if (isPermissionError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are not allowed to perform this action'),
          ),
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
    } finally {
      if (mounted) {
        setState(() => _addingMembers = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final fs = FirestoreService();
    return StreamBuilder<List<String>>(
      stream: _getActiveMemberIds(),
      builder: (context, activeMembersSnap) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: fs.dmChats.doc(widget.chatId).snapshots(),
          builder: (context, snap) {
            final theme = Theme.of(context);
            final isLight = theme.brightness == Brightness.light;
            final data = snap.data?.data() ?? const <String, dynamic>{};
            final name = ((data['name'] as String?) ?? 'Group').trim();
            final description = ((data['description'] as String?) ?? '').trim();
            final photoUrl = (data['photoUrl'] as String?)?.trim();
            final activeMembers = activeMembersSnap.data ?? const [];
            final invite = Map<String, dynamic>.from(
              (data['invite'] as Map?) ?? const {},
            );
            final code = (invite['code'] as String?)?.trim();
            final revoked = (invite['revoked'] as bool?) ?? false;

            if (_nameCtrl.text.isEmpty) _nameCtrl.text = name;
            if (_descCtrl.text.isEmpty) _descCtrl.text = description;

            final inviteLink = (code == null || code.isEmpty || revoked)
              ? null
              : _buildInviteLink(code);

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

            final visibleMembers = activeMembers
                .where((id) => !_optimisticallyRemovedMemberIds.contains(id))
                .toList(growable: false);

            return Scaffold(
              backgroundColor: isLight
                  ? theme.colorScheme.background
                  : theme.scaffoldBackgroundColor,
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: AppBar(
                  toolbarHeight: 52,
                  backgroundColor: isLight
                      ? theme.colorScheme.background
                      : theme.scaffoldBackgroundColor,
                  elevation: 0,
                  centerTitle: true,
                  title: Text(
                    'Group Info',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isLight
                          ? theme.colorScheme.onBackground
                          : Colors.white,
                    ),
                  ),
                  iconTheme: IconThemeData(
                    size: 20,
                    color: isLight
                        ? theme.colorScheme.onBackground
                        : const Color(0xFFA0A0A0),
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Search members',
                      onPressed: () {
                        FocusScope.of(context).requestFocus(FocusNode());
                        _memberSearchCtrl
                            .selection = TextSelection.fromPosition(
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
                        child: Icon(
                          Icons.more_vert_rounded,
                          color: isLight
                              ? theme.colorScheme.onBackground
                              : const Color(0xFFA0A0A0),
                        ),
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
                  final isAdmin = role == 'owner' || role == 'admin';
                  final isOwner = role == 'owner';
                  final canEditInfo = role == 'owner' || role == 'admin'
                      ? true
                      : (perms['membersCanEditSettings'] == true);
                  final canAddMembers = role == 'owner' || role == 'admin'
                      ? true
                      : (perms['membersCanAddMembers'] == true);

                  final moderation = Map<String, dynamic>.from(
                    (data['moderation'] as Map?) ?? const {},
                  );
                  final remoteSlowEnabled =
                      (moderation['slowModeEnabled'] as bool?) ?? false;
                  final remoteSlowDuration =
                      (moderation['slowModeDurationSec'] as int?) ?? 0;

                  final slowModeEnabled =
                      _slowModeEnabledOverride ?? remoteSlowEnabled;
                  final slowModeDurationSec =
                      _slowModeDurationOverride ?? remoteSlowDuration;

                  if (_slowModeEnabledOverride != null &&
                      _slowModeEnabledOverride == remoteSlowEnabled &&
                      (_slowModeDurationOverride ?? 0) == remoteSlowDuration) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      if (_slowModeEnabledOverride == null &&
                          _slowModeDurationOverride == null) {
                        return;
                      }
                      setState(() {
                        _slowModeEnabledOverride = null;
                        _slowModeDurationOverride = null;
                      });
                    });
                  }

                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 24, bottom: 14),
                          child: Column(
                            children: [
                              FutureBuilder<ImageProvider?>(
                                future: _photoBytesOverride != null
                                    ? Future.value(
                                        MemoryImage(_photoBytesOverride!),
                                      )
                                    : _avatarFutureFor(
                                        _photoUrlOverride ?? photoUrl,
                                      ),
                                builder: (context, imgSnap) {
                                  final img = imgSnap.data;
                                  final avatar = _GroupAvatar84(
                                    image: img,
                                    name: name,
                                  );
                                  if (!canEditInfo) return avatar;
                                  return GestureDetector(
                                    onTap: _uploadingPhoto
                                        ? null
                                        : () => _showGroupPhotoPicker(
                                            _photoUrlOverride ?? photoUrl,
                                          ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        avatar,
                                        Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            width: 26,
                                            height: 26,
                                            decoration: BoxDecoration(
                                              color: isLight
                                                  ? theme.colorScheme.surface
                                                  : const Color(0xFF1A1A1A),
                                              borderRadius:
                                                  BorderRadius.circular(13),
                                              border: Border.all(
                                                color: isLight
                                                    ? Colors.black.withOpacity(
                                                        0.08,
                                                      )
                                                    : const Color(0xFF2A2A2A),
                                                width: 1,
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.camera_alt_outlined,
                                              size: 14,
                                              color: isLight
                                                  ? theme.colorScheme.onSurface
                                                        .withOpacity(0.8)
                                                  : Colors.white70,
                                            ),
                                          ),
                                        ),
                                        if (_uploadingPhoto)
                                          Container(
                                            width: 84,
                                            height: 84,
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(
                                                0.35,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(42),
                                            ),
                                            child: const Center(
                                              child: SizedBox(
                                                width: 22,
                                                height: 22,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(Colors.white),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
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
                                '${activeMembers.length} members',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isLight
                                      ? theme.colorScheme.primary
                                      : const Color(0xFF8A8A8A),
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
                                                title: const Text(
                                                  'Mute 8 hours',
                                                ),
                                                onTap: () => Navigator.pop(
                                                  ctx,
                                                  const Duration(hours: 8),
                                                ),
                                              ),
                                              ListTile(
                                                leading: const Icon(
                                                  Icons.volume_off_outlined,
                                                ),
                                                title: const Text(
                                                  'Mute 1 week',
                                                ),
                                                onTap: () => Navigator.pop(
                                                  ctx,
                                                  const Duration(days: 7),
                                                ),
                                              ),
                                              ListTile(
                                                leading: const Icon(
                                                  Icons.volume_off_outlined,
                                                ),
                                                title: const Text(
                                                  'Mute forever',
                                                ),
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
                                    ? () => _openAddPeople(activeMembers)
                                    : () {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'You are not allowed to perform this action',
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
                                memberIds: visibleMembers,
                                canManage: isAdmin,
                                myRole: role,
                                onAdd: canAddMembers
                                    ? () => _openAddPeople(activeMembers)
                                    : null,
                                controller: _memberSearchCtrl,
                                onOptimisticRemove: (targetUid) {
                                  if (_optimisticallyRemovedMemberIds.contains(
                                    targetUid,
                                  )) {
                                    return;
                                  }
                                  setState(() {
                                    _removingMemberIds.add(targetUid);
                                  });

                                  Future.delayed(
                                    const Duration(milliseconds: 220),
                                    () {
                                      if (!mounted) return;
                                      setState(() {
                                        _removingMemberIds.remove(targetUid);
                                        _optimisticallyRemovedMemberIds.add(
                                          targetUid,
                                        );
                                      });
                                    },
                                  );
                                },
                                onOptimisticRemoveRollback: (targetUid) {
                                  if (!mounted) return;
                                  setState(() {
                                    _removingMemberIds.remove(targetUid);
                                    _optimisticallyRemovedMemberIds.remove(
                                      targetUid,
                                    );
                                  });
                                },
                                isRemoving: (uid) =>
                                    _removingMemberIds.contains(uid),
                              ),
                              if ((perms['adminsCanApproveMembers'] == true) &&
                                  isAdmin) ...[
                                const SizedBox(height: 18),
                                _JoinRequestsSection(chatId: widget.chatId),
                              ],
                              const SizedBox(height: 18),
                              const _SectionHeader(title: 'Moderation'),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isLight
                                      ? theme.colorScheme.surface
                                      : const Color(0xFF111111),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isLight
                                        ? Colors.black.withOpacity(0.05)
                                        : const Color(0xFF222222),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Slow Mode',
                                            style: TextStyle(
                                              color: isLight
                                                  ? theme.colorScheme.onSurface
                                                  : Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Switch(
                                          value: slowModeEnabled,
                                          activeColor:
                                              theme.colorScheme.primary,
                                          onChanged: !isAdmin
                                              ? null
                                              : (v) {
                                                  final nextDur =
                                                      slowModeDurationSec <= 0
                                                      ? 10
                                                      : slowModeDurationSec;
                                                  _setSlowMode(
                                                    enabled: v,
                                                    durationSec: nextDur,
                                                  );
                                                },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _SlowModeChip(
                                          label: '5s',
                                          selected:
                                              slowModeEnabled &&
                                              slowModeDurationSec == 5,
                                          enabled: isAdmin && slowModeEnabled,
                                          onTap: () => _setSlowMode(
                                            enabled: true,
                                            durationSec: 5,
                                          ),
                                        ),
                                        _SlowModeChip(
                                          label: '10s',
                                          selected:
                                              slowModeEnabled &&
                                              slowModeDurationSec == 10,
                                          enabled: isAdmin && slowModeEnabled,
                                          onTap: () => _setSlowMode(
                                            enabled: true,
                                            durationSec: 10,
                                          ),
                                        ),
                                        _SlowModeChip(
                                          label: '30s',
                                          selected:
                                              slowModeEnabled &&
                                              slowModeDurationSec == 30,
                                          enabled: isAdmin && slowModeEnabled,
                                          onTap: () => _setSlowMode(
                                            enabled: true,
                                            durationSec: 30,
                                          ),
                                        ),
                                        _SlowModeChip(
                                          label: '1m',
                                          selected:
                                              slowModeEnabled &&
                                              slowModeDurationSec == 60,
                                          enabled: isAdmin && slowModeEnabled,
                                          onTap: () => _setSlowMode(
                                            enabled: true,
                                            durationSec: 60,
                                          ),
                                        ),
                                        _SlowModeChip(
                                          label: '5m',
                                          selected:
                                              slowModeEnabled &&
                                              slowModeDurationSec == 300,
                                          enabled: isAdmin && slowModeEnabled,
                                          onTap: () => _setSlowMode(
                                            enabled: true,
                                            durationSec: 300,
                                          ),
                                        ),
                                        _SlowModeChip(
                                          label: '15m',
                                          selected:
                                              slowModeEnabled &&
                                              slowModeDurationSec == 900,
                                          enabled: isAdmin && slowModeEnabled,
                                          onTap: () => _setSlowMode(
                                            enabled: true,
                                            durationSec: 900,
                                          ),
                                        ),
                                        _SlowModeChip(
                                          label: 'Custom',
                                          selected: false,
                                          enabled: isAdmin && slowModeEnabled,
                                          onTap: () async {
                                            final ctrl =
                                                TextEditingController();
                                            final raw = await showDialog<String>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text(
                                                  'Custom slow mode (seconds)',
                                                ),
                                                content: TextField(
                                                  controller: ctrl,
                                                  keyboardType:
                                                      TextInputType.number,
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(ctx),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          ctrl.text.trim(),
                                                        ),
                                                    child: const Text('Set'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (raw == null) return;
                                            final sec = int.tryParse(raw) ?? 0;
                                            const maxSeconds =
                                                300; // 5 minutes max
                                            if (sec <= 0 || sec > maxSeconds) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Please enter a value between 1 and ${maxSeconds}s (5 minutes)',
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                            _setSlowMode(
                                              enabled: true,
                                              durationSec: sec,
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                    if (!isAdmin)
                                      Padding(
                                        padding: EdgeInsets.only(top: 10),
                                        child: Text(
                                          'Only admins can change moderation settings',
                                          style: TextStyle(
                                            color: isLight
                                                ? theme.colorScheme.onSurface
                                                      .withOpacity(0.6)
                                                : const Color(0xFF8A8A8A),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              _SettingsTile(
                                icon: Icons.dashboard_outlined,
                                title: 'Moderation Dashboard',
                                onTap: isAdmin
                                    ? () => Navigator.pushNamed(
                                        context,
                                        '/moderation-dashboard',
                                        arguments: {'chatId': widget.chatId},
                                      )
                                    : null,
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
                                onTap: null,
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
                                onShare: inviteLink == null
                                    ? null
                                    : () => _shareInviteLink(
                                        groupData: data,
                                        inviteLink: inviteLink,
                                      ),
                                onRotate: () => _rotateInvite(groupData: data),
                                onRevoke: () => _revokeInvite(groupData: data),
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
                                onTap: isOwner ? () => _deleteGroup() : null,
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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isLight ? theme.colorScheme.onBackground : Colors.white,
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
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: isLight ? theme.colorScheme.surface : const Color(0xFF101010),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight
              ? Colors.black.withOpacity(0.05)
              : const Color(0xFF1A1A1A),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: isLight
              ? theme.colorScheme.onSurface.withOpacity(0.6)
              : const Color(0xFFA5A5A5),
        ),
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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isLight ? theme.colorScheme.surface : const Color(0xFF141414),
        image: image == null
            ? null
            : DecorationImage(image: image!, fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: image != null
          ? null
          : Text(
              _initials(name),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isLight ? theme.colorScheme.onSurface : Colors.white,
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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
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
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isLight
                      ? theme.colorScheme.onBackground
                      : Colors.white,
                ),
              ),
            ),
            if (enabled) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.edit,
                size: 16,
                color: isLight
                    ? theme.colorScheme.onSurface.withOpacity(0.7)
                    : const Color(0xFFA0A0A0),
              ),
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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
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
                  color: isLight
                      ? theme.colorScheme.onBackground.withOpacity(0.6)
                      : (isPlaceholder
                            ? const Color(0xFF6F6F6F)
                            : const Color(0xFFA5A5A5)),
                  height: 1.25,
                ),
              ),
            ),
            if (enabled) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.edit_outlined,
                size: 16,
                color: isLight
                    ? theme.colorScheme.onSurface.withOpacity(0.7)
                    : const Color(0xFFA0A0A0),
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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isLight ? theme.colorScheme.surface : const Color(0xFF111111),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isLight
              ? Colors.black.withOpacity(0.05)
              : const Color(0xFF1A1A1A),
          width: 1,
        ),
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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isLight
                  ? theme.colorScheme.onSurface.withOpacity(0.7)
                  : const Color(0xFFA0A0A0),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isLight
                    ? theme.colorScheme.onSurface.withOpacity(0.6)
                    : const Color(0xFFA5A5A5),
              ),
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: isLight ? theme.colorScheme.surface : const Color(0xFF151515),
        child: FutureBuilder<String?>(
          future: _resolve(message.mediaUrl),
          builder: (context, snap) {
            final url = snap.data;
            final isVideo = message.messageType == MessageType.video;
            final isDoc = message.messageType == MessageType.file;

            Widget base;
            if (url == null || isDoc) {
              base = Container(
                color: isLight
                    ? theme.colorScheme.surface
                    : const Color(0xFF101010),
                alignment: Alignment.center,
                child: Icon(
                  isDoc
                      ? Icons.insert_drive_file_outlined
                      : Icons.image_outlined,
                  color: isLight
                      ? theme.colorScheme.onSurface.withOpacity(0.7)
                      : const Color(0xFFA0A0A0),
                  size: 22,
                ),
              );
            } else {
              base = CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (context, _) => Container(
                  color: isLight
                      ? theme.colorScheme.surface
                      : const Color(0xFF151515),
                ),
                errorWidget: (context, _, __) => Container(
                  color: isLight
                      ? theme.colorScheme.surface
                      : const Color(0xFF101010),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 22,
                    color: isLight
                        ? theme.colorScheme.onSurface.withOpacity(0.7)
                        : const Color(0xFFA0A0A0),
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
    final isLight = Theme.of(context).brightness == Brightness.light;
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
          child: Container(
            color: isLight ? Colors.grey.shade200 : const Color(0xFF151515),
          ),
        );
      },
    );
  }
}

class _MembersSection extends ConsumerStatefulWidget {
  final String chatId;
  final List<String> memberIds;
  final bool canManage;
  final String? myRole;
  final VoidCallback? onAdd;
  final TextEditingController controller;
  final void Function(String targetUid)? onOptimisticRemove;
  final void Function(String targetUid)? onOptimisticRemoveRollback;
  final bool Function(String uid)? isRemoving;
  const _MembersSection({
    required this.chatId,
    required this.memberIds,
    required this.canManage,
    required this.myRole,
    required this.onAdd,
    required this.controller,
    required this.onOptimisticRemove,
    required this.onOptimisticRemoveRollback,
    this.isRemoving,
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

    final fs = FirestoreService();
    final membersStream = fs.dmChats
        .doc(widget.chatId)
        .collection('members')
        .snapshots();

    final visible = <String>[];
    for (final id in widget.memberIds) {
      final u = ref
          .watch(userDocProvider(id))
          .maybeWhen(data: (x) => x, orElse: () => null);
      final name = ((u?.name ?? id)).trim().toLowerCase();
      if (q.isEmpty || name.contains(q)) visible.add(id);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: membersStream,
      builder: (context, snap) {
        final roleByUid = <String, String>{};
        final memberDataByUid = <String, Map<String, dynamic>>{};
        for (final d in snap.data?.docs ?? const []) {
          final uid = d.id;
          final data = d.data();
          memberDataByUid[uid] = data;
          final role = (data['role'] as String?) ?? '';
          if (role.isNotEmpty) roleByUid[uid] = role;
        }

        int roleRank(String? role) {
          final r = (role ?? '').toLowerCase();
          if (r == 'owner') return 0;
          if (r == 'admin') return 1;
          return 2;
        }

        String displayNameFor(String uid) {
          final u = ref
              .watch(userDocProvider(uid))
              .maybeWhen(data: (x) => x, orElse: () => null);
          return ((u?.name ?? uid)).trim().toLowerCase();
        }

        visible.sort((a, b) {
          final ar = roleRank(roleByUid[a]);
          final br = roleRank(roleByUid[b]);
          if (ar != br) return ar.compareTo(br);
          return displayNameFor(a).compareTo(displayNameFor(b));
        });

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
                color: Theme.of(context).brightness == Brightness.light
                    ? Theme.of(context).colorScheme.surface
                    : const Color(0xFF101010),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.black.withOpacity(0.05)
                      : const Color(0xFF1A1A1A),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: widget.controller,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.light
                      ? Theme.of(context).colorScheme.onSurface
                      : Colors.white,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  filled: Theme.of(context).brightness == Brightness.light,
                  fillColor: Theme.of(context).colorScheme.surface,
                  hintText: 'Search members',
                  hintStyle: TextStyle(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5)
                        : const Color(0xFF6F6F6F),
                  ),
                  border: InputBorder.none,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
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
                    key: ValueKey(id),
                    chatId: widget.chatId,
                    userId: id,
                    canManage: widget.canManage,
                    myRole: widget.myRole,
                    role: roleByUid[id],
                    memberData: memberDataByUid[id],
                    onOptimisticRemove: widget.onOptimisticRemove,
                    onOptimisticRemoveRollback:
                        widget.onOptimisticRemoveRollback,
                    isRemoving: widget.isRemoving?.call(id) ?? false,
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _MemberRow extends ConsumerWidget {
  final String chatId;
  final String userId;
  final bool canManage;
  final String? myRole;
  final String? role;
  final Map<String, dynamic>? memberData;
  final void Function(String targetUid)? onOptimisticRemove;
  final void Function(String targetUid)? onOptimisticRemoveRollback;
  final bool isRemoving;
  const _MemberRow({
    super.key,
    required this.chatId,
    required this.userId,
    required this.canManage,
    required this.myRole,
    required this.role,
    required this.memberData,
    required this.onOptimisticRemove,
    required this.onOptimisticRemoveRollback,
    required this.isRemoving,
  });

  Future<void> _openMemberActionsMenu(
    BuildContext buttonContext,
    WidgetRef ref,
  ) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    if (!canManage) return;
    if (userId == me) return;

    final effectiveMyRole = (myRole ?? 'member').toLowerCase();
    final isOwner = effectiveMyRole == 'owner';
    final isAdmin = effectiveMyRole == 'owner' || effectiveMyRole == 'admin';
    if (!isAdmin) return;

    final targetRole = (role ?? 'member').toLowerCase();
    final targetIsOwner = targetRole == 'owner';

    final rawMuted = memberData ?? const <String, dynamic>{};
    final muteUntilTs = rawMuted['muteUntil'];
    final muteUntil = muteUntilTs is Timestamp ? muteUntilTs.toDate() : null;
    final isMutedFlag = rawMuted['isMuted'] as bool?;
    final muted =
        (isMutedFlag ?? (muteUntil != null)) &&
        (muteUntil == null || DateTime.now().isBefore(muteUntil));
    final bannedUntilTs = rawMuted['bannedUntil'];
    final bannedUntil = bannedUntilTs is Timestamp
        ? bannedUntilTs.toDate()
        : null;
    final isBanned =
        bannedUntil != null && DateTime.now().isBefore(bannedUntil);

    final canEditAdmin = isOwner && !targetIsOwner;
    final canRemove = !targetIsOwner;

    Future<Duration?> pickCustomDuration() async {
      final controller = TextEditingController();
      final picked = await showDialog<Duration?>(
        context: buttonContext,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Custom ban duration'),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Minutes',
                hintText: 'e.g. 90',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final raw = controller.text.trim();
                  final mins = int.tryParse(raw);
                  if (mins == null || mins <= 0) {
                    Navigator.pop(ctx);
                    return;
                  }
                  Navigator.pop(ctx, Duration(minutes: mins));
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      controller.dispose();
      return picked;
    }

    final selected = await showModalBottomSheet<String>(
      context: buttonContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        Widget handleBar() {
          return Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }

        Widget sectionTitle(String text) {
          return Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                letterSpacing: 1.2,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }

        Widget tile({
          required IconData icon,
          required String title,
          required String subtitle,
          required Color iconColor,
          required VoidCallback onTap,
          bool danger = false,
        }) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: danger
                  ? Colors.red.withOpacity(0.08)
                  : Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: Icon(icon, color: iconColor),
              title: Text(title),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: onTap,
            ),
          );
        }

        Future<void> openMutePicker() async {
          final res = await showModalBottomSheet<String>(
            context: ctx,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (innerCtx) {
              return SafeArea(
                child: DraggableScrollableSheet(
                  initialChildSize: 0.35,
                  minChildSize: 0.2,
                  maxChildSize: 0.6,
                  expand: false,
                  builder: (context, scrollController) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: Column(
                        children: [
                          handleBar(),
                          Expanded(
                            child: ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              children: [
                                sectionTitle('Mute'),
                                if (muted)
                                  tile(
                                    icon: Icons.volume_up_outlined,
                                    title: 'Unmute member',
                                    subtitle: 'Restore messaging permissions',
                                    iconColor: Colors.orange,
                                    onTap: () =>
                                        Navigator.pop(innerCtx, 'unmute'),
                                  )
                                else ...[
                                  tile(
                                    icon: Icons.volume_off_outlined,
                                    title: 'Mute 1 hour',
                                    subtitle: 'Restrict messaging temporarily',
                                    iconColor: Colors.orange,
                                    onTap: () =>
                                        Navigator.pop(innerCtx, 'mute_1h'),
                                  ),
                                  tile(
                                    icon: Icons.volume_off_outlined,
                                    title: 'Mute 24 hours',
                                    subtitle: 'Restrict messaging for a day',
                                    iconColor: Colors.orange,
                                    onTap: () =>
                                        Navigator.pop(innerCtx, 'mute_24h'),
                                  ),
                                  tile(
                                    icon: Icons.volume_off_outlined,
                                    title: 'Mute until unmuted',
                                    subtitle: 'Restrict messaging indefinitely',
                                    iconColor: Colors.orange,
                                    onTap: () =>
                                        Navigator.pop(innerCtx, 'mute_forever'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );

          if (res != null && ctx.mounted) {
            Navigator.pop(ctx, res);
          }
        }

        Future<void> openBanPicker() async {
          final res = await showModalBottomSheet<String>(
            context: ctx,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (innerCtx) {
              final until = bannedUntil;
              final untilText = until == null
                  ? null
                  : '${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}';
              return SafeArea(
                child: DraggableScrollableSheet(
                  initialChildSize: 0.45,
                  minChildSize: 0.25,
                  maxChildSize: 0.85,
                  expand: false,
                  builder: (context, scrollController) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: Column(
                        children: [
                          handleBar(),
                          Expanded(
                            child: ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              children: [
                                sectionTitle('Security'),
                                if (isBanned && untilText != null)
                                  tile(
                                    icon: Icons.timer_outlined,
                                    title: 'Banned until $untilText',
                                    subtitle: 'This member cannot rejoin yet',
                                    iconColor: Colors.deepPurple,
                                    danger: true,
                                    onTap: () {},
                                  ),
                                if (isBanned)
                                  tile(
                                    icon: Icons.check_circle_outline,
                                    title: 'Unban user',
                                    subtitle: 'Allow rejoining the group',
                                    iconColor: Colors.deepPurple,
                                    onTap: () =>
                                        Navigator.pop(innerCtx, 'unban'),
                                  )
                                else ...[
                                  tile(
                                    icon: Icons.block_outlined,
                                    title: 'Ban for 15 minutes',
                                    subtitle: 'Prevent rejoining temporarily',
                                    iconColor: Colors.deepPurple,
                                    danger: true,
                                    onTap: () =>
                                        Navigator.pop(innerCtx, 'ban_15m'),
                                  ),
                                  tile(
                                    icon: Icons.block_outlined,
                                    title: 'Ban for 1 hour',
                                    subtitle: 'Prevent rejoining temporarily',
                                    iconColor: Colors.deepPurple,
                                    danger: true,
                                    onTap: () =>
                                        Navigator.pop(innerCtx, 'ban_1h'),
                                  ),
                                  tile(
                                    icon: Icons.block_outlined,
                                    title: 'Ban for 24 hours',
                                    subtitle: 'Prevent rejoining for a day',
                                    iconColor: Colors.deepPurple,
                                    danger: true,
                                    onTap: () =>
                                        Navigator.pop(innerCtx, 'ban_24h'),
                                  ),
                                  tile(
                                    icon: Icons.edit_outlined,
                                    title: 'Custom duration',
                                    subtitle: 'Choose a custom ban duration',
                                    iconColor: Colors.deepPurple,
                                    onTap: () =>
                                        Navigator.pop(innerCtx, 'ban_custom'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );

          if (res != null && ctx.mounted) {
            Navigator.pop(ctx, res);
          }
        }

        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.45,
            minChildSize: 0.25,
            maxChildSize: 0.85,
            expand: false,
            builder: (context, scrollController) {
              final targetLabel = targetRole == 'admin'
                  ? 'Remove admin'
                  : 'Make admin';
              final targetSubtitle = targetRole == 'admin'
                  ? 'Revoke moderation privileges'
                  : 'Grant moderation privileges';

              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    handleBar(),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          sectionTitle('Moderation'),
                          tile(
                            icon: muted
                                ? Icons.volume_up_outlined
                                : Icons.volume_off_outlined,
                            title: muted ? 'Unmute member' : 'Mute member',
                            subtitle: muted
                                ? 'Restore messaging permissions'
                                : 'Restrict messaging temporarily',
                            iconColor: Colors.orange,
                            onTap: () async => openMutePicker(),
                          ),

                          const SizedBox(height: 10),

                          sectionTitle('Member Controls'),
                          if (canEditAdmin)
                            tile(
                              icon: Icons.admin_panel_settings_outlined,
                              title: targetLabel,
                              subtitle: targetSubtitle,
                              iconColor: Colors.blue,
                              onTap: () => Navigator.pop(
                                ctx,
                                targetRole == 'admin' ? 'demote' : 'promote',
                              ),
                            ),
                          if (canRemove)
                            tile(
                              icon: Icons.person_remove_outlined,
                              title: 'Remove member',
                              subtitle: 'Remove from group permanently',
                              iconColor: Colors.red,
                              danger: true,
                              onTap: () => Navigator.pop(ctx, 'remove'),
                            ),

                          const SizedBox(height: 10),

                          sectionTitle('Security'),
                          tile(
                            icon: Icons.block_outlined,
                            title: isBanned ? 'Manage ban' : 'Ban user',
                            subtitle: isBanned
                                ? 'This member is currently banned'
                                : 'Prevent rejoining group',
                            iconColor: Colors.deepPurple,
                            danger: true,
                            onTap: () async => openBanPicker(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    if (selected == null) return;

    Future<void> runMute(Timestamp? until, {required bool isMuted}) async {
      final messenger = ScaffoldMessenger.of(buttonContext);
      try {
        await ref
            .read(groupModerationServiceProvider)
            .setMute(
              chatId: chatId,
              targetUid: userId,
              isMuted: isMuted,
              until: until,
            );
        messenger.showSnackBar(const SnackBar(content: Text('Mute updated')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
    }

    Future<void> runRemove() async {
      final messenger = ScaffoldMessenger.of(buttonContext);
      onOptimisticRemove?.call(userId);
      try {
        await ref
            .read(groupModerationServiceProvider)
            .removeMember(chatId: chatId, targetUid: userId);
        messenger.showSnackBar(const SnackBar(content: Text('Member removed')));
      } catch (e) {
        onOptimisticRemoveRollback?.call(userId);
        final isPermissionError = e.toString().toLowerCase().contains(
          'permission',
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              isPermissionError
                  ? 'You are not allowed to perform this action'
                  : 'Action failed: $e',
            ),
          ),
        );
      }
    }

    Future<void> runSetAdmin(bool makeAdmin) async {
      final messenger = ScaffoldMessenger.of(buttonContext);
      try {
        await ref
            .read(groupModerationServiceProvider)
            .setAdmin(chatId: chatId, targetUid: userId, isAdmin: makeAdmin);
        messenger.showSnackBar(const SnackBar(content: Text('Role updated')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
    }

    Future<void> runBan(Duration duration) async {
      final messenger = ScaffoldMessenger.of(buttonContext);
      try {
        await ref
            .read(groupModerationServiceProvider)
            .banUser(
              chatId: chatId,
              userId: userId,
              duration: duration,
              performedBy: me,
            );
        messenger.showSnackBar(const SnackBar(content: Text('Member banned')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
    }

    Future<void> runUnban() async {
      final messenger = ScaffoldMessenger.of(buttonContext);
      try {
        await ref
            .read(groupModerationServiceProvider)
            .unbanUser(chatId: chatId, userId: userId);
        messenger.showSnackBar(
          const SnackBar(content: Text('Member unbanned')),
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
    }

    if (selected == 'unmute') {
      await runMute(null, isMuted: false);
    } else if (selected == 'mute_1h') {
      await runMute(
        Timestamp.fromDate(DateTime.now().add(const Duration(hours: 1))),
        isMuted: true,
      );
    } else if (selected == 'mute_24h') {
      await runMute(
        Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
        isMuted: true,
      );
    } else if (selected == 'mute_forever') {
      await runMute(null, isMuted: true);
    } else if (selected == 'ban_15m') {
      await runBan(const Duration(minutes: 15));
    } else if (selected == 'ban_1h') {
      await runBan(const Duration(hours: 1));
    } else if (selected == 'ban_24h') {
      await runBan(const Duration(hours: 24));
    } else if (selected == 'ban_custom') {
      final duration = await pickCustomDuration();
      if (duration != null) {
        await runBan(duration);
      }
    } else if (selected == 'unban') {
      await runUnban();
    } else if (selected == 'promote') {
      await runSetAdmin(true);
    } else if (selected == 'demote') {
      await runSetAdmin(false);
    } else if (selected == 'remove') {
      await runRemove();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userDocProvider(userId));
    final effectiveRole = (role ?? '').toLowerCase();

    final content = Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light
            ? Theme.of(context).colorScheme.surface
            : const Color(0xFF101010),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.light
              ? Colors.black.withOpacity(0.05)
              : const Color(0xFF1A1A1A),
          width: 1,
        ),
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
                    backgroundColor:
                        Theme.of(context).brightness == Brightness.light
                        ? Theme.of(context).colorScheme.surface
                        : const Color(0xFF141414),
                    child: pfp.isEmpty
                        ? Text(
                            name.characters.isNotEmpty
                                ? name.characters.first.toUpperCase()
                                : 'U',
                            style: TextStyle(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.light
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.white,
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
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).brightness == Brightness.light
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.white,
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
                if (effectiveRole == 'admin' || effectiveRole == 'owner')
                  _RoleBadge(role: effectiveRole),
              ],
            ),
          ),
          if (canManage)
            Builder(
              builder: (buttonContext) => IconButton(
                onPressed: () => _openMemberActionsMenu(buttonContext, ref),
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: Theme.of(context).brightness == Brightness.light
                      ? Theme.of(context).colorScheme.primary
                      : const Color(0xFFA0A0A0),
                ),
              ),
            ),
        ],
      ),
    );

    final row = AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: isRemoving ? 0.0 : 1.0,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: isRemoving ? const SizedBox(height: 0) : content,
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress: canManage
            ? () => _openMemberActionsMenu(context, ref)
            : null,
        child: row,
      ),
    );
  }
}

class _SlowModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _SlowModeChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = selected
        ? (isLight
              ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
              : const Color(0xFF1E2A3A))
        : (isLight
              ? Theme.of(context).colorScheme.surface
              : const Color(0xFF0F0F0F));
    final border = selected
        ? (isLight
              ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
              : const Color(0xFF2A4A7A))
        : (isLight ? Colors.black.withOpacity(0.05) : const Color(0xFF222222));
    final fg = enabled
        ? (isLight ? Theme.of(context).colorScheme.onSurface : Colors.white)
        : const Color(0xFF6F6F6F);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: border, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isOwner
            ? Theme.of(context).colorScheme.primary
            : (isLight
                  ? Theme.of(context).colorScheme.surface
                  : const Color(0xFF1E1E1E)),
        borderRadius: BorderRadius.circular(6),
        border: isLight
            ? Border.all(color: Colors.black.withOpacity(0.05))
            : null,
      ),
      child: Text(
        isOwner ? 'OWNER' : 'ADMIN',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isOwner
              ? Colors.white
              : (isLight
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.white),
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 52,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isLight ? theme.colorScheme.surface : const Color(0xFF101010),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isLight
                ? Colors.black.withOpacity(0.05)
                : const Color(0xFF1A1A1A),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isLight
                  ? theme.colorScheme.onSurface.withOpacity(0.7)
                  : const Color(0xFFA0A0A0),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: onTap == null
                      ? const Color(0xFF6F6F6F)
                      : (isLight ? theme.colorScheme.onSurface : Colors.white),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isLight
                  ? theme.colorScheme.primary
                  : const Color(0xFFA0A0A0),
              size: 20,
            ),
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
  final VoidCallback? onShare;
  final VoidCallback onRotate;
  final VoidCallback onRevoke;
  const _InviteLinkCard({
    required this.inviteLink,
    required this.isBusy,
    required this.onShowQr,
    required this.onCopy,
    required this.onShare,
    required this.onRotate,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final theme = Theme.of(context);
    final linkText = inviteLink ?? 'No invite link generated';
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: isLight ? theme.colorScheme.surface : const Color(0xFF101010),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight
              ? Colors.black.withOpacity(0.05)
              : const Color(0xFF1A1A1A),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invite Link',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isLight ? theme.colorScheme.onSurface : Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isLight
                  ? const Color(0xFFF3F4F6)
                  : const Color(0xFF141414),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isLight
                    ? const Color(0xFFE5E7EB)
                    : const Color(0xFF1F1F1F),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.link,
                  size: 16,
                  color: isLight
                      ? theme.colorScheme.onSurface.withOpacity(0.5)
                      : const Color(0xFF8A8A8A),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    linkText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isLight
                          ? theme.colorScheme.onSurface.withOpacity(0.6)
                          : const Color(0xFFA5A5A5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              IconButton(
                onPressed: onCopy,
                icon: Icon(
                  Icons.copy,
                  size: 18,
                  color: isLight
                      ? theme.colorScheme.onSurface.withOpacity(0.7)
                      : const Color(0xFFA0A0A0),
                ),
                tooltip: 'Copy',
              ),
              IconButton(
                onPressed: onShare,
                icon: Icon(
                  Icons.share_outlined,
                  size: 18,
                  color: isLight
                      ? theme.colorScheme.onSurface.withOpacity(0.7)
                      : const Color(0xFFA0A0A0),
                ),
                tooltip: 'Share',
              ),
              IconButton(
                onPressed: onShowQr,
                icon: Icon(
                  Icons.qr_code_2,
                  size: 18,
                  color: isLight
                      ? theme.colorScheme.onSurface.withOpacity(0.7)
                      : const Color(0xFFA0A0A0),
                ),
                tooltip: 'QR',
              ),
              OutlinedButton(
                onPressed: isBusy ? null : onRotate,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: isLight
                        ? Colors.black.withOpacity(0.05)
                        : const Color(0xFF1A1A1A),
                  ),
                  foregroundColor: isLight
                      ? theme.colorScheme.primary
                      : Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  isBusy
                      ? 'Generating...'
                      : (inviteLink == null ? 'Generate' : 'Generate new'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (inviteLink != null)
                OutlinedButton(
                  onPressed: isBusy ? null : onRevoke,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.redAccent.withOpacity(0.35)),
                    backgroundColor: Colors.redAccent.withOpacity(0.1),
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Revoke',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
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
          color: Colors.redAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.redAccent.withOpacity(0.35),
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
