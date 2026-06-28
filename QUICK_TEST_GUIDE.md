# PHASE 1.1 + 1.2 - QUICK TEST GUIDE

## 🚀 How to Test (5 Minutes)

**NEW IN PHASE 1.2:** Rejoin support added! Users can now rejoin after leaving or declining.

### Prerequisites
- 4 devices/users in the same group
- App running on all devices

### Step-by-Step

#### 1️⃣ USER A: Start Call
```
Open group chat
→ Tap orange science icon 🧪
→ Tap "Start Group Call"
```
**Expected:**
- Status: "Ringing"
- In Call: 1 (User A)
- Invited: 3 (Users B, C, D)

#### 2️⃣ USER B: Join Call
```
Open group chat
→ Tap orange science icon 🧪
→ See blue banner: "You have been invited"
→ Tap "Join"
```
**Expected on ALL devices:**
- Status: "Active"
- In Call: 2 (Users A, B)
- Invited: 2 (Users C, D)
- ⚡ Updates appear INSTANTLY

#### 3️⃣ USER C: Join Call
```
Tap "Join"
```
**Expected on ALL devices:**
- In Call: 3 (Users A, B, C)
- Invited: 1 (User D)
- ⚡ Updates appear INSTANTLY

#### 4️⃣ USER D: Join Call
```
Tap "Join"
```
**Expected on ALL devices:**
- In Call: 4 (Users A, B, C, D)
- Invited: 0
- ⚡ Updates appear INSTANTLY

#### 5️⃣ USER C: Leave Call
```
Tap "Leave Call"
```
**Expected on ALL devices:**
- In Call: 3 (Users A, B, D)
- Left: 1 (User C)
- ⚡ Call continues for others

#### 6️⃣ USER C: Rejoin (NEW: Phase 1.2)
```
User C sees "Rejoin Call" button
→ Tap "Rejoin Call"
```
**Expected on ALL devices:**
- In Call: 4 (Users A, B, C, D)
- Left: 0
- ⚡ User C removed from "Left" list

#### 7️⃣ USER A: End Call
```
Tap "End Call for Everyone"
```
**Expected on ALL devices:**
- Status: "Ended"
- In Call: 0
- ⚡ Room terminated

---

## ✅ Success = All These True

### Phase 1.1 (Room Management)
- [ ] All 4 users can see the science icon 🧪
- [ ] User A can create room
- [ ] Other users see invitation instantly
- [ ] Users can join one by one
- [ ] Participant count updates on all devices
- [ ] Participant list updates on all devices
- [ ] Updates appear in < 1 second
- [ ] Initiator leaving ends call for all
- [ ] No audio plays (this is room management only)
- [ ] No video appears (this is room management only)

### Phase 1.2 (Rejoin Support) 🆕
- [ ] User can leave and see "Rejoin Call" button
- [ ] User can tap "Rejoin Call" and return to call
- [ ] User can decline and see "Join Call" button
- [ ] User can tap "Join Call" after declining
- [ ] Multiple leave/rejoin cycles work
- [ ] Rejoined user removed from "Left" list
- [ ] All devices see rejoin updates instantly

---

## 🐛 If Something Breaks

### Can't see science icon?
- Pull latest code
- Check `group_chat_detail_screen.dart` has orange icon
- Rebuild app

### Can't create room?
- Check Firestore rules allow write to `groupCalls/`
- Check user is member of group
- Check console for errors

### Updates not instant?
- Check internet connection
- Check Firestore is online
- Refresh screen (pull down)

### Call doesn't end?
- Check console logs for "Initiator leaving"
- Verify `endGroupCall()` is called
- Check Firestore rules

---

## 📱 What You'll See

### Status Card
```
┌─────────────────────────────┐
│ 👥 Test Group               │
├─────────────────────────────┤
│ Status: Active              │
│ Call ID: abc123...          │
└─────────────────────────────┘
```

### Call Info Card
```
┌─────────────────────────────┐
│ Call Information            │
├─────────────────────────────┤
│ Participants: 4             │
│ Invited: 0                  │
│ Declined: 0                 │
│ Left: 0                     │
└─────────────────────────────┘
```

### Participants Card
```
┌─────────────────────────────┐
│ Participants                │
├─────────────────────────────┤
│ ✓ In Call (4)               │
│   • User A (Initiator)      │
│   • User B                  │
│   • User C                  │
│   • User D                  │
└─────────────────────────────┘
```

---

## 🎯 What This Tests

✅ Room creation  
✅ Real-time Firestore sync  
✅ Participant tracking  
✅ Join/Leave lifecycle  
✅ **Rejoin after leave (Phase 1.2)** 🆕  
✅ **Join after decline (Phase 1.2)** 🆕  
✅ Initiator ending call  
✅ Status transitions  
✅ UI updates across devices  

❌ NOT tested (comes in Phase 2+):  
- Audio streaming
- Video streaming
- WebRTC connections
- Call quality
- Network issues

---

## ⚡ Pro Tips

1. **Open test screen on all devices before starting**
   - Easier to see instant updates

2. **Watch the participant count**
   - Should increment/decrement immediately

3. **Check console logs**
   - See `[GROUP_SIGNAL]` markers

4. **Test decline button too**
   - Start new call
   - Have one user decline
   - Others should still be able to join

5. **Test last participant leaving**
   - Start call with 2 users
   - Have both leave (non-initiator first)
   - Room should auto-end

6. **Test rejoin (Phase 1.2)** 🆕
   - Start call
   - User joins then leaves
   - User sees "Rejoin Call" button
   - User taps and rejoins successfully

7. **Test join after decline (Phase 1.2)** 🆕
   - Start call
   - User declines invitation
   - User sees "Join Call" button
   - User taps and joins successfully

---

**Total Test Time:** 5-7 minutes  
**Required Devices:** 4  
**Network:** Internet required  
**Audio/Video:** None (room management only)
