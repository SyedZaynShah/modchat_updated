import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get chats => _db.collection('chats');
  CollectionReference<Map<String, dynamic>> messages(String chatId) => chats.doc(chatId).collection('messages');
}
