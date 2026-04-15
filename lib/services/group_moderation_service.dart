import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firestore_service.dart';

class GroupModerationService {
  final FirestoreService _fs;
  final FirebaseAuth _auth;

  GroupModerationService(this._fs, {FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> _chatRef(String chatId) =>
      _fs.dmChats.doc(chatId);

  CollectionReference<Map<String, dynamic>> _auditLogsRef(String chatId) =>
      _chatRef(chatId).collection('auditLogs');

  DocumentReference<Map<String, dynamic>> _memberRef(
    String chatId,
    String uid,
  ) => _chatRef(chatId).collection('members').doc(uid);

  Future<String> _displayName(String uid) async {
    try {
      final snap = await _fs.users.doc(uid).get();
      final raw = (snap.data()?['name'] as String?) ?? '';
      final name = raw.trim();
      return name.isNotEmpty ? name : uid;
    } catch (_) {
      return uid;
    }
  }

  Future<void> _writeSystemMessage({
    required String chatId,
    required String text,
    required String action,
    required String actorId,
    String? targetId,
  }) async {
    final doc = _fs.messages(chatId).doc();
    final now = FieldValue.serverTimestamp();
    final membersSnap = await _chatRef(chatId).get();
    final members = List<String>.from(
      ((membersSnap.data()?['members'] as List?) ?? const <dynamic>[]),
    );

    await doc.set({
      'chatId': chatId,
      'senderId': actorId,
      'receiverId': '',
      'type': 'system',
      'text': text,
      'createdAt': now,
      'timestamp': now,
      'meta': {
        'action': action,
        'actorId': actorId,
        if (targetId != null) 'targetId': targetId,
      },
      'members': members,
      'visibleTo': members,
      'deletedFor': <String>[],
      'edited': false,
      'isDeletedForAll': false,
      'status': 1,
      'isSeen': false,
    });
  }

  Future<void> _writeSystemMessageWithNames({
    required String chatId,
    required String action,
    required String actorId,
    String? targetId,
    required String Function(String actorName, String? targetName) buildText,
  }) async {
    final doc = _fs.messages(chatId).doc();
    final now = FieldValue.serverTimestamp();
    final membersSnap = await _chatRef(chatId).get();
    final members = List<String>.from(
      ((membersSnap.data()?['members'] as List?) ?? const <dynamic>[]),
    );

    // Optimistic: write immediately so UI updates with zero lag.
    await doc.set({
      'chatId': chatId,
      'senderId': actorId,
      'receiverId': '',
      'type': 'system',
      'text': buildText(actorId, targetId),
      'createdAt': now,
      'timestamp': now,
      'meta': {
        'action': action,
        'actorId': actorId,
        if (targetId != null) 'targetId': targetId,
      },
      'members': members,
      'visibleTo': members,
      'deletedFor': <String>[],
      'edited': false,
      'isDeletedForAll': false,
      'status': 1,
      'isSeen': false,
    });

    // Upgrade text to display names without blocking UI.
    () async {
      final actorName = await _displayName(actorId);
      final targetName = targetId == null ? null : await _displayName(targetId);
      final resolved = buildText(actorName, targetName);
      await doc.set({'text': resolved}, SetOptions(merge: true));
    }().catchError((_) {});
  }

  void _logAuditEvent({
    required String chatId,
    required String action,
    required String performedBy,
    String? targetUser,
    Map<String, dynamic>? extra,
  }) {
    _auditLogsRef(chatId)
        .doc()
        .set({
          'action': action,
          'performedBy': performedBy,
          if (targetUser != null) 'targetUser': targetUser,
          if (extra != null) ...extra,
          'timestamp': FieldValue.serverTimestamp(),
        })
        .catchError((_) {});
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamChat(String chatId) =>
      _chatRef(chatId).snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamMember(
    String chatId,
    String uid,
  ) => _memberRef(chatId, uid).snapshots();

  Future<void> recordMyLastSentAt({required String chatId}) async {
    await _memberRef(chatId, _uid).set({
      'lastSentAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String?> getMyRole(String chatId) async {
    final snap = await _memberRef(chatId, _uid).get();
    return (snap.data()?['role'] as String?) ?? (snap.exists ? 'member' : null);
  }

  Future<void> setSlowMode({
    required String chatId,
    required bool enabled,
    required int durationSec,
  }) async {
    final chatRef = _chatRef(chatId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final mySnap = await tx.get(_memberRef(chatId, _uid));
      final role = (mySnap.data()?['role'] as String?) ?? 'member';
      final isAdmin = role == 'owner' || role == 'admin';
      if (!isAdmin) {
        throw Exception('Not authorized');
      }

      tx.set(chatRef, {
        'moderation': {
          'slowModeEnabled': enabled,
          'slowModeDurationSec': enabled ? max(0, durationSec) : 0,
        },
      }, SetOptions(merge: true));
    });

    final label = enabled
        ? 'Slow mode enabled (${max(0, durationSec)}s)'
        : 'Slow mode disabled';
    _writeSystemMessage(
      chatId: chatId,
      text: label,
      action: 'slow_mode_change',
      actorId: _uid,
    ).catchError((_) {});
    _logAuditEvent(
      chatId: chatId,
      action: 'slow_mode_change',
      performedBy: _uid,
      extra: {
        'enabled': enabled,
        'durationSec': enabled ? max(0, durationSec) : 0,
      },
    );
  }

  Future<void> muteUser({
    required String chatId,
    required String targetUid,
    required Timestamp? until,
  }) async {
    final chatRef = _chatRef(chatId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final mySnap = await tx.get(_memberRef(chatId, _uid));
      final myRole = (mySnap.data()?['role'] as String?) ?? 'member';
      final isAdmin = myRole == 'owner' || myRole == 'admin';
      if (!isAdmin) throw Exception('Not authorized');

      final targetRef = _memberRef(chatId, targetUid);
      final targetSnap = await tx.get(targetRef);
      if (!targetSnap.exists) throw Exception('Member not found');

      final targetRole = (targetSnap.data()?['role'] as String?) ?? 'member';
      if (targetRole == 'owner') throw Exception('Cannot mute owner');

      tx.set(targetRef, {'muteUntil': until}, SetOptions(merge: true));
      tx.set(chatRef, {
        'moderation': {
          'mutedUsers': {
            targetUid: {'until': until},
          },
        },
      }, SetOptions(merge: true));
    });

    _writeSystemMessageWithNames(
      chatId: chatId,
      action: until == null ? 'unmute' : 'mute',
      actorId: _uid,
      targetId: targetUid,
      buildText: (actorName, targetName) {
        final t = targetName ?? targetUid;
        return until == null ? '$actorName unmuted $t' : '$actorName muted $t';
      },
    ).catchError((_) {});
    _logAuditEvent(
      chatId: chatId,
      action: until == null ? 'unmute' : 'mute',
      performedBy: _uid,
      targetUser: targetUid,
      extra: {'until': until},
    );
  }

  Future<void> setAdmin({
    required String chatId,
    required String targetUid,
    required bool isAdmin,
  }) async {
    final chatRef = _chatRef(chatId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final chatSnap = await tx.get(chatRef);
      if (!chatSnap.exists) throw Exception('Group not found');
      final data = chatSnap.data() ?? const <String, dynamic>{};
      final ownerId = (data['ownerId'] as String?) ?? '';

      final mySnap = await tx.get(_memberRef(chatId, _uid));
      final myRole = (mySnap.data()?['role'] as String?) ?? 'member';
      if (myRole != 'owner') throw Exception('Not authorized');

      if (targetUid == ownerId) return;

      final targetRef = _memberRef(chatId, targetUid);
      final targetSnap = await tx.get(targetRef);
      if (!targetSnap.exists) throw Exception('Member not found');

      tx.set(targetRef, {
        'role': isAdmin ? 'admin' : 'member',
      }, SetOptions(merge: true));

      if (isAdmin) {
        tx.set(chatRef, {
          'admins': FieldValue.arrayUnion([targetUid]),
        }, SetOptions(merge: true));
      } else {
        tx.set(chatRef, {
          'admins': FieldValue.arrayRemove([targetUid]),
        }, SetOptions(merge: true));
      }
    });

    _writeSystemMessageWithNames(
      chatId: chatId,
      action: isAdmin ? 'promote_admin' : 'demote_admin',
      actorId: _uid,
      targetId: targetUid,
      buildText: (actorName, targetName) {
        final t = targetName ?? targetUid;
        return isAdmin ? '$t is now an admin' : '$t is no longer an admin';
      },
    ).catchError((_) {});
    _logAuditEvent(
      chatId: chatId,
      action: isAdmin ? 'promote_admin' : 'demote_admin',
      performedBy: _uid,
      targetUser: targetUid,
    );
  }

  Future<void> removeMember({
    required String chatId,
    required String targetUid,
  }) async {
    final chatRef = _chatRef(chatId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final chatSnap = await tx.get(chatRef);
      if (!chatSnap.exists) throw Exception('Group not found');
      final data = chatSnap.data() ?? const <String, dynamic>{};
      final ownerId = (data['ownerId'] as String?) ?? '';

      final mySnap = await tx.get(_memberRef(chatId, _uid));
      final myRole = (mySnap.data()?['role'] as String?) ?? 'member';
      final isAdmin = myRole == 'owner' || myRole == 'admin';
      if (!isAdmin) throw Exception('Not authorized');

      if (targetUid == ownerId) throw Exception('Cannot remove owner');

      tx.update(chatRef, {
        'members': FieldValue.arrayRemove([targetUid]),
        'memberCount': FieldValue.increment(-1),
        'admins': FieldValue.arrayRemove([targetUid]),
      });
      tx.delete(_memberRef(chatId, targetUid));
    });

    _writeSystemMessageWithNames(
      chatId: chatId,
      action: 'remove_member',
      actorId: _uid,
      targetId: targetUid,
      buildText: (actorName, targetName) {
        final t = targetName ?? targetUid;
        return '$actorName removed $t';
      },
    ).catchError((_) {});
    _logAuditEvent(
      chatId: chatId,
      action: 'remove_member',
      performedBy: _uid,
      targetUser: targetUid,
    );
  }

  Future<void> leaveGroup({required String chatId}) async {
    final chatRef = _chatRef(chatId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final chatSnap = await tx.get(chatRef);
      if (!chatSnap.exists) return;
      final data = chatSnap.data() ?? const <String, dynamic>{};
      final ownerId = (data['ownerId'] as String?) ?? '';
      if (ownerId == _uid) throw Exception('Owner cannot leave group');

      tx.update(chatRef, {
        'members': FieldValue.arrayRemove([_uid]),
        'memberCount': FieldValue.increment(-1),
        'admins': FieldValue.arrayRemove([_uid]),
      });
      tx.delete(_memberRef(chatId, _uid));
    });
  }

  Future<void> deleteGroup({required String chatId}) async {
    final chatRef = _chatRef(chatId);
    final myRole = await getMyRole(chatId);
    if (myRole != 'owner') throw Exception('Not authorized');

    const batchSize = 300;

    while (true) {
      final snap = await chatRef.collection('messages').limit(batchSize).get();
      if (snap.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < batchSize) break;
    }

    while (true) {
      final snap = await chatRef.collection('members').limit(batchSize).get();
      if (snap.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < batchSize) break;
    }

    await chatRef.delete();
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

  Future<String> generateNewInvite({
    required String chatId,
    Timestamp? expiresAt,
  }) async {
    final myRole = await getMyRole(chatId);
    final isAdmin = myRole == 'owner' || myRole == 'admin';
    if (!isAdmin) throw Exception('Not authorized');

    final code = _randomToken(12);
    await _chatRef(chatId).set({
      'invite': {
        'code': code,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': expiresAt,
        'revoked': false,
      },
    }, SetOptions(merge: true));
    return code;
  }

  Future<void> revokeInvite({required String chatId}) async {
    final myRole = await getMyRole(chatId);
    final isAdmin = myRole == 'owner' || myRole == 'admin';
    if (!isAdmin) throw Exception('Not authorized');

    await _chatRef(chatId).set({
      'invite': {'revoked': true},
    }, SetOptions(merge: true));
  }

  Future<String?> joinByInviteCode({required String inviteCode}) async {
    final snap = await _fs.dmChats
        .where('type', isEqualTo: 'group')
        .where('invite.code', isEqualTo: inviteCode)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;

    final doc = snap.docs.first;
    final chatId = doc.id;
    final data = doc.data();

    final invite =
        (data['invite'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final revoked = (invite['revoked'] as bool?) ?? false;
    if (revoked) throw Exception('Invite revoked');

    final expiresAt = invite['expiresAt'];
    if (expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now())) {
      throw Exception('Invite expired');
    }

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final chatRef = _chatRef(chatId);
      final fresh = await tx.get(chatRef);
      if (!fresh.exists) throw Exception('Group not found');
      final d = fresh.data() ?? const <String, dynamic>{};
      final members = List<String>.from((d['members'] as List?) ?? const []);
      if (members.contains(_uid)) return;

      tx.update(chatRef, {
        'members': FieldValue.arrayUnion([_uid]),
        'memberCount': FieldValue.increment(1),
      });

      tx.set(_memberRef(chatId, _uid), {
        'role': 'member',
        'muteUntil': null,
        'lastSentAt': null,
      }, SetOptions(merge: true));
    });

    _writeSystemMessageWithNames(
      chatId: chatId,
      action: 'member_join',
      actorId: _uid,
      targetId: _uid,
      buildText: (_, targetName) {
        final t = targetName ?? _uid;
        return '$t joined the group';
      },
    ).catchError((_) {});
    _logAuditEvent(
      chatId: chatId,
      action: 'add_member',
      performedBy: _uid,
      targetUser: _uid,
    );

    return chatId;
  }
}
