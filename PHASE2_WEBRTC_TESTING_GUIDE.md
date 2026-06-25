# Phase 2 WebRTC Voice Call - Testing Guide

## 🎯 Implementation Status: COMPLETE ✅

All Phase 2 WebRTC code has been implemented. The system is ready for device testing.

---

## 📋 What Has Been Implemented

### ✅ Core WebRTC Service
**File**: `lib/services/call_controller.dart`

- **RTCPeerConnection Setup**: Configured with Google STUN server
- **Audio Stream Management**: Local microphone + remote audio
- **Offer/Answer Exchange**: Complete SDP signaling via Firestore
- **ICE Candidate Exchange**: With intelligent buffering to prevent race conditions
- **Connection State Monitoring**: Full lifecycle tracking
- **Resource Cleanup**: Proper disposal of streams and connections

### ✅ UI Integration
**File**: `lib/screens/chat/call_screen.dart`

- **WebRTC Initialization**: Auto-starts when call screen opens
- **Mute/Unmute**: Connected to WebRTC audio track control
- **Speaker Toggle**: Uses flutter_webrtc Helper API
- **State Synchronization**: WebRTC state → UI state
- **Proper Disposal**: Cleanup when call ends

### ✅ Dependencies & Permissions
- ✅ `flutter_webrtc: ^1.2.1` in pubspec.yaml
- ✅ `RECORD_AUDIO` permission in AndroidManifest.xml
- ✅ `MODIFY_AUDIO_SETTINGS` permission in AndroidManifest.xml
- ✅ `BLUETOOTH` permissions for headset support

---

## 🧪 Testing Checklist

### Prerequisites
- [ ] Two Android devices (or one Android + one iOS)
- [ ] Both devices connected to internet (WiFi or mobile data)
- [ ] Both devices logged into different accounts
- [ ] Microphone permissions granted on both devices

### Step-by-Step Testing

#### 1️⃣ **Install and Run**
```bash
flutter pub get
flutter run --release
```

> **Note**: Use `--release` mode for better WebRTC performance

#### 2️⃣ **Grant Permissions**
- First call will request microphone permission
- Tap "Allow" on both devices
- If denied, go to app settings and enable manually

#### 3️⃣ **Initiate Call**
**Device A (Caller)**:
1. Open chat with Device B's user
2. Tap the call button (phone icon)
3. Call screen opens immediately
4. Status shows "Calling..."

**Device B (Receiver)**:
1. Incoming call popup appears
2. Tap "Accept"
3. Call screen opens
4. Status shows "Ringing..."

#### 4️⃣ **Verify Audio Connection**
**Expected Timeline**:
- **0-2 seconds**: "Calling..." / "Ringing..."
- **2-5 seconds**: WebRTC negotiation (offer/answer/ICE)
- **5-10 seconds**: Status changes to "Connected"
- **Audio starts flowing**: Both parties should hear each other

**Audio Test**:
- [ ] Device A speaks → Device B hears
- [ ] Device B speaks → Device A hears
- [ ] No echo (if echo occurs, see troubleshooting)
- [ ] Clear audio quality
- [ ] No audio delay (< 500ms)

#### 5️⃣ **Test Controls**
**Mute Button**:
- [ ] Device A mutes → Device B cannot hear Device A
- [ ] Device A unmutes → Device B can hear Device A again
- [ ] Button shows green when muted

**Speaker Button**:
- [ ] Tap speaker → Audio plays from loudspeaker
- [ ] Tap again → Audio plays from earpiece
- [ ] Button shows green when speaker is on

#### 6️⃣ **Test Call Duration**
- [ ] Duration timer appears when "Connected"
- [ ] Timer counts up correctly (00:01, 00:02, etc.)
- [ ] Format is MM:SS

#### 7️⃣ **Test Call Termination**
**Caller Ends Call**:
- [ ] Device A taps red button
- [ ] Status changes to "Call Ended"
- [ ] Overlay shows for 2 seconds
- [ ] Both screens close automatically

**Receiver Ends Call**:
- [ ] Device B taps red button
- [ ] Same behavior as above

#### 8️⃣ **Test Edge Cases**

**Network Switch During Call**:
- [ ] Turn WiFi off/on during call
- [ ] Call should recover (may take 5-10 seconds)

**Background/Foreground**:
- [ ] Put app in background → audio continues
- [ ] Return to foreground → call still active

**Timeout Test**:
- [ ] Make call but don't answer
- [ ] After 30 seconds → "Not Answered"
- [ ] Call terminates automatically

---

## 🔍 What to Look For

### Console Logs (Important!)
Open Android Studio Logcat or run `flutter logs` to see:

```
[CallController] Initializing WebRTC for call: abc123 (initiator: true)
[CallController] Getting local audio stream...
[CallController] Local stream acquired: stream-id-here
[CallController] Creating peer connection...
[CallController] Peer connection created
[CallController] Local tracks added to peer connection
[CallController] Creating offer...
[CallController] Offer created and sent to Firestore
[CallController] New ICE candidate: candidate:...
[CallController] ICE candidate sent to Firestore
[CallController] Answer received from Firestore
[CallController] Remote answer set
[CallController] ICE candidate added to peer connection
[CallController] Remote track received
[CallController] Remote stream assigned
[CallController] Connection state: RTCPeerConnectionState.connected
[CallController] ICE connection state: RTCIceConnectionState.connected
```

### Firestore Data Structure
Check your call document in Firestore console:

```json
{
  "callerId": "user1",
  "receiverId": "user2",
  "status": "accepted",
  "offer": {
    "type": "offer",
    "sdp": "v=0\r\no=..."
  },
  "answer": {
    "type": "answer",
    "sdp": "v=0\r\no=..."
  },
  "iceCandidates": [
    {
      "from": "caller",
      "candidate": "candidate:...",
      "sdpMid": "0",
      "sdpMLineIndex": 0
    },
    {
      "from": "receiver",
      "candidate": "candidate:...",
      "sdpMid": "0",
      "sdpMLineIndex": 0
    }
  ]
}
```

---

## 🐛 Troubleshooting

### Issue: "No audio from either side"

**Possible Causes**:
1. **Microphone permission denied**
   - Check app settings → Permissions → Microphone
   - Grant permission and restart app

2. **Offer/Answer not exchanged**
   - Check console logs for "Offer created" and "Answer received"
   - Check Firestore for offer/answer fields
   - Verify Firestore security rules allow read/write

3. **ICE candidates not flowing**
   - Check console logs for "ICE candidate sent"
   - Check Firestore for iceCandidates array
   - If empty, network may be blocking WebRTC

4. **Remote stream not received**
   - Look for "Remote track received" in console
   - If missing, check ICE connection state
   - May need TURN server (see below)

### Issue: "Audio only works one direction"

**Possible Causes**:
1. **Microphone muted on one device**
   - Check if mute button is green
   - Tap to unmute

2. **Local stream not added properly**
   - Restart app on device with no outgoing audio
   - Check console for "Local tracks added"

### Issue: "Echo or audio feedback"

**Possible Causes**:
1. **Multiple CallController instances**
   - **CRITICAL**: Ensure only ONE CallController per call
   - Check that dispose() is called properly
   - Verify no duplicate initialization

2. **Speaker too close to microphone**
   - Use earphones/headphones
   - Or use earpiece mode instead of speaker

### Issue: "Connection fails after 10+ seconds"

**Possible Causes**:
1. **Firewall blocking WebRTC**
   - Some corporate/school networks block peer-to-peer
   - Try on mobile data instead of WiFi
   - May need TURN server (see below)

2. **STUN server unreachable**
   - Check internet connectivity
   - Try different network

### Issue: "Microphone permission popup never appears"

**Solution**:
```bash
# Uninstall and reinstall app
flutter clean
flutter pub get
flutter run --release
```

---

## 🔧 Advanced Configuration

### Adding TURN Server (For Restrictive Networks)

If calls fail in corporate/restrictive networks, you need a TURN server:

**Edit**: `lib/services/call_controller.dart`

```dart
final Map<String, dynamic> configuration = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {
      'urls': 'turn:your-turn-server.com:3478',
      'username': 'your-username',
      'credential': 'your-password',
    },
  ],
};
```

**Free TURN Services**:
- Twilio TURN (free tier available)
- Metered.ca (limited free tier)
- xirsys.com (developer plan)

### iOS Configuration (If Testing on iPhone)

**Edit**: `ios/Runner/Info.plist`

```xml
<key>NSMicrophoneUsageDescription</key>
<string>ModChat needs microphone access for voice calls</string>
```

**Edit**: `ios/Runner/Runner.entitlements` (create if doesn't exist)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.playable-content</key>
    <true/>
</dict>
</plist>
```

---

## 📊 Performance Benchmarks

### Expected Metrics

| Metric | Target | Acceptable | Poor |
|--------|--------|------------|------|
| Connection Time | < 3s | 3-5s | > 5s |
| Audio Latency | < 200ms | 200-500ms | > 500ms |
| Audio Quality | Clear | Slight distortion | Robotic/choppy |
| ICE Candidates | 5-15 | 15-30 | > 30 |
| CPU Usage | < 10% | 10-20% | > 20% |
| Battery Drain | Normal | Slightly elevated | Rapid drain |

### How to Monitor

**CPU/Battery**:
- Android: Settings → Battery → App Usage
- iOS: Settings → Battery

**Network Usage**:
- Android Studio → Profiler → Network
- Look for consistent ~50-100 KB/s during call

---

## ✅ Success Criteria

Mark each item when verified:

- [ ] Both devices can initiate calls
- [ ] Both devices can receive calls
- [ ] Audio flows in both directions
- [ ] Audio quality is clear and natural
- [ ] Mute/unmute works correctly
- [ ] Speaker toggle works correctly
- [ ] Call duration timer works
- [ ] Call can be ended from either side
- [ ] No echo or feedback issues
- [ ] Connection stable for 2+ minute calls
- [ ] Works on WiFi
- [ ] Works on mobile data
- [ ] Reconnects after network switch
- [ ] No crashes or freezes
- [ ] Proper cleanup on call end

---

## 🚨 Known Limitations

### Current Phase 2 Scope
- ✅ Audio only (no video)
- ✅ 1-to-1 calls (no group calls)
- ✅ STUN only (no TURN fallback)
- ✅ Basic audio routing (no advanced AEC)

### What's NOT Implemented Yet
- ⏸️ Call quality indicators
- ⏸️ Bandwidth adaptation
- ⏸️ Network quality monitoring
- ⏸️ Bluetooth headset auto-switching
- ⏸️ Call recording
- ⏸️ Background audio notifications
- ⏸️ Call history with duration

---

## 🎓 Understanding WebRTC Flow

### Signaling Sequence

```
CALLER SIDE                    FIRESTORE                    RECEIVER SIDE
───────────                    ─────────                    ─────────────

1. Create call doc
   status: "calling"  ──────>  [Call Document]
                                                        ───> 2. Receive notification
                                                             
3. Initialize WebRTC                                        4. Accept call
   Get microphone                                              status: "accepted"
   Create PeerConnection                                       
                                                        ───> 5. Initialize WebRTC
4. Create OFFER     ──────>    offer: { sdp }                Get microphone
                                                        ───> 6. Set remote offer
                                                             
                                                             7. Create ANSWER
                               answer: { sdp }     <────────
                                                             
8. Set remote answer <──────   
                                                             
9. Exchange ICE     <──────>   iceCandidates: []  <──────>  9. Exchange ICE
                                                             
10. CONNECTED                                               10. CONNECTED
    Audio flows      ←═══════════════════════════════════>   Audio flows
```

### ICE Candidate Buffering

**Problem**: ICE candidates can arrive before remote SDP is set
**Solution**: Buffer candidates until `setRemoteDescription()` completes

```dart
// If remote description not set yet, buffer the candidate
if (!_remoteDescriptionSet) {
  _candidateBuffer.add(candidate);
} else {
  _peerConnection!.addCandidate(candidate);
}

// After setting remote description
_remoteDescriptionSet = true;
await _processBufferedCandidates();
```

---

## 📞 Testing Script

Use this conversation script for systematic testing:

### Test Call 1: Basic Functionality
1. **A**: "Can you hear me?"
2. **B**: "Yes, I can hear you clearly"
3. **A**: Mute → speak → unmute
4. **B**: "I couldn't hear you when muted"
5. **A**: Toggle speaker
6. **B**: "Your voice sounds different now"
7. Wait 30 seconds (test duration timer)
8. **A**: End call

### Test Call 2: Audio Quality
1. **B**: Count from 1 to 10 slowly
2. **A**: Confirm all numbers heard
3. **A**: Count from 1 to 10 slowly
4. **B**: Confirm all numbers heard
5. **B**: Speak quickly and continuously for 10 seconds
6. **A**: Confirm no audio drops
7. **B**: End call

### Test Call 3: Network Stress
1. Establish call
2. **A**: Toggle WiFi off/on
3. Wait 10 seconds
4. **B**: "Can you still hear me?"
5. **A**: Confirm
6. **B**: Toggle WiFi off/on
7. Wait 10 seconds
8. **A**: "Can you still hear me?"
9. **B**: Confirm
10. Either party: End call

---

## 🎯 Next Steps After Testing

### If Everything Works ✅
Congratulations! Your WebRTC voice call system is functional.

**Consider adding**:
- Call quality indicators (signal strength)
- Network bandwidth monitoring
- TURN server for restrictive networks
- Echo cancellation tuning
- Background audio support
- Call history with duration tracking

### If Issues Occur ⚠️

**Document the following**:
1. Which device(s) experienced issues
2. Exact error messages from console
3. Firestore call document snapshot
4. Network type (WiFi/mobile data)
5. Steps to reproduce

**Report back with**:
- Console logs from both devices
- Screenshots of Firestore call document
- Network conditions during test
- Which specific audio direction failed

---

## 📚 Additional Resources

### WebRTC Documentation
- [flutter_webrtc Documentation](https://github.com/flutter-webrtc/flutter-webrtc)
- [WebRTC Basics](https://webrtc.org/getting-started/overview)
- [STUN/TURN Servers](https://www.metered.ca/tools/openrelay/)

### Firebase Firestore
- [Real-time Listeners](https://firebase.google.com/docs/firestore/query-data/listen)
- [Security Rules](https://firebase.google.com/docs/firestore/security/get-started)

### Debugging Tools
- [WebRTC Internals (Chrome)](chrome://webrtc-internals)
- [Android Studio Logcat](https://developer.android.com/studio/debug/am-logcat)
- [Firestore Console](https://console.firebase.google.com)

---

## 🎉 Summary

Your Phase 2 WebRTC implementation is **COMPLETE** and ready for testing. All code is in place:

- ✅ WebRTC peer-to-peer audio streaming
- ✅ Firestore signaling infrastructure
- ✅ Mute/unmute functionality
- ✅ Speaker toggle functionality
- ✅ Proper resource cleanup
- ✅ UI integration with Phase 1 call flow

**No additional code changes needed** - just test on real devices and report back with results!

---

*Generated: Phase 2 WebRTC Implementation Complete*
