import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> resetPersistenceAndNetwork() async {
    final db = FirebaseFirestore.instance;
    if (kIsWeb) {
      try {
        await db.disableNetwork();
      } catch (_) {}
      try {
        await db.enableNetwork();
      } catch (_) {}
      return;
    }
    try {
      await db.disableNetwork();
    } catch (_) {}
    try {
      await db.clearPersistence();
    } catch (_) {}
    try {
      await db.enableNetwork();
    } catch (_) {}
  }

  CollectionReference<Map<String, dynamic>> get users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get dmChats =>
      _db.collection('dmChats');
  CollectionReference<Map<String, dynamic>> get groups =>
      _db.collection('groups');
  CollectionReference<Map<String, dynamic>> get moderationLogs =>
      _db.collection('moderationLogs');
  CollectionReference<Map<String, dynamic>> get calls =>
      _db.collection('calls');
  CollectionReference<Map<String, dynamic>> messages(String chatId) =>
      dmChats.doc(chatId).collection('messages');

  DocumentReference<Map<String, dynamic>> userHidesDoc(
    String uid,
    String chatId,
  ) => users.doc(uid).collection('hides').doc(chatId);
}
