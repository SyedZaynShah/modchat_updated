import 'package:cloud_firestore/cloud_firestore.dart';

/// Group Call Room Model
/// 
/// ONE ROOM DOCUMENT PER GROUP CALL
/// No invitations, no peerConnections, no SDP storage
/// Just participants and status tracking
class GroupCallRoom {
  final String roomId;
  final String groupId;
  final String hostId;
  final String status; // 'active', 'ended'
  final List<String> participants; // All users currently in the call
  final Timestamp createdAt;
  final Timestamp? endedAt;
  
  GroupCallRoom({
    required this.roomId,
    required this.groupId,
    required this.hostId,
    required this.status,
    required this.participants,
    required this.createdAt,
    this.endedAt,
  });
  
  factory GroupCallRoom.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GroupCallRoom(
      roomId: doc.id,
      groupId: data['groupId'] as String,
      hostId: data['hostId'] as String,
      status: data['status'] as String? ?? 'active',
      participants: List<String>.from(data['participants'] as List? ?? []),
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      endedAt: data['endedAt'] as Timestamp?,
    );
  }
  
  Map<String, dynamic> toFirestore() {
    return {
      'groupId': groupId,
      'hostId': hostId,
      'status': status,
      'participants': participants,
      'createdAt': createdAt,
      if (endedAt != null) 'endedAt': endedAt,
    };
  }
  
  bool get isActive => status == 'active';
  bool get isHost => false; // Will be set by service based on current user
  
  GroupCallRoom copyWith({
    String? roomId,
    String? groupId,
    String? hostId,
    String? status,
    List<String>? participants,
    Timestamp? createdAt,
    Timestamp? endedAt,
  }) {
    return GroupCallRoom(
      roomId: roomId ?? this.roomId,
      groupId: groupId ?? this.groupId,
      hostId: hostId ?? this.hostId,
      status: status ?? this.status,
      participants: participants ?? this.participants,
      createdAt: createdAt ?? this.createdAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }
}
