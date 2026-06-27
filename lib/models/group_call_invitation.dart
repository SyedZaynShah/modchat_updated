import 'package:cloud_firestore/cloud_firestore.dart';

/// PHASE 1.1: Group Call Invitation Model
/// 
/// One invitation document per invited user.
/// This ensures reliable delivery of incoming call notifications.
/// 
/// Each user listens ONLY for invitations where targetUserId == currentUserId.
/// This guarantees that every invited user receives notification exactly once.

enum InvitationStatus {
  pending,
  accepted,
  declined,
  expired,
}

extension InvitationStatusExt on InvitationStatus {
  String toFirestore() {
    switch (this) {
      case InvitationStatus.pending:
        return 'pending';
      case InvitationStatus.accepted:
        return 'accepted';
      case InvitationStatus.declined:
        return 'declined';
      case InvitationStatus.expired:
        return 'expired';
    }
  }

  static InvitationStatus fromString(String? value) {
    switch (value) {
      case 'pending':
        return InvitationStatus.pending;
      case 'accepted':
        return InvitationStatus.accepted;
      case 'declined':
        return InvitationStatus.declined;
      case 'expired':
        return InvitationStatus.expired;
      default:
        return InvitationStatus.pending;
    }
  }
}

class GroupCallInvitation {
  final String invitationId;
  final String callId;
  final String groupId;
  final String inviterId;
  final String targetUserId;
  final InvitationStatus status;
  final Timestamp createdAt;
  final Timestamp expiresAt;

  GroupCallInvitation({
    required this.invitationId,
    required this.callId,
    required this.groupId,
    required this.inviterId,
    required this.targetUserId,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  });

  factory GroupCallInvitation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GroupCallInvitation(
      invitationId: doc.id,
      callId: data['callId'] as String,
      groupId: data['groupId'] as String,
      inviterId: data['inviterId'] as String,
      targetUserId: data['targetUserId'] as String,
      status: InvitationStatusExt.fromString(data['status'] as String?),
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      expiresAt: data['expiresAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'callId': callId,
      'groupId': groupId,
      'inviterId': inviterId,
      'targetUserId': targetUserId,
      'status': status.toFirestore(),
      'createdAt': createdAt,
      'expiresAt': expiresAt,
    };
  }

  GroupCallInvitation copyWith({
    String? invitationId,
    String? callId,
    String? groupId,
    String? inviterId,
    String? targetUserId,
    InvitationStatus? status,
    Timestamp? createdAt,
    Timestamp? expiresAt,
  }) {
    return GroupCallInvitation(
      invitationId: invitationId ?? this.invitationId,
      callId: callId ?? this.callId,
      groupId: groupId ?? this.groupId,
      inviterId: inviterId ?? this.inviterId,
      targetUserId: targetUserId ?? this.targetUserId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
