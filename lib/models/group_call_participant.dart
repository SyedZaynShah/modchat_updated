/// Group Call Participant Model
/// 
/// Represents a participant in a group audio call with their current state.
class GroupCallParticipant {
  final String userId;
  final String name;
  final String? avatarUrl;
  final bool isMuted;
  final bool isSpeaking;
  final bool isHost;
  final ParticipantState state;
  
  GroupCallParticipant({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.isMuted = false,
    this.isSpeaking = false,
    this.isHost = false,
    this.state = ParticipantState.connected,
  });
  
  /// Create copy with updated fields
  GroupCallParticipant copyWith({
    String? userId,
    String? name,
    String? avatarUrl,
    bool? isMuted,
    bool? isSpeaking,
    bool? isHost,
    ParticipantState? state,
  }) {
    return GroupCallParticipant(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isMuted: isMuted ?? this.isMuted,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isHost: isHost ?? this.isHost,
      state: state ?? this.state,
    });
  }
  
  @override
  String toString() {
    return 'GroupCallParticipant(userId: $userId, name: $name, state: $state, muted: $isMuted, speaking: $isSpeaking)';
  }
}

/// Participant state in group call
enum ParticipantState {
  invited,      // In invitedParticipants array
  joining,      // Transitioning (UI state only)
  connected,    // In joinedParticipants, WebRTC connected
  muted,        // Audio track disabled
  speaking,     // In speakingParticipants array
  left,         // In leftParticipants array
  declined,     // In declinedParticipants array
}

extension ParticipantStateExtension on ParticipantState {
  String get displayName {
    switch (this) {
      case ParticipantState.invited:
        return 'Invited';
      case ParticipantState.joining:
        return 'Joining...';
      case ParticipantState.connected:
        return 'Connected';
      case ParticipantState.muted:
        return 'Muted';
      case ParticipantState.speaking:
        return 'Speaking';
      case ParticipantState.left:
        return 'Left';
      case ParticipantState.declined:
        return 'Declined';
    }
  }
  
  bool get isActive {
    return this == ParticipantState.connected ||
           this == ParticipantState.muted ||
           this == ParticipantState.speaking;
  }
}
