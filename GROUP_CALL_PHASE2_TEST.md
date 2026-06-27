# Group Call Phase 2 - Test Plan

## ✅ COMPLETED

### Architecture
- **CallPeerConnection**: Extracted from CallController (single source of truth for WebRTC transport)
- **GroupCallController**: Orchestrator only - creates CallPeerConnection instances
- **Permanent Signaling Structure**: `groupCalls/{callId}/peerConnections/{pairId}`

### Files Modified
- `lib/services/call_peer_connection.dart` - Fixed type casting errors
- `lib/services/group_call_controller.dart` - Complete rebuild (orchestrator only)
- `lib/screens/calls/group_audio_call_screen.dart` - Updated for new controller API
- `firebase/firestore.rules` - Added peerConnections subcollection rules

## 🎯 PHASE 2 GOAL

**Test audio between EXACTLY 2 users in a group call**

- User A starts group call
- User B joins
- A ↔ B connection established
- **A speaks → B hears**
- **B speaks → A hears**

## 📋 TEST PROCEDURE

### Prerequisites
1. Deploy Firestore rules: `firebase deploy --only firestore:rules`
2. Build app: `flutter build apk --debug`
3. Install on 2 physical devices

### Test Steps

1. **Device A**: User A opens group with 2+ members
2. **Device A**: Start group audio call
3. **Device B**: Accept incoming call
4. **Wait for connection**

### Expected Logs

**Both devices should show:**
```
[GROUP] Current user: <userId>
[GROUP] Participants: [userA, userB]
[GROUP] ✅ LOCAL_STREAM_CREATED: 1 audio tracks
[GROUP] Connecting to: <remotePeerId>
[GROUP] Pair: userA_userB
[GROUP] Role: INITIATOR (or RECEIVER)
[GROUP] Initializing connection: userA_userB
[GROUP] ✅ CONNECTION_INITIALIZED: userA_userB
[GROUP] 🔗 CONNECTION_STATE: userA_userB → RTCPeerConnectionStateConnected
[GROUP] 🧊 ICE_STATE: userA_userB → RTCIceConnectionStateConnected
[GROUP] ✅ PEER_CONNECTED: userA_userB
[GROUP] ✅ REMOTE_STREAM: userA ← userB (or vice versa)
[GROUP] ✅ REMOTE_AUDIO_TRACKS: 1
```

### Success Criteria

- [ ] Both devices show "Connected" status
- [ ] Timer starts on both devices
- [ ] **User A speaks → User B hears audio**
- [ ] **User B speaks → User A hears audio**
- [ ] Mute button works
- [ ] Speaker button works
- [ ] End call works

## 🐛 DEBUGGING

### If audio doesn't work:

1. **Check Firestore**:
   - Navigate to `groupCalls/{callId}/peerConnections/{userA_userB}`
   - Verify `offer` field exists with `{type, sdp}`
   - Verify `answer` field exists with `{type, sdp}`
   - Verify `iceCandidates` array has entries

2. **Check logs**:
   - Look for `[GROUP] ✅ LOCAL_STREAM_CREATED`
   - Look for `[GROUP] ✅ REMOTE_STREAM`
   - Look for `[GROUP] ✅ ICE_CONNECTED`
   - Look for any `❌` error messages

3. **Check permissions**:
   - Microphone permission granted on both devices
   - Firestore rules deployed correctly

4. **Check network**:
   - Both devices can reach Google STUN server
   - Firestore real-time listeners working

## 📝 KNOWN LIMITATIONS (Phase 2)

- Only connects to FIRST remote peer
- Ignores additional participants (logs warning)
- No video support
- Basic UI only

## 🚀 NEXT STEPS (After Phase 2 Success)

**DO NOT proceed until audio works perfectly**

- Phase 3: Host-only model (A ↔ B, A ↔ C)
- Phase 4: Full mesh (all-to-all connections)
- Phase 5: Video support

## 🔒 PERMANENT DECISIONS

**These NEVER change:**

1. Signaling structure: `groupCalls/{callId}/peerConnections/{pairId}`
2. pairId format: Always alphabetically sorted (e.g., `alice_bob`)
3. CallPeerConnection is the ONLY transport implementation
4. No custom WebRTC code outside CallPeerConnection

---

**Test Date**: _____________  
**Tested By**: _____________  
**Result**: ⬜ PASS  ⬜ FAIL  
**Notes**: _____________________________________________
