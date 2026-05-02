import 'package:cloud_firestore/cloud_firestore.dart';

class ChatSettings {
  final bool pinned;
  final int pinnedAt;
  final Timestamp? mutedUntil;
  final bool hidden;
  final bool archived;
  final bool unread;

  const ChatSettings({
    required this.pinned,
    required this.pinnedAt,
    required this.mutedUntil,
    required this.hidden,
    required this.archived,
    required this.unread,
  });

  static const ChatSettings empty = ChatSettings(
    pinned: false,
    pinnedAt: 0,
    mutedUntil: null,
    hidden: false,
    archived: false,
    unread: false,
  );

  bool get isMuted {
    final until = mutedUntil;
    if (until == null) return false;
    return until.toDate().isAfter(DateTime.now());
  }

  Map<String, dynamic> toMap() {
    return {
      'pinned': pinned,
      'pinnedAt': pinnedAt,
      'mutedUntil': mutedUntil,
      'hidden': hidden,
      'archived': archived,
      'unread': unread,
    };
  }

  static ChatSettings fromMap(Map<String, dynamic>? map) {
    final m = map ?? const <String, dynamic>{};
    return ChatSettings(
      pinned: (m['pinned'] as bool?) ?? false,
      pinnedAt: (m['pinnedAt'] as num?)?.toInt() ?? 0,
      mutedUntil: m['mutedUntil'] as Timestamp?,
      hidden: (m['hidden'] as bool?) ?? false,
      archived: (m['archived'] as bool?) ?? false,
      unread: (m['unread'] as bool?) ?? false,
    );
  }
}
