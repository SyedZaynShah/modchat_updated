# Phase 3.1: Core Video Stream Testing Guide

**Status:** ✅ Core Implementation Complete  
**Phase:** 3.1 - Basic Video Streaming  
**What Works:** CallController with video support, VideoCallScreen with basic UI  
**What's NOT Implemented Yet:** Integration with chat screen, video call button, incoming call routing  

---

## 🎯 PHASE 3.1 SCOPE

### ✅ What Was Implemented

**CallController Enhancements:**
- ✅ `isVideoCall` parameter (defaults to `false`)
- ✅ `localRenderer` and `remoteRenderer` properties
- ✅ `_initializeRenderers()` method
- ✅ Video constraints in `_getLocalStream()` when `isVideoCall=true`
- ✅ Local stream attachment to local renderer
- ✅ Remote stream attachment to remote renderer in `onTrack` callback
- ✅ Video included in offer/answer (`offerToReceiveVideo: isVideoCall`)
- ✅ Video renderer disposal in `dispose()`
- ✅ Audio routing: Speaker for video, earpiece for voice

**VideoCallScreen (Basic):**
- ✅ Full-screen remote video display
- ✅ Floating local preview (top-right, 120x160)
- ✅ Status text (top-left)
- ✅ End call button (bottom-center)
- ✅ Firestore status listener
- ✅ CallController initialization for video

### ❌ What's NOT Implemented Yet

**Integration (Phase 3.4):**
- ❌ `startVideoCall()` method in CallService
- ❌ Video call button in chat screen
- ❌ Incoming call routing based on call type
- ❌ Firestore `type` field handling

**Controls (Phase 3.3):**
- ❌ Camera toggle (on/off)
- ❌ Camera switch (front/back)
- ❌ Mute button in video UI

**Polish (Phase 3.5):**
- ❌ Premium UI styling
- ❌ Animations and transitions
- ❌ Loading states
- ❌ Error handling for permissions

---

## 🧪 HOW TO TEST PHASE 3.1

### Test Setup Requirements

**You Need:**
- 2 physical Android devices (emulators don't have cameras)
- Both devices on same WiFi network (for best results)
- Both devices with camera and microphone permissions granted
- Firebase project with Firestore configured
- ModChat app built and installed on both devices
- Two different user accounts logged in

**Recommended:**
- Good lighting for both devices
- Test in quiet environment to verify audio
- Keep devices close initially (reduce network variables)

---

## 🔬 MANUAL TESTING PROCEDURE

Since integration is not complete, you need to **manually create a video call** in Firestore:

### Step 1: Prepare Both Devices

**Device A (Caller):**
- Launch ModChat
- Login as User A
- Note User A's ID (check in settings or Firestore console)
- Wait on home screen

**Device B (Receiver):**
- Launch ModChat
- Login as User B
- Note User B's ID
- Wait on home screen

### Step 2: Manually Create Call Document in Firestore

Open Firebase Console → Firestore Database → Add Document:

**Collection:** `calls`  
**Document ID:** Auto-generate  

**Fields:**
```javascript
{
  "callerId": "USER_A_ID",           // Replace with actual User A ID
  "callerName": "User A Name",       // Replace with actual name
  "receiverId": "USER_B_ID",         // Replace with actual User B ID
  "type": "voice",                   // Keep as "voice" for now (video routing not implemented)
  "status": "calling",               // Initial status
  "createdAt": <Firestore Timestamp> // Use Firestore console to add current timestamp
}
```

**Copy the Document ID** - you'll need it to open VideoCallScreen manually.

### Step 3: Manually Navigate to VideoCallScreen

**Option A: Modify Code Temporarily (Recommended)**

Add a debug button in your chat screen or home screen:

```dart
// In chat_detail_screen.dart or home screen
ElevatedButton(
  onPressed: () {
    Navigator.pushNamed(
      context,
      VideoCallScreen.routeName,
      arguments: {
        'callId': 'PASTE_CALL_ID_HERE',     // From Firestore
        'peerId': 'OTHER_USER_ID',
        'peerName': 'Other User Name',
        'isIncoming': false, // true for receiver, false for caller
      },
    );
  },
  child: Text('🧪 Test Video Call'),
)
```

**Option B: Directly Navigate via Code**

In `main.dart` or your router, add temporary navigation:

```dart
// After login, navigate directly to video call screen
Navigator.of(context).pushNamed(
  VideoCallScreen.routeName,
  arguments: {
    'callId': 'YOUR_CALL_ID',
    'peerId': 'PEER_ID',
    'peerName': 'Peer Name',
    'isIncoming': false,
  },
);
```

### Step 4: Open VideoCallScreen on Both Devices

**Device A (Caller):**
- Open VideoCallScreen with `isIncoming: false`
- Watch for camera permission request
- Grant camera permission

**Device B (Receiver):**
- Open VideoCallScreen with `isIncoming: true`
- Watch for camera permission request
- Grant camera permission

### Step 5: Update Call Status to "accepted"

Once both devices are on VideoCallScreen:

**In Firestore Console:**
- Find your call document
- Change `status: "calling"` → `status: "accepted"`
- Add field: `answeredAt: <current timestamp>`

**Both devices should now attempt WebRTC connection.**

---

## ✅ WHAT TO VERIFY

### Critical Success Criteria

**1. Camera Permission Request:**
- [ ] Device A shows camera permission dialog
- [ ] Device B shows camera permission dialog
- [ ] App handles permission denial gracefully (no crash)

**2. Local Video Preview:**
- [ ] Device A shows own camera in top-right preview
- [ ] Device B shows own camera in top-right preview
- [ ] Local preview is mirrored (front camera)
- [ ] Local preview maintains aspect ratio

**3. Remote Video Display:**
- [ ] Device A sees Device B's video full-screen
- [ ] Device B sees Device A's video full-screen
- [ ] Remote video fills screen (no black bars if possible)
- [ ] Remote video is NOT mirrored

**4. Audio During Video Call:**
- [ ] Device A can hear Device B speaking
- [ ] Device B can hear Device A speaking
- [ ] No echo or feedback
- [ ] Audio routed to SPEAKER by default (not earpiece)

**5. Video Track Confirmation (Check Console Logs):**
- [ ] Console shows: `📹 Video tracks: 1`
- [ ] Console shows: `🎤 Audio tracks: 1`
- [ ] Console shows: `📹 Local stream attached to renderer`
- [ ] Console shows: `📹 Remote stream attached to renderer`

**6. End Call:**
- [ ] Tap end call button on either device
- [ ] Both devices exit VideoCallScreen
- [ ] No crashes
- [ ] Resources cleaned up (check logs for disposal)

### Console Log Verification

**Look for these log messages:**

```
[CallController] Initializing WebRTC for call: <callId> (initiator: true/false, video: true)
[CallController] Initializing video renderers...
[CallController] ✅ Video renderers initialized
[CallController] 📹 Video tracks: 1
[CallController] 🎤 Audio tracks: 1
[CallController] 📹 Local stream attached to renderer
[CallController] Remote track received: video
[CallController] 📹 Remote stream attached to renderer
[CallController] 🔊 Video call: Audio routed to SPEAKER
```

---

## 🚨 COMMON ISSUES & TROUBLESHOOTING

### Issue: Permission Denied Error

**Symptom:** App crashes or shows error when opening VideoCallScreen

**Solution:**
1. Check `AndroidManifest.xml` has `CAMERA` permission:
   ```xml
   <uses-permission android:name="android.permission.CAMERA" />
   ```
2. Manually grant camera permission in device settings:
   - Settings → Apps → ModChat → Permissions → Camera → Allow

### Issue: Local Video Not Showing

**Symptom:** Top-right preview is blank or black

**Check:**
1. Console logs: Is video track acquired?
   - Should see: `📹 Video tracks: 1`
2. Is renderer initialized?
   - Should see: `✅ Video renderers initialized`
3. Is stream attached?
   - Should see: `📹 Local stream attached to renderer`

**Debug:**
```dart
// Add in VideoCallScreen after initialization
print('Local renderer srcObject: ${_callController?.localRenderer?.srcObject}');
print('Local renderer initialized: ${_callController?.localRenderer != null}');
```

### Issue: Remote Video Not Showing

**Symptom:** Full-screen remote video is blank, says "Waiting for remote video..."

**Check:**
1. Is call status `"accepted"` in Firestore?
2. Are both devices connected (ICE candidates exchanged)?
3. Console logs on both devices:
   - Should see: `Remote track received: video`
   - Should see: `📹 Remote stream attached to renderer`

**Debug:**
- Check ICE connection state:
  ```
  [CallController] ICE connection state: connected
  ```
- If stuck at `checking` or `failed`, it's a network issue (STUN/firewall)

### Issue: Audio Not Working

**Symptom:** Video works but no audio

**Check:**
1. Are audio tracks present?
   - Should see: `🎤 Audio tracks: 1`
2. Is speaker enabled?
   - Should see: `🔊 Video call: Audio routed to SPEAKER`
3. Device volume turned up?

**Debug:**
```dart
// Check audio tracks
_callController?.localStream?.getAudioTracks().forEach((track) {
  print('Local audio track enabled: ${track.enabled}');
});
```

### Issue: Black Screen / No Video Render

**Symptom:** VideoCallScreen is completely black

**Possible Causes:**
1. WebRTC not initialized yet (500ms delay)
2. Renderers not initialized
3. MediaStream permission denied
4. Device has no camera

**Solution:**
- Wait 2-3 seconds after opening screen
- Check console for initialization errors
- Try re-launching the screen

### Issue: Only One Direction Works

**Symptom:** Device A sees Device B, but not vice versa

**Cause:** Typically means one device's offer/answer wasn't set correctly

**Debug:**
- Check Firestore document has both `offer` and `answer` fields
- Check console for:
  ```
  [CallController] Offer created and sent to Firestore
  [CallController] Answer created and sent to Firestore
  ```

### Issue: Connection Timeout

**Symptom:** Video never connects, stays on "Connecting..."

**Causes:**
1. Firewall blocking WebRTC
2. STUN server unreachable
3. ICE candidates not exchanging

**Solution:**
- Ensure both devices on same WiFi
- Check Firestore for `iceCandidates` array (should have multiple entries)
- Try different network (mobile data vs WiFi)

---

## 📊 PERFORMANCE VERIFICATION

### Check These Metrics:

**Video Quality:**
- [ ] Resolution: 720p (1280x720) if device supports
- [ ] Frame rate: ~30 FPS (smooth motion)
- [ ] Latency: <500ms (no noticeable delay)

**Resource Usage:**
- [ ] Memory: Use Android Studio Profiler
- [ ] Check for memory leaks after ending call
- [ ] CPU usage acceptable (<80% sustained)

**Battery Drain:**
- [ ] Monitor battery level during 5-minute test call
- [ ] Should drain ~5-10% per 5 minutes (acceptable for video)

---

## 🧹 CLEANUP VERIFICATION

After ending call, verify proper cleanup:

**Console Logs to Check:**
```
[CallController] Disposing CallController (video: true)...
[CallController] Video renderers disposed
[CallController] CallController disposed
```

**Manual Verification:**
1. End call on Device A
2. Check both devices exit cleanly
3. Camera light turns OFF on both devices (camera released)
4. No crashes or errors
5. Can immediately start another call (resources freed)

**Memory Leak Test:**
1. Open video call
2. End video call
3. Repeat 5 times
4. Check memory in Android Studio Profiler
5. Memory should stabilize (not continuously grow)

---

## ✅ PHASE 3.1 SUCCESS CRITERIA

**Phase 3.1 is successful if:**

✅ **Core Functionality:**
- [ ] Camera permission requested and granted
- [ ] Local video displays in preview
- [ ] Remote video displays full-screen
- [ ] Audio works during video call
- [ ] Both users can see each other's video
- [ ] Both users can hear each other

✅ **Technical:**
- [ ] Video tracks acquired (check logs)
- [ ] Renderers initialized correctly
- [ ] Streams attached correctly
- [ ] WebRTC connection established
- [ ] ICE candidates exchanged

✅ **Cleanup:**
- [ ] Ending call cleans up resources
- [ ] No memory leaks
- [ ] Camera released (light turns off)
- [ ] No crashes

✅ **Regression:**
- [ ] **CRITICAL:** Voice calls still work unchanged
- [ ] Existing CallController voice mode works
- [ ] CallScreen (voice UI) unchanged

---

## 🚀 NEXT STEPS AFTER PHASE 3.1 SUCCESS

Once Phase 3.1 is verified working:

### Phase 3.4: Integration (Before Phase 3.2/3.3)
1. Add `startVideoCall()` to CallService
2. Add `type` field handling
3. Add video call button to chat screen
4. Add incoming call routing by type
5. **Test end-to-end video call flow** (no manual Firestore edits)

### Phase 3.2: Premium UI
1. Improve VideoCallScreen styling
2. Add call duration display
3. Add connection status indicators
4. Polish animations

### Phase 3.3: Camera Controls
1. Add camera toggle button
2. Add camera switch button
3. Add mute button to video UI
4. Test all controls

### Phase 3.5: Final Polish
1. Error handling
2. Loading states
3. Memory profiling
4. Comprehensive testing

---

## 📝 TEST RESULTS TEMPLATE

Use this template to document your test results:

```markdown
# Phase 3.1 Test Results

**Date:** _______________
**Devices Tested:**
- Device A: _______________
- Device B: _______________

## Camera Permission
- [ ] Permission requested on Device A
- [ ] Permission requested on Device B
- [ ] No crash if denied

## Local Video
- [ ] Device A shows local preview
- [ ] Device B shows local preview
- [ ] Preview mirrored correctly
- [ ] Preview aspect ratio correct

## Remote Video
- [ ] Device A sees Device B video
- [ ] Device B sees Device A video
- [ ] Full-screen display correct
- [ ] Not mirrored

## Audio
- [ ] Device A hears Device B
- [ ] Device B hears Device A
- [ ] No echo
- [ ] Speaker routing works

## Cleanup
- [ ] End call works
- [ ] Resources disposed
- [ ] No crashes
- [ ] Camera released

## Console Logs
Video tracks acquired: ___
Audio tracks acquired: ___
Renderers initialized: ___
Remote stream received: ___

## Issues Found
1. _______________
2. _______________

## Voice Call Regression Test
- [ ] Voice calls still work
- [ ] No performance degradation

## Overall Result
- [ ] ✅ PASS - Ready for Phase 3.4
- [ ] ⚠️ PARTIAL - Minor issues, continue
- [ ] ❌ FAIL - Major issues, needs fixes
```

---

## 🎯 CRITICAL REMINDER

**DO NOT PROCEED TO PHASE 3.2, 3.3, or 3.5 UNTIL:**
- ✅ Phase 3.1 core video streaming works
- ✅ Both users see each other's video
- ✅ Audio works during video call
- ✅ Console logs confirm video tracks
- ✅ Cleanup works correctly
- ✅ Voice calls still work (regression test)

**The point of Phase 3.1 is to isolate WebRTC video functionality from UI/controls/integration complexity.**

If video doesn't render, you know it's a WebRTC/media/renderer issue, not a UI or control button problem.

---

**Good luck testing! 🎥🚀**
