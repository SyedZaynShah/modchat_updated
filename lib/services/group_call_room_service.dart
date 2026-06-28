import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import 'call_service.dart';
import '../models/group_call_room.dart';

/// Group Call Room Service
/// 
/// ARCHITECTURE PRINCIPLE:
/// Group call = multiple 1-to-1 calls coordinated together
/// 
/// NO separate signaling system
/// NO invitation collections
/// REUSES existing call architecture
class GroupCallRoomService {
  final FirestoreService _firestoreService = FirestoreService();
  final CallService _callService = CallService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  static const int MAX_PARTICIPANTS = 8;
  
  /// Get group call rooms collection
  CollectionReference<Map<String, dynamic>> get _rooms =>
      _firestoreService.firestore.collection('groupCallRooms');
  
  /// Start a group audio call
  /// 
  /// 1. Create room document
  /// 2. Create 1-to-1 call documents for each member (reusing existing system)
  /// 3. Existing incoming call listener handles the rest!
  Future<String> startGroupAudioCall({
    required String groupId,
    required String hostId,
    required String hostName,
  }) async {
    print('[GroupCallRoom] 📞 Starting group audio call');
    print('[GroupCallRoom] 👥 Group: $groupId');
    print('[GroupCallRoom] 🎤 Host: $hostId');
    
    // Check for existing active room
    final existingRoom = await getActiveRoom(groupId);
    if (existingRoom != null) {
      print('[GroupCallRoom] ♻️ Active room already exists: ${existingRoom.roomId}');
      throw Exception('Group call already in progress');
    }
    
    // Get group members
    final members = await _getGroupMembers(groupId);
    if (members.length < 2) {
      throw Exception('Group must have at least 2 members');
    }
    
    if (!members.contains(hostId)) {
      throw Exception('Host must be a group member');
    }
    
    // Create room with host as first participant
    final roomData = {
      'groupId': groupId,
      'hostId': hostId,
      'status': 'active',
      'participants': [hostId], // Host auto-joins
      'createdAt': FieldValue.serverTimestamp(),
    };
    
    final roomRef = await _rooms.add(roomData);
    final roomId = roomRef.id;
    
    print('[GroupCallRoom] ✅ Room created: $roomId');
    
    // Create 1-to-1 call documents for each member (except host)
    final otherMembers = members.where((id) => id != hostId).toList();
    print('[GroupCallRoom] 📞 Creating ${otherMembers.length} call documents');
    
    final callIds = <String, String>{}; // Map member ID to call ID
    
    for (var memberId in otherMembers) {
      try {
        // Reuse existing call system!
        final callId = await _callService.startVoiceCall(
          callerId: hostId,
          callerName: hostName,
          receiverId: memberId,
        );
        
        callIds[memberId] = callId;
        
        print('[GroupCallRoom] ✅ Call created: $hostId → $memberId (callId: $callId)');
      } catch (e) {
        print('[GroupCallRoom] ⚠️ Failed to create call for $memberId: $e');
        // Continue creating calls for other members
      }
    }
    
    // Store call IDs in room for tracking
    await roomRef.update({
      'callIds': callIds,
    });
    
    print('[GroupCallRoom] ✅ Group call started: $roomId');
    return roomId;
  }
  
  /// Join an existing group call
  /// 
  /// User accepts their 1-to-1 call, then joins room
  Future<void> joinRoom(String roomId, String userId) async {
    print('[GroupCallRoom] ➕ User $userId joining room $roomId');
    
    final roomDoc = await _rooms.doc(roomId).get();
    if (!roomDoc.exists) {
      throw Exception('Room not found');
    }
    
    final room = GroupCallRoom.fromFirestore(roomDoc);
    
    // Check participant limit
    if (room.participants.length >= MAX_PARTICIPANTS) {
      print('[GroupCallRoom] ⚠️ Room is full');
      throw Exception('Room is full (max 8 participants)');
    }
    
    // Check if already in room
    if (room.participants.contains(userId)) {
      print('[GroupCallRoom] ⚠️ User already in room');
      return;
    }
    
    // Add to participants
    await _rooms.doc(roomId).update({
      'participants': FieldValue.arrayUnion([userId]),
    });
    
    print('[GroupCallRoom] ✅ User joined room');
  }
  
  /// Leave the group call
  Future<void> leaveRoom(String roomId, String userId) async {
    print('[GroupCallRoom] ➖ User $userId leaving room $roomId');
    
    final roomDoc = await _rooms.doc(roomId).get();
    if (!roomDoc.exists) return;
    
    final room = GroupCallRoom.fromFirestore(roomDoc);
    
    // If host leaves, end the call for everyone
    if (room.hostId == userId) {
      print('[GroupCallRoom] 🚪 Host leaving → ending call');
      await endRoom(roomId);
      return;
    }
    
    // Remove from participants
    await _rooms.doc(roomId).update({
      'participants': FieldValue.arrayRemove([userId]),
    });
    
    print('[GroupCallRoom] ✅ User left room');
    
    // Check if room is empty
    final updatedDoc = await _rooms.doc(roomId).get();
    if (updatedDoc.exists) {
      final updatedRoom = GroupCallRoom.fromFirestore(updatedDoc);
      if (updatedRoom.participants.isEmpty || updatedRoom.participants.length == 1) {
        print('[GroupCallRoom] 🚪 Room empty → ending call');
        await endRoom(roomId);
      }
    }
  }
  
  /// End the group call (host only or automatic)
  Future<void> endRoom(String roomId) async {
    print('[GroupCallRoom] 🔚 Ending room $roomId');
    
    final roomDoc = await _rooms.doc(roomId).get();
    if (!roomDoc.exists) return;
    
    final data = roomDoc.data()!;
    final callIds = data['callIds'] as Map<String, dynamic>?;
    
    // End all individual 1-to-1 calls
    if (callIds != null) {
      for (var callId in callIds.values) {
        try {
          await _callService.endCall(callId as String);
          print('[GroupCallRoom] ✅ Ended call: $callId');
        } catch (e) {
          print('[GroupCallRoom] ⚠️ Failed to end call $callId: $e');
        }
      }
    }
    
    // Mark room as ended
    await _rooms.doc(roomId).update({
      'status': 'ended',
      'participants': [],
      'endedAt': FieldValue.serverTimestamp(),
    });
    
    print('[GroupCallRoom] ✅ Room ended');
  }
  
  /// Get active room for a group
  Future<GroupCallRoom?> getActiveRoom(String groupId) async {
    try {
      final snapshot = await _rooms
          .where('groupId', isEqualTo: groupId)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      
      if (snapshot.docs.isEmpty) return null;
      
      return GroupCallRoom.fromFirestore(snapshot.docs.first);
    } catch (e) {
      print('[GroupCallRoom] Error getting active room: $e');
      return null;
    }
  }
  
  /// Get room by call ID (to detect if incoming call is part of group call)
  Future<GroupCallRoom?> getRoomByCallId(String callId) async {
    try {
      // Query rooms where callIds contains this callId
      final snapshot = await _rooms
          .where('status', isEqualTo: 'active')
          .get();
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final callIds = data['callIds'] as Map<String, dynamic>?;
        
        if (callIds != null && callIds.containsValue(callId)) {
          return GroupCallRoom.fromFirestore(doc);
        }
      }
      
      return null;
    } catch (e) {
      print('[GroupCallRoom] Error getting room by call ID: $e');
      return null;
    }
  }
  
  /// Listen to a specific room
  Stream<DocumentSnapshot<Map<String, dynamic>>> listenToRoom(String roomId) {
    return _rooms.doc(roomId).snapshots();
  }
  
  /// Get group members
  Future<List<String>> _getGroupMembers(String groupId) async {
    try {
      final groupDoc = await _firestoreService.dmChats.doc(groupId).get();
      if (!groupDoc.exists) return [];
      
      final data = groupDoc.data();
      if (data == null) return [];
      
      return List<String>.from(data['members'] as List? ?? []);
    } catch (e) {
      print('[GroupCallRoom] Error getting members: $e');
      return [];
    }
  }
  
  /// Check if user can start a group call
  Future<bool> canStartGroupCall(String groupId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    
    try {
      final members = await _getGroupMembers(groupId);
      return members.contains(uid) && members.length >= 2;
    } catch (e) {
      print('[GroupCallRoom] Error checking permission: $e');
      return false;
    }
  }
}
