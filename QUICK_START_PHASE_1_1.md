# 🚀 Quick Start: Phase 1.1 Testing

## ✅ Implementation Complete

Phase 1.1 (Perfect Signaling) is ready for testing.

---

## 📱 What You Need

- **5 Real Devices** (not simulators)
- **5 Test Accounts** (Users A, B, C, D, E)
- **1 Group Chat** with all 5 users as members
- **Stable Internet** on all devices

---

## 🎯 What to Test

**One simple goal:** Verify every invited user receives the incoming call **exactly once**.

---

## 🧪 5-Minute Test

### Setup (2 min)
1. Install app on 5 devices
2. Login as Users A, B, C, D, E
3. Create group with all 5 users
4. Open group chat on all devices

### Test (3 min)

**STEP 1: User A starts call**
- Open group chat
- Press call button
- ✅ Should see call screen immediately
- ✅ Should NOT see incoming dialog

**STEP 2: Check other users (B, C, D, E)**
- ✅ Should ALL see incoming call dialog
- ✅ Dialog shows group name and "From: User A"
- ✅ Dialog has Accept and Decline buttons

**STEP 3: User B accepts**
- Press "Accept"
- ✅ Should navigate to call screen
- ✅ Should see Status: ACTIVE
- ✅ Should see Joined: [A, B]

**STEP 4: User C declines**
- Press "Decline"
- ✅ Dialog should close
- ✅ Should NOT see dialog again

**STEP 5: User A ends call**
- Press "End Call for Everyone"
- ✅ All users should exit call screen

---

## ✅ Pass Criteria

Check ALL these:

- [ ] Users B, C, D, E all received incoming call
- [ ] User A did NOT receive incoming call
- [ ] Each dialog appeared exactly once
- [ ] Accept worked (navigated to call screen)
- [ ] Decline worked (dialog closed)
- [ ] No duplicate dialogs

**If ALL checked:** Phase 1.1 PASSES ✅

**If ANY unchecked:** Phase 1.1 FAILS ❌ - See troubleshooting below

---

## 🔍 Console Logs

Open console on all devices. You should see:

### User A (Caller):
```
[GROUP_SIGNAL] ROOM_CREATED: xxx
[GROUP_SIGNAL] INVITATION_CREATED -> B
[GROUP_SIGNAL] INVITATION_CREATED -> C
[GROUP_SIGNAL] INVITATION_CREATED -> D
[GROUP_SIGNAL] INVITATION_CREATED -> E
```

### Users B, C, D, E (Invited):
```
[GROUP_SIGNAL] INVITATION_RECEIVED -> {userId}
[GROUP_SIGNAL] INCOMING_SCREEN_SHOWN
```

### User B (Accepts):
```
[GROUP_SIGNAL] INVITATION_ACCEPTED -> B
[GROUP_SIGNAL] USER_JOINED -> B
```

### User C (Declines):
```
[GROUP_SIGNAL] INVITATION_DECLINED -> C
```

---

## 🐛 Troubleshooting

### Problem 1: User didn't receive invitation

**Check:**
1. Is user in the group?
2. Check Firebase Console → groupCallInvitations
3. Is there an invitation document for this user?
4. Check console logs for errors

**Solution:**
- Verify Firestore rules deployed
- Verify user is group member
- Check internet connection

### Problem 2: Duplicate dialogs

**Check:**
1. Console shows multiple `INCOMING_SCREEN_SHOWN`
2. Dialog appears more than once

**Solution:**
- Check duplicate protection logic
- Verify `_shownInvitationIds` set is working
- May need to restart app

### Problem 3: Caller sees dialog

**Check:**
1. User A sees incoming dialog
2. Console shows `INCOMING_SCREEN_SHOWN` on caller device

**Solution:**
- Check invitation creation logic
- Initiator should NOT be in invitation list
- Bug in service logic

### Problem 4: Accept/Decline doesn't work

**Check:**
1. Press button but nothing happens
2. Console shows errors

**Solution:**
- Check Firestore rules
- Check network connection
- Check permission errors in console

---

## 🔥 Firebase Console Check

### View Invitations

1. Go to Firebase Console
2. Firestore → groupCallInvitations
3. You should see documents like:

```
inv1: {
  targetUserId: "B",
  callId: "xxx",
  status: "pending"
}
```

**Verify:**
- One document per invited user
- 4 documents total (B, C, D, E)
- No document for User A (caller)

### Watch Status Changes

When User B accepts:
```
inv1: {
  status: "accepted"  ← Changed
}
```

When User C declines:
```
inv2: {
  status: "declined"  ← Changed
}
```

---

## 📊 Expected Results

### Firestore After Test

**groupCalls collection:**
```javascript
{
  callId: "xxx",
  groupId: "group123",
  initiatorId: "A",
  joinedParticipants: ["A", "B"],
  invitedParticipants: ["D", "E"],
  declinedParticipants: ["C"],
  leftParticipants: [],
  status: "active"
}
```

**groupCallInvitations collection:**
```javascript
inv1: { targetUserId: "B", status: "accepted" }
inv2: { targetUserId: "C", status: "declined" }
inv3: { targetUserId: "D", status: "pending" }
inv4: { targetUserId: "E", status: "pending" }
```

---

## 🎯 Success = ALL GREEN

- ✅ Every invited user received incoming call
- ✅ Incoming screen appeared exactly once
- ✅ Accept worked
- ✅ Decline worked
- ✅ Caller did NOT receive own invitation
- ✅ No duplicate notifications
- ✅ Real-time updates worked

**If ALL green:** Phase 1.1 is PERFECT ✅

---

## 🚀 Next Phase

**ONLY after Phase 1.1 passes:**

Phase 2 will add:
- WebRTC audio transport
- Offer/Answer signaling
- ICE candidate exchange
- Actual audio streaming
- Mute/unmute controls

**DO NOT START PHASE 2 UNTIL SIGNALING IS PERFECT.**

---

## 📚 Full Documentation

For complete details:
- **`PHASE_1_1_SIGNALING_TEST.md`** - Comprehensive test guide
- **`PHASE_1_1_COMPLETE.md`** - Implementation details

---

## ⚡ TL;DR

1. Start call on User A device
2. Check Users B, C, D, E all see incoming dialog
3. Accept on one, decline on another
4. Verify no duplicates
5. End call

**If it works:** ✅ PASS  
**If it doesn't:** ❌ FAIL - See troubleshooting

---

**Test now. Verify signaling is bulletproof. Then proceed to Phase 2.**
