# 🚀 QUICK TEST GUIDE - Group Call WebRTC

## ⚡ 2-MINUTE SETUP

### Requirements
- 2 physical devices (or emulators)
- Both logged in to different accounts
- Both members of the same group
- Microphone permissions granted

---

## 📱 TEST STEPS

### Step 1: Start Call (Device A)
```
1. Open group chat
2. Tap phone icon (top-right)
3. Wait on call screen
```

**Expected:** Call screen opens, shows "Ringing..."

---

### Step 2: Receive Call (Device B)
```
Wait 2-5 seconds
```

**Expected:** Incoming call screen appears automatically

**❌ If not:** Check console for `[IncomingGroupCallListener]` logs

---

### Step 3: Accept Call (Device B)
```
1. Tap "Accept" button
```

**Expected:** Navigate to call screen, see Device A as participant

---

### Step 4: Verify Connection (Both Devices)
```
Watch console logs carefully
```

**Must See:**
```
✅ Initializing local audio stream
✅ Local stream initialized
✅ Creating peer connection
✅ Offer sent / Answer sent
✅ ICE candidate sent (multiple)
✅ ICE candidate received (multiple)
✅ Connection state: connected
✅ Received track from {userId}
```

**Timing:** Should complete in 5-10 seconds

---

### Step 5: Test Audio
```
Device A: Say "Hello from A"
Device B: Should HEAR it

Device B: Say "Hello from B"
Device A: Should HEAR it
```

**✅ Success:** Both can hear each other clearly

**❌ Failure:** Check:
- Microphone permissions granted?
- Volume turned up?
- Speaker/earpiece working?
- Console shows "Received track"?

---

## 🔍 QUICK DEBUG

### No Incoming Call?
```
1. Check Device B console:
   [IncomingGroupCallListener] 🔔 Incoming group call

2. If missing, check:
   - Is Device B in group members?
   - Is app wrapped with IncomingGroupCallListener?
```

### No Connection?
```
1. Check both consoles for:
   [GroupCallController] 📤 Creating offer
   [GroupCallController] 📨 Received answer

2. If missing:
   - Check Firestore rules deployed
   - Check network connectivity
```

### No Audio?
```
1. Check both consoles for:
   [GroupCallController] 📥 Received track from {userId}

2. If missing:
   - Microphone permission denied?
   - Track not added to peer connection?

3. If present but no audio:
   - Volume too low?
   - Speaker/earpiece issue?
   - Try toggling speaker button
```

---

## ✅ SUCCESS CHECKLIST

Mark each when verified:

- [ ] Device B receives incoming call screen
- [ ] Device B accepts and joins call
- [ ] Console shows "Offer sent" (Device A)
- [ ] Console shows "Answer sent" (Device B)
- [ ] Console shows "ICE candidate sent" (both, multiple times)
- [ ] Console shows "Connection state: connected" (both)
- [ ] Console shows "Received track" (both)
- [ ] Device A hears Device B
- [ ] Device B hears Device A
- [ ] Audio is clear (no distortion/delay)

**All checked = SIGNALING WORKS! ✅**

---

## 🆘 HELP

If any step fails, see detailed debugging in:
- `test_group_call_signaling.md` - Full test procedure
- `GROUP_CALL_SIGNALING_FIX_STATUS.md` - Implementation details

---

## 📊 FIRESTORE CHECK

If issues persist, verify Firestore data:

### 1. Check Call Document
```
Path: groupCalls/{callId}

Should have:
- status: "active"
- participants: [userA, userB]
- joinedParticipants: [userA, userB]
```

### 2. Check Signaling
```
Path: groupCalls/{callId}/signaling/{userA}_{userB}

Should have:
- type: "offer"
- sdp: "v=0\r\no=- ..."
- from: userA
- to: userB
```

### 3. Check ICE Candidates
```
Path: groupCalls/{callId}/signaling/{userA}_{userB}_ice/candidates/

Should have multiple documents (may be auto-deleted)
```

---

## 🎯 EXPECTED TIMELINE

| Step | Duration | Cumulative |
|------|----------|------------|
| Start call | Instant | 0s |
| Incoming screen appears | 2-5s | 5s |
| Accept call | Instant | 5s |
| Offer/Answer exchange | 1-2s | 7s |
| ICE candidate exchange | 2-5s | 12s |
| Connection established | Instant | 12s |
| Audio flows | Instant | 12s |
| **Total** | **~12 seconds** | **✅** |

If taking longer than 30 seconds, something is wrong.

---

## 📝 REPORTING RESULTS

### If Success ✅
Report:
- ✅ All tests passed
- ✅ Audio quality: Good/Excellent
- ✅ Connection time: ~X seconds
- ✅ No errors in console

### If Failure ❌
Report:
- Which step failed?
- Console logs from both devices
- Firestore screenshots
- Error messages
- Network type (WiFi/Mobile data)

---

**Quick Reference:** This is a condensed test guide. For full details, see `test_group_call_signaling.md`.

**Last Updated:** 2026-06-26
