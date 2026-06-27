import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import '../models/group_call.dart';

/// PHASE 1: Group Call Room Management Service
/// 
/// This service manages ONLY room operations:
/// - Creating call rooms
/// - Joining rooms
/// - Declining invitations
/// - Leaving rooms
/// - Ending rooms
/// - Real-time room updates
/// 
/// NO WebRTC. NO audio transport. NO video. NO signaling.
class GroupCallService {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  /// Check if user can start a group call (Phase 1: Always true if member)
  Future<bool> canStartGroupCall(String groupId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    
    try {
      final groupDoc = await _firestoreService.dmChats.doc(groupId).get();
      if (!groupDoc.exists) return false;
      
      final data = groupDoc.data();
      if (data == null) return false;
      
      final members = List<String>.from(data['members'] as List? ?? []);
      return members.contains(uid);
    } catch (e) {
      print('[GroupCallService] Error checking permission: $e');
      return false;
    }
  }
  
  /// Get all group members for invitation
  Future<List<String>> _getGroupMembers(String groupId) async {
    try {
      final groupDoc = await _firestoreService.dmChats.doc(groupId).get();
      if (!groupDoc.exists) return [];
      
      final data = groupDoc.data();
      if (data == null) return [];
      
      return List<String>.from(data['members'] as List? ?? []);
    } catch (e) {
      print('[GroupCallService] Error getting members: $e');
      return [];
    }
  }
  
  /// PHASE 1.1: Create dedicated invitation documents
  /// 
  /// Creates one invitation document per invited user.
  /// This ensures reliable delivery of incoming call notifications.
  Future<void> _createInvitations({
    required String callId,
    required String groupId,
    required String inviterId,
    required List<String> invitedUserIds,
  }) async {
    print('[GROUP_SIGNAL] Creating ${invitedUserIds.length} invitation documents');
    
    final now = Timestamp.now();
    final expiresAt = Timestamp.fromDate(
      DateTime.now().add(Duration(minutes: 1)), // 1 minute timeout
    );
    
    for (var targetUserId in invitedUserIds) {
      try {
        final invitationData = {
          'callId': callId,
          'groupId': groupId,
          'inviterId': inviterId,
          'targetUserId': targetUserId,
          'status': 'pending',
          'createdAt': now,
          'expiresAt': expiresAt,
        };
        
        await _firestoreService.firestore
            .collection('groupCallInvitations')
            .add(invitationData);
        
        print('[GROUP_SIGNAL] INVITATION_CREATED -> $targetUserId');
      } catch (e) {
        print('[GROUP_SIGNAL] ❌ Failed to create invitation for $targetUserId: $e');
      }
    }
  }
  
  /// Create a group call room
  /// 
  /// STEP 1: User starts call
  /// - Creates room document in groupCalls collection
  /// - Sets status to "ringing"
  /// - Initiator auto-joins (added to joinedParticipants)
  /// - Creates dedicated invitation document for each invited user
  Future<String> createGroupCall({
    required String groupId,
    required String initiatorId,
  }) async {
    return await startGroupAudioCall(groupId: groupId, initiatorId: initiatorId);
  }
  
  /// Alias for createGroupCall (backward compatibility)
  Future<String> startGroupAudioCall({
    required String groupId,
    required String initiatorId,
  }) async {
    print('[GROUP_SIGNAL] 📞 Starting group call');
    print('[GROUP_SIGNAL] 👥 Group: $groupId');
    print('[GROUP_SIGNAL] 🎤 Initiator: $initiatorId');
    
    // Get all group members
    final allMembers = await _getGroupMembers(groupId);
    
    if (allMembers.length < 2) {
      throw Exception('Group must have at least 2 members for a call');
    }
    
    if (!allMembers.contains(initiatorId)) {
      throw Exception('Initiator must be a group member');
    }
    
    // Check for existing active call
    final existingCall = await getActiveGroupCall(groupId);
    if (existingCall != null) {
      print('[GROUP_SIGNAL] ♻️ Active call already exists: ${existingCall.callId}');
      return existingCall.callId;
    }
    
    // Separate initiator from invited participants
    final invited = allMembers.where((id) => id != initiatorId).toList();
    
    print('[GROUP_SIGNAL] 👥 Invited: ${invited.length}');
    print('[GROUP_SIGNAL] 👤 Initiator auto-joined: $initiatorId');
    
    // Create room document
    final roomData = {
      'type': 'group_audio',                    // PHASE 3: Explicit call type
      'groupId': groupId,
      'initiatorId': initiatorId,
      'invitedParticipants': invited,
      'joinedParticipants': [initiatorId], // Initiator auto-joins
      'declinedParticipants': [],
      'leftParticipants': [],
      'speakingParticipants': [],               // PHASE 3: Speaking detection
      'status': 'ringing',
      'maxParticipants': 8,                     // PHASE 3: Enforce limit
      'createdAt': FieldValue.serverTimestamp(),
    };
    
    try {
      final docRef = await _firestoreService.groupCalls.add(roomData);
      final callId = docRef.id;
      print('[GROUP_SIGNAL] ROOM_CREATED: $callId');
      
      // PHASE 1.1: Create dedicated invitation documents
      await _createInvitations(
        callId: callId,
        groupId: groupId,
        inviterId: initiatorId,
        invitedUserIds: invited,
      );
      
      print('[GROUP_SIGNAL] ✅ Call setup complete');
      return callId;
    } catch (e) {
      print('[GROUP_SIGNAL] ❌ Failed to create call: $e');
      rethrow;
    }
  }
  
  /// PHASE 1.1: Listen to incoming group call invitations
  /// 
  /// Each user listens ONLY for invitations where targetUserId == currentUserId.
  /// This guarantees reliable delivery of incoming call notifications.
  Stream<QuerySnapshot<Map<String, dynamic>>> listenToIncomingGroupCallInvitations() {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      return const Stream.empty();
    }

    print('[GROUP_SIGNAL] 👂 Listening for invitations -> $currentUserId');

    return _firestoreService.firestore
        .collection('groupCallInvitations')
        .where('targetUserId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }
  
  /// PHASE 1.1: Accept group call invitation
  /// 
  /// Updates invitation status and joins the call
  Future<void> acceptInvitation(String invitationId, String callId) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      print('[GROUP_SIGNAL] INVITATION_ACCEPTED -> $currentUserId');
      
      // Update invitation status
      await _firestoreService.firestore
          .collection('groupCallInvitations')
          .doc(invitationId)
          .update({'status': 'accepted'});
      
      // Join the call
      await joinGroupCall(callId, currentUserId);
      
      print('[GROUP_SIGNAL] USER_JOINED -> $currentUserId');
    } catch (e) {
      print('[GROUP_SIGNAL] ❌ Error accepting invitation: $e');
      rethrow;
    }
  }
  
  /// PHASE 1.1: Decline group call invitation
  /// 
  /// Updates invitation status and marks user as declined
  Future<void> declineInvitation(String invitationId, String callId) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      print('[GROUP_SIGNAL] INVITATION_DECLINED -> $currentUserId');
      
      // Update invitation status
      await _firestoreService.firestore
          .collection('groupCallInvitations')
          .doc(invitationId)
          .update({'status': 'declined'});
      
      // Mark as declined in call
      await declineGroupCall(callId, currentUserId);
    } catch (e) {
      print('[GROUP_SIGNAL] ❌ Error declining invitation: $e');
      rethrow;
    }
  }
  
  /// Join a group call room
  /// 
  /// STEP 4: User accepts call
  /// - Remove from invitedParticipants
  /// - Add to joinedParticipants
  /// - Change status to "active" when first non-initiator joins
  /// PHASE 3: Enforce 8-participant limit
  /// PHASE 3.1: Support rejoin - remove from leftParticipants if present
  /// PHASE 3.1: Use Firestore transaction to prevent race conditions
  Future<void> joinGroupCall(String callId, String userId) async {
    print('[GroupCallService] ➕ User $userId joining call $callId');
    
    try {
      // PHASE 3.1: Use transaction for atomic participant count check
      await _firestoreService.firestore.runTransaction((transaction) async {
        final callRef = _firestoreService.groupCalls.doc(callId);
        final callDoc = await transaction.get(callRef);
        
        if (!callDoc.exists) {
          throw Exception('Call not found');
        }
        
        final call = GroupCall.fromFirestore(callDoc);
        
        // PHASE 3.1: Atomic check - participant limit
        if (call.joinedParticipants.length >= 8) {
          print('[GroupCallService] ⚠️ Call is full (max 8 participants)');
          throw Exception('Call is full. Maximum 8 participants allowed.');
        }
        
        // Duplicate join protection - already in call
        if (call.joinedParticipants.contains(userId)) {
          print('[GroupCallService] ⚠️ User already joined');
          return; // No-op, transaction will succeed without changes
        }
        
        // Block declined users from joining
        if (call.declinedParticipants.contains(userId)) {
          print('[GroupCallService] ⚠️ User already declined - cannot join');
          throw Exception('Cannot join after declining');
        }
        
        // PHASE 3.1 FIX: Allow rejoin - remove from leftParticipants
        final wasInLeftParticipants = call.leftParticipants.contains(userId);
        if (wasInLeftParticipants) {
          print('[GroupCallService] 🔄 User rejoining after leaving');
        }
        
        // Check if user was invited (or is rejoining)
        if (!call.invitedParticipants.contains(userId) && 
            call.initiatorId != userId && 
            !wasInLeftParticipants) {
          throw Exception('You are not invited to this call');
        }
        
        // PHASE 3.1: Atomic update - build transaction updates
        final updates = <String, dynamic>{
          'joinedParticipants': FieldValue.arrayUnion([userId]),
          'status': 'active', // Activate when anyone joins
          'startedAt': FieldValue.serverTimestamp(), // PHASE 3: Track start time
        };
        
        // Remove from invited if present
        if (call.invitedParticipants.contains(userId)) {
          updates['invitedParticipants'] = FieldValue.arrayRemove([userId]);
        }
        
        // Remove from leftParticipants if rejoining
        if (wasInLeftParticipants) {
          updates['leftParticipants'] = FieldValue.arrayRemove([userId]);
        }
        
        transaction.update(callRef, updates);
        
        print('[GroupCallService] ✅ User joined (transaction committed)');
        print('[GroupCallService] 📊 Status: active');
        if (wasInLeftParticipants) {
          print('[GroupCallService] 🔄 User successfully rejoined');
        }
      });
    } catch (e) {
      print('[GroupCallService] ❌ Error joining: $e');
      rethrow;
    }
  }
  
  /// Decline a group call invitation
  /// 
  /// STEP 5: User declines
  /// - Remove from invitedParticipants
  /// - Add to declinedParticipants
  Future<void> declineGroupCall(String callId, String userId) async {
    print('[GroupCallService] ❌ User $userId declining call $callId');
    
    try {
      final callDoc = await _firestoreService.groupCalls.doc(callId).get();
      if (!callDoc.exists) return;
      
      final call = GroupCall.fromFirestore(callDoc);
      
      // Duplicate invitation protection
      if (call.declinedParticipants.contains(userId)) {
        print('[GroupCallService] ⚠️ Already declined');
        return;
      }
      
      if (call.joinedParticipants.contains(userId)) {
        print('[GroupCallService] ⚠️ Already joined');
        return;
      }
      
      if (call.leftParticipants.contains(userId)) {
        print('[GroupCallService] ⚠️ Already left');
        return;
      }
      
      // Update room: move from invited to declined
      await _firestoreService.groupCalls.doc(callId).update({
        'invitedParticipants': FieldValue.arrayRemove([userId]),
        'declinedParticipants': FieldValue.arrayUnion([userId]),
      });
      
      print('[GroupCallService] ✅ User declined');
    } catch (e) {
      print('[GroupCallService] ❌ Error declining: $e');
      rethrow;
    }
  }
  
  /// Leave a group call room
  /// 
  /// STEP 6: User leaves
  /// - Remove from joinedParticipants
  /// - Add to leftParticipants
  /// - End call if no participants remain
  /// - End call if initiator leaves
  Future<void> leaveGroupCall(String callId, String userId) async {
    print('[GroupCallService] ➖ User $userId leaving call $callId');
    
    try {
      final callDoc = await _firestoreService.groupCalls.doc(callId).get();
      if (!callDoc.exists) return;
      
      final call = GroupCall.fromFirestore(callDoc);
      
      if (!call.joinedParticipants.contains(userId)) {
        print('[GroupCallService] ⚠️ User not in call');
        return;
      }
      
      // Case 1: Initiator leaves → end call
      if (call.initiatorId == userId) {
        print('[GroupCallService] 🚪 Initiator leaving → ending call');
        await endGroupCall(callId);
        return;
      }
      
      // Update room: move from joined to left
      await _firestoreService.groupCalls.doc(callId).update({
        'joinedParticipants': FieldValue.arrayRemove([userId]),
        'leftParticipants': FieldValue.arrayUnion([userId]),
      });
      
      print('[GroupCallService] ✅ User left');
      
      // Case 2: No participants remain → end call
      final updatedDoc = await _firestoreService.groupCalls.doc(callId).get();
      if (updatedDoc.exists) {
        final updatedCall = GroupCall.fromFirestore(updatedDoc);
        if (updatedCall.joinedParticipants.isEmpty) {
          print('[GroupCallService] 🚪 No participants remain → ending call');
          await endGroupCall(callId);
        }
      }
    } catch (e) {
      print('[GroupCallService] ❌ Error leaving: $e');
      rethrow;
    }
  }
  
  /// End a group call room
  /// 
  /// STEP 8: Room ends
  /// - Set status to "ended"
  /// - Clear all joined participants
  /// PHASE 3: Record end timestamp
  Future<void> endGroupCall(String callId) async {
    print('[GroupCallService] 🔚 Ending call $callId');
    
    try {
      await _firestoreService.groupCalls.doc(callId).update({
        'status': 'ended',
        'joinedParticipants': [],
        'endedAt': FieldValue.serverTimestamp(), // PHASE 3: Track end time
      });
      
      print('[GroupCallService] ✅ Call ended');
    } catch (e) {
      print('[GroupCallService] ❌ Error ending call: $e');
      rethrow;
    }
  }
  
  /// Listen to incoming group calls for current user
  /// 
  /// Shows calls where:
  /// - User is in invitedParticipants (not yet responded)
  /// - Status is "ringing" or "active"
  Stream<QuerySnapshot<Map<String, dynamic>>> listenToIncomingGroupCalls() {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      return const Stream.empty();
    }

    // Listen for calls where user is invited
    return _firestoreService.groupCalls
        .where('invitedParticipants', arrayContains: currentUserId)
        .where('status', whereIn: ['ringing', 'active'])
        .snapshots();
  }
  
  /// Listen to a specific group call for real-time updates
  Stream<DocumentSnapshot<Map<String, dynamic>>> listenToGroupCall(String callId) {
    return _firestoreService.groupCalls.doc(callId).snapshots();
  }
  
  /// Get active group call for a group (if any)
  Future<GroupCall?> getActiveGroupCall(String groupId) async {
    try {
      final snapshot = await _firestoreService.groupCalls
          .where('groupId', isEqualTo: groupId)
          .where('status', whereIn: ['ringing', 'active'])
          .limit(1)
          .get();
      
      if (snapshot.docs.isEmpty) return null;
      
      return GroupCall.fromFirestore(snapshot.docs.first);
    } catch (e) {
      print('[GroupCallService] Error getting active call: $e');
      return null;
    }
  }
}
