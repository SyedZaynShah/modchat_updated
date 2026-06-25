# Phase 2 WebRTC Testing Guide

## PRE-TESTING CHECKLIST

### 1. Dependencies Installed
```bash
flutter pub get
```
Verify `flutter_webrtc: ^1.2.1` in pubspec.yaml ✅

### 2. Permissions Configured
**Android:** ✅ Already configured
- INTERNET
- RECORD_AUDIO
- MODIFY_AUDIO_SETTINGS

**iOS:** ⚠️ Need to add (if testing on iOS):
```xml
<key>NSMicrophoneUsageDescription</key>
<string>ModChat needs microphone access for voice calls</string>
```

### 3. Two Test Devices Required
- Device A (Caller)
- Device B (Receiver)
- Both connected to internet
- Both logged in to different accounts

---

## TEST 1: BASIC CALL SETUP

### Steps:
1. Device A: Open app, login
2. Device B: Open app, login  
3. Device A: Navigate to chat with Device B
4. Device A: Press call button (phone icon)

### Expected Results:
✅ Device A:
- Call screen opens immediately
- Shows "Calling..."
- Avatar pulses
- Console log: `[CallController] Initializing WebRTC...`
- Console log: `[CallController] Getting local audio stream...`

✅ Device B:
- Incoming call popup appears
- Shows caller name
- "Incoming Voice Call" text
- Accept/Decline buttons visible

### Console Logs to Verify (Device A):
```
DEBUG: _startVoiceCall() called
DEBUG: Getting user names...
DEBUG: Starting call - callerName: X, peerName: Y
=== CALL CREATION DEBUG ===
AUTH UID: [uid]
CALLER ID: [uid]
RECEIVER ID: [peerId]
CALL STATE [id]: -> calling
CALL STATE [id]: calling -> ringing
[CallScreen] Initializing WebRTC...
[CallController] Initializing WebRTC for call: [callId] (initiator: true)
[CallController] Getting local audio stream...
[CallController] Local stream acquired: [streamId]
[CallController] Creating peer connection...
[CallController] Peer connection created
[CallController] Local tracks added to peer connection
[CallController] Starting call document listener...
[CallController] Starting ICE candidates listener...
[CallController] Creating offer...
[CallController] Offer created and sent to Firestore
```

### If Test Fails:
- Check microphone permission granted
- Check Firestore rules deployed
- Check internet connection
- Check console for errors

---

## TEST 2: CALL ACCEPTANCE & CONNECTION

### Steps:
1. Complete Test 1 (call initiated)
2. Device B: Press "Accept" button

### Expected Results:
✅ Device B:
- Incoming popup closes
- Call screen opens
- Shows "Ringing..." with animated dots
- Console log: `[CallController] Initializing WebRTC...`
- Console log: `[CallController] Offer received from Firestore`
- Console log: `[CallController] Answer created and sent to Firestore`

✅ Device A:
- Status changes from "Ringing..." to "Connected"
- Call duration starts: 00:00, 00:01, 00:02...
- Mute/Speaker buttons appear
- Console log: `[CallController] Answer received from Firestore`
- Console log: `[CallController] Remote track received`
- Console log: `[CallController] Connection state: RTCPeerConnectionStateConnected`

✅ Both Devices:
- Duration counter running
- Green "Connected" status
- Control buttons visible

### Console Logs to Verify (Device B):
```
[CallController] Initializing WebRTC for call: [callId] (initiator: false)
[CallController] Getting local audio stream...
[CallController] Local stream acquired: [streamId]
[CallController] Creating peer connection...
[CallController] Peer connection created
[CallController] Local tracks added to peer connection
[CallController] Waiting for offer...
[CallController] Offer received from Firestore
[CallController] Creating answer...
[CallController] Remote offer set
[CallController] Answer created and sent to Firestore
[CallController] New ICE candidate: [candidate]
[CallController] ICE candidate sent to Firestore
[CallController] Remote track received
[CallController] Remote stream assigned
[CallController] Connection state: RTCPeerConnectionStateConnected
```

### If Test Fails:
- Check both devices have internet
- Check Firestore call document exists
- Verify offer/answer in Firestore console
- Check ICE candidates array populated

---

## TEST 3: AUDIO TRANSMISSION ⭐ CRITICAL

### Steps:
1. Complete Test 2 (call connected)
2. Device A: Speak clearly: "Testing, one, two, three"
3. Device B: Listen
4. Device B: Speak clearly: "Testing, one, two, three"
5. Device A: Listen

### Expected Results:
✅ **Device A speaks → Device B hears**
✅ **Device B speaks → Device A hears**
✅ Audio clear, no static
✅ No echo (when using headphones)
✅ Reasonable latency (<500ms)

### Audio Quality Check:
- [ ] Voice recognizable
- [ ] No robotic/choppy sound
- [ ] No significant delay
- [ ] No echo (with headphones)
- [ ] Normal volume level

### If Audio Doesn't Work:

#### Check 1: Microphone Permission
```
Device A & B: Check Settings → Apps → ModChat → Permissions
Verify: Microphone = Allowed
```

#### Check 2: Console Logs
```
Look for:
✅ [CallController] Local stream acquired
✅ [CallController] Remote track received
✅ [CallController] Remote stream assigned

Missing? Check microphone permission or WebRTC initialization failed
```

#### Check 3: Firestore Document
```
Open Firebase Console → Firestore → calls collection → [callId]

Verify exists:
{
  "offer": { "type": "offer", "sdp": "v=0..." },
  "answer": { "type": "answer", "sdp": "v=0..." },
  "iceCandidates": [ {...}, {...}, ... ]  // Array not empty
}

Missing offer/answer? WebRTC signaling failed
Empty iceCandidates? ICE negotiation failed
```

#### Check 4: Connection State
```
Console should show:
[CallController] Connection state: RTCPeerConnectionStateConnected

If shows "failed" or "disconnected":
- Network firewall blocking WebRTC
- STUN server unreachable
- NAT traversal failed → May need TURN server
```

#### Check 5: Audio Routing
```
Android: Audio should play through earpiece by default
Press Speaker button → Audio through loudspeaker

If no audio at all:
- Check device volume
- Check not on silent mode
- Try toggling speaker button
```

---

## TEST 4: MUTE FUNCTION

### Steps:
1. Call connected, audio working
2. Device A: Press Mute button
3. Device A: Speak loudly
4. Device B: Verify can't hear Device A
5. Device A: Press Mute button again (unmute)
6. Device A: Speak loudly
7. Device B: Verify can hear Device A again

### Expected Results:
✅ Mute button turns green when active
✅ Device B can't hear Device A when muted
✅ Device A can still hear Device B when muted
✅ Unmute restores audio
✅ Console log: `[CallController] Microphone muted`
✅ Console log: `[CallController] Microphone unmuted`

### Visual Indicators:
- Muted: Green circular button, mic_off icon
- Unmuted: Dark circular button, mic icon

### If Test Fails:
- Check `_callController.toggleMute()` is called
- Check local stream tracks enabled/disabled
- Verify WebRTC initialization completed

---

## TEST 5: SPEAKER TOGGLE

### Steps:
1. Call connected, audio working
2. Device A: Default audio through earpiece
3. Device A: Press Speaker button
4. Device B: Speak
5. Device A: Verify audio now through loudspeaker (loud)
6. Device A: Press Speaker button again
7. Device B: Speak
8. Device A: Verify audio back through earpiece (quiet)

### Expected Results:
✅ Speaker button turns green when active
✅ Audio clearly louder through speaker
✅ Audio quieter through earpiece
✅ Console log: `[CallController] Speaker enabled`
✅ Console log: `[CallController] Speaker disabled`

### Visual Indicators:
- Speaker ON: Green circular button, volume_up icon
- Speaker OFF: Dark circular button, volume_down icon

### Platform Notes:
- **Android:** Should work out of the box
- **iOS:** May need audio session configuration (manual)

### If Test Fails:
- Check `Helper.setSpeakerphoneOn()` available in flutter_webrtc
- iOS: May need AVAudioSession configuration
- Try adjusting device volume

---

## TEST 6: CALL DURATION

### Steps:
1. Call connected
2. Wait and observe duration counter

### Expected Results:
✅ Duration shows: 00:00, 00:01, 00:02, 00:03...
✅ Updates every second
✅ Format: MM:SS
✅ Visible below "Connected" status

### If Test Fails:
- Check `_startCallDurationTimer()` is called when status = accepted
- Check timer not cancelled prematurely

---

## TEST 7: CALL END & CLEANUP

### Steps:
1. Call connected, audio working
2. Device A: Press "End Call" button (red circle)

### Expected Results:
✅ Device A:
- "Call Ended" overlay appears
- Displays for 2 seconds
- Screen closes automatically
- Console log: `[CallController] Disposing CallController...`
- Console log: `[CallController] CallController disposed`

✅ Device B:
- "Call Ended" overlay appears
- Displays for 2 seconds
- Screen closes automatically
- Resources cleaned up

### Console Logs to Verify:
```
[CallController] Disposing CallController...
[CallController] CallController disposed
```

### Resource Cleanup Check:
- [ ] Microphone released (can record voice note after)
- [ ] No memory leaks
- [ ] Firestore listeners cancelled
- [ ] Peer connection closed
- [ ] Streams disposed

### If Test Fails:
- Check `_callController.dispose()` is called in CallScreen.dispose()
- Check no errors in console during cleanup
- Try recording voice note after call to verify mic released

---

## TEST 8: CALL DECLINE

### Steps:
1. Device A: Start call to Device B
2. Device B: Press "Decline" button (red)

### Expected Results:
✅ Device A:
- "Call Declined" overlay appears
- Displays for 2 seconds
- Screen closes automatically

✅ Device B:
- Incoming popup closes immediately
- No overlay shown

✅ Firestore:
- Call document status = "declined"

### If Test Fails:
- Check decline flow from Phase 1 still works
- WebRTC should NOT initialize on decline

---

## TEST 9: CALL TIMEOUT

### Steps:
1. Device A: Start call to Device B
2. Device B: Do NOT answer
3. Wait 30 seconds

### Expected Results:
✅ Device A:
- After 30s: "Not Answered" overlay
- Displays for 2 seconds
- Screen closes automatically

✅ Device B:
- Incoming popup closes automatically
- No notification shown

✅ Firestore:
- Call document status = "missed"

### If Test Fails:
- Check Phase 1 timeout logic still works
- WebRTC should dispose if timeout occurs

---

## TEST 10: MULTIPLE CALLS PREVENTION

### Steps:
1. Device A: Start call to Device B
2. Device B: Accept
3. Device A: While on call, try to call Device C

### Expected Results:
✅ Device A:
- Snackbar: "Finish current call first"
- New call NOT created

### If Test Fails:
- Check `checkActiveCall()` is called before startVoiceCall
- Check Firestore queries for active calls

---

## ADVANCED TESTING

### Test 11: Network Switch
**Steps:**
1. Call connected
2. Device A: Switch from WiFi to Mobile Data
3. Observe behavior

**Expected:**
- Connection may drop temporarily
- May need manual reconnection (not implemented yet)

**Known Issue:** Network switching breaks peer connection

---

### Test 12: Background App
**Steps:**
1. Call connected
2. Device A: Press home button (background app)
3. Observe audio

**Expected:**
- Audio may stop (platform-dependent)
- Needs background audio configuration (not implemented)

**Known Issue:** Background audio not configured

---

### Test 13: Echo Test (No Headphones)
**Steps:**
1. Call connected
2. Both devices WITHOUT headphones
3. Device A: Speak loudly
4. Device B: Listen

**Expected:**
- Should NOT hear echo (your own voice back)
- Echo cancellation should work

**If Echo Occurs:**
- Enable `echoCancellation: true` in audio constraints
- Use headphones during calls
- Tune audio processing parameters

---

### Test 14: Long Call (Battery Test)
**Steps:**
1. Call connected
2. Keep call active for 10+ minutes
3. Monitor battery drain

**Expected:**
- Battery drains faster than normal
- Device may get warm
- This is normal for WebRTC

---

## FIRESTORE VERIFICATION

### Check Call Document:
```
Firebase Console → Firestore → calls → [callId]

Expected fields:
{
  "callerId": "user_a_id",
  "callerName": "User A",
  "receiverId": "user_b_id",
  "type": "voice",
  "status": "accepted",  // or "ended" after call
  "createdAt": Timestamp,
  "answeredAt": Timestamp,
  "endedAt": Timestamp or null,
  
  // WebRTC fields:
  "offer": {
    "type": "offer",
    "sdp": "v=0\r\no=- 123456789..."  // Long SDP string
  },
  
  "answer": {
    "type": "answer",
    "sdp": "v=0\r\no=- 987654321..."  // Long SDP string
  },
  
  "iceCandidates": [
    {
      "candidate": "candidate:1234...",
      "sdpMid": "0",
      "sdpMLineIndex": 0,
      "from": "caller"
    },
    {
      "candidate": "candidate:5678...",
      "sdpMid": "0",
      "sdpMLineIndex": 0,
      "from": "receiver"
    },
    // More candidates...
  ]
}
```

### If Missing:
- **No offer:** Caller WebRTC initialization failed
- **No answer:** Receiver WebRTC initialization failed
- **Empty iceCandidates:** ICE negotiation failed
- **No "from" field:** Old call document, not Phase 2

---

## COMMON ISSUES & SOLUTIONS

### Issue 1: "Permission Denied" Error
**Solution:**
```
Settings → Apps → ModChat → Permissions → Microphone → Allow
Restart app
```

### Issue 2: No Audio on iOS
**Solution:**
```swift
// Add to iOS project (AppDelegate.swift):
import AVFoundation

override func application(...) {
  let audioSession = AVAudioSession.sharedInstance()
  try? audioSession.setCategory(.playAndRecord, mode: .voiceChat)
  try? audioSession.setActive(true)
}
```

### Issue 3: Connection State "failed"
**Solution:**
- Check internet connection
- STUN server may be blocked
- May need TURN server for strict firewalls
- Try different network (WiFi vs Mobile Data)

### Issue 4: Echo Heard
**Solution:**
- Use headphones
- Enable echo cancellation in audio constraints
- Lower device volume
- Keep devices physically apart during testing

### Issue 5: "Multiple CallController instances" Error
**Solution:**
- Only create ONE CallController per call
- Check CallScreen doesn't recreate controller
- Verify dispose() called when screen closes

### Issue 6: Audio Choppy/Robotic
**Solution:**
- Check network quality (poor WiFi/4G)
- Check CPU usage (other apps running)
- May need audio codec tuning
- Try different network

---

## SUCCESS CRITERIA

### Phase 2 Testing Complete When:
- [ ] Test 1: Call setup works ✅
- [ ] Test 2: Call acceptance works ✅
- [ ] Test 3: **Audio bidirectional** ✅ **CRITICAL**
- [ ] Test 4: Mute/unmute works ✅
- [ ] Test 5: Speaker toggle works ✅
- [ ] Test 6: Call duration updates ✅
- [ ] Test 7: Call end cleans up resources ✅
- [ ] Test 8: Call decline works ✅
- [ ] Test 9: Call timeout works ✅
- [ ] Test 10: Multiple calls prevented ✅

### Production Ready When:
- [ ] Audio quality acceptable
- [ ] No echo issues
- [ ] Battery drain acceptable
- [ ] Background audio working (if needed)
- [ ] iOS audio routing configured
- [ ] Network switching handled
- [ ] All edge cases tested

---

## REPORTING ISSUES

### When Reporting a Bug:
1. **Test number** that failed
2. **Console logs** (full output)
3. **Firestore call document** (screenshot)
4. **Steps to reproduce**
5. **Device model** (Android/iOS, version)
6. **Network type** (WiFi/4G/5G)
7. **Expected vs Actual** behavior

### Example Bug Report:
```
Test: #3 Audio Transmission
Issue: Device B can't hear Device A
Console Logs: [attach logs]
Firestore: offer exists, answer exists, 0 ICE candidates
Device A: Samsung Galaxy S21, Android 13, WiFi
Device B: iPhone 13, iOS 16, WiFi
Expected: Bidirectional audio
Actual: One-way audio only (A hears B, B doesn't hear A)
```

---

## NEXT STEPS AFTER TESTING

### If All Tests Pass:
1. Deploy to production
2. Monitor real user calls
3. Collect feedback
4. Plan Phase 3 (video, group calls, etc.)

### If Tests Fail:
1. Review console logs
2. Check Firestore data
3. Verify WebRTC initialization
4. Debug specific failing test
5. Fix issue
6. Re-test

### Future Enhancements:
- Add call history/logs
- Add call quality indicators
- Add background audio support
- Add call recording
- Add video calls (Phase 3)
- Add group calls (Phase 4)

---

**Phase 2 Testing Guide Complete** ✅
**Ready to Test Real Audio!** 🎤
