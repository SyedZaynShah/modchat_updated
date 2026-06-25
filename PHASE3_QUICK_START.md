# Phase 3: Video Calling - Quick Start Guide

**Status:** ✅ Phase 3.4 Integration Complete  
**Ready to Test:** YES  

---

## 🚀 HOW TO TEST VIDEO CALLS

### Prerequisites
- 2 physical Android devices (emulators won't work - need cameras)
- Both devices with ModChat installed
- Both users logged in
- Camera and microphone permissions granted

---

## 📱 TESTING STEPS

### Test 1: Start a Video Call

**On Device A:**
1. Open a chat with User B
2. Look at top-right of screen
3. You'll see two icons: 📹 (video) and 📞 (phone)
4. **Tap the video camera icon** 📹
5. VideoCallScreen should open immediately
6. You should see your own video in top-right corner
7. Screen shows "Calling..." or "Ringing..."

**Expected Result:**
- ✅ VideoCallScreen opens (full screen with your camera preview)
- ✅ Your face visible in small preview (top-right)
- ✅ Status text shows peer name and "Calling..."
- ✅ No errors

---

### Test 2: Receive a Video Call

**On Device B:**
1. Wait for incoming call notification
2. Popup should say **"Incoming Video Call"** (not "Voice Call")
3. Tap green "Accept" button
4. VideoCallScreen should open
5. You should see User A's video full-screen
6. Your own video in top-right corner

**Expected Result:**
- ✅ Popup clearly says "Incoming **Video** Call"
- ✅ After accepting, VideoCallScreen opens (not voice call screen)
- ✅ You see User A's video full-screen
- ✅ You see your own video in preview (top-right)
- ✅ Both users can hear each other

---

### Test 3: Voice Call Regression (Critical!)

**Test voice calls still work:**

**On Device A:**
1. Open a chat with User B
2. **Tap the phone icon** 📞 (not video)
3. CallScreen should open (NOT VideoCallScreen)
4. Should be voice-only (no video preview)

**On Device B:**
1. Wait for incoming call notification
2. Popup should say **"Incoming Voice Call"**
3. Accept call
4. CallScreen should open (voice-only, no video)

**Expected Result:**
- ✅ Voice calls unchanged
- ✅ No video preview for voice calls
- ✅ Audio works normally
- ✅ Voice UI displays (not video UI)

---

## ✅ SUCCESS CRITERIA

### Video Call Works If:
- ✅ User A sees User B's video full-screen
- ✅ User B sees User A's video full-screen
- ✅ Both users see their own video in top-right preview
- ✅ Audio works both directions
- ✅ End call button works (red button at bottom)
- ✅ No crashes or errors

### Voice Call Still Works If:
- ✅ Phone button works
- ✅ Voice call uses CallScreen (not VideoCallScreen)
- ✅ No video preview shown
- ✅ Audio works
- ✅ Exactly same behavior as before Phase 3

---

## 🎯 WHAT TO LOOK FOR

### In VideoCallScreen:
```
┌─────────────────────────┐
│ Status Text   [Preview] │  ← Status + your video (top-right)
│                         │
│    Remote Video         │  ← Full-screen video of other person
│    (Full Screen)        │
│                         │
│         (🔴)            │  ← Red end call button (bottom)
└─────────────────────────┘
```

### In CallScreen (Voice):
```
┌─────────────────────────┐
│                         │
│      [Avatar]           │  ← Avatar, no video
│      User Name          │
│      00:00:15           │  ← Call duration
│                         │
│   🔇  🔊  🔴           │  ← Mute, Speaker, End call
└─────────────────────────┘
```

---

## 🚨 TROUBLESHOOTING

### Issue: Video button does nothing

**Check:**
1. Are you logged in?
2. Camera permission granted?
3. Check console logs for errors

**Console should show:**
```
DEBUG: _startVideoCall() called
DEBUG: Starting video call - callerName: ..., peerName: ...
DEBUG: Video call created with ID: ...
DEBUG: Navigating to VideoCallScreen...
```

---

### Issue: Wrong screen opens

**Problem:** Video call opens voice screen or vice versa

**Check Firestore:**
1. Firebase Console → Firestore → calls collection
2. Find your call document
3. Check `type` field:
   - Should be `"video"` for video calls
   - Should be `"voice"` for voice calls

---

### Issue: No video visible

**Check:**
1. Camera permissions granted on both devices?
2. Both devices on VideoCallScreen?
3. Wait 3-5 seconds for WebRTC connection

**Console should show:**
```
[CallController] 📹 Video tracks: 1
[CallController] 🎤 Audio tracks: 1
[CallController] 📹 Local stream attached to renderer
[CallController] 📹 Remote stream attached to renderer
```

---

### Issue: "Incoming Voice Call" for video

**Problem:** Video call shows as "Incoming Voice Call"

**Cause:** Type not passed correctly

**Fix:** Check that `type: "video"` in Firestore call document

---

## 📊 VERIFICATION CHECKLIST

### Before Declaring Success:

**Video Calls:**
- [ ] Video button visible in chat screen
- [ ] Tapping video button opens VideoCallScreen
- [ ] Local preview visible (your face)
- [ ] Remote video visible (other person's face)
- [ ] Audio works both directions
- [ ] End call button works
- [ ] Incoming video calls show "Incoming Video Call"
- [ ] Accepting video call opens VideoCallScreen

**Voice Calls (Regression):**
- [ ] Phone button visible in chat screen
- [ ] Tapping phone button opens CallScreen (not VideoCallScreen)
- [ ] Voice calls have NO video preview
- [ ] Audio works
- [ ] Incoming voice calls show "Incoming Voice Call"
- [ ] Accepting voice call opens CallScreen (not VideoCallScreen)

**Firestore:**
- [ ] Video calls create document with `type: "video"`
- [ ] Voice calls create document with `type: "voice"`

---

## 🎓 TECHNICAL NOTES

### What Changed in Phase 3.4

**Before Phase 3.4:**
- Only voice calls worked
- Video button did nothing
- No way to start video calls through UI

**After Phase 3.4:**
- Video button functional
- Video calls integrated into production flow
- Incoming calls route correctly based on type
- No manual Firestore setup required

### Architecture

**Call Flow:**
```
User taps video button
    ↓
CallService.startVideoCall()
    ↓
Firestore doc created with type: "video"
    ↓
VideoCallScreen opens
    ↓
CallController initialized with isVideoCall: true
    ↓
Video + audio streams acquired
    ↓
Other user receives incoming call
    ↓
IncomingCallListener detects type: "video"
    ↓
IncomingCallScreen shows "Incoming Video Call"
    ↓
Accept → VideoCallScreen opens
    ↓
Both users on VideoCallScreen with video
```

**Key Components:**
- `CallService.startVideoCall()` - Creates call with type: "video"
- `CallController(isVideoCall: true)` - Acquires video streams
- `VideoCallScreen` - Displays video UI
- `IncomingCallListener` - Routes based on type field
- `IncomingCallScreen` - Shows correct call type

---

## 🎥 CONSOLE LOGS TO EXPECT

### When Starting Video Call:
```
DEBUG: _startVideoCall() called
DEBUG: Getting user names...
DEBUG: Starting video call - callerName: User A, peerName: User B
=== CALL CREATION DEBUG ===
CALL TYPE: video
===========================
DEBUG: Video call created with ID: <callId>
DEBUG: Navigating to VideoCallScreen...
[VideoCallScreen] Initializing WebRTC for video call...
[CallController] Initializing WebRTC for call: <id> (initiator: true, video: true)
[CallController] Initializing video renderers...
[CallController] ✅ Video renderers initialized
[CallController] 📹 Video tracks: 1
[CallController] 🎤 Audio tracks: 1
[CallController] 📹 Local stream attached to renderer
[CallController] 🔊 Video call: Audio routed to SPEAKER
```

### When Remote Video Connects:
```
[CallController] Remote track received: video
[CallController] Remote track received: audio
[CallController] 📹 Remote stream attached to renderer
[VideoCallScreen] 📹 Remote video stream received
[CallController] ICE connection state: RTCIceConnectionStateConnected
[CallController] Connection state: RTCPeerConnectionStateConnected
```

---

## 📚 DOCUMENTATION

### For More Details:
- `PHASE3.4_INTEGRATION_COMPLETE.md` - Full implementation details
- `PHASE3_CURRENT_STATUS.md` - Current status and roadmap
- `PHASE3.1_TESTING_GUIDE.md` - Phase 3.1 testing (core video)
- `PHASE3.1_CONSOLE_LOGS_REFERENCE.md` - Expected console logs
- `PHASE3_VIDEO_CALLING_SPEC.md` - Complete technical specification

---

## 🚦 NEXT STEPS

### After Testing Phase 3.4:

**If Video Calls Work:**
1. ✅ Declare Phase 3.4 complete
2. Proceed to Phase 3.2 (Premium UI)
3. Then Phase 3.3 (Camera controls)
4. Then Phase 3.5 (Polish)

**If Issues Found:**
1. Check troubleshooting section above
2. Review console logs
3. Verify Firestore documents
4. Test on different devices/networks

---

## ✅ QUICK TEST SCRIPT

**Copy/paste this to test systematically:**

```
PHASE 3.4 TEST SCRIPT

Device A - Video Call Initiation:
[ ] Tap video button
[ ] VideoCallScreen opens
[ ] Local preview visible
[ ] Status shows "Calling..."

Device B - Video Call Reception:
[ ] Popup says "Incoming Video Call"
[ ] Accept button tapped
[ ] VideoCallScreen opens
[ ] Local preview visible
[ ] Remote video visible (Device A)

Device A - After Connection:
[ ] Remote video visible (Device B)
[ ] Audio works (can hear Device B)

Both Devices:
[ ] End call button works
[ ] Screens close properly
[ ] No crashes

Voice Call Regression:
Device A - Voice Call Initiation:
[ ] Tap phone button
[ ] CallScreen opens (NOT VideoCallScreen)
[ ] No video preview
[ ] Voice-only UI

Device B - Voice Call Reception:
[ ] Popup says "Incoming Voice Call"
[ ] Accept button tapped
[ ] CallScreen opens (NOT VideoCallScreen)
[ ] Voice-only UI
[ ] Audio works

Firestore Verification:
[ ] Video calls have type: "video"
[ ] Voice calls have type: "voice"

RESULT: [ ] PASS / [ ] FAIL
```

---

**Phase 3.4 Integration complete! Test and report results! 🎥🚀**
