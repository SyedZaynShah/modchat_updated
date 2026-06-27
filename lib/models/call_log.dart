import 'package:cloud_firestore/cloud_firestore.dart';

enum CallLogStatus {
  missed,
  completed,
  declined,
  cancelled,
  failed,
}

extension CallLogStatusExt on CallLogStatus {
  String get value {
    switch (this) {
      case CallLogStatus.missed:
        return 'missed';
      case CallLogStatus.completed:
        return 'completed';
      case CallLogStatus.declined:
        return 'declined';
      case CallLogStatus.cancelled:
        return 'cancelled';
      case CallLogStatus.failed:
        return 'failed';
    }
  }

  static CallLogStatus fromString(String? value) {
    switch (value) {
      case 'missed':
        return CallLogStatus.missed;
      case 'completed':
        return CallLogStatus.completed;
      case 'declined':
        return CallLogStatus.declined;
      case 'cancelled':
        return CallLogStatus.cancelled;
      case 'failed':
        return CallLogStatus.failed;
      default:
        return CallLogStatus.missed;
    }
  }
}

class CallLog {
  final String id;
  final String callId;
  final String type; // 'voice' or 'video'
  final String callerId;
  final String receiverId;
  final Timestamp startedAt;
  final Timestamp? answeredAt;
  final Timestamp? endedAt;
  final int durationSeconds;
  final CallLogStatus status;
  final String initiatorId;

  CallLog({
    required this.id,
    required this.callId,
    required this.type,
    required this.callerId,
    required this.receiverId,
    required this.startedAt,
    this.answeredAt,
    this.endedAt,
    this.durationSeconds = 0,
    required this.status,
    required this.initiatorId,
  });

  factory CallLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CallLog(
      id: doc.id,
      callId: data['callId'] as String? ?? doc.id,
      type: data['type'] as String? ?? 'voice',
      callerId: data['callerId'] as String,
      receiverId: data['receiverId'] as String,
      startedAt: data['startedAt'] as Timestamp? ?? Timestamp.now(),
      answeredAt: data['answeredAt'] as Timestamp?,
      endedAt: data['endedAt'] as Timestamp?,
      durationSeconds: (data['durationSeconds'] as int?) ?? 0,
      status: CallLogStatusExt.fromString(data['status'] as String?),
      initiatorId: data['initiatorId'] as String,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'callId': callId,
      'type': type,
      'callerId': callerId,
      'receiverId': receiverId,
      'startedAt': startedAt,
      'answeredAt': answeredAt,
      'endedAt': endedAt,
      'durationSeconds': durationSeconds,
      'status': status.value,
      'initiatorId': initiatorId,
    };
  }

  bool isIncoming(String userId) => receiverId == userId && initiatorId != userId;
  bool isOutgoing(String userId) => initiatorId == userId;
  bool isMissed() => status == CallLogStatus.missed;
}
