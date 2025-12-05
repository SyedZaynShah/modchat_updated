import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
