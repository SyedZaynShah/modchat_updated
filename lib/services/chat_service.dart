import 'dart:typed_data';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message_model.dart';
import 'firestore_service.dart';
import 'storage_service.dart';

class ChatService {
  ChatService(this._fs);
  final FirestoreService _fs;
  final _auth = FirebaseAuth.instance;
  final _storage = StorageService();

  String chatIdFor(String a, String b) {
    final list = [a, b]..sort();
    return list.join('_');
  }

  Future<String> startOrOpenChat(String peerId) async {
    final me = _auth.currentUser!.uid;
    final members = [me, peerId]..sort();
    // Try to find existing chat with exact members match
    final existing = await _fs.dmChats
        .where('members', isEqualTo: members)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      return existing.docs.first.id;
    }
    final chatId = chatIdFor(me, peerId);
    final chatDoc = _fs.dmChats.doc(chatId);
    await chatDoc.set({
      'id': chatId,
      'type': 'dm',
      'members': members,
      'createdAt': FieldValue.serverTimestamp(),
      'lastActivityAt': FieldValue.serverTimestamp(),
      'lastMessage': null,
      'lastMessageType': null,
      'lastTimestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return chatId;
  }

  Future<String> createGroup({
    required String name,
    required List<String> memberIds,
    String? description,
    String? photoUrl,
  }) async {
    final me = _auth.currentUser!.uid;
    final members = <String>{...memberIds, me}.toList()..sort();
    if (members.length < 2) {
      throw ArgumentError('Group must have at least 2 members');
    }

    final chatRef = _fs.dmChats.doc();
    final chatId = chatRef.id;
    final now = FieldValue.serverTimestamp();

    // IMPORTANT: create the chat doc first. Many Firestore rule sets check
    // membership by reading the parent chat doc, and rules do not see
    // "pending" writes from the same transaction when evaluating a subcollection
    // create. Writing members docs in the same transaction can therefore cause
    // permission-denied.
    await FirebaseFirestore.instance.runTransaction((tx) async {
      tx.set(chatRef, {
        'id': chatId,
        'type': 'group',
        'name': name,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (description != null) 'description': description,
        'ownerId': me,
        'createdBy': me,
        'createdAt': now,
        'state': 'active',
        'members': members,
        'memberCount': members.length,
        'settings': {
          'threadsEnabled': true,
          'slowModeDurationSec': 0,
          'whoCanSend': 'all',
          'whoCanAddMembers': 'admins',
          'permissions': {
            'membersCanEditSettings': false,
            'membersCanSendMessages': true,
            'membersCanAddMembers': false,
            'membersCanInvite': false,
            'adminsCanApproveMembers': false,
            'adminsCanEditAdmins': true,
          },
        },
        'lastMessage': null,
        'lastMessageType': null,
        'lastTimestamp': now,
        'lastActivityAt': now,
      });
    });

    final batch = FirebaseFirestore.instance.batch();
    for (final uid in members) {
      final role = uid == me ? 'owner' : 'member';
      final memberRef = chatRef.collection('members').doc(uid);
      batch.set(memberRef, {
        'userId': uid,
        'role': role,
        'joinedAt': now,
        'muteUntil': null,
        'lastSentAt': null,
        'isBanned': false,
      });
    }
    await batch.commit();

    return chatId;
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> streamChats(
    String uid,
  ) {
    return _fs.dmChats
        .where('members', arrayContains: uid)
        .orderBy('lastTimestamp', descending: true)
        .snapshots()
        .map((s) => s.docs)
        .distinct((prev, next) {
          if (identical(prev, next)) return true;
          if (prev.length != next.length) return false;
          for (var i = 0; i < prev.length; i++) {
            final a = prev[i];
            final b = next[i];
            if (a.id != b.id) return false;
            final at = a.data()['lastTimestamp'];
            final bt = b.data()['lastTimestamp'];
            if ('$at' != '$bt') return false;
          }
          return true;
        });
  }

  Stream<List<MessageModel>> streamMessages(String chatId) {
    final uid = _auth.currentUser?.uid;
    return _fs
        .messages(chatId)
        .orderBy('timestamp', descending: false)
        .snapshots(includeMetadataChanges: true)
        .map((s) {
          final docs = s.docs.where((d) {
            final data = d.data();
            final visibleTo = List<String>.from(
              (data['visibleTo'] as List?) ?? const [],
            );
            if (visibleTo.isNotEmpty) {
              return uid == null ? true : visibleTo.contains(uid);
            }
            final deletedFor = List<String>.from(
              (data['deletedFor'] as List?) ?? const [],
            );
            final deleteForMap = Map<String, dynamic>.from(
              (data['deleteFor'] as Map?) ?? const {},
            );
            final hiddenByMap = uid == null
                ? false
                : (deleteForMap[uid] == true);
            return uid == null
                ? true
                : (!deletedFor.contains(uid) && !hiddenByMap);
          });
          return docs.map((d) => MessageModel.fromDoc(d)).toList();
        })
        .distinct((prev, next) {
          if (prev.length != next.length) return false;
          for (var i = 0; i < prev.length; i++) {
            final a = prev[i];
            final b = next[i];
            if (a.id != b.id) return false;
            if (a.status != b.status) return false;
            if (a.isSeen != b.isSeen) return false;
            if (a.edited != b.edited) return false;
            if (a.isDeletedForAll != b.isDeletedForAll) return false;
            if ('${a.text}' != '${b.text}') return false;
            if ('${a.mediaUrl}' != '${b.mediaUrl}') return false;
            if ('${a.reactions}' != '${b.reactions}') return false;
            if (a.hasPendingWrites != b.hasPendingWrites) return false;
          }
          return true;
        });
  }

  Future<void> toggleReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    final uid = _auth.currentUser!.uid;
    final ref = _fs.messages(chatId).doc(messageId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final isDeletedForAll =
          (data['isDeletedForAll'] as bool?) ??
          (data['deletedForEveryone'] as bool?) ??
          false;
      if (isDeletedForAll) return;

      final raw =
          (data['reactions'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};

      bool hadSameEmoji = false;
      final keys = raw.keys.map((e) => '$e').toList();
      for (final k in keys) {
        final current = raw[k];
        if (current is! List) continue;
        final list = current.map((e) => '$e').toList();
        if (k == emoji && list.contains(uid)) {
          hadSameEmoji = true;
        }
        list.removeWhere((e) => e == uid);
        if (list.isEmpty) {
          raw.remove(k);
        } else {
          raw[k] = list;
        }
      }

      if (!hadSameEmoji) {
        final current = raw[emoji];
        final list = <String>[];
        if (current is List) {
          list.addAll(current.map((e) => '$e'));
        }
        if (!list.contains(uid)) list.add(uid);
        raw[emoji] = list;
      }

      tx.update(ref, {'reactions': raw});
    });
  }

  Future<void> togglePinMessage({
    required String chatId,
    required String messageId,
    int limit = 5,
  }) async {
    final uid = _auth.currentUser!.uid;
    final chatRef = _fs.dmChats.doc(chatId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(chatRef);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;

      final type = (data['type'] as String?) ?? 'dm';
      final members = List<String>.from((data['members'] as List?) ?? const []);

      if (type != 'group') {
        if (!members.contains(uid)) {
          throw Exception('Not authorized to pin messages in this chat');
        }
      } else {
        final roleRef = chatRef.collection('members').doc(uid);
        final roleSnap = await tx.get(roleRef);
        final role =
            (roleSnap.data() as Map<String, dynamic>?)?['role'] as String?;
        final isAdmin = role == 'owner' || role == 'admin';
        if (!isAdmin) {
          final msgRef = _fs.messages(chatId).doc(messageId);
          final msgSnap = await tx.get(msgRef);
          if (!msgSnap.exists) {
            throw Exception('Message not found');
          }
          final msgData = msgSnap.data() as Map<String, dynamic>;
          final senderId = msgData['senderId'] as String?;
          if (senderId != uid) {
            throw Exception('Not authorized to pin this message');
          }
        }
      }

      final raw = (data['pinnedMessages'] as List?) ?? const [];
      final pinned = <Map<String, dynamic>>[];

      for (final e in raw) {
        if (e is String) {
          pinned.add({
            'messageId': e,
            'pinnedBy': '',
            'pinnedAt': Timestamp.fromMillisecondsSinceEpoch(0),
          });
        } else if (e is Map) {
          final m = e.cast<String, dynamic>();
          final mid = (m['messageId'] as String?) ?? '';
          if (mid.isEmpty) continue;
          pinned.add({
            'messageId': mid,
            'pinnedBy': (m['pinnedBy'] as String?) ?? '',
            'pinnedAt':
                m['pinnedAt'] ?? Timestamp.fromMillisecondsSinceEpoch(0),
          });
        }
      }

      final alreadyPinned = pinned.any((p) => p['messageId'] == messageId);
      if (alreadyPinned) {
        pinned.removeWhere((p) => p['messageId'] == messageId);
      } else {
        pinned.insert(0, {
          'messageId': messageId,
          'pinnedBy': uid,
          'pinnedAt': Timestamp.now(),
        });
        if (pinned.length > limit) {
          pinned.removeRange(limit, pinned.length);
        }
      }

      tx.update(chatRef, {'pinnedMessages': pinned});
    });
  }

  Future<void> forwardExistingMessageToChat({
    required MessageModel source,
    required String targetChatId,
  }) async {
    final uid = _auth.currentUser!.uid;
    final chatSnap = await _fs.dmChats.doc(targetChatId).get();
    if (!chatSnap.exists) return;
    final chat = chatSnap.data() as Map<String, dynamic>;
    final members = List<String>.from((chat['members'] as List?) ?? const []);
    final type = (chat['type'] as String?) ?? 'dm';

    String receiverId = '';
    if (type != 'group') {
      receiverId = members.firstWhere((m) => m != uid, orElse: () => '');
    }

    final msgRef = _fs.messages(targetChatId).doc();
    final now = FieldValue.serverTimestamp();

    final mediaType = source.messageType == MessageType.text
        ? null
        : source.messageType.name;

    await msgRef.set({
      'chatId': targetChatId,
      'senderId': uid,
      'receiverId': receiverId,
      'text': source.messageType == MessageType.text
          ? (source.text ?? '')
          : null,
      'mediaUrl': source.messageType == MessageType.text
          ? null
          : source.mediaUrl,
      'mediaType': mediaType,
      'mediaSize': source.mediaSize,
      'timestamp': now,
      'isSeen': false,
      'status': 1,
      'members': members,
      'visibleTo': members,
      'deletedFor': <String>[],
      'edited': false,
      'isDeletedForAll': false,
      'forwarded': true,
      'originalSender': source.senderId,
      'originalMessageId': source.id,
    });

    await _fs.dmChats.doc(targetChatId).update({
      'lastMessage': source.messageType == MessageType.text
          ? (source.text ?? '')
          : source.messageType.name,
      'lastMessageType': source.messageType == MessageType.text
          ? 'text'
          : source.messageType.name,
      'lastTimestamp': now,
      'lastActivityAt': now,
    });
  }

  Future<void> sendText({
    required String chatId,
    required String peerId,
    required String text,
    Map<String, dynamic>? replyTo,
  }) async {
    final uid = _auth.currentUser!.uid;
    final doc = _fs.messages(chatId).doc();
    final now = FieldValue.serverTimestamp();
    await doc.set({
      'chatId': chatId,
      'senderId': uid,
      'receiverId': peerId,
      'text': text,
      'mediaUrl': null,
      'mediaType': null,
      if (replyTo != null) 'replyTo': replyTo,
      'timestamp': now,
      'isSeen': false,
      'status': 1,
      'members': [uid, peerId],
      'visibleTo': [uid, peerId],
      'deletedFor': <String>[],
      'edited': false,
      'isDeletedForAll': false,
    });
    await _fs.dmChats.doc(chatId).update({
      'lastMessage': text,
      'lastMessageType': 'text',
      'lastTimestamp': now,
      'lastActivityAt': now,
    });
  }

  Future<void> sendMedia({
    required String chatId,
    required String peerId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required MessageType type,
    int? audioDurationMs,
    Map<String, dynamic>? replyTo,
  }) async {
    final uid = _auth.currentUser!.uid;
    final msgRef = _fs.messages(chatId).doc();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = _extOf(fileName);
    final path = 'chatMedia/$chatId/$uid/$ts${ext.isNotEmpty ? '.$ext' : ''}';
    final bucket = switch (type) {
      MessageType.audio => _storage.audioBucket,
      _ => _storage.mediaBucket,
    };
    final now = FieldValue.serverTimestamp();
    final mediaType = _mediaTypeFor(fileName, contentType, type);

    // Optimistic: write message doc immediately so it appears in the UI.
    await msgRef.set({
      'chatId': chatId,
      'senderId': uid,
      'receiverId': peerId,
      'text': null,
      'mediaUrl': path,
      'fileName': ext.isNotEmpty ? '$ts.$ext' : '$ts',
      'mediaType': mediaType,
      'mediaSize': bytes.length,
      if (type == MessageType.audio && audioDurationMs != null)
        'audioDurationMs': audioDurationMs,
      if (replyTo != null) 'replyTo': replyTo,
      'timestamp': now,
      'isSeen': false,
      'status': 1,
      'members': [uid, peerId],
      'visibleTo': [uid, peerId],
      'deletedFor': <String>[],
      'edited': false,
      'isDeletedForAll': false,
      'uploadStatus': 'uploading',
    });

    await _fs.dmChats.doc(chatId).update({
      'lastMessage': type.name,
      'lastMessageType': type.name,
      'lastTimestamp': now,
      'lastActivityAt': now,
    });

    // Retry upload once on transient SocketException
    Future<void> doUpload() async {
      await _storage.uploadBytes(
        data: bytes,
        bucket: bucket,
        path: path,
        contentType: contentType,
      );
    }

    try {
      await doUpload();
      await msgRef.set({'uploadStatus': 'done'}, SetOptions(merge: true));
    } on SocketException {
      try {
        await Future.delayed(const Duration(milliseconds: 400));
        await doUpload();
        await msgRef.set({'uploadStatus': 'done'}, SetOptions(merge: true));
      } catch (e) {
        await msgRef.set({'uploadStatus': 'failed'}, SetOptions(merge: true));
        rethrow;
      }
    } catch (e) {
      await msgRef.set({'uploadStatus': 'failed'}, SetOptions(merge: true));
      rethrow;
    }
  }

  Future<void> sendGroupText({
    required String chatId,
    required List<String> memberIds,
    required String text,
    Map<String, dynamic>? replyTo,
  }) async {
    final uid = _auth.currentUser!.uid;
    final members = {...memberIds, uid}.toList()..sort();
    final doc = _fs.messages(chatId).doc();
    final now = FieldValue.serverTimestamp();
    await doc.set({
      'chatId': chatId,
      'senderId': uid,
      'receiverId': '',
      'text': text,
      'mediaUrl': null,
      'mediaType': null,
      if (replyTo != null) 'replyTo': replyTo,
      'timestamp': now,
      'isSeen': false,
      'status': 1,
      'members': members,
      'visibleTo': members,
      'deletedFor': <String>[],
      'edited': false,
      'isDeletedForAll': false,
    });
    await _fs.dmChats.doc(chatId).update({
      'lastMessage': text,
      'lastMessageType': 'text',
      'lastTimestamp': now,
      'lastActivityAt': now,
      'memberCount': members.length,
    });
  }

  Future<void> sendGroupMedia({
    required String chatId,
    required List<String> memberIds,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required MessageType type,
    int? audioDurationMs,
    Map<String, dynamic>? replyTo,
  }) async {
    final uid = _auth.currentUser!.uid;
    final members = {...memberIds, uid}.toList()..sort();
    final msgRef = _fs.messages(chatId).doc();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = _extOf(fileName);
    final path = 'chatMedia/$chatId/$uid/$ts${ext.isNotEmpty ? '.$ext' : ''}';
    final bucket = switch (type) {
      MessageType.audio => _storage.audioBucket,
      _ => _storage.mediaBucket,
    };
    final now = FieldValue.serverTimestamp();
    final mediaType = _mediaTypeFor(fileName, contentType, type);

    // Optimistic: write message doc immediately so it appears in the UI.
    await msgRef.set({
      'chatId': chatId,
      'senderId': uid,
      'receiverId': '',
      'text': null,
      'mediaUrl': path,
      'fileName': ext.isNotEmpty ? '$ts.$ext' : '$ts',
      'mediaType': mediaType,
      'mediaSize': bytes.length,
      if (type == MessageType.audio && audioDurationMs != null)
        'audioDurationMs': audioDurationMs,
      if (replyTo != null) 'replyTo': replyTo,
      'timestamp': now,
      'isSeen': false,
      'status': 1,
      'members': members,
      'visibleTo': members,
      'deletedFor': <String>[],
      'edited': false,
      'isDeletedForAll': false,
      'uploadStatus': 'uploading',
    });

    await _fs.dmChats.doc(chatId).update({
      'lastMessage': type.name,
      'lastMessageType': type.name,
      'lastTimestamp': now,
      'lastActivityAt': now,
      'memberCount': members.length,
    });

    Future<void> doUpload() async {
      await _storage.uploadBytes(
        data: bytes,
        bucket: bucket,
        path: path,
        contentType: contentType,
      );
    }

    try {
      await doUpload();
      await msgRef.set({'uploadStatus': 'done'}, SetOptions(merge: true));
    } on SocketException {
      try {
        await Future.delayed(const Duration(milliseconds: 400));
        await doUpload();
        await msgRef.set({'uploadStatus': 'done'}, SetOptions(merge: true));
      } catch (e) {
        await msgRef.set({'uploadStatus': 'failed'}, SetOptions(merge: true));
        rethrow;
      }
    } catch (e) {
      await msgRef.set({'uploadStatus': 'failed'}, SetOptions(merge: true));
      rethrow;
    }
  }

  Future<void> acknowledgeDelivered(String chatId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      final q = await _fs
          .messages(chatId)
          .where('receiverId', isEqualTo: uid)
          .where('deliveredAt', isNull: true)
          .get();
      for (final d in q.docs) {
        batch.update(d.reference, {
          'deliveredAt': FieldValue.serverTimestamp(),
          'status': 2,
        });
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return;
      rethrow;
    }
  }

  Future<void> markAllSeen(String chatId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      final q = await _fs
          .messages(chatId)
          .where('receiverId', isEqualTo: uid)
          .where('isSeen', isEqualTo: false)
          .get();
      for (final d in q.docs) {
        batch.update(d.reference, {
          'isSeen': true,
          'seenAt': FieldValue.serverTimestamp(),
          'status': 3,
        });
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return;
      rethrow;
    }
  }

  Future<void> editMessage({
    required String chatId,
    required String messageId,
    required String newText,
  }) async {
    final uid = _auth.currentUser!.uid;
    final ref = _fs.messages(chatId).doc(messageId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data() as Map<String, dynamic>;
    if (data['senderId'] != uid) {
      throw Exception('Not authorized to edit this message');
    }
    if ((data['forwarded'] as bool?) == true) {
      throw Exception('Forwarded messages cannot be edited');
    }
    await ref.update({
      'text': newText,
      'edited': true,
      'editedAt': FieldValue.serverTimestamp(),
    });
    await _refreshChatLastMessage(chatId);
  }

  Future<void> deleteForMe({
    required String chatId,
    required String messageId,
  }) async {
    final uid = _auth.currentUser!.uid;
    final userDoc = _fs.users.doc(uid);
    try {
      await userDoc.update({
        'hides.$chatId': FieldValue.arrayUnion([messageId]),
      });
    } catch (_) {
      await userDoc.set({
        'hides': {
          chatId: [messageId],
        },
      }, SetOptions(merge: true));
    }
    // Also persist on message doc so other clients/devices respect deletion
    final msgRef = _fs.messages(chatId).doc(messageId);
    try {
      await msgRef.set({
        'deletedFor': FieldValue.arrayUnion([uid]),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      // Many rule sets disallow non-sender updates. Hiding via userDoc is
      // sufficient for "Delete for me" across this client; do not error.
      if (e.code == 'permission-denied') return;
      rethrow;
    }
  }

  Future<void> deleteForEveryone({
    required String chatId,
    required String messageId,
  }) async {
    final ref = _fs.messages(chatId).doc(messageId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data() as Map<String, dynamic>;
    final uid = _auth.currentUser!.uid;
    if (data['senderId'] != uid) {
      throw Exception('Not authorized to delete this message for everyone');
    }
    await ref.update({
      'isDeletedForAll': true,
      'deletedForEveryone': true, // compatibility flag
      'text': '',
      'mediaUrl': null,
      'mediaType': null,
      'deletedAt': FieldValue.serverTimestamp(),
    });

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final chatRef = _fs.dmChats.doc(chatId);
        final chatSnap = await tx.get(chatRef);
        if (!chatSnap.exists) return;
        final data = chatSnap.data() as Map<String, dynamic>;
        final raw = (data['pinnedMessages'] as List?) ?? const [];
        if (raw.isEmpty) return;
        final next = <Map<String, dynamic>>[];
        for (final e in raw) {
          if (e is String) {
            if (e != messageId) {
              next.add({
                'messageId': e,
                'pinnedBy': '',
                'pinnedAt': Timestamp.fromMillisecondsSinceEpoch(0),
              });
            }
          } else if (e is Map) {
            final m = e.cast<String, dynamic>();
            final mid = (m['messageId'] as String?) ?? '';
            if (mid.isEmpty || mid == messageId) continue;
            next.add(m);
          }
        }
        tx.update(chatRef, {'pinnedMessages': next});
      });
    } catch (_) {}

    await _refreshChatLastMessage(chatId);
  }

  Future<void> _refreshChatLastMessage(String chatId) async {
    // Recompute last message snapshot based on latest non-deleted message
    final q = await _fs
        .messages(chatId)
        .orderBy('timestamp', descending: true)
        .limit(10)
        .get();

    String? lastText;
    String? lastType;
    FieldValue now = FieldValue.serverTimestamp();
    for (final d in q.docs) {
      final data = d.data();
      final deleted =
          (data['isDeletedForAll'] as bool?) == true ||
          (data['deletedForEveryone'] as bool?) == true;
      if (deleted) continue;
      final mediaType = (data['mediaType'] as String?)?.toLowerCase();
      final text = data['text'] as String?;
      if (mediaType == null || mediaType.isEmpty) {
        lastType = 'text';
        lastText = text ?? '';
      } else {
        lastType = mediaType;
        lastText = mediaType; // keep existing behavior for media previews
      }
      break;
    }
    await _fs.dmChats.doc(chatId).update({
      'lastMessage': lastText,
      'lastMessageType': lastType,
      'lastTimestamp': now,
      'lastActivityAt': now,
    });
  }

  Future<void> deleteChatPermanently(String chatId) async {
    try {
      // Delete messages in batches to respect Firestore limits
      const batchSize = 300;
      while (true) {
        final snap = await _fs.messages(chatId).limit(batchSize).get();
        if (snap.docs.isEmpty) break;
        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        if (snap.docs.length < batchSize) break;
      }
      await _fs.dmChats.doc(chatId).delete();
    } catch (e) {
      // If we cannot delete (e.g., insufficient permission), try hiding the chat for current user
      try {
        await hideChatForMe(chatId);
      } catch (_) {
        // Swallow to avoid crashing UI; caller may show error feedback.
      }
    }
  }

  Future<void> hideChatForMe(String chatId) async {
    final uid = _auth.currentUser!.uid;
    final userDoc = _fs.users.doc(uid);
    await userDoc.set({
      'hiddenChats': FieldValue.arrayUnion([chatId]),
    }, SetOptions(merge: true));
  }

  String _mediaTypeFor(String name, String contentType, MessageType type) {
    if (type == MessageType.image) return 'image';
    if (type == MessageType.video) return 'video';
    if (type == MessageType.audio) return 'audio';
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf') || contentType.contains('pdf')) return 'pdf';
    if (lower.endsWith('.doc') ||
        lower.endsWith('.docx') ||
        contentType.contains('msword') ||
        contentType.contains('officedocument.wordprocessingml')) {
      return 'doc';
    }
    if (lower.endsWith('.ppt') ||
        lower.endsWith('.pptx') ||
        contentType.contains('powerpoint')) {
      return 'ppt';
    }
    if (lower.endsWith('.zip') ||
        lower.endsWith('.rar') ||
        contentType.contains('zip') ||
        contentType.contains('rar')) {
      return 'zip';
    }
    return 'file';
  }

  String _extOf(String name) {
    final dot = name.lastIndexOf('.');
    return (dot != -1 && dot < name.length - 1)
        ? name.substring(dot + 1).toLowerCase()
        : '';
  }
}
