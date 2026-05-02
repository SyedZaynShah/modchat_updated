import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/message_model.dart';
import 'firestore_service.dart';

class ChatService {
  ChatService(this._fs);
  final FirestoreService _fs;
  final _auth = FirebaseAuth.instance;

  String chatIdFor(String a, String b) {
    final list = [a, b]..sort();
    return list.join('_');
  }

  Future<String> startOrOpenChat(String peerId) async {
    final me = _auth.currentUser!.uid;
    final members = [me, peerId]..sort();
    final now = FieldValue.serverTimestamp();
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
      'lastRead': {me: now, peerId: now},
      'typing': {
        me: {'active': false, 'type': null, 'timestamp': now},
        peerId: {'active': false, 'type': null, 'timestamp': now},
      },
      'createdAt': now,
      'lastActivityAt': now,
      'lastMessage': null,
      'lastMessageType': null,
      'lastTimestamp': now,
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
        'lastRead': {for (final uid in members) uid: now},
        'typing': {
          for (final uid in members)
            uid: {'active': false, 'type': null, 'timestamp': now},
        },
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
        'removedAt': null, // null = currently active member
        'removeType': null,
        'removedBy': null,
        'muteUntil': null,
        'lastSentAt': null,
        'isBanned': false,
        'bannedUntil': null,
        'banReason': null,
      });
    }
    await batch.commit();

    return chatId;
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> streamChats(
    String uid,
  ) {
    print('chat_list_query:start uid=$uid');
    return _fs.dmChats
        .where('members', arrayContains: uid)
        .orderBy('lastTimestamp', descending: true)
        .limit(50)
        .snapshots()
        .handleError((error, stackTrace) {
          if (error is FirebaseException) {
            print(
              'chat_list_query:error code=${error.code} message=${error.message}',
            );
          } else {
            print('chat_list_query:error $error');
          }
        })
        .map((s) {
          print('chat_list_query:docs_received count=${s.docs.length}');
          final docs = s.docs
              .where((d) {
                final data = d.data();
                final members = data['members'];
                if (members is! List) {
                  print('chat_list_query:skip_invalid_members chatId=${d.id}');
                  return false;
                }
                return true;
              })
              .toList(growable: false);
          return docs;
        })
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
        .asyncMap((s) async {
          // Get member doc for timeline filtering
          Timestamp? joinedAt;
          Timestamp? removedAt;
          if (uid != null) {
            try {
              final memberSnap = await _fs.dmChats
                  .doc(chatId)
                  .collection('members')
                  .doc(uid)
                  .get();
              if (memberSnap.exists) {
                final mData = memberSnap.data() ?? {};
                joinedAt = mData['joinedAt'] as Timestamp?;
                removedAt = mData['removedAt'] as Timestamp?;
              }
            } catch (_) {
              // If member doc missing or error, allow all messages (fallback)
            }
          }

          final docs = s.docs.where((d) {
            final data = d.data();

            // Timeline filtering: only show messages within membership period
            final msgTimestamp = data['timestamp'] as Timestamp?;
            if (msgTimestamp != null && uid != null) {
              // If user has joinedAt, hide messages before join time
              if (joinedAt != null && msgTimestamp.compareTo(joinedAt) < 0) {
                return false;
              }
              // If user has been removed, hide only messages after removal time
              if (removedAt != null && msgTimestamp.compareTo(removedAt) > 0) {
                return false;
              }
            }

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
            if (a.text != b.text) return false;
            if (a.mediaUrl != b.mediaUrl) return false;
            if (a.uploadStatus != b.uploadStatus) return false;
            if (a.uploadProgress != b.uploadProgress) return false;
            if (a.localPath != b.localPath) return false;
            if (a.cachedPath != b.cachedPath) return false;
            if (a.thumbnailUrl != b.thumbnailUrl) return false;
            if (a.reactions != b.reactions) return false;
            if (a.hasPendingWrites != b.hasPendingWrites) return false;
          }
          return true;
        });
  }

  void _logMessageWrite(Map<String, dynamic> data) {
    print('MESSAGE WRITE $data');
  }

  Future<bool> _ensureMemberOrLog(String chatId) async {
    final uid = _auth.currentUser?.uid;
    print('SENDING MESSAGE:');
    print('uid: $uid');
    print('chatId: $chatId');
    if (uid == null) {
      print('❌ USER NOT MEMBER');
      return false;
    }

    final memberRef = _fs.dmChats.doc(chatId).collection('members').doc(uid);
    final memberDoc = await memberRef.get();
    if (memberDoc.exists) return true;

    final chatSnap = await _fs.dmChats.doc(chatId).get();
    if (!chatSnap.exists) {
      print('❌ USER NOT MEMBER');
      return false;
    }

    final data = chatSnap.data() ?? const <String, dynamic>{};
    final members = List<String>.from((data['members'] as List?) ?? const []);
    final type = (data['type'] as String?) ?? 'dm';
    if (!members.contains(uid)) {
      print('❌ USER NOT MEMBER');
      return false;
    }
    if (type == 'group') {
      // For groups, message create rules depend on members/{uid} existing.
      // After join/approve flows there can be a short race before the doc is readable.
      for (var i = 0; i < 4; i++) {
        await Future.delayed(const Duration(milliseconds: 220));
        final retry = await memberRef.get();
        if (retry.exists) return true;
      }
      print('❌ USER NOT MEMBER');
      return false;
    }
    return true;
  }

  void _validateOutboundMessagePayload(Map<String, dynamic> data) {
    if (!data.containsKey('createdAt') || data['createdAt'] == null) {
      throw Exception('createdAt missing');
    }
    if (!data.containsKey('senderId') ||
        data['senderId'] != _auth.currentUser?.uid) {
      throw Exception('senderId mismatch');
    }
    final mediaUrl = data['mediaUrl'];
    if (mediaUrl is String && mediaUrl.startsWith('file://')) {
      throw Exception('LOCAL FILE PATH DETECTED');
    }
    print('RULE CHECK senderId: ${data['senderId']}');
    if (mediaUrl is String) {
      print('MEDIA URL: $mediaUrl');
    }
  }

  Future<String> _uploadWithProgress({
    required String bucket,
    required String path,
    required String fileLabel,
    required Uint8List bytes,
    required String contentType,
    String? localFilePath,
    required void Function(double value) onProgress,
  }) async {
    print('Bucket: $bucket');
    print('Uploading to path: $path');
    print('Uploading file: $fileLabel');
    print('Uploading to: $bucket/$path');

    try {
      onProgress(0.0);
      final from = Supabase.instance.client.storage.from(bucket);
      late final String res;

      if (kIsWeb) {
        res = await from.uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: false,
            cacheControl: '3600',
          ),
        );
      } else {
        if (localFilePath == null || localFilePath.isEmpty) {
          print('FILE MISSING: $localFilePath');
          throw Exception('Invalid file path');
        }
        final file = File(localFilePath);
        final exists = await file.exists();
        print('Local file: ${file.path}');
        print('File exists: $exists');
        if (!exists) {
          print('FILE MISSING: $localFilePath');
          throw Exception('Invalid file path');
        }

        res = await from.upload(
          path,
          file,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: false,
            cacheControl: '3600',
          ),
        );
      }

      if (res.isEmpty) {
        print('UPLOAD FAILED: empty response');
        throw Exception('Upload failed');
      }

      print('UPLOAD SUCCESS: $res');
      onProgress(1.0);
      return '$bucket/$path';
    } catch (e) {
      print('UPLOAD ERROR: $e');
      rethrow;
    }
  }

  String getBucket({required bool isGroup, required String type}) {
    if (type == 'profile') return 'profilePictures';
    if (type == 'groupImage') return 'groupImages';
    return 'chatMedia';
  }

  /// Gets a stable public URL for a Supabase storage path.
  /// Returns null if bucket/path is invalid.
  String? getPublicUrl(String bucket, String path) {
    try {
      return Supabase.instance.client.storage.from(bucket).getPublicUrl(path);
    } catch (e) {
      print('Failed to get public URL: $e');
      return null;
    }
  }

  String sanitizeFileName(String name) {
    return name.replaceAll(' ', '_').replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '');
  }

  String _buildUniqueMediaPath({
    required String chatId,
    required String senderId,
    required String fileName,
    String? messageId,
  }) {
    final sanitizedName = sanitizeFileName(fileName);
    print('FILE NAME CLEANED: $sanitizedName');
    final unique =
        messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final path = '$chatId/${unique}_${senderId}_$sanitizedName';
    print('UPLOAD PATH: $path');
    return path;
  }

  Future<void> _markUploadFailed(
    DocumentReference<Map<String, dynamic>> msgRef,
  ) async {
    await msgRef.set({
      'status': 'failed',
      'uploadStatus': 'failed',
      'uploadProgress': 0.0,
      'mediaUrl': null,
    }, SetOptions(merge: true));
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
          (data['userReactions'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final userReactions = <String, String>{};
      raw.forEach((k, v) {
        final id = k.trim();
        final em = v.toString().trim();
        if (id.isEmpty || em.isEmpty) return;
        userReactions[id] = em;
      });

      final current = userReactions[uid];
      if (current == emoji) {
        userReactions.remove(uid);
      } else {
        userReactions[uid] = emoji;
      }

      tx.set(ref, {'userReactions': userReactions}, SetOptions(merge: true));
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
        final role = roleSnap.data()?['role'] as String?;
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
    if (!await _ensureMemberOrLog(targetChatId)) return;
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

    final payload = <String, dynamic>{
      'chatId': targetChatId,
      'senderId': uid,
      'receiverId': receiverId,
      if (source.messageType == MessageType.text) 'text': (source.text ?? ''),
      if (source.messageType != MessageType.text && source.mediaUrl != null)
        'mediaUrl': source.mediaUrl,
      if (source.messageType != MessageType.text && source.mediaPath != null)
        'mediaPath': source.mediaPath,
      if (source.messageType != MessageType.text && source.storagePath != null)
        'storagePath': source.storagePath,
      if (mediaType != null) 'mediaType': mediaType,
      if (source.mediaSize != null) 'mediaSize': source.mediaSize,
      'type': source.messageType.name,
      'createdAt': now,
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
    };
    _validateOutboundMessagePayload(payload);
    _logMessageWrite(payload);
    await msgRef.set(payload);

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
    if (!await _ensureMemberOrLog(chatId)) return;
    final uid = _auth.currentUser!.uid;
    final doc = _fs.messages(chatId).doc();
    final now = FieldValue.serverTimestamp();
    final payload = <String, dynamic>{
      'chatId': chatId,
      'senderId': uid,
      'receiverId': peerId,
      'text': text,
      'type': 'text',
      if (replyTo != null) 'replyTo': replyTo,
      'createdAt': now,
      'timestamp': now,
      'isSeen': false,
      'status': 1,
      'members': [uid, peerId],
      'visibleTo': [uid, peerId],
      'deletedFor': <String>[],
      'edited': false,
      'isDeletedForAll': false,
    };
    _validateOutboundMessagePayload(payload);
    _logMessageWrite(payload);
    await doc.set(payload);
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
    String? localPath,
    String? thumbnailPath,
    int? audioDurationMs,
    Map<String, dynamic>? replyTo,
  }) async {
    if (!await _ensureMemberOrLog(chatId)) return;
    final uid = _auth.currentUser!.uid;
    final msgRef = _fs.messages(chatId).doc();
    final ext = _extOf(fileName);
    final mediaType = _mediaTypeFor(fileName, contentType, type);
    final bucket = getBucket(isGroup: false, type: mediaType);
    final path = _buildUniqueMediaPath(
      chatId: chatId,
      senderId: uid,
      fileName: fileName,
      messageId: msgRef.id,
    );
    final mediaPath = '$bucket/$path';
    final now = FieldValue.serverTimestamp();

    // Optimistic: write message doc immediately so it appears in the UI.
    final payload = <String, dynamic>{
      'chatId': chatId,
      'senderId': uid,
      'receiverId': peerId,
      'mediaPath': mediaPath,
      'storagePath': path,
      'type': type.name,
      if (thumbnailPath != null) 'thumbnailUrl': thumbnailPath,
      'fileName': ext.isNotEmpty
          ? '${DateTime.now().millisecondsSinceEpoch}.$ext'
          : '${DateTime.now().millisecondsSinceEpoch}',
      'mediaType': mediaType,
      'mediaSize': bytes.length,
      if (type == MessageType.audio && audioDurationMs != null)
        'audioDurationMs': audioDurationMs,
      if (replyTo != null) 'replyTo': replyTo,
      'createdAt': now,
      'timestamp': now,
      'isSeen': false,
      'status': 1,
      'members': [uid, peerId],
      'visibleTo': [uid, peerId],
      'deletedFor': <String>[],
      'edited': false,
      'isDeletedForAll': false,
      'uploadStatus': 'uploading',
      'uploadProgress': 0.0,
    };
    _validateOutboundMessagePayload(payload);
    _logMessageWrite(payload);
    await msgRef.set(payload);
    print('MEDIA URL: $mediaPath');
    print('MEDIA PATH SAVED: $mediaPath');

    await _fs.dmChats.doc(chatId).update({
      'lastMessage': type.name,
      'lastMessageType': type.name,
      'lastTimestamp': now,
      'lastActivityAt': now,
    });

    Future<void> doUpload() async {
      if (localPath != null && localPath.isNotEmpty) {
        final file = File(localPath);
        final exists = await file.exists();
        if (!exists) {
          print('FILE DOES NOT EXIST: $localPath');
          throw Exception('Invalid file path');
        }
      }
      await _uploadWithProgress(
        bucket: bucket,
        path: path,
        fileLabel: localPath ?? fileName,
        bytes: bytes,
        contentType: contentType,
        localFilePath: localPath,
        onProgress: (value) {
          unawaited(
            msgRef.set({'uploadProgress': value}, SetOptions(merge: true)),
          );
        },
      );

      // Generate stable public URL after successful upload
      final publicUrl = getPublicUrl(bucket, path);

      await msgRef.set({
        'mediaPath': mediaPath,
        'storagePath': path,
        if (publicUrl != null) 'mediaUrl': publicUrl,
        'status': 1,
        'uploadStatus': 'done',
        'uploadProgress': 1.0,
        if (localPath != null && localPath.isNotEmpty) 'cachedPath': localPath,
      }, SetOptions(merge: true));
      print('MEDIA URL: $mediaPath');
      print('PUBLIC URL: $publicUrl');
    }

    try {
      await doUpload();
    } on SocketException {
      try {
        await Future.delayed(const Duration(milliseconds: 400));
        await doUpload();
      } catch (e) {
        print('UPLOAD ERROR: $e');
        await _markUploadFailed(msgRef);
        return;
      }
    } catch (e) {
      print('UPLOAD ERROR: $e');
      await _markUploadFailed(msgRef);
      return;
    }
  }

  Future<void> sendGroupText({
    required String chatId,
    required List<String> memberIds,
    required String text,
    Map<String, dynamic>? replyTo,
  }) async {
    if (!await _ensureMemberOrLog(chatId)) return;
    final uid = _auth.currentUser!.uid;
    final members = {...memberIds, uid}.toList()..sort();
    final doc = _fs.messages(chatId).doc();
    final now = FieldValue.serverTimestamp();
    final payload = <String, dynamic>{
      'chatId': chatId,
      'senderId': uid,
      'receiverId': '',
      'text': text,
      'type': 'text',
      if (replyTo != null) 'replyTo': replyTo,
      'createdAt': now,
      'timestamp': now,
      'isSeen': false,
      'status': 1,
      'members': members,
      'visibleTo': members,
      'deletedFor': <String>[],
      'edited': false,
      'isDeletedForAll': false,
    };
    _validateOutboundMessagePayload(payload);
    _logMessageWrite(payload);
    await doc.set(payload);
    await _fs.dmChats.doc(chatId).update({
      'lastMessage': text,
      'lastMessageType': 'text',
      'lastTimestamp': now,
      'lastActivityAt': now,
      'memberCount': members.length,
    });
    // Update per-user lastSentAt for slow mode tracking
    await _fs.dmChats.doc(chatId).collection('members').doc(uid).update({
      'lastSentAt': now,
    });
  }

  Future<void> sendGroupMedia({
    required String chatId,
    required List<String> memberIds,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required MessageType type,
    String? localPath,
    String? thumbnailPath,
    int? audioDurationMs,
    Map<String, dynamic>? replyTo,
  }) async {
    if (!await _ensureMemberOrLog(chatId)) return;
    final uid = _auth.currentUser!.uid;
    final members = {...memberIds, uid}.toList()..sort();
    final msgRef = _fs.messages(chatId).doc();
    final ext = _extOf(fileName);
    final mediaType = _mediaTypeFor(fileName, contentType, type);
    final bucket = getBucket(isGroup: true, type: mediaType);
    final path = _buildUniqueMediaPath(
      chatId: chatId,
      senderId: uid,
      fileName: fileName,
      messageId: msgRef.id,
    );
    final mediaPath = '$bucket/$path';
    final now = FieldValue.serverTimestamp();

    // Optimistic: write message doc immediately so it appears in the UI.
    final payload = <String, dynamic>{
      'chatId': chatId,
      'senderId': uid,
      'receiverId': '',
      'mediaPath': mediaPath,
      'storagePath': path,
      'type': type.name,
      if (thumbnailPath != null) 'thumbnailUrl': thumbnailPath,
      'fileName': ext.isNotEmpty
          ? '${DateTime.now().millisecondsSinceEpoch}.$ext'
          : '${DateTime.now().millisecondsSinceEpoch}',
      'mediaType': mediaType,
      'mediaSize': bytes.length,
      if (type == MessageType.audio && audioDurationMs != null)
        'audioDurationMs': audioDurationMs,
      if (replyTo != null) 'replyTo': replyTo,
      'createdAt': now,
      'timestamp': now,
      'isSeen': false,
      'status': 1,
      'members': members,
      'visibleTo': members,
      'deletedFor': <String>[],
      'edited': false,
      'isDeletedForAll': false,
      'uploadStatus': 'uploading',
      'uploadProgress': 0.0,
    };
    _validateOutboundMessagePayload(payload);
    _logMessageWrite(payload);
    await msgRef.set(payload);
    print('MEDIA URL: $mediaPath');
    print('MEDIA PATH SAVED: $mediaPath');

    await _fs.dmChats.doc(chatId).update({
      'lastMessage': type.name,
      'lastMessageType': type.name,
      'lastTimestamp': now,
      'lastActivityAt': now,
      'memberCount': members.length,
    });
    // Update per-user lastSentAt for slow mode tracking
    await _fs.dmChats.doc(chatId).collection('members').doc(uid).update({
      'lastSentAt': now,
    });

    Future<void> doUpload() async {
      if (localPath != null && localPath.isNotEmpty) {
        final file = File(localPath);
        final exists = await file.exists();
        if (!exists) {
          print('FILE DOES NOT EXIST: $localPath');
          throw Exception('Invalid file path');
        }
      }
      await _uploadWithProgress(
        bucket: bucket,
        path: path,
        fileLabel: localPath ?? fileName,
        bytes: bytes,
        contentType: contentType,
        localFilePath: localPath,
        onProgress: (value) {
          unawaited(
            msgRef.set({'uploadProgress': value}, SetOptions(merge: true)),
          );
        },
      );

      // Generate stable public URL after successful upload
      final publicUrl = getPublicUrl(bucket, path);

      await msgRef.set({
        'mediaPath': mediaPath,
        'storagePath': path,
        if (publicUrl != null) 'mediaUrl': publicUrl,
        'status': 1,
        'uploadStatus': 'done',
        'uploadProgress': 1.0,
        if (localPath != null && localPath.isNotEmpty) 'cachedPath': localPath,
      }, SetOptions(merge: true));
      print('MEDIA URL: $mediaPath');
      print('PUBLIC URL: $publicUrl');
    }

    try {
      await doUpload();
    } on SocketException {
      try {
        await Future.delayed(const Duration(milliseconds: 400));
        await doUpload();
      } catch (e) {
        print('UPLOAD ERROR: $e');
        await _markUploadFailed(msgRef);
        return;
      }
    } catch (e) {
      print('UPLOAD ERROR: $e');
      await _markUploadFailed(msgRef);
      return;
    }
  }

  Future<void> retryMediaUpload({required MessageModel message}) async {
    if (message.messageType == MessageType.text) {
      throw Exception('Cannot retry a text message');
    }
    final localPath = message.localPath;
    if (localPath == null || localPath.isEmpty) {
      print('Retry failed: file missing');
      await _markUploadFailed(_fs.messages(message.chatId).doc(message.id));
      return;
    }
    final file = File(localPath);
    final exists = await file.exists();
    print('Local file: ${file.path}');
    print('File exists: $exists');
    if (!exists) {
      print('Retry failed: file missing');
      await _markUploadFailed(_fs.messages(message.chatId).doc(message.id));
      return;
    }

    final bytes = await file.readAsBytes();
    final retryFileName = localPath.split(Platform.pathSeparator).last;
    final ext = _extOf(localPath);
    final mediaType = _mediaTypeFor('', '', message.messageType);
    final contentType = _contentTypeForMediaType(mediaType, ext);
    final isGroup = message.receiverId.isEmpty;
    final bucket = getBucket(isGroup: isGroup, type: mediaType);
    final uid = _auth.currentUser!.uid;
    // Always generate a fresh path on retry; never reuse previous broken path.
    final path = _buildUniqueMediaPath(
      chatId: message.chatId,
      senderId: uid,
      fileName: retryFileName,
      messageId: null,
    );
    final mediaPath = '$bucket/$path';

    final msgRef = _fs.messages(message.chatId).doc(message.id);
    await msgRef.set({
      'status': 1,
      'uploadStatus': 'uploading',
      'uploadProgress': 0.0,
      'mediaPath': mediaPath,
      'storagePath': path,
    }, SetOptions(merge: true));
    print('MEDIA PATH SAVED: $mediaPath');

    try {
      await _uploadWithProgress(
        bucket: bucket,
        path: path,
        fileLabel: localPath,
        bytes: bytes,
        contentType: contentType,
        localFilePath: localPath,
        onProgress: (value) {
          unawaited(
            msgRef.set({'uploadProgress': value}, SetOptions(merge: true)),
          );
        },
      );

      // Generate stable public URL after successful upload
      final publicUrl = getPublicUrl(bucket, path);

      await msgRef.set({
        'mediaPath': mediaPath,
        'storagePath': path,
        if (publicUrl != null) 'mediaUrl': publicUrl,
        'status': 1,
        'uploadStatus': 'done',
        'uploadProgress': 1.0,
        'cachedPath': localPath,
      }, SetOptions(merge: true));
    } catch (e) {
      print('UPLOAD ERROR: $e');
      await _markUploadFailed(msgRef);
      return;
    }
  }

  String _contentTypeForMediaType(String mediaType, String ext) {
    switch (mediaType) {
      case 'image':
        if (ext == 'png') return 'image/png';
        if (ext == 'webp') return 'image/webp';
        return 'image/jpeg';
      case 'video':
        if (ext == 'webm') return 'video/webm';
        if (ext == 'mov') return 'video/quicktime';
        return 'video/mp4';
      case 'audio':
        if (ext == 'mp3') return 'audio/mpeg';
        if (ext == 'ogg') return 'audio/ogg';
        if (ext == 'm4a') return 'audio/mp4';
        return 'audio/wav';
      default:
        if (ext == 'pdf') return 'application/pdf';
        if (ext == 'zip') return 'application/zip';
        if (ext == 'rar') return 'application/vnd.rar';
        return 'application/octet-stream';
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

  Future<void> updateLastRead(String chatId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _fs.dmChats.doc(chatId).set({
        'lastRead': {uid: FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
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
