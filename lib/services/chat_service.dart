import 'dart:typed_data';
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
    final chatId = chatIdFor(me, peerId);
    final chatDoc = _fs.chats.doc(chatId);
    final snap = await chatDoc.get();
    if (!snap.exists) {
      await chatDoc.set({
        'id': chatId,
        'members': [me, peerId],
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'lastMessageType': null,
        'lastTimestamp': FieldValue.serverTimestamp(),
      });
    }
    return chatId;
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> streamChats(String uid) {
    return _fs.chats
        .where('members', arrayContains: uid)
        .orderBy('lastTimestamp', descending: true)
        .snapshots()
        .map((s) => s.docs);
  }

  Stream<List<MessageModel>> streamMessages(String chatId) {
    return _fs
        .messages(chatId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((s) => s.docs.map((d) => MessageModel.fromMap(d.data(), d.id)).toList());
  }

  Future<void> sendText({required String chatId, required String peerId, required String text}) async {
    final uid = _auth.currentUser!.uid;
    final doc = _fs.messages(chatId).doc();
    final now = FieldValue.serverTimestamp();
    await doc.set({
      'chatId': chatId,
      'senderId': uid,
      'receiverId': peerId,
      'text': text,
      'messageType': 'text',
      'timestamp': now,
      'isSeen': false,
      'status': 1,
    });
    await _fs.chats.doc(chatId).update({
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
  }) async {
    final uid = _auth.currentUser!.uid;
    final msgRef = _fs.messages(chatId).doc();
    final path = '$chatId/${msgRef.id}/$fileName';
    final bucket = switch (type) {
      MessageType.audio => _storage.audioBucket,
      _ => _storage.mediaBucket,
    };
    final uploaded = await _storage.uploadBytes(
      data: bytes,
      bucket: bucket,
      path: path,
      contentType: contentType,
    );

    final now = FieldValue.serverTimestamp();
    await msgRef.set({
      'chatId': chatId,
      'senderId': uid,
      'receiverId': peerId,
      'text': null,
      'messageType': type.name,
      'mediaUrl': uploaded.signedUrl,
      'mediaSize': uploaded.size,
      'timestamp': now,
      'isSeen': false,
      'status': 1,
    });

    await _fs.chats.doc(chatId).update({
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
}
