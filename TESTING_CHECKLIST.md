# ✅ Group Call Testing Checklist

Use this checklist to track your testing progress. Check off each item as you verify it works.

---

## 📋 PRE-TEST SETUP

- [ ] App compiled without errors
- [ ] App installed on Device A
- [ ] App installed on Device B
- [ ] Device A logged in (User A)
- [ ] Device B logged in (User B)
- [ ] Both users are members of same group
- [ ] Microphone permission granted on Device A
- [ ] Microphone permission granted on Device B
- [ ] Both devices have stable network (WiFi or mobile data)
- [ ] Console logs visible on both devices

---

## 🧪 TEST 1: CALL INITIATION

### Device A Actions
- [ ] Open group chat
- [ ] Phone icon visible in top-right AppBar
- [ ] Tap phone icon
- [ ] Navigate to call screen
- [ ] See own name with "Host" badge
- [ ] Status shows "Ringing..." or "Connecting..."

### Device A Console
- [ ] `[GroupCallService] ✅ Call created`
- [ ] `[GroupCallController] 🎤 Initializing local audio stream`
- [ ] `[GroupCallController] ✅ Local stream initialized`

**Result:** ✅ Pass / ❌ Fail

**Notes:**
```
(Add any observations or issues)
```

---

## 🧪 TEST 2: INCOMING CALL DETECTION

### Device B Experience
- [ ] Wait 2-5 seconds
- [ ] Incoming call screen appears automatically
- [ ] NO need to open group chat
- [ ] Screen shows group name
- [ ] Screen shows initiator name: "X is calling..."
- [ ] Accept button visible
- [ ] Decline button visible

### Device B Console
- [ ] `[IncomingGroupCallListener] 🔔 Incoming group call`

**Result:** ✅ Pass / ❌ Fail

**Notes:**
```
(If failed, what happened? Screen didn't appear? Wrong info displayed?)
```

---

## 🧪 TEST 3: CALL ACCEPTANCE

### Device B Actions
- [ ] Tap "Accept" button
- [ ] Navigate to call screen
- [ ] See Device A as participant
- [ ] Status shows "Connecting..."

### Device B Console
- [ ] `[IncomingGroupCallScreen] 📞 Accepting group call`
- [ ] `[IncomingGroupCallScreen] ✅ Joined call, navigating to call screen`
- [ ] `[GroupCallController] 🎤 Initializing local audio stream`
- [ ] `[GroupCallController] ✅ Local stream initialized`

**Result:** ✅ Pass / ❌ Fail

**Notes:**
```
(Any errors or unexpected behavior?)
```

---

## 🧪 TEST 4: WEBRTC SIGNALING - DEVICE A

### Device A Console Logs
- [ ] `[GroupAudioCallScreen] ➕ Adding participant: <B's userId>`
- [ ] `[GroupCallController] 🔗 Creating peer connection for <B>`
- [ ] `[GroupCallController] 📤 Creating offer for <B>`
- [ ] `[GroupCallController] ✅ Offer sent to <B>`
- [ ] `[GroupCallController] 👂 Listening to signaling for <B>`
- [ ] `[GroupCallController] 📨 Received answer from <B>`
- [ ] `[GroupCallController] ✅ Answer set for <B>`
- [ ] `[GroupCallController] 📤 ICE candidate sent to <B>` (multiple times)
- [ ] `[GroupCallController] 📥 ICE candidate from <B>` (multiple times)
- [ ] `[GroupCallController] 🔗 Connection state for <B>: checking`
- [ ] `[GroupCallController] 🔗 Connection state for <B>: connected`
- [ ] `[GroupCallController] 📥 Received track from <B>`

**Total ICE candidates sent:** _____
**Total ICE candidates received:** _____
**Time to connect:** _____ seconds

**Result:** ✅ Pass / ❌ Fail

**Notes:**
```
(Where did it stop? What error appeared?)
```

---

## 🧪 TEST 5: WEBRTC SIGNALING - DEVICE B

### Device B Console Logs
- [ ] `[GroupAudioCallScreen] ➕ Adding participant: <A's userId>`
- [ ] `[GroupCallController] 🔗 Creating peer connection for <A>`
- [ ] `[GroupCallController] 👂 Listening to signaling for <A>`
- [ ] `[GroupCallController] 📨 Received offer from <A>`
- [ ] `[GroupCallController] ✅ Answer sent to <A>`
- [ ] `[GroupCallController] 📤 ICE candidate sent to <A>` (multiple times)
- [ ] `[GroupCallController] 📥 ICE candidate from <A>` (multiple times)
- [ ] `[GroupCallController] 🔗 Connection state for <A>: checking`
- [ ] `[GroupCallController] 🔗 Connection state for <A>: connected`
- [ ] `[GroupCallController] 📥 Received track from <A>`

**Total ICE candidates sent:** _____
**Total ICE candidates received:** _____
**Time to connect:** _____ seconds

**Result:** ✅ Pass / ❌ Fail

**Notes:**
```
(Any differences from Device A?)
```

---

## 🧪 TEST 6: AUDIO TRANSMISSION - A TO B

### Test Steps
- [ ] Device A: Speak clearly: "Hello from Device A"
- [ ] Device B: Audio heard clearly
- [ ] No distortion
- [ ] No delay (< 500ms)
- [ ] No echo
- [ ] Volume adequate

**Audio Quality:** ⭐⭐⭐⭐⭐ (rate 1-5 stars)

**Result:** ✅ Pass / ❌ Fail

**Notes:**
```
(Describe audio quality, any issues)
```

---

## 🧪 TEST 7: AUDIO TRANSMISSION - B TO A

### Test Steps
- [ ] Device B: Speak clearly: "Hello from Device B"
- [ ] Device A: Audio heard clearly
- [ ] No distortion
- [ ] No delay (< 500ms)
- [ ] No echo
- [ ] Volume adequate

**Audio Quality:** ⭐⭐⭐⭐⭐ (rate 1-5 stars)

**Result:** ✅ Pass / ❌ Fail

**Notes:**
```
(Describe audio quality, any issues)
```

---

## 🧪 TEST 8: MUTE FUNCTIONALITY

### Device A Tests
- [ ] Tap "Mute" button
- [ ] Button shows "muted" state (icon changes)
- [ ] Device A speaks
- [ ] Device B does NOT hear
- [ ] Console: `[GroupCallController] 🎤 Mute: true`

- [ ] Tap "Mute" again (unmute)
- [ ] Button shows "unmuted" state
- [ ] Device A speaks
- [ ] Device B hears clearly
- [ ] Console: `[GroupCallController] 🎤 Mute: false`

**Result:** ✅ Pass / ❌ Fail

**Notes:**
```
(Did mute work both ways?)
```

---

## 🧪 TEST 9: SPEAKER FUNCTIONALITY

### Device A Tests
- [ ] Tap "Speaker" button
- [ ] Button shows "speaker on" state
- [ ] Audio routes to loudspeaker (audible without holding to ear)
- [ ] Console: `[GroupCallController] 🔊 Speaker: true`

- [ ] Tap "Speaker" again
- [ ] Button shows "speaker off" state
- [ ] Audio routes to earpiece (must hold to ear)
- [ ] Console: `[GroupCallController] 🔊 Speaker: false`

**Result:** ✅ Pass / ❌ Fail

**Notes:**
```
(Did speaker toggle work? Any audio routing issues?)
```

---

## 🧪 TEST 10: THIRD PARTICIPANT (Optional)

### Device C Actions
- [ ] App installed on Device C
- [ ] Logged in as User C
- [ ] Member of same group
- [ ] Wait for incoming call screen
- [ ] Tap Accept

### Device C Console
- [ ] Local stream initialized
- [ ] Creating peer connection for A
- [ ] Creating peer connection for B
- [ ] Connection state: connected (both)
- [ ] Received track from A
- [ ] Received track from B

### All Devices
- [ ] Device A shows 3 participants
- [ ] Device B shows 3 participants
- [ ] Device C shows 3 participants
- [ ] A can hear B and C
- [ ] B can hear A and C
- [ ] C can hear A and B

**Result:** ✅ Pass / ❌ Fail

**Notes:**
```
(How many peer connections? Audio quality with 3?)
```

---

## 🧪 TEST 11: FIRESTORE DATA VERIFICATION

### Call Document
Navigate to: `Firebase Console → Firestore → groupCalls → {callId}`

- [ ] Document exists
- [ ] `groupId`: correct group ID
- [ ] `initiatorId`: User A's ID
- [ ] `participants`: array with [A, B] (or [A, B, C])
- [ ] `joinedParticipants`: array with [A, B] (or [A, B, C])
- [ ] `status`: "active"
- [ ] `type`: "audio"
- [ ] `hostId`: User A's ID

**Screenshot:** (optional)

---

### Signaling Documents
Navigate to: `groupCalls → {callId} → signaling`

- [ ] Document `{A}_{B}` exists
  - [ ] `type`: "offer"
  - [ ] `sdp`: long string starting with "v=0"
  - [ ] `from`: User A's ID
  - [ ] `to`: User B's ID

- [ ] Document `{B}_{A}` exists
  - [ ] `type`: "answer"
  - [ ] `sdp`: long string starting with "v=0"
  - [ ] `from`: User B's ID
  - [ ] `to`: User A's ID

**Screenshot:** (optional)

---

### ICE Candidates
Navigate to: `groupCalls → {callId} → signaling → {A}_{B}_ice → candidates`

- [ ] Collection exists
- [ ] Multiple candidate documents present (or were present before cleanup)
- [ ] Each has: `candidate`, `sdpMid`, `sdpMLineIndex`, `from`

**Note:** Candidates may be auto-deleted after processing, so might be empty.

---

## 🧪 TEST 12: EDGE CASES

### Call End
- [ ] Device A: Tap "End Call" button
- [ ] Call ends on Device A
- [ ] Call ends on Device B (screen closes or updates)
- [ ] Firestore: status updated to "ended"
- [ ] No errors in console

### Network Interruption (Optional)
- [ ] Temporarily disable WiFi on one device
- [ ] Re-enable WiFi
- [ ] Check if call reconnects or needs manual rejoin

### Multiple Calls
- [ ] Start second call while first is active
- [ ] Verify: Should not allow (or should end first call)

---

## 📊 OVERALL RESULTS

### Summary
- **Tests Passed:** _____ / 12
- **Tests Failed:** _____
- **Tests Skipped:** _____

### Overall Status
- [ ] ✅ All critical tests passed (1-9)
- [ ] ⚠️ Some tests failed (specify below)
- [ ] ❌ Critical failure (audio not working)

---

## 🐛 ISSUES ENCOUNTERED

### Issue 1
**Test:** _____
**Description:**
```
(What went wrong?)
```
**Console Logs:**
```
(Relevant error messages)
```
**Firestore Data:**
```
(What was in Firestore?)
```

### Issue 2
**Test:** _____
**Description:**
```

```

### Issue 3
**Test:** _____
**Description:**
```

```

---

## 💡 RECOMMENDATIONS

Based on test results:

- [ ] Feature is production-ready
- [ ] Minor issues need fixing (list above)
- [ ] Major issues need addressing (list above)
- [ ] Feature needs re-implementation

---

## 📝 ADDITIONAL NOTES

```
(Any other observations, suggestions, or feedback)







```

---

## ✅ SIGN-OFF

**Tested By:** _____________________
**Date:** _____________________
**Environment:** 
- Device A Model: _____________________
- Device B Model: _____________________
- Device C Model: _____________________ (if tested)
- Network: WiFi / Mobile Data
- Flutter Version: _____________________
- App Version: _____________________

**Overall Assessment:**
```
(Final verdict: Ready for production? Needs more work? Specific next steps?)
```

---

**For detailed debugging, see:** `test_group_call_signaling.md`
**For quick test, see:** `QUICK_TEST_GUIDE.md`
**For implementation details, see:** `GROUP_CALL_IMPLEMENTATION_COMPLETE.md`
