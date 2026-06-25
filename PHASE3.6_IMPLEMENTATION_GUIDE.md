# Phase 3.6: Implementation Guide

**Date:** 2026-06-25  
**Status:** 📋 READY TO IMPLEMENT  

---

## 🎯 IMPLEMENTATION ORDER

Follow this exact order for smooth integration:

### **Step 1: Reconnection Handling** (CRITICAL - 3-4 hours)
### **Step 2: Network Quality Indicator** (HIGH VALUE - 2-3 hours)
### **Step 3: Call History** (EXPECTED - 3-4 hours)
### **Step 4: Picture-in-Picture** (OPTIONAL - 5-6 hours)

---

## 📋 STEP 1: RECONNECTION HANDLING

**Priority:** CRITICAL ⭐⭐⭐  
**Time:** 3-4 hours  

### 1.1 Add Reconnection State Enum

**File:** `lib/services/call_controller.dart`

**Add after MediaState enum:**
```dart
/// Reconnection state for handling network drops
enum ReconnectionState {
  stable,           // Normal connection
  reconnecting,     // Attempting to reconnect
  reconnected,      // Successfully reconnected (brief state)
  failed,           // Reconnection attempts exhausted
}
```

### 1.2 Add Reconnection State Tracking

**File:** `lib/services/call_controller.dart`

**Add to CallController class fields:**
```dart
// Reconnection handling
ReconnectionState _reconnectionState = ReconnectionState.stable;
Timer? _reconnectionTimer;
static const Duration _reconnectionTimeout = Duration(seconds: 15);
Function(ReconnectionState)? onReconnectionStateChange;
```

### 1.3 Add Reconnection Getter

**Add public getter:**
```dart
/// Get current reconnection state
ReconnectionState get reconnectionState => _reconnectionState;
```

### 1.4 Modify ICE Connection State Handler

**Find:** `_peerConnection!.onIceConnectionState`  
**Replace with:**
```dart
_peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
  print('[CallController] 🧊 ICE_CONNECTION_STATE: $state');
  
  if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
    print('[CallController] ❌ ICE_FAILED: Connection cannot be established');
    _handleReconnectionFailed();
  } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
    print('[CallController] ⚠️ ICE_DISCONNECTED: Starting reconnection...');
    _handleIceDisconnected();
  } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
    print('[CallController] ✅ ICE_CONNECTED: Peer connection established');
    _handleIceReconnected();
  } else if (state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
    print('[CallController] ✅ ICE_COMPLETED: All candidates processed');
    _handleIceReconnected();
  }
};
```

### 1.5 Add Reconnection Handler Methods

**Add these methods to CallController:**
```dart
/// Handle ICE disconnected - start reconnection
void _handleIceDisconnected() {
  if (_reconnectionState == ReconnectionState.reconnecting) {
    print('[CallController] ⚠️ RECONNECTION: Already reconnecting, ignoring');
    return;
  }
  
  print('[CallController] 🔄 RECONNECTION_START: Network dropped, attempting reconnect...');
  _reconnectionState = ReconnectionState.reconnecting;
  onReconnectionStateChange?.call(_reconnectionState);
  
  _startReconnectionTimer();
}

/// Start reconnection timeout timer
void _startReconnectionTimer() {
  _reconnectionTimer?.cancel();
  
  print('[CallController] ⏱️ RECONNECTION_TIMER: Starting ${_reconnectionTimeout.inSeconds}s timeout');
  
  _reconnectionTimer = Timer(_reconnectionTimeout, () {
    if (_reconnectionState == ReconnectionState.reconnecting) {
      print('[CallController] ❌ RECONNECTION_TIMEOUT: Failed to reconnect');
      _handleReconnectionFailed();
    }
  });
}

/// Handle successful reconnection
void _handleIceReconnected() {
  if (_reconnectionState != ReconnectionState.reconnecting) {
    return; // Only handle if we were reconnecting
  }
  
  print('[CallController] ✅ RECONNECTION_SUCCESS: Connection restored');
  
  _reconnectionTimer?.cancel();
  _reconnectionState = ReconnectionState.reconnected;
  onReconnectionStateChange?.call(_reconnectionState);
  
  // Show "Connected" briefly, then back to stable
  Future.delayed(Duration(seconds: 2), () {
    if (_reconnectionState == ReconnectionState.reconnected) {
      _reconnectionState = ReconnectionState.stable;
      onReconnectionStateChange?.call(_reconnectionState);
      print('[CallController] ✅ RECONNECTION_COMPLETE: Back to stable');
    }
  });
}

/// Handle reconnection failure - end call
void _handleReconnectionFailed() {
  _reconnectionTimer?.cancel();
  _reconnectionState = ReconnectionState.failed;
  onReconnectionStateChange?.call(_reconnectionState);
  
  print('[CallController] ❌ RECONNECTION_FAILED: Network issue could not be resolved');
  
  // Notify UI that call should end due to network
  // UI will handle ending the call gracefully
}
```

### 1.6 Update Dispose Method

**Add to dispose() method before existing cleanup:**
```dart
// Cancel reconnection timer
_reconnectionTimer?.cancel();
_reconnectionTimer = null;
_reconnectionState = ReconnectionState.stable;
```

### 1.7 Update VideoCallScreen UI

**File:** `lib/screens/chat/video_call_screen.dart`

**Add state field:**
```dart
ReconnectionState _reconnectionState = ReconnectionState.stable;
```

**Update _initializeWebRTC() callback:**
```dart
_callController = CallController(
  callId: widget.callId,
  isInitiator: !widget.isIncoming,
  isVideoCall: true,
  onRemoteStream: (MediaStream stream) {
    // ... existing code ...
  },
  onConnectionStateChange: (String state) {
    // ... existing code ...
  },
  onReconnectionStateChange: (ReconnectionState state) {
    print('[VideoCallScreen] 🔄 RECONNECTION_STATE: $state');
    if (mounted) {
      setState(() {
        _reconnectionState = state;
      });
      
      // End call if reconnection failed
      if (state == ReconnectionState.failed) {
        _showReconnectionFailedDialog();
      }
    }
  },
);
```

**Add dialog method:**
```dart
void _showReconnectionFailedDialog() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('Connection Lost'),
      content: Text('Unable to reconnect. The call has been ended.'),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(); // Close dialog
            Navigator.of(context).pop(); // Close call screen
          },
          child: Text('OK'),
        ),
      ],
    ),
  );
}
```

**Update _getStatusText() method:**
```dart
String _getStatusText() {
  // Check reconnection state first
  if (_reconnectionState == ReconnectionState.reconnecting) {
    return 'Reconnecting...';
  } else if (_reconnectionState == ReconnectionState.reconnected) {
    return 'Connected';
  }
  
  // Normal status display
  if (_currentState == CallState.accepted && _connectedAt != null) {
    return _formatDuration(_callDuration);
  }
  return _currentState.displayText;
}
```

### 1.8 Test Reconnection

**Test Steps:**
1. Start video call
2. Toggle airplane mode for 5 seconds
3. Verify "Reconnecting..." appears
4. Disable airplane mode
5. Verify "Connected" appears briefly
6. Verify call continues normally

---

## 📋 STEP 2: NETWORK QUALITY INDICATOR

**Priority:** HIGH VALUE ⭐⭐⭐  
**Time:** 2-3 hours  

### 2.1 Add Network Quality Enum

**File:** `lib/models/network_quality.dart` (NEW FILE)

**Create new file:**
```dart
/// Network quality levels for real-time connection feedback
enum NetworkQuality {
  excellent,    // Solid connection, no issues
  good,         // Connected, minor packet loss
  fair,         // Intermittent issues
  poor,         // Significant quality degradation
  reconnecting, // Disconnected, attempting reconnect
  failed,       // Connection failed permanently
}

extension NetworkQualityDisplay on NetworkQuality {
  /// Get display text
  String get displayText {
    switch (this) {
      case NetworkQuality.excellent:
        return 'Excellent';
      case NetworkQuality.good:
        return 'Good';
      case NetworkQuality.fair:
        return 'Fair';
      case NetworkQuality.poor:
        return 'Poor';
      case NetworkQuality.reconnecting:
        return 'Reconnecting';
      case NetworkQuality.failed:
        return 'Failed';
    }
  }
  
  /// Get indicator color
  Color get color {
    switch (this) {
      case NetworkQuality.excellent:
      case NetworkQuality.good:
        return Colors.green;
      case NetworkQuality.fair:
        return Colors.yellow;
      case NetworkQuality.poor:
        return Colors.orange;
      case NetworkQuality.reconnecting:
      case NetworkQuality.failed:
        return Colors.red;
    }
  }
  
  /// Get number of bars (1-5)
  int get bars {
    switch (this) {
      case NetworkQuality.excellent:
        return 5;
      case NetworkQuality.good:
        return 4;
      case NetworkQuality.fair:
        return 3;
      case NetworkQuality.poor:
        return 2;
      case NetworkQuality.reconnecting:
      case NetworkQuality.failed:
        return 0;
    }
  }
}
```

### 2.2 Add Quality Tracking to CallController

**File:** `lib/services/call_controller.dart`

**Add to class fields:**
```dart
// Network quality tracking
NetworkQuality _networkQuality = NetworkQuality.fair;
Function(NetworkQuality)? onNetworkQualityChange;
```

**Add getter:**
```dart
/// Get current network quality
NetworkQuality get networkQuality => _networkQuality;
```

**Add quality calculation method:**
```dart
/// Calculate network quality based on connection states
void _updateNetworkQuality(
  RTCIceConnectionState iceState,
  RTCPeerConnectionState? connectionState,
) {
  NetworkQuality newQuality;
  
  // Determine quality based on ICE state (primary indicator)
  if (iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
      iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
    // Check peer connection state for refinement
    if (connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      newQuality = NetworkQuality.excellent;
    } else {
      newQuality = NetworkQuality.good;
    }
  } else if (iceState == RTCIceConnectionState.RTCIceConnectionStateChecking ||
             iceState == RTCIceConnectionState.RTCIceConnectionStateNew) {
    newQuality = NetworkQuality.fair;
  } else if (iceState == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
    newQuality = NetworkQuality.reconnecting;
  } else if (iceState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
             iceState == RTCIceConnectionState.RTCIceConnectionStateClosed) {
    newQuality = NetworkQuality.failed;
  } else {
    newQuality = NetworkQuality.fair;
  }
  
  // Update if changed
  if (newQuality != _networkQuality) {
    _networkQuality = newQuality;
    print('[CallController] 📶 NETWORK_QUALITY: ${newQuality.displayText}');
    onNetworkQualityChange?.call(newQuality);
  }
}
```

**Update ICE connection handler to call quality update:**
```dart
_peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
  print('[CallController] 🧊 ICE_CONNECTION_STATE: $state');
  
  // Update network quality
  _updateNetworkQuality(state, _peerConnection?.connectionState);
  
  // ... existing reconnection logic ...
};
```

**Update peer connection handler:**
```dart
_peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
  print('[CallController] 🔗 CONNECTION_STATE: $state');
  
  // Update network quality
  _updateNetworkQuality(
    _peerConnection?.iceConnectionState ?? RTCIceConnectionState.RTCIceConnectionStateNew,
    state,
  );
  
  // ... existing state change logic ...
};
```

### 2.3 Create Network Quality Indicator Widget

**File:** `lib/widgets/network_quality_indicator.dart` (NEW FILE)

**Create widget:**
```dart
import 'package:flutter/material.dart';
import '../models/network_quality.dart';

/// Network quality indicator widget (signal bars style)
class NetworkQualityIndicator extends StatelessWidget {
  final NetworkQuality quality;
  final bool showLabel;

  const NetworkQualityIndicator({
    super.key,
    required this.quality,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Signal bars
        _buildSignalBars(),
        
        // Optional label
        if (showLabel) ...[
          const SizedBox(width: 6),
          Text(
            quality.displayText,
            style: TextStyle(
              color: quality.color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSignalBars() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(5, (index) {
        final isActive = index < quality.bars;
        return Container(
          width: 4,
          height: 8.0 + (index * 3.0), // Increasing height
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: isActive ? quality.color : Colors.grey.withOpacity(0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
```

### 2.4 Integrate into VideoCallScreen

**File:** `lib/screens/chat/video_call_screen.dart`

**Add state field:**
```dart
NetworkQuality _networkQuality = NetworkQuality.fair;
```

**Update _initializeWebRTC():**
```dart
onNetworkQualityChange: (NetworkQuality quality) {
  print('[VideoCallScreen] 📶 NETWORK_QUALITY_UPDATE: ${quality.displayText}');
  if (mounted) {
    setState(() {
      _networkQuality = quality;
    });
  }
},
```

**Update _buildTopInfoBar():**
```dart
Widget _buildTopInfoBar() {
  return SafeArea(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Contact name and network quality
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.peerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(
                      color: Colors.black45,
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              NetworkQualityIndicator(quality: _networkQuality),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _getStatusText(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              shadows: const [
                Shadow(
                  color: Colors.black45,
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
```

**Add import at top of file:**
```dart
import '../widgets/network_quality_indicator.dart';
import '../models/network_quality.dart';
```

---

## 📋 STEP 3: CALL HISTORY

**Priority:** EXPECTED FEATURE ⭐⭐⭐  
**Time:** 3-4 hours  

### 3.1 Create Call History Model

**File:** `lib/models/call_history.dart` (NEW FILE)

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class CallHistory {
  final String callId;
  final String type;           // 'voice' | 'video'
  final String direction;      // 'incoming' | 'outgoing'
  final String status;         // 'completed' | 'missed' | 'declined' | 'cancelled'
  final String callerId;
  final String callerName;
  final String receiverId;
  final String? receiverName;
  final int? duration;         // seconds (null if not answered)
  final DateTime createdAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;

  CallHistory({
    required this.callId,
    required this.type,
    required this.direction,
    required this.status,
    required this.callerId,
    required this.callerName,
    required this.receiverId,
    this.receiverName,
    this.duration,
    required this.createdAt,
    this.answeredAt,
    this.endedAt,
  });

  factory CallHistory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CallHistory(
      callId: doc.id,
      type: data['type'] ?? 'voice',
      direction: data['direction'] ?? 'outgoing',
      status: data['status'] ?? 'completed',
      callerId: data['callerId'] ?? '',
      callerName: data['callerName'] ?? '',
      receiverId: data['receiverId'] ?? '',
      receiverName: data['receiverName'],
      duration: data['duration'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      answeredAt: data['answeredAt'] != null 
          ? (data['answeredAt'] as Timestamp).toDate() 
          : null,
      endedAt: data['endedAt'] != null 
          ? (data['endedAt'] as Timestamp).toDate() 
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'callId': callId,
      'type': type,
      'direction': direction,
      'status': status,
      'callerId': callerId,
      'callerName': callerName,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'duration': duration,
      'createdAt': Timestamp.fromDate(createdAt),
      'answeredAt': answeredAt != null ? Timestamp.fromDate(answeredAt!) : null,
      'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
    };
  }
}
```

### 3.2 Update FirestoreService

**File:** `lib/services/firestore_service.dart`

**Add callHistory collection:**
```dart
CollectionReference<Map<String, dynamic>> get callHistory =>
    _firestore.collection('callHistory');
```

### 3.3 Save Call History in CallService

**File:** `lib/services/call_service.dart`

**Add method to save history:**
```dart
/// Save call to history
Future<void> _saveCallHistory(String callId, String currentUserId) async {
  try {
    print('[CallService] 💾 Saving call history for $callId');
    
    final callDoc = await _firestoreService.calls.doc(callId).get();
    if (!callDoc.exists) {
      print('[CallService] ⚠️ Call document not found, cannot save history');
