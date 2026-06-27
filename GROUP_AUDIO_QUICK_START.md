# GROUP AUDIO CALLING - QUICK START GUIDE

## 🚀 5-Minute Developer Guide

---

## WHAT WAS BUILT

WhatsApp-style group audio calls with up to 8 participants using WebRTC mesh topology.

---

## HOW TO START A GROUP CALL

```dart
// In your group chat screen, add a call button:
IconButton(
  icon: Icon(Icons.call),
  onPressed: () async {
    final groupCallService = GroupCallService();
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    
    // Start the call
    final callId = await groupCallService.startGroupAudioCall(
      groupId: currentGroupId,
      initiatorId: currentUserId,
    );
    
    // Navigate to call screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupAudioCallScreen(
          callId: callId,
          groupId: currentGroupId,
          groupName: currentGroupName,
          isInitiator: true, // Host
        ),
      ),
    );
  },
)
```

---

## HOW TO RECEIVE A GROUP CALL

```dart
// Add this listener in your app's main entry point or group chat screen:

final groupCallService = GroupCallService();

// Listen for incoming invitations
groupCallService.listenToIncomingGroupCallInvitations().listen((snapshot) {
  for (var doc in snapshot.docs) {
    final invitation = doc.data();
    final callId = invitation['callId'];
    final groupId = invitation['groupId'];
    
    // Show incoming call screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IncomingGroupCallScreen(
          invitationId: doc.id,
          callId: callId,
          groupId: groupId,
        ),
      ),
    );
  }
});
```

---

## HOW TO ACCEPT A CALL

```dart
// In IncomingGroupCallScreen:
await groupCallService.acceptInvitation(invitationId, callId);

// Navigate to call screen
Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (_) => GroupAudioCallScreen(
      callId: callId,
      groupId: groupId,
      groupName: groupName,
      isInitiator: false, // Participant
    ),
  ),
);
```

---

## HOW TO DECLINE A CALL

```dart
await groupCallService.declineInvitation(invitationId, callId);
Navigator.pop(context);
```

---

## KEY FILES TO KNOW

### Core Logic:
1. **`lib/services/group_call_service.dart`**
   - Room management (join/leave/end)
   - Invitation handling
   - Firestore operations

2. **`lib/services/group_call_controller.dart`**
   - WebRTC mesh coordinator
   - Peer connection management
   - Audio transport
   - Speaking detection

3. **`lib/screens/calls/group_audio_call_screen.dart`**
   - Premium UI
   - Participant grid
   - Controls (mute/speaker/leave)

### Data Models:
4. **`lib/models/group_call.dart`**
   - Call document structure
   - Status enums

5. **`lib/models/group_call_participant.dart`**
   - Participant data
   - State management

### Security:
6. **`firebase/firestore.rules`**
   - Group member verification
   - 8-participant limit
   - Permission enforcement

---

## FIRESTORE STRUCTURE

```
groupCalls/
  {callId}/
    type: "group_audio"
    groupId: "..."
    initiatorId: "..."
    status: "ringing" | "active" | "ended"
    joinedParticipants: []
    invitedParticipants: []
    declinedParticipants: []
    leftParticipants: []
    speakingParticipants: []
    maxParticipants: 8
    
    peerConnections/
      {alice_bob}/
        offer: {...}
        answer: {...}
        iceCandidates: [...]

groupCallInvitations/
  {invitationId}/
    callId: "..."
    groupId: "..."
    inviterId: "..."
    targetUserId: "..."
    status: "pending" | "accepted" | "declined"
```

---

## DEBUGGING

### Check Firestore Console:
1. Go to Firebase Console → Firestore
2. Navigate to `groupCalls/{callId}`
3. Verify:
   - `status` is correct
   - `joinedParticipants` contains expected users
   - `type` = "group_audio"

### Check Logs:
```dart
// Search for these log prefixes:
[GroupCallService]     // Room management
[GroupCallController]  // WebRTC
[GroupCallScreen]      // UI updates
```

### Common Issues:

**"Call is full"**
- Maximum 8 participants reached
- Check `joinedParticipants.length`

**"No audio"**
- Check microphone permissions
- Verify peer connections established
- Check STUN server reachable

**"Can't join call"**
- Verify user is group member
- Check Firestore security rules
- Confirm invitation exists

---

## TESTING LOCALLY

### 3-Device Test:
1. **Device A (Host)**:
   - Start group call
   - Verify auto-joined

2. **Device B (Participant 1)**:
   - Accept invitation
   - Verify audio works both ways

3. **Device C (Participant 2)**:
   - Accept invitation
   - Verify all 3 hear each other

### Test Checklist:
- [ ] Audio transmission works
- [ ] Speaking detection glows
- [ ] Mute button works
- [ ] Speaker toggle works
- [ ] Leave call works
- [ ] Call ends when host leaves
- [ ] Rejoin works

---

## PRODUCTION DEPLOYMENT

### Step 1: Deploy Security Rules
```bash
firebase deploy --only firestore:rules --project=your-project-id
```

### Step 2: Build App
```bash
flutter build apk --release
```

### Step 3: Test Staging
- Deploy to internal testing
- Test with 3+ devices
- Verify all features work

### Step 4: Gradual Rollout
- 5% → 20% → 50% → 100%
- Monitor metrics at each stage

---

## MONITORING

### Key Metrics:
- **Call setup time**: < 3 seconds
- **Audio latency**: < 500ms
- **Participant limit**: Enforced at 8
- **Crash rate**: < 1%

### Firebase Console:
- Firestore → Usage (check reads/writes)
- Crashlytics → Errors
- Performance → Call setup duration

---

## COMMON CUSTOMIZATIONS

### Change Participant Limit:
```dart
// In group_call_service.dart
final roomData = {
  'maxParticipants': 12, // Change from 8
  // ...
};

// Also update firestore.rules:
function respectsParticipantLimit() {
  return request.resource.data.joinedParticipants.size() <= 12;
}
```

### Add Call Quality Indicator:
```dart
// In GroupCallController
int getConnectionQuality() {
  // Check RTCPeerConnectionState
  final goodConnections = _peerConnections.values.where(
    (pc) => pc.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected
  ).length;
  
  return (goodConnections / _peerConnections.length * 100).toInt();
}
```

### Custom Speaking Threshold:
```dart
// In GroupCallController._checkAudioLevel()
if (level > 0.3) { // Increase from 0.2 for less sensitivity
  _isSpeaking = true;
}
```

---

## ARCHITECTURE OVERVIEW

```
┌─────────────────────────────────────────┐
│          GROUP AUDIO CALL               │
└─────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
  GroupCallService      GroupCallController
   (Room Mgmt)           (WebRTC Mesh)
        │                       │
        ▼                       ▼
    Firestore              flutter_webrtc
   (Signaling)            (Audio Transport)
```

**Key Point**: Reuses existing `CallController` patterns from 1-to-1 calls.

---

## HELPFUL COMMANDS

### Check Firestore Rules:
```bash
firebase firestore:rules:get --project=your-project-id
```

### Test Rules Locally:
```bash
firebase emulators:start --only firestore
```

### View Logs (Android):
```bash
adb logcat | grep "GroupCall"
```

### View Logs (iOS):
```bash
# Open Xcode → Devices → View Logs
```

---

## SUPPORT RESOURCES

- **Full Architecture**: `GROUP_AUDIO_PHASE_3_ARCHITECTURE.md`
- **Test Plan**: `GROUP_AUDIO_PHASE_3_TEST_PLAN.md`
- **Migration Guide**: `GROUP_AUDIO_PHASE_3_MIGRATION.md`
- **Summary**: `GROUP_AUDIO_PHASE_3_SUMMARY.md`

---

## QUICK TROUBLESHOOTING

| Problem | Solution |
|---------|----------|
| No audio | Check mic permissions, verify peer connections |
| Can't join | Verify group membership, check Firestore rules |
| Call full | Max 8 participants, someone must leave first |
| Echo/feedback | Use earpiece, disable speaker mode |
| High latency | Check network, verify STUN server accessible |
| Call stuck | Check Firestore, call may need cleanup |

---

## EMERGENCY ROLLBACK

If critical bug found:

```dart
// Add to feature_flags.dart
const bool enableGroupAudio = false;

// In UI code:
if (FeatureFlags.enableGroupAudio) {
  // Show group call button
}
```

Redeploy app immediately.

---

**That's it!** You now know how to use, test, and deploy group audio calling.

For detailed implementation, see the full architecture document.

---

**Quick Start Version**: 1.0  
**Last Updated**: [Date]
