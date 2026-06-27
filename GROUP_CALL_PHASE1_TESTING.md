# Group Call Phase 1 Testing Guide

## ⚠️ PHASE 1 SCOPE

**WHAT IS IMPLEMENTED:**
- ✅ Room creation
- ✅ Participant invitation tracking
- ✅ Join room functionality
- ✅ Decline invitation functionality
- ✅ Leave room functionality
- ✅ End room functionality
- ✅ Real-time room state updates
- ✅ Duplicate invitation protection

**WHAT IS NOT IMPLEMENTED (Phase 2):**
- ❌ WebRTC audio transport
- ❌ WebRTC video transport
- ❌ PeerConnections
- ❌ Offer/Answer signaling
- ❌ ICE candidates
- ❌ Actual media streaming
- ❌ Mute/unmute controls
- ❌ Speaker controls
- ❌ Call timer

---

## 🗂️ Firestore Structure

### Collection: `groupCalls/{callId}`

```javascript
{
  callId: "auto-generated",
  groupId: "group123",
  initiatorId: "userA",
  status: "ringing" | "active" | "ended",
  createdAt: Timestamp,
  invitedParticipants: ["userB", "userC", "userD", "userE"],
  joinedParticipants: ["userA"],
  declinedParticipants: [],
  leftParticipants: []
}
```

---

## 🧪 Test Scenarios

### Setup: 5 Users in Group
- User A (Initiator)
- User B
- User C
- User D
- User E

---

### Test 1: Room Creation
**Action:** User A starts group call

**Expected State:**
```javascript
{
  status: "ringing",
  initiatorId: "userA",
  joinedParticipants: ["userA"],
  invitedParticipants: ["userB", "userC", "userD", "userE"],
  declinedParticipants: [],
  leftParticipants: []
}
```

**Verify:**
- ✅ Room document created in Firestore
- ✅ User A in `joinedParticipants`
- ✅ Users B, C, D, E in `invitedParticipants`
- ✅ Status is "ringing"

---

### Test 2: First User Joins (Accept)
**Action:** User B accepts invitation

**Expected State:**
```javascript
{
  status: "active",  // ← Status changes to active
  joinedParticipants: ["userA", "userB"],
  invitedParticipants: ["userC", "userD", "userE"],
  declinedParticipants: [],
  leftParticipants: []
}
```

**Verify:**
- ✅ User B moved from `invitedParticipants` to `joinedParticipants`
- ✅ Status changed from "ringing" to "active"
- ✅ Real-time update received by all devices

---

### Test 3: User Declines
**Action:** User C declines invitation

**Expected State:**
```javascript
{
  status: "active",
  joinedParticipants: ["userA", "userB"],
  invitedParticipants: ["userD", "userE"],
  declinedParticipants: ["userC"],
  leftParticipants: []
}
```

**Verify:**
- ✅ User C moved from `invitedParticipants` to `declinedParticipants`
- ✅ User C's incoming call UI dismissed
- ✅ User C cannot see incoming call again (duplicate protection)

---

### Test 4: Another User Joins
**Action:** User D accepts invitation

**Expected State:**
```javascript
{
  status: "active",
  joinedParticipants: ["userA", "userB", "userD"],
  invitedParticipants: ["userE"],
  declinedParticipants: ["userC"],
  leftParticipants: []
}
```

**Verify:**
- ✅ User D moved to `joinedParticipants`
- ✅ Real-time updates work for all participants

---

### Test 5: User Leaves
**Action:** User B leaves the call

**Expected State:**
```javascript
{
  status: "active",
  joinedParticipants: ["userA", "userD"],
  invitedParticipants: ["userE"],
  declinedParticipants: ["userC"],
  leftParticipants: ["userB"]
}
```

**Verify:**
- ✅ User B moved from `joinedParticipants` to `leftParticipants`
- ✅ User B's call UI closed
- ✅ User B cannot rejoin (duplicate protection)
- ✅ Call continues for User A and User D

---

### Test 6: Initiator Leaves (End Call)
**Action:** User A (initiator) leaves the call

**Expected State:**
```javascript
{
  status: "ended",
  joinedParticipants: [],
  invitedParticipants: ["userE"],
  declinedParticipants: ["userC"],
  leftParticipants: ["userB"]
}
```

**Verify:**
- ✅ Status changed to "ended"
- ✅ All `joinedParticipants` cleared
- ✅ All participants' call UI closed
- ✅ Room document preserved for history

---

### Test 7: Last Participant Leaves
**Setup:** User A and User B in call, User A leaves

**Expected State:**
```javascript
{
  status: "ended",
  joinedParticipants: [],
  // ...
}
```

**Verify:**
- ✅ When last participant leaves, status changes to "ended"
- ✅ Call automatically ends

---

### Test 8: Duplicate Invitation Protection
**Actions:** 
1. User B joins call
2. User B's device receives another incoming call notification

**Expected:**
- ✅ No incoming call UI shown (User B already in `joinedParticipants`)

**Actions:**
1. User C declines call
2. User C's device receives another incoming call notification

**Expected:**
- ✅ No incoming call UI shown (User C already in `declinedParticipants`)

---

## 🔍 Code Integration Points

### Service Methods to Test

```dart
final service = GroupCallService();

// Create room
String callId = await service.createGroupCall(
  groupId: 'group123',
  initiatorId: 'userA',
);

// Join room
await service.joinGroupCall(callId, 'userB');

// Decline invitation
await service.declineGroupCall(callId, 'userC');

// Leave room
await service.leaveGroupCall(callId, 'userB');

// End room
await service.endGroupCall(callId);

// Listen to incoming calls
service.listenToIncomingGroupCalls().listen((snapshot) {
  for (var doc in snapshot.docs) {
    final call = GroupCall.fromFirestore(doc);
    // Show incoming call UI
  }
});

// Listen to specific call
service.listenToGroupCall(callId).listen((snapshot) {
  if (snapshot.exists) {
    final call = GroupCall.fromFirestore(snapshot);
    // Update UI with call state
  }
});
```

---

## ✅ Success Criteria

All tests must pass before proceeding to Phase 2:

- [ ] Room creation works
- [ ] Initiator auto-joins on creation
- [ ] Status transitions (ringing → active → ended)
- [ ] Join functionality moves users correctly
- [ ] Decline functionality works
- [ ] Leave functionality works
- [ ] Initiator leaving ends call
- [ ] Last participant leaving ends call
- [ ] Real-time updates work for all devices
- [ ] Duplicate invitation protection works
- [ ] Firestore security rules allow proper access
- [ ] No WebRTC code exists in Phase 1

---

## 🚫 Phase 1 Limitations

**YOU SHOULD NOT SEE:**
- ❌ Audio waveforms
- ❌ Mute/unmute buttons
- ❌ Speaker toggle
- ❌ Call timer
- ❌ Video streams
- ❌ Connection quality indicators

**YOU SHOULD SEE:**
- ✅ Participant list with status
- ✅ Join/Decline buttons (for invited users)
- ✅ Leave/End call buttons (for joined users)
- ✅ Real-time participant status updates
- ✅ Simple participant status UI (Joined/Invited/Declined)

---

## 🎯 Next Steps

After Phase 1 testing passes:

**STOP. DO NOT PROCEED TO PHASE 2 WITHOUT APPROVAL.**

Phase 2 will add:
- WebRTC audio transport
- Offer/Answer signaling
- ICE candidate exchange
- Actual audio streaming
- Mute/unmute functionality

---

## 📝 Notes

- Phase 1 is purely about room state management
- Think of it like WhatsApp's "Connecting..." screen before audio starts
- All participant tracking happens in Firestore
- No audio/video transport happens in Phase 1
- This ensures room management architecture is solid before adding WebRTC complexity
