import 'package:cloud_firestore/cloud_firestore.dart';

/// PHASE 1: Room Management Only - NO WebRTC
/// 
/// This model represents a group call room with participant tracking.
/// It does NOT contain any WebRTC-related fields (no offers, answers, ICE candidates).

enum GroupCallStatus {
  ringing,
  active,
  ended,
}

extension GroupCallStatusExt on GroupCallStatus {
  String toFirestore() {
    switch (this) {
      case GroupCallStatus.ringing:
        return 'ringing';
      case GroupCallStatus.active:
        return 'active';
      case GroupCallStatus.ended:
        return 'ended';
    }
  }

  static GroupCallStatus fromString(String? value) {
    switch (value) {
      case 'ringing':
        return GroupCallStatus.ringing;
      case 'active':
        return GroupCallStatus.active;
      case 'ended':
        return GroupCallStatus.ended;
      default:
        return GroupCallStatus.ringing;
    }
  }
}

class GroupCall {
  final String callId;
  final String groupId;
  final String initiatorId;
  final List<String> invitedParticipants; // Users invited (not yet joined)
  final List<String> joinedParticipants; // Users who accepted and joined
  final List<String> declinedParticipants; // Users who declined
  final List<String> leftParticipants; // Users who left after joining
  final GroupCallStatus status;
  final Timestamp createdAt;
  final Timestamp? startedAt; // When the call actually started (first user joined)

  GroupCall({
    required this.callId,
    required this.groupId,
    required this.initiatorId,
    required this.invitedParticipants,
    required this.joinedParticipants,
    required this.declinedParticipants,
    required this.leftParticipants,
    required this.status,
    required this.createdAt,
    this.startedAt,
  });

  factory GroupCall.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GroupCall(
      callId: doc.id,
      groupId: data['groupId'] as String,
      initiatorId: data['initiatorId'] as String,
      invitedParticipants: List<String>.from(data['invitedParticipants'] as List? ?? []),
      joinedParticipants: List<String>.from(data['joinedParticipants'] as List? ?? []),
      declinedParticipants: List<String>.from(data['declinedParticipants'] as List? ?? []),
      leftParticipants: List<String>.from(data['leftParticipants'] as List? ?? []),
      status: GroupCallStatusExt.fromString(data['status'] as String?),
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      startedAt: data['startedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'groupId': groupId,
      'initiatorId': initiatorId,
      'invitedParticipants': invitedParticipants,
      'joinedParticipants': joinedParticipants,
      'declinedParticipants': declinedParticipants,
      'leftParticipants': leftParticipants,
      'status': status.toFirestore(),
      'createdAt': createdAt,
      'startedAt': startedAt,
    };
  }

  GroupCall copyWith({
    String? callId,
    String? groupId,
    String? initiatorId,
    List<String>? invitedParticipants,
    List<String>? joinedParticipants,
    List<String>? declinedParticipants,
    List<String>? leftParticipants,
    GroupCallStatus? status,
    Timestamp? createdAt,
    Timestamp? startedAt,
  }) {
    return GroupCall(
      callId: callId ?? this.callId,
      groupId: groupId ?? this.groupId,
      initiatorId: initiatorId ?? this.initiatorId,
      invitedParticipants: invitedParticipants ?? this.invitedParticipants,
      joinedParticipants: joinedParticipants ?? this.joinedParticipants,
      declinedParticipants: declinedParticipants ?? this.declinedParticipants,
      leftParticipants: leftParticipants ?? this.leftParticipants,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
    );
  }
}
