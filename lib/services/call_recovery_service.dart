import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import '../models/call_state.dart';

/// Service for cleaning up stale calls after app crashes/kills
class CallRecoveryService {
  final FirestoreService _firestoreService = FirestoreService();

  /// Clean up stale calls on app startup
  /// Should be called once after user login
  Future<void> cleanupStaleCalls() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      print('[CallRecovery] No user logged in, skipping cleanup');
      return;
    }

    print('[CallRecovery] ========================================');
    print('[CallRecovery] Starting stale call cleanup for user: $currentUserId');
    print('[CallRecovery] ========================================');

    try {
      await _cleanupStaleAcceptedCalls(currentUserId);
      await _cleanupStaleRingingCalls(currentUserId);
      
      print('[CallRecovery] ========================================');
      print('[CallRecovery] ✅ Cleanup complete');
      print('[CallRecovery] ========================================');
    } catch (e) {
      print('[CallRecovery] ❌ ERROR during cleanup: $e');
    }
  }

  /// FIX 1: Cleanup stale accepted calls
  /// These are calls that were active when app crashed
  Future<void> _cleanupStaleAcceptedCalls(String userId) async {
    print('[CallRecovery] 🔍 Checking for stale ACCEPTED calls...');
    
    // Find accepted calls where user is caller
    final asCallerQuery = await _firestoreService.calls
        .where('callerId', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .get();

    // Find accepted calls where user is receiver
    final asReceiverQuery = await _firestoreService.calls
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .get();

    final staleCalls = [...asCallerQuery.docs, ...asReceiverQuery.docs];
    
    if (staleCalls.isEmpty) {
      print('[CallRecovery] ✅ No stale accepted calls found');
      return;
    }

    print('[CallRecovery] 🚨 Found ${staleCalls.length} stale accepted call(s)');
    
    int cleanedCount = 0;
    
    for (final doc in staleCalls) {
      final data = doc.data();
      final createdAt = data['createdAt'] as Timestamp?;
      
      if (createdAt == null) {
        print('[CallRecovery] ⚠️ Call ${doc.id} has no createdAt, skipping');
        continue;
      }

      final age = DateTime.now().difference(createdAt.toDate());
      final ageMinutes = age.inMinutes;
      
      print('[CallRecovery] 📞 Call ${doc.id}:');
      print('[CallRecovery]    Status: ${data['status']}');
      print('[CallRecovery]    Age: $ageMinutes minutes');
      print('[CallRecovery]    Caller: ${data['callerId']}');
      print('[CallRecovery]    Receiver: ${data['receiverId']}');
      
      // Clean up calls older than 5 minutes
      // (Normal calls should have ended before this)
      if (ageMinutes > 5) {
        print('[CallRecovery]    🧹 Cleaning up (older than 5 minutes)...');
        
        try {
          await _firestoreService.calls.doc(doc.id).update({
            'status': 'ended',
            'endedAt': FieldValue.serverTimestamp(),
          });
          
          cleanedCount++;
          print('[CallRecovery]    ✅ Marked as ended');
        } catch (e) {
          print('[CallRecovery]    ❌ Failed to cleanup: $e');
        }
      } else {
        print('[CallRecovery]    ⏱️ Too recent, keeping (< 5 minutes old)');
      }
    }
    
    if (cleanedCount > 0) {
      print('[CallRecovery] ✅ Cleaned up $cleanedCount stale accepted call(s)');
    }
  }

  /// FIX 2: Cleanup stale calling/ringing calls
  /// These are calls that never got answered and timed out
  Future<void> _cleanupStaleRingingCalls(String userId) async {
    print('[CallRecovery] 🔍 Checking for stale CALLING/RINGING calls...');
    
    // Find calling/ringing calls where user is caller
    final asCallerQuery = await _firestoreService.calls
        .where('callerId', isEqualTo: userId)
        .where('status', whereIn: ['calling', 'ringing'])
        .get();

    // Find calling/ringing calls where user is receiver
    final asReceiverQuery = await _firestoreService.calls
        .where('receiverId', isEqualTo: userId)
        .where('status', whereIn: ['calling', 'ringing'])
        .get();

    final staleCalls = [...asCallerQuery.docs, ...asReceiverQuery.docs];
    
    if (staleCalls.isEmpty) {
      print('[CallRecovery] ✅ No stale calling/ringing calls found');
      return;
    }

    print('[CallRecovery] 🚨 Found ${staleCalls.length} stale calling/ringing call(s)');
    
    int cleanedCount = 0;
    
    for (final doc in staleCalls) {
      final data = doc.data();
      final createdAt = data['createdAt'] as Timestamp?;
      
      if (createdAt == null) {
        print('[CallRecovery] ⚠️ Call ${doc.id} has no createdAt, skipping');
        continue;
      }

      final age = DateTime.now().difference(createdAt.toDate());
      final ageSeconds = age.inSeconds;
      
      print('[CallRecovery] 📞 Call ${doc.id}:');
      print('[CallRecovery]    Status: ${data['status']}');
      print('[CallRecovery]    Age: $ageSeconds seconds');
      print('[CallRecovery]    Caller: ${data['callerId']}');
      print('[CallRecovery]    Receiver: ${data['receiverId']}');
      
      // Clean up calls older than 60 seconds
      // (Normal timeout is 30s, this catches anything that slipped through)
      if (ageSeconds > 60) {
        print('[CallRecovery]    🧹 Cleaning up (older than 60 seconds)...');
        
        try {
          await _firestoreService.calls.doc(doc.id).update({
            'status': 'missed',
            'endedAt': FieldValue.serverTimestamp(),
          });
          
          cleanedCount++;
          print('[CallRecovery]    ✅ Marked as missed');
        } catch (e) {
          print('[CallRecovery]    ❌ Failed to cleanup: $e');
        }
      } else {
        print('[CallRecovery]    ⏱️ Too recent, keeping (< 60 seconds old)');
      }
    }
    
    if (cleanedCount > 0) {
      print('[CallRecovery] ✅ Cleaned up $cleanedCount stale calling/ringing call(s)');
    }
  }

  /// Get all active calls for debug screen
  Future<List<Map<String, dynamic>>> getActiveCallsForDebug() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return [];
    }

    // Find all active calls (calling, ringing, accepted)
    final asCallerQuery = await _firestoreService.calls
        .where('callerId', isEqualTo: currentUserId)
        .where('status', whereIn: ['calling', 'ringing', 'accepted'])
        .get();

    final asReceiverQuery = await _firestoreService.calls
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', whereIn: ['calling', 'ringing', 'accepted'])
        .get();

    final activeCalls = <Map<String, dynamic>>[];
    
    for (final doc in [...asCallerQuery.docs, ...asReceiverQuery.docs]) {
      final data = doc.data();
      final createdAt = data['createdAt'] as Timestamp?;
      
      activeCalls.add({
        'id': doc.id,
        'status': data['status'],
        'type': data['type'],
        'callerId': data['callerId'],
        'receiverId': data['receiverId'],
        'createdAt': createdAt,
        'age': createdAt != null 
            ? DateTime.now().difference(createdAt.toDate())
            : null,
        'role': data['callerId'] == currentUserId ? 'caller' : 'receiver',
      });
    }
    
    return activeCalls;
  }

  /// Force end a specific call (for debug screen)
  Future<void> forceEndCall(String callId) async {
    print('[CallRecovery] 🔨 Force ending call: $callId');
    
    try {
      await _firestoreService.calls.doc(callId).update({
        'status': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
      });
      
      print('[CallRecovery] ✅ Call force-ended successfully');
    } catch (e) {
      print('[CallRecovery] ❌ Failed to force-end call: $e');
      rethrow;
    }
  }
}

