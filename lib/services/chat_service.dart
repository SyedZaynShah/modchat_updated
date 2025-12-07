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
      'members': members,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': null,
      'lastMessageType': null,
      'lastTimestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
            if ('${a.text}' != '${b.text}') return false;
            if ('${a.mediaUrl}' != '${b.mediaUrl}') return false;
            if (a.hasPendingWrites != b.hasPendingWrites) return false;
          }
          return true;
        });
  }

  Future<void> sendText({
    required String chatId,
    required String peerId,
    required String text,
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
    } on SocketException {
      await Future.delayed(const Duration(milliseconds: 400));
      await doUpload();
    }

    final now = FieldValue.serverTimestamp();
    final mediaType = _mediaTypeFor(fileName, contentType, type);
    await msgRef.set({
      'chatId': chatId,
      'senderId': uid,
      'receiverId': peerId,
      'text': null,
      // Store only storage path (no scheme)
      'mediaUrl': path,
      'fileName': ext.isNotEmpty ? '$ts.$ext' : '$ts',
      'mediaType': mediaType,
      'mediaSize': bytes.length,
      if (type == MessageType.audio && audioDurationMs != null)
        'audioDurationMs': audioDurationMs,
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
      'lastMessage': type.name,
      'lastMessageType': type.name,
      'lastTimestamp': now,
    });
  }

  Future<void> acknowledgeDelivered(String chatId) async {
    final uid = _auth.currentUser!.uid;
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
  }

  Future<void> markAllSeen(String chatId) async {
    final uid = _auth.currentUser!.uid;
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
    await ref.update({
      'text': newText,
      'edited': true,
      'editedAt': FieldValue.serverTimestamp(),
    });
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
      'isDeleted': true,
      'isDeletedForAll': true,
      'deletedForEveryone': true, // compatibility flag
      'messageType': 'deleted',
      'text': '',
      'mediaUrl': null,
      'mediaType': null,
      'deletedAt': FieldValue.serverTimestamp(),
    });
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
