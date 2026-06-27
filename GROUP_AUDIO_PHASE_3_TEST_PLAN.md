# GROUP AUDIO CALLING - PHASE 3 TEST PLAN

## 🧪 COMPREHENSIVE TESTING GUIDE

---

## TEST ENVIRONMENT SETUP

### Prerequisites:
- [ ] 3+ test devices (Android/iOS/Web mix recommended)
- [ ] 3+ test accounts with different user IDs
- [ ] Group chat with all test accounts as members
- [ ] Firebase project with updated security rules deployed
- [ ] App built with Phase 3 code

### Test Accounts:
```
Account A (Host): alice@test.com
Account B: bob@test.com
Account C: charlie@test.com
Account D: david@test.com
```

---

## 🟢 PHASE 1: BASIC FUNCTIONALITY

### Test 1.1: Host Starts Group Audio Call

**Steps:**
1. Login as Account A
2. Open group chat with all test accounts
3. Tap group call button
4. Verify call document created in Firestore

**Expected:**
- [x] Call status = "ringing"
- [x] Host auto-added to `joinedParticipants`
- [x] Other members added to `invitedParticipants`
- [x] Invitation documents created for each member
- [x] Type field = "group_audio"

**Firestore Verification:**
```javascript
groupCalls/{callId}:
{
  type: "group_audio",
  status: "ringing",
  initiatorId: "alice_uid",
  joinedParticipants: ["alice_uid"],
  invitedParticipants: ["bob_uid", "charlie_uid", "david_uid"],
  speakingParticipants: [],
  maxParticipants: 8
}
```

---

### Test 1.2: Participant Receives Incoming Call

**Steps:**
1. Ensure Account B is logged in
2. Wait for incoming call notification
3. Verify incoming call screen appears

**Expected:**
- [x] Push notification received (if app backgrounded)
- [x] Incoming group call screen shows
- [x] Group name displayed
- [x] Host name shown ("Alice is calling...")
- [x] Accept/Decline buttons visible

---

### Test 1.3: Participant Accepts Call

**Steps:**
1. On Account B device, tap "Accept"
2. Wait for group call screen to load
3. Verify WebRTC initialization

**Expected:**
- [x] Invitation status updated to "accepted"
- [x] User moved to `joinedParticipants`
- [x] Call status changed to "active"
- [x] WebRTC peer connections established
- [x] Group call screen opens
- [x] Participant grid shows Alice and Bob
- [x] Audio routing to earpiece by default

**Firestore Verification:**
```javascript
groupCalls/{callId}:
{
  status: "active",
  joinedParticipants: ["alice_uid", "bob_uid"],
  invitedParticipants: ["charlie_uid", "david_uid"],
  startedAt: Timestamp
}
```

---

### Test 1.4: Participant Declines Call

**Steps:**
1. On Account C device, tap "Decline"
2. Verify call screen closes
3. Check Firestore update

**Expected:**
- [x] Invitation status updated to "declined"
- [x] User moved to `declinedParticipants`
- [x] No further notifications
- [x] Incoming call screen closes

**Firestore Verification:**
```javascript
groupCalls/{callId}:
{
  invitedParticipants: ["david_uid"],
  declinedParticipants: ["charlie_uid"]
}
```

---

## 🔊 PHASE 2: AUDIO TRANSPORT

### Test 2.1: Audio Transmission (2 Participants)

**Setup:** Alice (host) and Bob have joined

**Steps:**
1. On Alice device, speak into microphone
2. On Bob device, verify audio heard
3. On Bob device, speak into microphone
4. On Alice device, verify audio heard

**Expected:**
- [x] Alice's voice heard clearly on Bob's device
- [x] Bob's voice heard clearly on Alice's device
- [x] No echo or feedback
- [x] Audio quality is clear
- [x] Latency < 500ms

---

### Test 2.2: Audio Transmission (3+ Participants)

**Setup:** Alice, Bob, and David have joined

**Steps:**
1. Each participant speaks in turn
2. Verify all others can hear
3. Test simultaneous speaking

**Expected:**
- [x] Mesh topology works (3 peer connections for 3 users)
- [x] All participants hear each other
- [x] Mixed audio from multiple speakers works
- [x] No audio dropouts

**WebRTC Verification:**
```
Alice peer connections: [Bob, David]
Bob peer connections: [Alice, David]
David peer connections: [Alice, Bob]
```

---

### Test 2.3: Speaking Detection

**Steps:**
1. On Alice device, start speaking
2. On Bob and David devices, observe Alice's participant tile
3. Alice stops speaking
4. Bob starts speaking

**Expected:**
- [x] Alice's tile glows green when speaking
- [x] `speakingParticipants` array updated in real-time
- [x] Glow disappears when Alice stops
- [x] Bob's tile glows when Bob speaks
- [x] UI updates within 200ms

**Firestore Verification:**
```javascript
// When Alice speaks:
speakingParticipants: ["alice_uid"]

// When Alice stops and Bob speaks:
speakingParticipants: ["bob_uid"]
```

---

## 🎛️ PHASE 3: CONTROLS

### Test 3.1: Mute Button

**Steps:**
1. On Bob device, tap mute button
2. Speak into microphone
3. On Alice device, verify no audio heard
4. On Bob device, tap unmute
5. Speak again

**Expected:**
- [x] Mute button icon changes to mic_off
- [x] No audio transmitted when muted
- [x] Bob's tile shows muted icon
- [x] Unmute restores audio transmission
- [x] Bob removed from `speakingParticipants` when muted

---

### Test 3.2: Speaker Toggle

**Steps:**
1. On Alice device, tap speaker button
2. Verify audio routes to loudspeaker
3. Tap speaker button again
4. Verify audio routes back to earpiece

**Expected:**
- [x] Audio volume increases (loudspeaker)
- [x] Audio still clear without distortion
- [x] Icon changes (hearing ↔ volume_up)
- [x] Toggle works instantly

---

### Test 3.3: Leave Call (Non-Host)

**Steps:**
1. On Bob device, tap "Leave Call"
2. Verify screen closes
3. On Alice device, verify Bob removed from grid
4. Check Firestore state

**Expected:**
- [x] Bob's peer connections closed
- [x] Bob's audio stops on all devices
- [x] Bob moved to `leftParticipants`
- [x] Bob removed from `joinedParticipants`
- [x] Call continues for remaining participants
- [x] Bob's tile disappears from Alice's grid

**Firestore Verification:**
```javascript
groupCalls/{callId}:
{
  joinedParticipants: ["alice_uid", "david_uid"],
  leftParticipants: ["bob_uid"]
}
```

---

### Test 3.4: Rejoin After Leave

**Steps:**
1. Bob left the call (previous test)
2. In group chat, check for "Join Ongoing Call" button
3. Bob taps "Join Ongoing Call"
4. Verify Bob rejoins successfully

**Expected:**
- [x] "Join Ongoing Call" button visible while call active
- [x] Bob moved back to `joinedParticipants`
- [x] Removed from `leftParticipants`
- [x] New peer connections established
- [x] Audio works immediately

---

### Test 3.5: End Call (Host)

**Steps:**
1. On Alice device (host), tap "End Call"
2. Verify call ends for all participants
3. Check Firestore state

**Expected:**
- [x] Call status changed to "ended"
- [x] All participants' screens close
- [x] All peer connections terminated
- [x] `endedAt` timestamp recorded
- [x] All participants removed from `joinedParticipants`

**Firestore Verification:**
```javascript
groupCalls/{callId}:
{
  status: "ended",
  joinedParticipants: [],
  endedAt: Timestamp
}
```

---

### Test 3.6: Auto-End When Last Participant Leaves

**Steps:**
1. Start new call with Alice and Bob
2. Alice leaves
3. Bob leaves (last participant)
4. Check Firestore state

**Expected:**
- [x] Call status automatically set to "ended"
- [x] No participants remain in call
- [x] Call document preserved (not deleted)

---

## 📊 PHASE 4: SCALABILITY

### Test 4.1: Maximum 8 Participants

**Steps:**
1. Create group with 10 members
2. Host starts call
3. First 7 participants accept (total 8 with host)
4. 9th participant attempts to join

**Expected:**
- [x] First 8 participants join successfully
- [x] 9th participant sees "Call is full" error
- [x] Firestore rules enforce max 8 participants
- [x] All 8 participants hear each other clearly

**Performance Metrics:**
- [x] Mesh maintains 8 participants (28 peer connections total)
- [x] Audio quality remains acceptable
- [x] Latency < 1 second

---

### Test 4.2: Participant Joins Full Call Then Someone Leaves

**Steps:**
1. 8 participants in call (full)
2. One participant leaves (now 7)
3. Waiting participant attempts to join

**Expected:**
- [x] 9th slot opens when participant leaves
- [x] New participant can now join
- [x] Total never exceeds 8

---

## 🌐 PHASE 5: NETWORK CONDITIONS

### Test 5.1: Poor Network (Caller)

**Steps:**
1. Start call with good connection
2. On Alice device, enable network throttling (slow 3G)
3. Continue call

**Expected:**
- [x] Audio quality degrades gracefully
- [x] No complete audio dropouts
- [x] Reconnection attempts visible
- [x] Call doesn't crash

---

### Test 5.2: Network Disconnect & Reconnect

**Steps:**
1. Call active with 3 participants
2. On Bob device, turn off WiFi/data
3. Wait 10 seconds
4. Turn WiFi/data back on

**Expected:**
- [x] Bob's connection drops
- [x] Reconnection indicator shows
- [x] Peer connections re-establish
- [x] Audio resumes automatically
- [x] If reconnection fails after 15s, participant dropped

---

### Test 5.3: Background/Foreground

**Steps:**
1. Call active
2. On Bob device, press home button (background app)
3. Wait 30 seconds
4. Return to app

**Expected:**
- [x] Call continues in background
- [x] Audio still transmitted/received
- [x] UI updates when returning to foreground
- [x] No WebRTC errors

---

## 🔐 PHASE 6: SECURITY

### Test 6.1: Non-Group Member Cannot Join

**Steps:**
1. Start call in Group A
2. Attempt to join with Account E (not in group)
3. Check Firestore security rules

**Expected:**
- [x] Join request rejected
- [x] Firestore rules prevent read access
- [x] Error message shown

---

### Test 6.2: Cannot Exceed Participant Limit via Direct Firestore Write

**Steps:**
1. Attempt to manually add 9th participant via Firestore console
2. Verify security rules block the write

**Expected:**
- [x] Firestore rules reject write
- [x] Error: "Participant limit exceeded"

---

## 📱 PHASE 7: UI/UX

### Test 7.1: Call Duration Timer

**Steps:**
1. Join call
2. Observe call duration display
3. Verify updates every second

**Expected:**
- [x] Timer starts from 00:00
- [x] Format: MM:SS or HH:MM:SS
- [x] Updates smoothly
- [x] Synced across all devices

---

### Test 7.2: Participant Grid Layout

**Steps:**
1. Test with 2, 3, 4, 6, and 8 participants
2. Verify grid adapts

**Expected:**
- [x] 2 participants: 2-column grid
- [x] 4 participants: 2x2 grid
- [x] 6+ participants: scrollable 2-column grid
- [x] Tiles are sized appropriately
- [x] Speaking glow is visible

---

### Test 7.3: Dark/Light Mode

**Steps:**
1. Test call UI in light mode
2. Switch to dark mode
3. Verify UI adapts

**Expected:**
- [x] All UI elements visible in both modes
- [x] Speaking glow visible in both modes
- [x] Contrast is sufficient
- [x] No white flash during mode switch

---

## 🐛 PHASE 8: ERROR HANDLING

### Test 8.1: Microphone Permission Denied

**Steps:**
1. Revoke microphone permission
2. Attempt to join call
3. Observe error handling

**Expected:**
- [x] Permission prompt shown
- [x] Clear error message if denied
- [x] Call screen doesn't crash
- [x] User returned to chat

---

### Test 8.2: Call Ends While Joining

**Steps:**
1. Start call with Alice
2. Bob starts joining
3. Alice ends call during Bob's join process

**Expected:**
- [x] Bob receives "Call ended" message
- [x] Bob's screen closes gracefully
- [x] No WebRTC errors logged
- [x] No hanging connections

---

### Test 8.3: Firestore Connection Lost

**Steps:**
1. Call active
2. Disable Firestore in Firebase console
3. Observe behavior

**Expected:**
- [x] WebRTC audio continues (P2P)
- [x] Speaking detection stops updating
- [x] UI shows connection warning
- [x] Signaling fails for new participants

---

## 📊 PERFORMANCE BENCHMARKS

### Metrics to Track:

| Metric | Target | Actual |
|--------|--------|--------|
| Call setup time (join to audio) | < 3 seconds | ___ |
| Audio latency (2 participants) | < 300ms | ___ |
| Audio latency (8 participants) | < 1000ms | ___ |
| Speaking detection delay | < 200ms | ___ |
| Memory usage (idle) | < 100MB | ___ |
| Memory usage (8 participants) | < 300MB | ___ |
| Battery drain (30 min call) | < 15% | ___ |

---

## ✅ REGRESSION TESTING

### Verify Existing Features Still Work:

- [x] 1-to-1 voice calls work
- [x] 1-to-1 video calls work
- [x] Call logs saved correctly
- [x] Chat messages not affected
- [x] User online status works
- [x] Push notifications work

---

## 🚀 PRODUCTION READINESS CHECKLIST

### Before Deployment:

- [ ] All Phase 1-8 tests passed
- [ ] Performance benchmarks met
- [ ] No regression issues
- [ ] Security rules deployed
- [ ] Error handling verified
- [ ] Multi-device testing complete
- [ ] Battery consumption acceptable
- [ ] Network resilience tested
- [ ] Documentation complete
- [ ] Rollback strategy tested

---

## 📝 TEST EXECUTION LOG

### Test Session 1: [Date]
**Tester:** _______________  
**Devices:** _______________  
**Results:** _______________

### Test Session 2: [Date]
**Tester:** _______________  
**Devices:** _______________  
**Results:** _______________

### Test Session 3: [Date]
**Tester:** _______________  
**Devices:** _______________  
**Results:** _______________

---

## 🐛 KNOWN ISSUES

### Issue #1:
**Description:** _______________  
**Severity:** High/Medium/Low  
**Status:** Open/In Progress/Resolved  
**Workaround:** _______________

---

**Test Plan Version:** 1.0  
**Last Updated:** [Date]  
**Next Review:** [Date]
