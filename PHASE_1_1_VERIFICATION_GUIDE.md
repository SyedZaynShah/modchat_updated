# PHASE 1.1: GROUP ROOM VERIFICATION GUIDE

## ✅ IMPLEMENTATION COMPLETE

**Date:** 2026-06-28  
**Status:** Ready for Testing  
**Components:** GroupCall Model + GroupCallService + Test Screen

---

## 🎯 WHAT WAS IMPLEMENTED

### ✅ GroupCall Model
**Location:** `lib/models/group_call.dart`

**Fields:**
- `callId` - Unique room identifier
- `groupId` - Group this call belongs to
- `initiatorId` - User who started the call
- `invitedParticipants` - Users invited but not yet responded
- `joinedParticipants` - Users currently in the room
- `declinedParticipants` - Users who declined
- `leftParticipants` - Users who left after joining
- `status` - ringing | active | ended
- `createdAt` - Room creation timestamp
- `startedAt` - When first non-initiator joined

### ✅ GroupCallService
**Location:** `lib/services/group_call_service.dart`

**Methods:**
- `createGroupCall()` - Create new room
- `joinGroupCall()` - Join existing room
- `declineGroupCall()` - Decline invitation
- `leaveGroupCall()` - Leave room
- `endGroupCall()` - End room (initiator or auto)
- `listenToGroupCall()` - Real-time updates
- `getActiveGroupCall()` - Check for existing call

### ✅ Test Screen
**Location:** `lib/screens/calls/group_call_test_screen.dart`

**Features:**
- Real-time participant count
- Live participant list with status
- Join/Leave/Decline buttons
- Auto-updates across all devices
- No WebRTC, No audio, No video

### ✅ Navigation
- Orange science icon (🧪) added to group chat header
- Tap to open test screen

---

## 🚫 WHAT IS NOT INCLUDED

As per Phase 1.1 requirements, the following are **EXPLICITLY EXCLUDED**:

- ❌ NO WebRTC (RTCPeerConnection)
- ❌ NO CallController
- ❌ NO CallService
- ❌ NO MediaStream
- ❌ NO getUserMedia()
- ❌ NO Audio transport
- ❌ NO Video transport
- ❌ NO Signaling (offer/answer/ICE)
- ❌ NO Call screens with audio controls

**This is PURE room management only.**

---

## 📋 TESTING PROCEDURE

### Prerequisites
- 4 test devices/users (A, B, C, D)
- All users must be members of the same group

### Test Scenario

#### STEP 1: User A Creates Room
1. Open group chat
2. Tap orange science icon (🧪)
3. Tap "Start Group Call"
4. Observe:
   - ✅ Status changes to "Ringing"
   - ✅ Room ID displayed
   - ✅ "In Call" shows 1 participant (User A auto-joins)
   - ✅ "Invited" shows all other members (B, C, D)

#### STEP 2: User B Joins Room
1. User B opens same group chat
2. Tap orange science icon (🧪)
3. See blue invitation banner: "You have been invited to this call"
4. Tap "Join"
5. Observe on ALL DEVICES:
   - ✅ Status changes to "Active"
   - ✅ "In Call" shows 2 participants (A, B)
   - ✅ "Invited" shows 2 participants (C, D)
   - ✅ Updates appear **instantly**

#### STEP 3: User C Joins Room
1. User C opens same group chat
2. Tap orange science icon (🧪)
3. Tap "Join"
4. Observe on ALL DEVICES:
   - ✅ "In Call" shows 3 participants (A, B, C)
   - ✅ "Invited" shows 1 participant (D)
   - ✅ Updates appear **instantly**

#### STEP 4: User D Joins Room
1. User D opens same group chat
2. Tap orange science icon (🧪)
3. Tap "Join"
4. Observe on ALL DEVICES:
   - ✅ "In Call" shows 4 participants (A, B, C, D)
   - ✅ "Invited" shows 0 participants
   - ✅ Updates appear **instantly**

#### STEP 5: User C Leaves Room
1. User C taps "Leave Call"
2. Observe on ALL DEVICES:
   - ✅ "In Call" shows 3 participants (A, B, D)
   - ✅ "Left" shows 1 participant (C)
   - ✅ User C sees "You left this call"
   - ✅ Call continues for A, B, D

#### STEP 6: User A (Initiator) Leaves Room
1. User A taps "End Call for Everyone"
2. Observe on ALL DEVICES:
   - ✅ Status changes to "Ended"
   - ✅ All participants removed from "In Call"
   - ✅ "No Active Call" displayed
   - ✅ Room terminated for everyone

#### STEP 7: Test Decline Functionality
1. User A starts new call
2. User B taps "Decline"
3. Observe on ALL DEVICES:
   - ✅ "Declined" shows 1 participant (B)
   - ✅ User B sees "You declined this call"
   - ✅ User B can still see room as observer

#### STEP 8: Test Last Participant Leaving
1. User A starts new call
2. User B joins
3. User A leaves (initiator)
4. Observe:
   - ✅ Call ends (initiator left)
5. Start new call with A
6. User B joins
7. User A leaves (initiator)
8. Call should end

---

## ✅ SUCCESS CRITERIA

All of the following must be TRUE:

1. ✅ User can create room
2. ✅ Room ID is displayed
3. ✅ Participant count updates in real-time
4. ✅ Participant list updates in real-time
5. ✅ All devices see updates **instantly** (< 1 second)
6. ✅ Initiator auto-joins room
7. ✅ Status changes: ringing → active → ended
8. ✅ Users can join, decline, or leave
9. ✅ Initiator leaving ends call for everyone
10. ✅ Last participant leaving ends call
11. ✅ No WebRTC code is executed
12. ✅ No audio/video streams created
13. ✅ No CallController instantiated
14. ✅ No RTCPeerConnection created

---

## 🗄️ FIRESTORE STRUCTURE

### Collection: `groupCalls/`

Example Document:
```json
{
  "type": "group_audio",
  "groupId": "group_xyz",
  "initiatorId": "user_a",
  "invitedParticipants": ["user_c", "user_d"],
  "joinedParticipants": ["user_a", "user_b"],
  "declinedParticipants": [],
  "leftParticipants": [],
  "speakingParticipants": [],
  "status": "active",
  "maxParticipants": 8,
  "createdAt": Timestamp,
  "startedAt": Timestamp
}
```

### Real-Time Listener Query
```dart
FirebaseFirestore.instance
  .collection('groupCalls')
  .doc(callId)
  .snapshots()
```

---

## 🔧 TROUBLESHOOTING

### Issue: Updates not appearing instantly
**Check:**
- Firestore rules allow read access
- All users are listening to same callId
- Internet connection stable

### Issue: Cannot join call
**Check:**
- User is member of group
- Call status is not 'ended'
- User not already in joinedParticipants

### Issue: Cannot create call
**Check:**
- User is member of group
- No existing active call for group
- Firestore rules allow write access

### Issue: Call doesn't end when initiator leaves
**Check:**
- GroupCallService.leaveGroupCall() logic
- Check if userId == initiatorId
- Verify endGroupCall() is called

---

## 📊 CONSOLE LOG MARKERS

When testing, watch console for these markers:

```
[GROUP_SIGNAL] 📞 Starting group call
[GROUP_SIGNAL] ROOM_CREATED: <callId>
[GROUP_SIGNAL] USER_JOINED -> <userId>
[GROUP_SIGNAL] INVITATION_DECLINED -> <userId>
[GroupCallService] ➕ User <userId> joining call <callId>
[GroupCallService] ✅ User joined
[GroupCallService] ➖ User <userId> leaving call <callId>
[GroupCallService] 🚪 Initiator leaving → ending call
[GroupCallService] 🔚 Ending call <callId>
```

---

## 🎯 NEXT PHASE

After Phase 1.1 verification passes:

**Phase 2: Signaling Infrastructure**
- Design mesh signaling protocol
- Implement offer/answer exchange
- Add ICE candidate routing

**Phase 3: WebRTC Audio Transport**
- Create GroupCallController
- Manage multiple peer connections
- Implement audio streaming
- Add UI controls (mute, speaker)

---

## 📝 NOTES

- Room management is COMPLETELY INDEPENDENT of WebRTC
- This phase verifies Firestore real-time sync only
- No audio will play during this test
- Test screen is for verification only (will be removed later)
- Orange science icon is temporary (Phase 1.1 only)

---

## ✅ COMPLETION CHECKLIST

Mark each item when verified:

- [ ] User A can create room
- [ ] User B sees invitation instantly
- [ ] User B can join
- [ ] User C sees B joined instantly
- [ ] User C can join
- [ ] User D sees C joined instantly
- [ ] User D can join
- [ ] All 4 users visible on all devices
- [ ] Participant count accurate on all devices
- [ ] User can decline invitation
- [ ] User can leave after joining
- [ ] Initiator leaving ends call for all
- [ ] Last participant leaving ends call
- [ ] Status changes visible to all

---

**Status:** 🟢 Ready for Testing  
**Date:** 2026-06-28  
**Phase:** 1.1 - Room Verification Only
