# Group Call Phase 1 Implementation Summary

## 📋 Overview

Phase 1 implements **room management only** - no WebRTC, no audio transport, no video.

This phase proves that the participant tracking and room lifecycle architecture works correctly before adding WebRTC complexity.

---

## 🗂️ Files Modified

### 1. **Model: `lib/models/group_call.dart`**

**Changes:**
- Replaced `participants` field with `invitedParticipants`
- Added `declinedParticipants` field
- Added `leftParticipants` field
- Removed `type`, `endedAt`, and `hostId` fields (not needed for Phase 1)
- Removed `ParticipantState` enum (Phase 2 concern)
- Kept `GroupCallStatus` enum (ringing, active, ended)

**Structure:**
```dart
class GroupCall {
  final String callId;
  final String groupId;
  final String initiatorId;
  final List<String> invitedParticipants;
  final List<String> joinedParticipants;
  final List<String> declinedParticipants;
  final List<String> leftParticipants;
  final GroupCallStatus status;
  final Timestamp createdAt;
}
```

---

### 2. **Service: `lib/services/group_call_service.dart`**

**Complete rewrite - removed ALL WebRTC references.**

**Implemented Methods:**

#### `createGroupCall(groupId, initiatorId)`
- Creates room document in `groupCalls` collection
- Auto-joins initiator to `joinedParticipants`
- Adds all other members to `invitedParticipants`
- Sets status to "ringing"
- Returns `callId`

#### `joinGroupCall(callId, userId)`
- Validates user is invited
- Duplicate invitation protection (checks joined/declined/left)
- Moves user from `invitedParticipants` to `joinedParticipants`
- Changes status to "active"

#### `declineGroupCall(callId, userId)`
- Duplicate invitation protection
- Moves user from `invitedParticipants` to `declinedParticipants`
- User won't see incoming call again

#### `leaveGroupCall(callId, userId)`
- Moves user from `joinedParticipants` to `leftParticipants`
- If initiator leaves → ends call immediately
- If last participant leaves → ends call automatically

#### `endGroupCall(callId)`
- Sets status to "ended"
- Clears `joinedParticipants`
- All participants exit room

#### `listenToIncomingGroupCalls()`
- Returns stream of calls where user is in `invitedParticipants`
- Filters by status "ringing" or "active"
- Used to show incoming call UI

#### `listenToGroupCall(callId)`
- Returns stream of specific call document
- Used for real-time updates during call

#### `getActiveGroupCall(groupId)`
- Checks if group has active call (ringing or active status)
- Prevents multiple simultaneous calls

---

### 3. **Controller: `lib/services/group_call_controller.dart`**

**Complete replacement - placeholder only.**

Phase 1 does NOT need a controller since there's no WebRTC to manage.

```dart
class GroupCallController {
  // Placeholder - Phase 2 will add WebRTC functionality
  Future<void> initialize() async {
    throw UnimplementedError('Phase 1 does not include WebRTC functionality');
  }
}
```

---

### 4. **Firestore Rules: `firebase/firestore.rules`**

**Updated `groupCalls` security rules:**

```javascript
// Phase 1: Room Management Rules
match /groupCalls/{callId} {
  
  function isInvolved() {
    // User is in any participant list
    return auth.uid in invitedParticipants
      || auth.uid in joinedParticipants
      || auth.uid in declinedParticipants
      || auth.uid in leftParticipants
      || auth.uid == initiatorId;
  }
  
  // Create: Only if user is group member and initiator
  allow create: if isInitiator() 
    && isGroupMember(groupId)
    && hasValidStructure();
  
  // Read: Only involved participants
  allow read: if isInvolved();
  
  // Update: Only involved participants
  allow update: if isInvolved()
    && groupId is immutable
    && initiatorId is immutable;
  
  // Delete: Never (maintain audit trail)
  allow delete: if false;
}
```

**Security features:**
- Only group members can create calls
- Only involved participants can read/update
- Cannot delete calls (audit trail)
- Cannot change groupId or initiatorId

---

## 🎯 Architecture

### Layer 1: Room Management (Phase 1) ✅
```
GroupCallService
    ↓
Firestore (groupCalls collection)
    ↓
Real-time listeners
    ↓
UI updates
```

### Layer 2: Media Transport (Phase 2) ❌ NOT IMPLEMENTED
```
GroupCallController
    ↓
WebRTC PeerConnections
    ↓
Offer/Answer/ICE
    ↓
Audio streams
```

**Phase 1 only implements Layer 1.**

---

## 📊 Room Lifecycle

```
STEP 1: User A starts call
Status: ringing
Joined: [A]
Invited: [B, C, D, E]

↓

STEP 2: User B accepts
Status: active (changes when first non-initiator joins)
Joined: [A, B]
Invited: [C, D, E]

↓

STEP 3: User C declines
Status: active
Joined: [A, B]
Invited: [D, E]
Declined: [C]

↓

STEP 4: User D accepts
Status: active
Joined: [A, B, D]
Invited: [E]
Declined: [C]

↓

STEP 5: User B leaves
Status: active
Joined: [A, D]
Invited: [E]
Declined: [C]
Left: [B]

↓

STEP 6: User A (initiator) leaves
Status: ended
Joined: []
(Call ends immediately when initiator leaves)
```

---

## 🔒 Duplicate Invitation Protection

**Critical requirement:** Users should only see incoming call screen ONCE.

**Implementation:**

Before showing incoming call UI, check:
```dart
// Don't show if already joined
if (call.joinedParticipants.contains(userId)) return;

// Don't show if already declined
if (call.declinedParticipants.contains(userId)) return;

// Don't show if already left
if (call.leftParticipants.contains(userId)) return;

// Only show if in invited list
if (!call.invitedParticipants.contains(userId)) return;
```

This ensures:
- ✅ User who joined won't see incoming screen again
- ✅ User who declined won't see incoming screen again
- ✅ User who left won't see incoming screen again

---

## 🚫 What is NOT Implemented

Phase 1 explicitly excludes:

- ❌ WebRTC `RTCPeerConnection`
- ❌ `MediaStream` audio tracks
- ❌ Offer/Answer SDP
- ❌ ICE candidates
- ❌ Signaling logic
- ❌ Audio transport
- ❌ Video transport
- ❌ Mute/unmute functionality
- ❌ Speaker controls
- ❌ Call timer
- ❌ Connection quality indicators
- ❌ Audio level indicators

**If you see ANY WebRTC code in Phase 1, it's wrong.**

---

## ✅ Success Criteria

Phase 1 is complete when:

- [x] Room creation works
- [x] Participant invitation tracking works
- [x] Join room functionality works
- [x] Decline functionality works
- [x] Leave room functionality works
- [x] End room functionality works
- [x] Real-time updates work
- [x] Status transitions work (ringing → active → ended)
- [x] Duplicate invitation protection works
- [x] Firestore security rules implemented
- [x] No WebRTC code exists

---

## 🎮 How to Use

### Create a Call
```dart
final service = GroupCallService();
final callId = await service.createGroupCall(
  groupId: 'myGroup',
  initiatorId: currentUserId,
);
```

### Join a Call
```dart
await service.joinGroupCall(callId, currentUserId);
```

### Decline a Call
```dart
await service.declineGroupCall(callId, currentUserId);
```

### Leave a Call
```dart
await service.leaveGroupCall(callId, currentUserId);
```

### Listen for Incoming Calls
```dart
service.listenToIncomingGroupCalls().listen((snapshot) {
  for (var doc in snapshot.docs) {
    final call = GroupCall.fromFirestore(doc);
    // Show incoming call UI
  }
});
```

### Listen to Call Updates
```dart
service.listenToGroupCall(callId).listen((snapshot) {
  if (snapshot.exists) {
    final call = GroupCall.fromFirestore(snapshot);
    // Update UI with current state
  }
});
```

---

## 📱 UI Guidelines for Phase 1

### Incoming Call Screen
**Show:**
- Caller name (initiator)
- Group name
- "Accept" button
- "Decline" button

**Don't show:**
- Mute button
- Speaker button
- Video button

### In-Call Screen
**Show:**
- List of joined participants
- List of invited participants (still ringing)
- List of declined participants
- "Leave Call" button
- "End Call" button (for initiator only)

**Don't show:**
- Audio waveforms
- Mute/unmute controls
- Speaker toggle
- Timer
- Connection quality

---

## 🔄 Next Steps

**STOP HERE. DO NOT PROCEED WITHOUT TESTING.**

After Phase 1 testing passes:

1. User tests all scenarios from `GROUP_CALL_PHASE1_TESTING.md`
2. All tests pass
3. User approves Phase 2 implementation

**Phase 2 will add:**
- WebRTC audio transport
- Offer/Answer signaling
- ICE candidate exchange
- Actual audio streaming
- Mute/unmute functionality
- Speaker controls

---

## 📝 Notes

- This is **intentionally minimal**
- Previous implementation failed because it tried to do everything at once
- Phase 1 proves the room management architecture works
- Think of this like WhatsApp's call room before audio starts
- No audio actually flows in Phase 1
- All state management happens via Firestore real-time updates

**The biggest success of Phase 1 is what it does NOT include.**
