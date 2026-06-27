# MODCHAT PHASE 3: GROUP AUDIO CALLING
## Complete Architecture & Implementation Guide

---

## 📋 OVERVIEW

**Status**: Phase 1 (Room Management) ✅ COMPLETE  
**Next**: Phase 3 (Group Audio with WebRTC) 🚀 IMPLEMENTING

**Goal**: Build WhatsApp-style group audio calls on top of existing 1-to-1 architecture.

---

## 🏗️ ARCHITECTURE DIAGRAM

```
┌──────────────────────────────────────────────────────────────┐
│                     GROUP AUDIO CALL FLOW                     │
└──────────────────────────────────────────────────────────────┘

    HOST                  FIRESTORE                 PARTICIPANTS
     │                        │                           │
     │ 1. Start Call          │                           │
     ├────────────────────────>                           │
     │    groupCalls/{callId} │                           │
     │    + invitations       │                           │
     │                        │                           │
     │                        │ 2. Push Invitations       │
     │                        ├───────────────────────────>
     │                        │                           │
     │                        │ 3. Accept/Decline         │
     │                        <───────────────────────────┤
     │                        │                           │
     │                        │ 4. Update Participants    │
     │<───────────────────────┤                           │
     │                        │                           │
     │ 5. WebRTC Mesh Setup   │                           │
     ├────────────────────────┼───────────────────────────>
     │    Peer A ↔ Peer B     │    Peer connections       │
     │    Peer A ↔ Peer C     │    using Firestore        │
     │    Peer B ↔ Peer C     │    for signaling          │
     │                        │                           │
     │ 6. Audio Transport     │                           │
     ├◄───────────────────────┼───────────────────────────►
     │    Direct P2P Audio    │                           │
     │                        │                           │
     │ 7. Leave/End           │                           │
     ├────────────────────────>                           │
     │    Update participants │                           │
     │    Auto-end if empty   │                           │
     │                        │                           │
```

---

## 📊 FIRESTORE SCHEMA

### Collection: `groupCalls/{callId}`

```javascript
{
  callId: "auto-generated",
  type: "group_audio",              // NEW: Explicit call type
  groupId: "group123",
  initiatorId: "uid_host",
  
  // Status lifecycle
  status: "ringing" | "active" | "ended",
  
  // Participant tracking
  invitedParticipants: ["uid2", "uid3", "uid4"],
  joinedParticipants: ["uid_host", "uid2"],
  declinedParticipants: ["uid3"],
  leftParticipants: [],
  
  // NEW: Speaking detection
  speakingParticipants: ["uid_host"],  // Updated in real-time
  
  // Timestamps
  createdAt: Timestamp,
  startedAt: Timestamp,              // When first participant joins
  endedAt: Timestamp,                // When call ends
  
  // Limits
  maxParticipants: 8                 // Enforce participant limit
}
```

### Collection: `groupCallInvitations/{invitationId}`

```javascript
{
  callId: "call123",
  groupId: "group123",
  inviterId: "uid_host",
  targetUserId: "uid2",              // One-to-one mapping
  status: "pending" | "accepted" | "declined" | "expired",
  createdAt: Timestamp,
  expiresAt: Timestamp               // Auto-expire after 1 minute
}
```

### Subcollection: `groupCalls/{callId}/peerConnections/{pairId}`

```javascript
// pairId format: "alice_bob" (alphabetically sorted)
{
  offer: {
    type: "offer",
    sdp: "v=0\r\no=..."
  },
  answer: {
    type: "answer",
    sdp: "v=0\r\no=..."
  },
  iceCandidates: [
    {
      candidate: "...",
      sdpMid: "0",
      sdpMLineIndex: 0,
      from: "alice"
    }
  ],
  createdAt: Timestamp
}
```

---

## 🔒 SECURITY RULES UPDATES

### Requirements:
1. Only group members can read/join calls
2. Only host can end calls (or auto-end when empty)
3. Participants can update their own state
4. Maximum 8 participants enforced
5. Invitation documents are 1-to-1 (secure delivery)

### Rules Already Implemented ✅

See `firebase/firestore.rules`:
- ✅ `groupCalls` collection with participant array checks
- ✅ `groupCallInvitations` with targetUserId filtering
- ✅ `peerConnections` subcollection for signaling
- ✅ Group membership verification

---

## 🎭 WEBRTC MESH ARCHITECTURE

### Mesh Topology (4 participants example)

```
    A ↔ B
    ↕   ↕
    C ↔ D
    
Each participant maintains N-1 peer connections
where N = number of joined participants.

Example with 4 users:
- User A: 3 connections (to B, C, D)
- User B: 3 connections (to A, C, D)  
- User C: 3 connections (to A, B, D)
- User D: 3 connections (to A, B, C)
```

### Peer Connection Lifecycle

1. **User joins call**
   - Get list of already-joined participants
   - Initiate peer connections to each existing participant
   - Existing participants receive notification and accept connections

2. **Peer connection setup**
   - Initiator creates offer → Firestore
   - Receiver reads offer, creates answer → Firestore
   - Both exchange ICE candidates → Firestore
   - Audio tracks flow directly P2P

3. **User leaves call**
   - Close all peer connections
   - Remove from `joinedParticipants`
   - Other participants update their connection lists

4. **Call ends**
   - When last participant leaves OR host ends call
   - All peer connections terminated
   - Status set to "ended"

---

## 🎯 PARTICIPANT STATES

```javascript
enum ParticipantState {
  invited,      // In invitedParticipants array
  joining,      // Transitioning (UI state only)
  connected,    // In joinedParticipants, WebRTC connected
  muted,        // Audio track disabled
  speaking,     // In speakingParticipants array
  left,         // In leftParticipants array  
  declined,     // In declinedParticipants array
}
```

---

## 🎤 SPEAKING DETECTION

### Implementation Strategy

```dart
// Monitor local audio stream levels
Future<void> _startSpeakingDetection() async {
  _audioLevelTimer = Timer.periodic(
    Duration(milliseconds: 100),
    (_) => _checkAudioLevel(),
  );
}

Future<void> _checkAudioLevel() async {
  // Platform-specific audio level detection
  final level = await _getAudioLevel(); // 0.0 - 1.0
  
  if (level > 0.2 && !_isSpeaking) {
    _isSpeaking = true;
    await _updateSpeakingState(true);
  } else if (level <= 0.2 && _isSpeaking) {
    _isSpeaking = false;
    await _updateSpeakingState(false);
  }
}

Future<void> _updateSpeakingState(bool speaking) async {
  if (speaking) {
    await _firestoreService.groupCalls.doc(callId).update({
      'speakingParticipants': FieldValue.arrayUnion([currentUserId])
    });
  } else {
    await _firestoreService.groupCalls.doc(callId).update({
      'speakingParticipants': FieldValue.arrayRemove([currentUserId])
    });
  }
}
```

---

## 📱 UI SPECIFICATIONS

### Group Call Screen Layout

```
┌─────────────────────────────────────┐
│  [Group Avatar]                     │
│  Group Name                         │
│  00:42  •  4 participants           │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────┐  ┌─────────┐          │
│  │  Alice  │  │   Bob   │          │
│  │   🔊    │  │   🔇    │          │
│  └─────────┘  └─────────┘          │
│                                     │
│  ┌─────────┐  ┌─────────┐          │
│  │ Charlie │  │  David  │          │
│  │   🔇    │  │   🔊    │          │
│  └─────────┘  └─────────┘          │
│                                     │
├─────────────────────────────────────┤
│     [🎤]    [🔊]    [❌]            │
│     Mute   Speaker  Leave           │
└─────────────────────────────────────┘
```

### Participant Grid Item

```dart
Widget _buildParticipantTile(Participant p) {
  return Container(
    decoration: BoxDecoration(
      border: Border.all(
        color: p.isSpeaking ? Colors.green : Colors.grey,
        width: p.isSpeaking ? 3 : 1,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundImage: NetworkImage(p.avatarUrl),
        ),
        SizedBox(height: 8),
        Text(p.name),
        if (p.isMuted) Icon(Icons.mic_off, size: 16),
      ],
    ),
  );
}
```

### Incoming Call Screen

```
┌─────────────────────────────────────┐
│                                     │
│       [Group Avatar - Large]        │
│                                     │
│         Engineering Team            │
│                                     │
│    Alice is calling...              │
│                                     │
│    👤 Bob  👤 Charlie  👤 You       │
│                                     │
│                                     │
│    ┌─────────────┐  ┌─────────────┐│
│    │   DECLINE   │  │   ACCEPT    ││
│    │      ❌     │  │      ✅     ││
│    └─────────────┘  └─────────────┘│
│                                     │
└─────────────────────────────────────┘
```

---

## 🔄 CALL LIFECYCLE

### 1. Host Starts Call

```dart
final callId = await groupCallService.startGroupAudioCall(
  groupId: currentGroupId,
  initiatorId: currentUserId,
);

// Automatically:
// - Creates call document
// - Sets status to "ringing"
// - Host auto-joins (added to joinedParticipants)
// - Creates invitation for each group member
```

### 2. Participants Receive Invitation

```dart
// Incoming call listener detects new invitation
incomingGroupCallsStreamProvider.watch((snapshot) {
  for (var doc in snapshot.docs) {
    final invitation = GroupCallInvitation.fromFirestore(doc);
    
    // Show incoming call screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IncomingGroupCallScreen(
          invitation: invitation,
        ),
      ),
    );
  }
});
```

### 3. User Accepts Invitation

```dart
await groupCallService.acceptInvitation(
  invitationId,
  callId,
);

// Automatically:
// - Updates invitation status to "accepted"
// - Joins call (added to joinedParticipants)
// - Removes from invitedParticipants
// - Opens group call screen with WebRTC
```

### 4. WebRTC Connection Setup

```dart
// In GroupCallScreen initState
await _groupCallController.initialize();

// GroupCallController:
// 1. Gets list of joined participants
// 2. Creates peer connection for each participant
// 3. Exchanges SDP offers/answers via Firestore
// 4. Collects ICE candidates
// 5. Establishes direct P2P audio streams
```

### 5. User Leaves Call

```dart
await groupCallService.leaveGroupCall(callId, currentUserId);

// Automatically:
// - Closes all peer connections
// - Removes from joinedParticipants  
// - Adds to leftParticipants
// - Checks if call should end (no participants remaining)
```

### 6. Call Ends

```dart
// Auto-ends when:
// - Last participant leaves
// - Host explicitly ends call

await groupCallService.endGroupCall(callId);

// Sets status to "ended"
// Clears joinedParticipants
```

---

## 📝 FILES CREATED/MODIFIED

### New Files:
1. ✅ `lib/services/group_audio_call_controller.dart` - WebRTC mesh coordinator
2. ✅ `lib/screens/calls/group_audio_call_screen.dart` - Premium call UI
3. ✅ `lib/models/group_call_participant.dart` - Participant data model
4. ✅ `lib/widgets/group_call_participant_tile.dart` - Speaking detection UI

### Modified Files:
1. ✅ `lib/services/group_call_service.dart` - Add audio-specific methods
2. ✅ `lib/providers/group_call_providers.dart` - Add speaking state provider
3. ✅ `firebase/firestore.rules` - Enforce max participants, speaking array
4. ✅ `lib/widgets/incoming_group_call_listener.dart` - Update for audio calls

---

## 🧪 TEST PLAN

### Manual Testing Checklist:

#### Basic Flow:
- [ ] Host starts group audio call in group chat
- [ ] All online group members receive incoming call notification
- [ ] Participant accepts call → joins successfully
- [ ] Participant declines call → no further notifications
- [ ] Audio transport works (participants can hear each other)
- [ ] Speaking indicator glows when user speaks
- [ ] Mute button works (mutes local audio)
- [ ] Speaker toggle works (changes audio output)

#### Edge Cases:
- [ ] Participant leaves call → others continue
- [ ] Host leaves call → call ends for everyone
- [ ] Last participant leaves → call auto-ends
- [ ] Participant rejoins after accidentally leaving
- [ ] Maximum 8 participants enforced
- [ ] 9th user sees "Call Full" message
- [ ] Network interruption → reconnection attempts
- [ ] Network failure after 15s → call drops

#### Multi-Device:
- [ ] 3+ devices in same call (audio mesh works)
- [ ] Mixed platforms (Android + iOS + Web)
- [ ] Background mode handling
- [ ] Incoming notification while app backgrounded

---

## 🚀 DEPLOYMENT STRATEGY

### Phase 3A: Foundation (Day 1)
1. Update Firestore schema (add `type`, `speakingParticipants`)
2. Deploy security rules updates
3. Implement `GroupAudioCallController` (WebRTC mesh)
4. Test 2-participant audio call

### Phase 3B: UI (Day 2)
5. Build `GroupAudioCallScreen` with participant grid
6. Implement speaking detection UI
7. Add mute/speaker/leave controls
8. Test 4-participant call with UI

### Phase 3C: Polish (Day 3)
9. Add participant count badge
10. Implement call duration timer
11. Add network quality indicators
12. Test edge cases (leave/rejoin/end)

### Phase 3D: Production (Day 4)
13. Load testing (8 participants)
14. Performance profiling
15. Final security review
16. Deploy to production

---

## 🔙 ROLLBACK STRATEGY

### If Critical Issues Found:

1. **Disable Group Audio Feature Flag**
   ```dart
   // lib/config/feature_flags.dart
   const bool enableGroupAudio = false; // Set to false
   ```

2. **Revert Firestore Rules**
   ```bash
   firebase deploy --only firestore:rules --project=your-project-id
   ```

3. **Database Cleanup**
   ```javascript
   // Clean up any stuck calls
   db.groupCalls
     .where('status', 'in', ['ringing', 'active'])
     .where('createdAt', '<', Date.now() - 60000)
     .get()
     .then(snapshot => {
       snapshot.forEach(doc => doc.ref.update({ status: 'ended' }));
     });
   ```

---

## ✅ SUCCESS CRITERIA

### Phase 3 Complete When:

- [x] 1-to-1 calls still work (no regression)
- [x] Video calls still work (no regression)
- [ ] Single Firestore call document per group call
- [ ] Multiple participants can join simultaneously
- [ ] Active participant tracking works
- [ ] Speaking detection highlights active speaker
- [ ] Participants can leave without ending call
- [ ] Host can end call for everyone
- [ ] Call auto-ends when empty
- [ ] Maximum 8 participants enforced
- [ ] Rejoin support works
- [ ] Audio quality is clear (no echo/feedback)
- [ ] Network resilience (15s reconnection timeout)

---

## 📚 REFERENCES

### Existing Architecture:
- `lib/services/call_controller.dart` - 1-to-1 WebRTC implementation
- `lib/services/call_service.dart` - Call lifecycle management
- `lib/screens/chat/call_screen.dart` - 1-to-1 voice call UI
- `lib/screens/chat/video_call_screen.dart` - 1-to-1 video call UI

### Libraries Used:
- `flutter_webrtc` - WebRTC peer connections
- `cloud_firestore` - Signaling and state sync
- `flutter_riverpod` - State management

---

**End of Architecture Document**
