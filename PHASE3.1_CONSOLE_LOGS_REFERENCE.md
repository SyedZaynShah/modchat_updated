# Phase 3.1: Expected Console Logs Reference

**Purpose:** Quick reference for console logs you should see during Phase 3.1 testing  
**Use this to verify:** Video initialization, track acquisition, and renderer attachment  

---

## 📱 DEVICE A (CALLER) - Expected Logs

### When Opening VideoCallScreen

```
[VideoCallScreen] Initializing WebRTC for video call...
[CallController] Initializing WebRTC for call: <callId> (initiator: true, video: true)
```

### Video Renderer Initialization

```
[CallController] Initializing video renderers...
[CallController] ✅ Video renderers initialized
```

### Local Stream Acquisition

```
[CallController] Getting local media stream (video: true)...
[CallController] Local stream acquired: <streamId>
[CallController] 📹 Video tracks: 1
[CallController] 🎤 Audio tracks: 1
```

### Local Renderer Attachment

```
[CallController] 📹 Local stream attached to renderer
```

### Peer Connection Creation

```
[CallController] Creating peer connection...
[CallController] Peer connection created
[CallController] Local tracks added to peer connection
```

### Audio Routing

```
[CallController] 🔊 Video call: Audio routed to SPEAKER
```

### Offer Creation (Caller Only)

```
[CallController] Creating offer...
[CallController] Offer created and sent to Firestore
```

### Remote Stream Reception

```
[CallController] Remote track received: video
[CallController] Remote track received: audio
[CallController] 📹 Remote stream attached to renderer
[CallController] Remote stream assigned
[VideoCallScreen] 📹 Remote video stream received
```

### WebRTC Connection States

```
[CallController] Connection state: RTCPeerConnectionState.RTCPeerConnectionStateConnecting
[CallController] ICE connection state: RTCIceConnectionState.RTCIceConnectionStateChecking
[CallController] Signaling state: RTCSignalingState.RTCSignalingStateHaveLocalOffer
```

### When Connected

```
[CallController] Connection state: RTCPeerConnectionState.RTCPeerConnectionStateConnected
[CallController] ICE connection state: RTCIceConnectionState.RTCIceConnectionStateConnected
```

### When Ending Call

```
[VideoCallScreen] ERROR ending call: <error or success>
[CallController] Disposing CallController (video: true)...
[CallController] Video renderers disposed
[CallController] CallController disposed
```

---

## 📱 DEVICE B (RECEIVER) - Expected Logs

### When Opening VideoCallScreen

```
[VideoCallScreen] Initializing WebRTC for video call...
[CallController] Initializing WebRTC for call: <callId> (initiator: false, video: true)
```

### Video Renderer Initialization

```
[CallController] Initializing video renderers...
[CallController] ✅ Video renderers initialized
```

### Local Stream Acquisition

```
[CallController] Getting local media stream (video: true)...
[CallController] Local stream acquired: <streamId>
[CallController] 📹 Video tracks: 1
[CallController] 🎤 Audio tracks: 1
```

### Local Renderer Attachment

```
[CallController] 📹 Local stream attached to renderer
```

### Peer Connection Creation

```
[CallController] Creating peer connection...
[CallController] Peer connection created
[CallController] Local tracks added to peer connection
```

### Audio Routing

```
[CallController] 🔊 Video call: Audio routed to SPEAKER
```

### Waiting for Offer

```
[CallController] Waiting for offer...
```

### Answer Creation (Receiver Only)

```
[CallController] Offer received from Firestore
[CallController] Creating answer...
[CallController] Remote offer set
[CallController] Processing 0 buffered ICE candidates... (or N candidates)
[CallController] Answer created and sent to Firestore
```

### Remote Stream Reception

```
[CallController] Remote track received: video
[CallController] Remote track received: audio
[CallController] 📹 Remote stream attached to renderer
[CallController] Remote stream assigned
[VideoCallScreen] 📹 Remote video stream received
```

### WebRTC Connection States

```
[CallController] Connection state: RTCPeerConnectionState.RTCPeerConnectionStateConnecting
[CallController] ICE connection state: RTCIceConnectionState.RTCIceConnectionStateChecking
[CallController] Signaling state: RTCSignalingState.RTCSignalingStateHaveRemoteOffer
[CallController] Signaling state: RTCSignalingState.RTCSignalingStateStable
```

### When Connected

```
[CallController] Connection state: RTCPeerConnectionState.RTCPeerConnectionStateConnected
[CallController] ICE connection state: RTCIceConnectionState.RTCIceConnectionStateConnected
```

### When Ending Call

```
[VideoCallScreen] ERROR ending call: <error or success>
[CallController] Disposing CallController (video: true)...
[CallController] Video renderers disposed
[CallController] CallController disposed
```

---

## ✅ CRITICAL LOG CHECKPOINTS

### Checkpoint 1: Initialization (Both Devices)
**Must See:**
```
✅ [CallController] Initializing WebRTC for call: <id> (initiator: true/false, video: true)
✅ [CallController] ✅ Video renderers initialized
✅ [CallController] 📹 Video tracks: 1
✅ [CallController] 🎤 Audio tracks: 1
✅ [CallController] 📹 Local stream attached to renderer
```

**If Missing:** Initialization failed, check camera permissions

---

### Checkpoint 2: Signaling (Caller)
**Must See:**
```
✅ [CallController] Creating offer...
✅ [CallController] Offer created and sent to Firestore
```

**If Missing:** Firestore write failed, check Firestore rules

---

### Checkpoint 3: Signaling (Receiver)
**Must See:**
```
✅ [CallController] Offer received from Firestore
✅ [CallController] Creating answer...
✅ [CallController] Answer created and sent to Firestore
```

**If Missing:** Firestore listener not working, check call status in Firestore

---

### Checkpoint 4: Remote Stream (Both Devices)
**Must See:**
```
✅ [CallController] Remote track received: video
✅ [CallController] Remote track received: audio
✅ [CallController] 📹 Remote stream attached to renderer
✅ [CallController] Remote stream assigned
```

**If Missing:** WebRTC connection failed, check ICE connection state

---

### Checkpoint 5: Connection (Both Devices)
**Must See:**
```
✅ [CallController] ICE connection state: RTCIceConnectionState.RTCIceConnectionStateConnected
✅ [CallController] Connection state: RTCPeerConnectionState.RTCPeerConnectionStateConnected
```

**If Missing:** Network connectivity issue, try same WiFi network

---

### Checkpoint 6: Cleanup (Both Devices)
**Must See:**
```
✅ [CallController] Disposing CallController (video: true)...
✅ [CallController] Video renderers disposed
✅ [CallController] CallController disposed
```

**If Missing:** Memory leak risk, verify dispose() is called

---

## 🚨 ERROR LOGS TO WATCH FOR

### Camera Permission Denied

```
❌ [CallController] ERROR getting local stream: PermissionDeniedError
```

**Solution:** Grant camera permission in device settings

---

### Renderer Initialization Failed

```
❌ [CallController] ERROR initializing renderers: <error>
```

**Solution:** Check flutter_webrtc package version, try device restart

---

### Offer/Answer Creation Failed

```
❌ [CallController] ERROR creating offer: <error>
❌ [CallController] ERROR creating answer: <error>
```

**Solution:** Check peer connection state, verify STUN server reachable

---

### ICE Candidate Failed

```
❌ [CallController] ERROR adding ICE candidate: <error>
```

**Solution:** Usually not critical, but check if connection still succeeds

---

### Disposal Error

```
❌ [CallController] ERROR setting earpiece audio: <error>
```

**Solution:** Platform-specific issue, usually non-blocking

---

## 📊 ICE CONNECTION STATE PROGRESSION

**Normal Progression:**
```
1. RTCIceConnectionState.RTCIceConnectionStateNew
2. RTCIceConnectionState.RTCIceConnectionStateChecking
3. RTCIceConnectionState.RTCIceConnectionStateConnected
```

**Failed Connection:**
```
1. RTCIceConnectionState.RTCIceConnectionStateNew
2. RTCIceConnectionState.RTCIceConnectionStateChecking
3. RTCIceConnectionState.RTCIceConnectionStateFailed  ← PROBLEM
```

**If Failed:** Network/firewall issue, try different network

---

## 📊 PEER CONNECTION STATE PROGRESSION

**Normal Progression:**
```
1. RTCPeerConnectionState.RTCPeerConnectionStateNew
2. RTCPeerConnectionState.RTCPeerConnectionStateConnecting
3. RTCPeerConnectionState.RTCPeerConnectionStateConnected
```

**Failed Connection:**
```
1. RTCPeerConnectionState.RTCPeerConnectionStateNew
2. RTCPeerConnectionState.RTCPeerConnectionStateConnecting
3. RTCPeerConnectionState.RTCPeerConnectionStateFailed  ← PROBLEM
```

---

## 📊 SIGNALING STATE PROGRESSION

**Caller (Initiator):**
```
1. RTCSignalingState.RTCSignalingStateStable (initial)
2. RTCSignalingState.RTCSignalingStateHaveLocalOffer (after offer)
3. RTCSignalingState.RTCSignalingStateStable (after answer received)
```

**Receiver:**
```
1. RTCSignalingState.RTCSignalingStateStable (initial)
2. RTCSignalingState.RTCSignalingStateHaveRemoteOffer (offer received)
3. RTCSignalingState.RTCSignalingStateStable (after answer sent)
```

---

## 🎯 LOG ANALYSIS TIPS

### Video Not Showing?

**Check logs for:**
1. `📹 Video tracks: 1` ← Video track acquired?
2. `✅ Video renderers initialized` ← Renderers ready?
3. `📹 Local stream attached to renderer` ← Local video attached?
4. `📹 Remote stream attached to renderer` ← Remote video attached?

**Debug Strategy:**
- If track count is 0 → Camera permission issue
- If renderers not initialized → Initialization failed
- If streams not attached → Renderer attachment failed

---

### Audio Not Working?

**Check logs for:**
1. `🎤 Audio tracks: 1` ← Audio track acquired?
2. `🔊 Video call: Audio routed to SPEAKER` ← Audio routing set?

**Debug Strategy:**
- If track count is 0 → Microphone permission issue
- If routing not set → Helper.setSpeakerphoneOn() failed

---

### Connection Not Establishing?

**Check logs for:**
1. ICE connection state stuck at `Checking`?
2. Peer connection state stuck at `Connecting`?
3. No `Remote track received` logs?

**Debug Strategy:**
- Check Firestore for `iceCandidates` array (should have entries)
- Verify both devices on same network
- Check for firewall blocking WebRTC

---

### Memory Leak?

**Check logs for:**
1. `Disposing CallController (video: true)...` on end call
2. `Video renderers disposed`
3. `CallController disposed`

**Debug Strategy:**
- If disposal logs missing → dispose() not called
- Use Android Studio Profiler to verify memory release
- Test 5+ consecutive calls, memory should stabilize

---

## 🔍 ADVANCED DEBUGGING

### Enable Verbose WebRTC Logs (If Needed)

Add to initialization:

```dart
// In main.dart or before CallController initialization
import 'package:flutter_webrtc/flutter_webrtc.dart';

void enableWebRTCLogging() {
  // Enable verbose WebRTC internal logs
  // Note: This is platform-specific and may not work on all devices
}
```

### Log Stream Details

Add to CallController after stream acquisition:

```dart
print('Local stream ID: ${_localStream?.id}');
print('Local video tracks: ${_localStream?.getVideoTracks().length}');
print('Local audio tracks: ${_localStream?.getAudioTracks().length}');

_localStream?.getVideoTracks().forEach((track) {
  print('Video track: ${track.id}, enabled: ${track.enabled}, kind: ${track.kind}');
});

_localStream?.getAudioTracks().forEach((track) {
  print('Audio track: ${track.id}, enabled: ${track.enabled}, kind: ${track.kind}');
});
```

### Log Renderer State

Add to VideoCallScreen:

```dart
print('Local renderer initialized: ${_callController?.localRenderer != null}');
print('Remote renderer initialized: ${_callController?.remoteRenderer != null}');
print('Local renderer srcObject: ${_callController?.localRenderer?.srcObject}');
print('Remote renderer srcObject: ${_callController?.remoteRenderer?.srcObject}');
```

---

## ✅ HEALTHY LOG SUMMARY

**A successful Phase 3.1 test should show:**

✅ Both devices initialize WebRTC with `video: true`  
✅ Both devices acquire video tracks (`📹 Video tracks: 1`)  
✅ Both devices initialize renderers (`✅ Video renderers initialized`)  
✅ Both devices attach local streams to renderers  
✅ Caller creates offer, receiver creates answer  
✅ ICE candidates exchange  
✅ Both devices receive remote tracks (`Remote track received: video`)  
✅ Both devices attach remote streams to renderers  
✅ Connection states reach `Connected`  
✅ On end call, both devices dispose cleanly  

**Total critical logs:** ~15-20 per device

**Time to connection:** 2-5 seconds (network dependent)

---

## 📋 LOG CHECKLIST TEMPLATE

Use this checklist while testing:

```markdown
# Device A (Caller) Logs

## Initialization
- [ ] Initializing WebRTC (video: true)
- [ ] Video renderers initialized
- [ ] Video tracks: 1
- [ ] Audio tracks: 1
- [ ] Local stream attached

## Signaling
- [ ] Creating offer
- [ ] Offer sent to Firestore

## Connection
- [ ] Remote track received: video
- [ ] Remote track received: audio
- [ ] Remote stream attached
- [ ] ICE state: Connected
- [ ] Connection state: Connected

## Cleanup
- [ ] Disposing CallController
- [ ] Video renderers disposed
- [ ] CallController disposed

# Device B (Receiver) Logs

## Initialization
- [ ] Initializing WebRTC (video: true)
- [ ] Video renderers initialized
- [ ] Video tracks: 1
- [ ] Audio tracks: 1
- [ ] Local stream attached

## Signaling
- [ ] Offer received
- [ ] Creating answer
- [ ] Answer sent to Firestore

## Connection
- [ ] Remote track received: video
- [ ] Remote track received: audio
- [ ] Remote stream attached
- [ ] ICE state: Connected
- [ ] Connection state: Connected

## Cleanup
- [ ] Disposing CallController
- [ ] Video renderers disposed
- [ ] CallController disposed
```

---

**Use this reference while testing Phase 3.1 to quickly verify WebRTC initialization and connection!**
