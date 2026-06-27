# Phase 1.1: Perfect Signaling Test Guide

## 🎯 OBJECTIVE

**Prove that signaling is 100% reliable BEFORE touching WebRTC.**

Every invited user must receive the incoming call notification **exactly once**.

---

## 🚫 WHAT THIS PHASE DOES NOT INCLUDE

- ❌ NO WebRTC
- ❌ NO Audio transport
- ❌ NO Video transport
- ❌ NO CallController
- ❌ NO PeerConnection
- ❌ NO Offers/Answers
- ❌ NO ICE candidates

**This phase is SIGNALING ONLY.**

---

## 🏗️ NEW ARCHITECTURE

### Dedicated Invitation Documents

**Old approach (unreliable):**
- Users query `groupCalls` collection
- Generic queries can miss updates
- Unreliable delivery

**New approach (reliable):**
- One invitation document per user
- Each user listens for `targetUserId == currentUserId`
- Guaranteed delivery

### Firestore Structure

```javascript
// Collection: groupCallInvitations
{
  invitationId: "auto-generated",
  callId: "...",
  groupId: "...",
  inviterId: "userA",
  targetUserId: "userB",  // ← Specific user
  status: "pending",
  createdAt: Timestamp,
  expiresAt: Timestamp
}
```

**Example:**
User A calls group with members: A, B, C, D, E

Creates **4 invitation documents:**
1. Invitation for B (targetUserId: B)
2. Invitation for C (targetUserId: C)
3. Invitation for D (targetUserId: D)
4. Invitation for E (targetUserId: E)

---

## 🔍 VERIFICATION LOGS

All operations log with `[GROUP_SIGNAL]` prefix:

```
[GROUP_SIGNAL] ROOM_CREATED: {callId}
[GROUP_SIGNAL] INVITATION_CREATED -> {userId}
[GROUP_SIGNAL] INVITATION_RECEIVED -> {userId}
[GROUP_SIGNAL] INCOMING_SCREEN_SHOWN
[GROUP_SIGNAL] INVITATION_ACCEPTED -> {userId}
[GROUP_SIGNAL] INVITATION_DECLINED -> {userId}
[GROUP_SIGNAL] USER_JOINED -> {userId}
```

Watch console logs on all devices to verify delivery.

---

## ✅ SUCCESS CRITERIA

All criteria must pass on **5 real devices**:

1. ✅ Every invited user receives incoming call
2. ✅ Incoming screen appears exactly once per user
3. ✅ Accept works correctly
4. ✅ Decline works correctly
5. ✅ Caller does NOT receive own invitation
6. ✅ No duplicate notifications
7. ✅ Real-time updates work

---

## 🧪 TEST SCENARIOS

### Test Setup
- **5 Users:** A, B, C, D, E
- **Group:** All 5 users are members
- **5 Devices:** One per user (real devices, not simulators)

---

### Test 1: Complete Flow

**STEP 1: User A starts call**

**Expected:**
- ✅ User A sees call screen immediately (no incoming dialog)
- ✅ Console log: `[GROUP_SIGNAL] ROOM_CREATED: {callId}`
- ✅ Console logs: `[GROUP_SIGNAL] INVITATION_CREATED -> B`
- ✅ Console logs: `[GROUP_SIGNAL] INVITATION_CREATED -> C`
- ✅ Console logs: `[GROUP_SIGNAL] INVITATION_CREATED -> D`
- ✅ Console logs: `[GROUP_SIGNAL] INVITATION_CREATED -> E`

**STEP 2: Users B, C, D, E receive invitation**

**Expected on each device:**
- ✅ Console log: `[GROUP_SIGNAL] INVITATION_RECEIVED -> {userId}`
- ✅ Console log: `[GROUP_SIGNAL] INCOMING_SCREEN_SHOWN`
- ✅ Incoming call dialog appears
- ✅ Shows group name
- ✅ Shows "From: User A"
- ✅ Shows "Accept" and "Decline" buttons

**Verify:**
- [ ] User B sees dialog
- [ ] User C sees dialog
- [ ] User D sees dialog
- [ ] User E sees dialog
- [ ] User A does NOT see dialog

**STEP 3: User B accepts**

**Actions:**
- User B presses "Accept"

**Expected:**
- ✅ Console log: `[GROUP_SIGNAL] INVITATION_ACCEPTED -> B`
- ✅ Console log: `[GROUP_SIGNAL] USER_JOINED -> B`
- ✅ User B navigates to call screen
- ✅ User B sees: Status = ACTIVE
- ✅ User B sees: Joined = [A, B]
- ✅ User B sees: Invited = [C, D, E]

**STEP 4: User C declines**

**Actions:**
- User C presses "Decline"

**Expected:**
- ✅ Console log: `[GROUP_SIGNAL] INVITATION_DECLINED -> C`
- ✅ Dialog closes
- ✅ All users see: Declined = [C]

**STEP 5: User D accepts**

**Actions:**
- User D presses "Accept"

**Expected:**
- ✅ Console log: `[GROUP_SIGNAL] INVITATION_ACCEPTED -> D`
- ✅ Console log: `[GROUP_SIGNAL] USER_JOINED -> D`
- ✅ User D navigates to call screen
- ✅ All users see: Joined = [A, B, D]
- ✅ All users see: Declined = [C]
- ✅ All users see: Invited = [E]

**STEP 6: User E ignores (does nothing)**

**Expected:**
- ✅ User E dialog stays visible
- ✅ User E can accept or decline later
- ✅ All users see: Invited = [E]

**STEP 7: User B leaves call**

**Actions:**
- User B presses "Leave Call"

**Expected:**
- ✅ User B exits call screen
- ✅ All remaining users see: Joined = [A, D]
- ✅ All remaining users see: Left = [B]

**STEP 8: User A ends call**

**Actions:**
- User A presses "End Call for Everyone"

**Expected:**
- ✅ Status changes to "ended"
- ✅ All users exit call screen
- ✅ User E's dialog dismisses

---

### Test 2: Duplicate Protection

**STEP 1:** User A starts call

**STEP 2:** User B receives invitation

**STEP 3:** User B accepts

**STEP 4:** User B should NOT see incoming dialog again

**Expected:**
- ✅ Console log: `[GROUP_SIGNAL] ⚠️ Already shown - ignoring`
- ✅ No duplicate dialog appears

---

### Test 3: Decline Protection

**STEP 1:** User A starts call

**STEP 2:** User C receives invitation

**STEP 3:** User C declines

**STEP 4:** User C should NOT see incoming dialog again

**Expected:**
- ✅ Console log: `[GROUP_SIGNAL] ⚠️ Already shown - ignoring`
- ✅ No duplicate dialog appears

---

### Test 4: Multiple Simultaneous Calls

**STEP 1:** User A starts call in Group 1

**STEP 2:** User F starts call in Group 2 (User B is in both groups)

**Expected:**
- ✅ User B sees incoming dialog for Group 1 call
- ✅ User B sees incoming dialog for Group 2 call
- ✅ Both dialogs are distinct
- ✅ User B can respond to each independently

---

### Test 5: Caller Experience

**STEP 1:** User A starts call

**Expected:**
- ✅ User A does NOT see incoming dialog
- ✅ User A directly opens call screen
- ✅ User A sees: Status = RINGING
- ✅ User A sees: Joined = [A]
- ✅ User A sees: Invited = [B, C, D, E]

---

## 🔥 Firebase Console Verification

### Check Invitations Collection

1. Go to Firebase Console
2. Navigate to Firestore
3. Open `groupCallInvitations` collection

**Verify structure:**
```javascript
{
  callId: "...",
  groupId: "...",
  inviterId: "userA",
  targetUserId: "userB",
  status: "pending",
  createdAt: Timestamp,
  expiresAt: Timestamp
}
```

**Verify counts:**
- Group with 5 members (A, B, C, D, E)
- User A starts call
- Should see **4 invitation documents** (one per invited user)

### Check Status Updates

Watch invitation documents update in real-time:

**When User B accepts:**
```javascript
{
  status: "accepted"  // ← Changed from "pending"
}
```

**When User C declines:**
```javascript
{
  status: "declined"  // ← Changed from "pending"
}
```

---

## 📊 Console Log Checklist

Watch console on all 5 devices. You should see:

### User A (Caller):
```
[GROUP_SIGNAL] 📞 Starting group call
[GROUP_SIGNAL] ROOM_CREATED: xxx
[GROUP_SIGNAL] Creating 4 invitation documents
[GROUP_SIGNAL] INVITATION_CREATED -> B
[GROUP_SIGNAL] INVITATION_CREATED -> C
[GROUP_SIGNAL] INVITATION_CREATED -> D
[GROUP_SIGNAL] INVITATION_CREATED -> E
[GROUP_SIGNAL] ✅ Call setup complete
```

### User B (Accepts):
```
[GROUP_SIGNAL] 👂 Listening for invitations -> B
[GROUP_SIGNAL] INVITATION_RECEIVED -> B
[GROUP_SIGNAL] Invitation ID: xxx
[GROUP_SIGNAL] INCOMING_SCREEN_SHOWN
[GROUP_SIGNAL] User accepting invitation xxx
[GROUP_SIGNAL] INVITATION_ACCEPTED -> B
[GROUP_SIGNAL] USER_JOINED -> B
[GROUP_SIGNAL] ✅ User joined call xxx
```

### User C (Declines):
```
[GROUP_SIGNAL] 👂 Listening for invitations -> C
[GROUP_SIGNAL] INVITATION_RECEIVED -> C
[GROUP_SIGNAL] INCOMING_SCREEN_SHOWN
[GROUP_SIGNAL] User declining invitation xxx
[GROUP_SIGNAL] INVITATION_DECLINED -> C
[GROUP_SIGNAL] ✅ User declined call xxx
```

---

## ❌ FAILURE SCENARIOS

If any of these occur, **signaling is broken**:

### Failure 1: Missing Invitation
- User does not receive incoming call
- Console does NOT show `INVITATION_RECEIVED`
- **Cause:** Invitation document not created or listener not working

### Failure 2: Duplicate Dialog
- User sees incoming call dialog multiple times
- Console shows multiple `INCOMING_SCREEN_SHOWN` for same invitation
- **Cause:** Duplicate protection not working

### Failure 3: Caller Sees Dialog
- User A (caller) sees incoming call dialog
- Console shows `INCOMING_SCREEN_SHOWN` on caller device
- **Cause:** Not filtering out caller's own invitations

### Failure 4: Slow Delivery
- Invitation takes >2 seconds to appear
- **Cause:** Firestore listener lag or indexing issues

### Failure 5: Accept/Decline Fails
- User presses Accept/Decline but nothing happens
- Console shows error
- **Cause:** Permission error or service method failure

---

## 🛠️ DEBUGGING

### Check 1: Firestore Rules
Verify rules allow invitation operations:
```bash
firebase deploy --only firestore:rules
```

### Check 2: Firestore Indexes
Check if query needs index:
- targetUserId == currentUserId
- status == 'pending'

### Check 3: Console Logs
Enable verbose logging on all devices.

### Check 4: Network
Ensure all devices have stable internet connection.

---

## ✅ SIGN-OFF CHECKLIST

Before proceeding to Phase 2 (WebRTC), ALL must pass:

- [ ] **Test 1:** Complete flow passes on 5 devices
- [ ] **Test 2:** Duplicate protection works
- [ ] **Test 3:** Decline protection works
- [ ] **Test 4:** Multiple calls work
- [ ] **Test 5:** Caller experience correct
- [ ] **Firebase:** Invitation documents created correctly
- [ ] **Firebase:** Status updates in real-time
- [ ] **Logs:** All expected logs appear
- [ ] **Logs:** No error logs
- [ ] **UI:** Incoming dialog appears exactly once
- [ ] **UI:** Accept navigates to call screen
- [ ] **UI:** Decline dismisses dialog
- [ ] **No WebRTC:** Confirmed zero WebRTC code executed

---

## 🚀 NEXT PHASE

**Only after ALL tests pass:**

Phase 2 will add:
- WebRTC audio transport
- Offer/Answer signaling
- ICE candidate exchange
- Actual audio streaming

**DO NOT START PHASE 2 UNTIL SIGNALING IS PERFECT.**

---

## 📝 Test Results Log

Date: ___________

### Test 1: Complete Flow
- [ ] PASS
- [ ] FAIL
- Notes: ________________________________

### Test 2: Duplicate Protection
- [ ] PASS
- [ ] FAIL
- Notes: ________________________________

### Test 3: Decline Protection
- [ ] PASS
- [ ] FAIL
- Notes: ________________________________

### Test 4: Multiple Calls
- [ ] PASS
- [ ] FAIL
- Notes: ________________________________

### Test 5: Caller Experience
- [ ] PASS
- [ ] FAIL
- Notes: ________________________________

### Overall Result
- [ ] ALL TESTS PASSED - Ready for Phase 2
- [ ] SOME TESTS FAILED - Fix and retest

---

**Signaling must be bulletproof before adding WebRTC complexity.**
