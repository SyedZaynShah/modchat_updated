/// Enum representing all possible call states
enum CallState {
  /// Call is being initiated by caller
  calling,
  
  /// Call is ringing on receiver's device
  ringing,
  
  /// Call has been accepted and is in progress
  accepted,
  
  /// Call was declined by receiver
  declined,
  
  /// Call was not answered (timeout)
  missed,
  
  /// Call was cancelled by caller before answer
  cancelled,
  
  /// Call has ended normally
  ended,
  
  /// Call failed due to error
  failed;

  /// Check if this is a terminal state (call is over)
  bool get isTerminal => this == declined || 
                         this == missed || 
                         this == cancelled ||
                         this == ended || 
                         this == failed;

  /// Check if call is active (in progress)
  bool get isActive => this == calling || 
                       this == ringing || 
                       this == accepted;

  /// Get user-friendly display text
  String get displayText {
    switch (this) {
      case CallState.calling:
        return 'Calling...';
      case CallState.ringing:
        return 'Ringing...';
      case CallState.accepted:
        return 'Connected';
      case CallState.declined:
        return 'Call Declined';
      case CallState.missed:
        return 'Not Answered';
      case CallState.cancelled:
        return 'Call Cancelled';
      case CallState.ended:
        return 'Call Ended';
      case CallState.failed:
        return 'Call Failed';
    }
  }

  /// Parse from string
  static CallState fromString(String? value) {
    if (value == null) return CallState.calling;
    
    switch (value.toLowerCase()) {
      case 'calling':
        return CallState.calling;
      case 'ringing':
        return CallState.ringing;
      case 'accepted':
        return CallState.accepted;
      case 'declined':
        return CallState.declined;
      case 'missed':
        return CallState.missed;
      case 'cancelled':
        return CallState.cancelled;
      case 'ended':
        return CallState.ended;
      case 'failed':
        return CallState.failed;
      default:
        return CallState.calling;
    }
  }

  /// Convert to string for Firestore
  String toFirestore() => name;
}
