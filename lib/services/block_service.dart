import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firestore_service.dart';

class BlockService {
  final FirestoreService _fs;
  final FirebaseAuth _auth;

  BlockService(this._fs, {FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _fs.users.doc(uid);

  Future<void> blockUser({required String peerId}) async {
    if (peerId.isEmpty) return;
    if (peerId == _uid) return;

    await _userRef(_uid).set({
      'blockedUsers': FieldValue.arrayUnion([peerId]),
    }, SetOptions(merge: true));
  }

  Future<void> unblockUser({required String peerId}) async {
    if (peerId.isEmpty) return;
    if (peerId == _uid) return;

    await _userRef(_uid).set({
      'blockedUsers': FieldValue.arrayRemove([peerId]),
    }, SetOptions(merge: true));
  }
}
