# Phase 2A - CallController Verification Test

## 🎯 GOAL

**Verify CallController can be used for group call transport**

NOT testing audio yet - testing initialization checkpoints first.

## ✅ CRITICAL CHECKPOINTS

### Checkpoint A: Virtual Call Document
- [ ] Document created in Firestore
- [ ] Document verified after creation
- [ ] Document has required fields

### Checkpoint B: CallController Initialization  
- [ ] Device A: CallController instance created
- [ ] Device A: CallController.initialize() started
- [ ] Device A: CallController.initialize() completed
- [ ] Device B: CallController instance created
- [ ] Device B: CallController.initialize() started
- [ ] Device B: CallController.initialize() completed

### Checkpoint C: WebRTC Signaling
- [ ] Device A (Initiator): Offer created
- [ ] Device A: Offer sent to Firestore
- [ ] Device B (Receiver): Offer received
- [ ] Device B: Answer created
- [ ] Device B: Answer sent to Firestore
- [ ] Device A: Answer received

### Checkpoint D: ICE Connection
- [ ] Device A: ICE Connected
- [ ] Device B: ICE Connected

### Checkpoint E: Track Reception
- [ ] Device A: onTrack fired
- [ ] Device A: Remote audio track received
- [ ] Device B: onTrack fired
- [ ] Device B: Remote audio track received

### Checkpoint F: Audio (ONLY TEST AFTER ALL ABOVE PASS)
- [ ] User A speaks → User B hears
- [ ] User B speaks → User A hears

## 📋 VERIFICATION LOGS

### Device A (Initiator) - Expected Log Sequence

```
[PHASE2A] ========================================
[PHASE2A] STARTING INITIALIZATION
[PHASE2A] Current user: userA
[PHASE2A] Joined participants: [userA, userB]
[PHASE2A] Connecting to: userB
[PHASE2A] Role: INITIATOR
[PHASE2A] Virtual call ID: group_xxx_userA_userB

[PHASE2A] ========================================
[PHASE2A] CHECKPOINT A: Creating virtual call document
[PHASE2A] ✅ CHECKPOINT A: Virtual call document created
[PHASE2A] ✅ CHECKPOINT A: Document verified in Firestore

[PHASE2A] ========================================
[PHASE2A] CHECKPOINT B: Creating CallController
[PHASE2A] ✅ CHECKPOINT B: CallController instance created
[PHASE2A] CHECKPOINT B: Initializing CallController...

[CallController] Initializing WebRTC
[CallController] Getting local stream
[CallController] ✅ Local stream acquired
[CallController] Creating peer connection
[CallController] Local tracks added
[CallController] Starting call document listener
[CallController] Starting ICE candidates listener
[CallController] Creating offer...
[CallController] ✅ Offer created and sent

[PHASE2A] ✅ CHECKPOINT B: CallController.initialize() completed
[PHASE2A] ========================================

[CallController] Answer received from Firestore
[CallController] Remote answer set
[CallController] 🧊 ICE_CONNECTION_STATE: Checking
[CallController] 🧊 ICE_CONNECTION_STATE: Connected
[CallController] 🎯 TRACK_RECEIVED: audio track

[PHASE2A] ========================================
[PHASE2A] ✅ CHECKPOINT C: onRemoteStream callback fired
[PHASE2A] Audio tracks: 1
[PHASE2A] ✅ CHECKPOINT C: Peer connection CONNECTED
```

### Device B (Receiver) - Expected Log Sequence

```
[PHASE2A] ========================================
[PHASE2A] STARTING INITIALIZATION
[PHASE2A] Current user: userB
[PHASE2A] Joined participants: [userA, userB]
[PHASE2A] Connecting to: userA
[PHASE2A] Role: RECEIVER
[PHASE2A] Virtual call ID: group_xxx_userA_userB

[PHASE2A] ========================================
[PHASE2A] CHECKPOINT A: Creating virtual call document
[PHASE2A] ✅ CHECKPOINT A: Virtual call document created
[PHASE2A] ✅ CHECKPOINT A: Document verified in Firestore

[PHASE2A] ========================================
[PHASE2A] CHECKPOINT B: Creating CallController
[PHASE2A] ✅ CHECKPOINT B: CallController instance created
[PHASE2A] CHECKPOINT B: Initializing CallController...

[CallController] Initializing WebRTC
[CallController] Getting local stream
[CallController] ✅ Local stream acquired
[CallController] Creating peer connection
[CallController] Local tracks added
[CallController] Starting call document listener
[CallController] Starting ICE candidates listener

[CallController] Offer received from Firestore
[CallController] Creating answer...
[CallController] Remote offer set
[CallController] ✅ Answer created and sent

[PHASE2A] ✅ CHECKPOINT B: CallController.initialize() completed
[PHASE2A] ========================================

[CallController] 🧊 ICE_CONNECTION_STATE: Checking
[CallController] 🧊 ICE_CONNECTION_STATE: Connected
[CallController] 🎯 TRACK_RECEIVED: audio track

[PHASE2A] ========================================
[PHASE2A] ✅ CHECKPOINT C: onRemoteStream callback fired
[PHASE2A] Audio tracks: 1
[PHASE2A] ✅ CHECKPOINT C: Peer connection CONNECTED
```

## 🐛 DEBUGGING BY CHECKPOINT

### If Checkpoint A Fails
**Problem**: Virtual call document not created
- Check Firestore rules allow writes to `calls` collection
- Check user authenticated
- Look for Firestore permission errors in logs

### If Checkpoint B Fails on Device A but works on Device B (or vice versa)
**Problem**: One device not creating CallController
- Check both devices show `[PHASE2A] STARTING INITIALIZATION`
- Check both devices have `joinedParticipants.length >= 2`
- Check group call listener working on both devices

### If Checkpoint B.initialize() Fails
**Problem**: CallController initialization error
- Check microphone permissions granted
- Check no other app using microphone
- Look for media acquisition errors
- Check peer connection creation errors

### If Offer Created but Not Received
**Problem**: Firestore signaling broken
- Check Firestore `calls/group_xxx_userA_userB` document exists
- Check `offer` field populated
- Check Device B's listener is active
- Check Firestore rules allow reads

### If Answer Created but Not Received
**Problem**: Signaling broken (reverse direction)
- Check `answer` field in Firestore document
- Check Device A's listener is active

### If ICE Never Connects
**Problem**: Network/STUN issue
- Check both devices can reach stun.l.google.com:19302
- Check `iceCandidates` array has entries in Firestore
- Check ICE candidates being exchanged

### If onTrack Never Fires
**Problem**: Tracks not being sent/received
- Check `[CallController] Local tracks added` appears
- Check peer connection state is Connected
- Check audio tracks exist in local stream

## ⚠️ TEST RULES

1. **DO NOT test audio until all checkpoints pass**
2. **If any checkpoint fails, STOP and debug that checkpoint**
3. **Both devices must show same checkpoints** (except initiator/receiver differences)
4. **Collect full logs from BOTH devices** before debugging

---

**Test Date**: _____________  
**All Checkpoints Pass**: ⬜ YES  ⬜ NO  
**Which Checkpoint Failed**: _____________  
**Notes**: _____________________________________________
