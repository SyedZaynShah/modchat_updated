import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// MINIMAL SIGNAL TEST SERVICE
/// 
/// Purpose: Prove signal delivery works
/// No logic. No complexity. Just send and receive.
class SignalTestService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// SENDER: Create signal
  Future<String?> sendTestSignal(String targetUserId) async {
    final senderId = _auth.currentUser?.uid;
    if (senderId == null) {
      print('[SIGNAL] ❌ No current user');
      return null;
    }

    print('[SIGNAL] CREATED');
    print('[SIGNAL] SENDER: $senderId');
    print('[SIGNAL] TARGET_USER: $targetUserId');

    try {
      final docRef = await _firestore.collection('groupCallSignals').add({
        'senderId': senderId,
        'targetUserId': targetUserId,
        'createdAt': FieldValue.serverTimestamp(),
        'received': false,
      });

      final signalId = docRef.id;
      print('[SIGNAL] SIGNAL_ID: $signalId');

      // Verify it was created
      final doc = await docRef.get();
      if (doc.exists) {
        print('[SIGNAL] VERIFIED_IN_FIRESTORE');
        print('[SIGNAL] Data: ${doc.data()}');
      } else {
        print('[SIGNAL] ❌ VERIFICATION_FAILED');
      }

      return signalId;
    } catch (e) {
      print('[SIGNAL] ❌ CREATE_FAILED: $e');
      return null;
    }
  }

  /// RECEIVER: Listen for signals
  Stream<QuerySnapshot> listenForSignals() {
    final currentUserId = _auth.currentUser?.uid;
    
    print('[SIGNAL] LISTENER_STARTED');
    print('[SIGNAL] CURRENT_USER: $currentUserId');
    
    if (currentUserId == null) {
      print('[SIGNAL] ❌ No current user');
      return const Stream.empty();
    }

    print('[SIGNAL] Query: groupCallSignals where targetUserId==$currentUserId');

    return _firestore
        .collection('groupCallSignals')
        .where('targetUserId', isEqualTo: currentUserId)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();
  }

  /// ACKNOWLEDGEMENT: Mark signal as received
  Future<void> acknowledgeSignal(String signalId) async {
    print('[SIGNAL] ACK_SENT for $signalId');

    try {
      await _firestore
          .collection('groupCallSignals')
          .doc(signalId)
          .update({'received': true});

      print('[SIGNAL] ACK_UPDATED');

      // Verify
      final doc = await _firestore
          .collection('groupCallSignals')
          .doc(signalId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        print('[SIGNAL] ACK_VERIFIED: received=${data?['received']}');
      }
    } catch (e) {
      print('[SIGNAL] ❌ ACK_FAILED: $e');
    }
  }

  /// DEBUG: Get current user info
  String? getCurrentUserId() {
    return _auth.currentUser?.uid;
  }
}
