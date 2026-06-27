# PHASE 2A - Deployment and Testing Guide

## BUILD STATUS: ✅ SUCCESS
- Build completed successfully at 202.4s
- APK location: `build\app\outputs\flutter-apk\app-debug.apk`
- Gradle cache corruption fixed

## DEPLOYMENT STEPS

### 1. Deploy to Device A
```bash
# Connect Device A via USB
adb devices
# Verify Device A appears

# Install APK
adb install build\app\outputs\flutter-apk\app-debug.apk
```

### 2. Deploy to Device B
```bash
# Connect Device B via USB
adb devices
# Verify Device B appears

# Install APK
adb install build\app\outputs\flutter-apk\app-debug.apk
```

### 3. Setup Logging (CRITICAL)

**Device A:**
```bash
adb logcat -s flutter > device_a_logs.txt
```

**Device B:**
```bash
adb logcat -s flutter > device_b_logs.txt
```

Keep these running during the entire test.

## TEST PROCEDURE

Follow the checkpoint verification in `PHASE2A_TEST.md` exactly:

### Checkpoint A: Virtual Call Document Creation
**Device A (Initiator):**
1. Open the app
2. Login as User A
3. Navigate to a group
4. Tap "Start Group Call"

**Expected Logs (Device A):**
```
[PHASE2A] CHECKPOINT A: Creating virtual call document
[PHASE2A] CHECKPOINT A: Virtual call ID: group_{callId}_{userA}_{userB}
[PHASE2A] CHECKPOINT A: Virtual call document created successfully
```

**Verify in Firestore Console:**
- Document exists at `calls/group_{callId}_{userA}_{userB}`
- Fields: callerId, receiverId, type='audio', status='accepted', isGroupCallVirtual=true

**STOP HERE if Checkpoint A fails**

### Checkpoint B: CallController Initialization
**Device A:**
Expected logs:
```
[PHASE2A] CHECKPOINT B: Creating CallController instance
[PHASE2A] CHECKPOINT B: Calling initialize()
[PHASE2A] STARTING INITIALIZATION
```

**Device B (Joiner):**
1. Open the app
2. Login as User B
3. Accept the incoming group call
4. Should auto-navigate to group_audio_call_screen

Expected logs:
```
[PHASE2A] CHECKPOINT B: Creating CallController instance
[PHASE2A] CHECKPOINT B: Calling initialize()
[PHASE2A] STARTING INITIALIZATION
```

**CRITICAL:** Both devices MUST show these logs. If only one device shows them, the other device is NOT creating CallController.

**STOP HERE if Checkpoint B fails on either device**

### Checkpoint C: WebRTC Signaling (Offer/Answer)
**Monitored via CallController logs:**

**Device A should show:**
```
Creating offer
Offer created successfully
Setting local description
```

**Device B should show:**
```
Received offer
Creating answer
Answer created successfully
Setting local description
```

**Verify in Firestore Console:**
- `calls/group_{callId}_{userA}_{userB}` document updated with:
  - `offer` field populated (Device A)
  - `answer` field populated (Device B)

**STOP HERE if Checkpoint C fails**

### Checkpoint D: ICE Connection
**Both devices should show:**
```
ICE connection state: checking
ICE connection state: connected
```

**STOP HERE if Checkpoint D fails**

### Checkpoint E: Remote Track Reception
**Both devices should show:**
```
[PHASE2A] CHECKPOINT E: onTrack fired
[PHASE2A] CHECKPOINT E: Remote track kind: audio
[PHASE2A] CHECKPOINT E: Remote stream ID: {streamId}
```

**CRITICAL:** If this doesn't appear on BOTH devices, remote audio will never play.

**STOP HERE if Checkpoint E fails**

### Checkpoint F: Audio Test
**Only perform this test if ALL checkpoints A-E passed on BOTH devices.**

1. Device A: Speak into microphone
2. Device B: Listen for audio
3. Device B: Speak into microphone
4. Device A: Listen for audio

**Success criteria:**
- A speaks → B hears
- B speaks → A hears

## DEBUGGING FAILED CHECKPOINTS

### Checkpoint A Failed
- Check Firestore rules deployed
- Check internet connection
- Check user authentication
- Check group document exists
- Check participant list includes both users

### Checkpoint B Failed (One Device)
- Check logs: Did that device receive the group call notification?
- Check: Did IncomingGroupCallListener trigger?
- Check: Did user tap Accept?
- Check: Did navigation to group_audio_call_screen succeed?
- Check: Does GroupCallController.initialize() get called?

### Checkpoint B Failed (Both Devices)
- Check GroupCallController constructor
- Check if _callController is null
- Check if _callController.initialize() is being called

### Checkpoint C Failed
- Check virtual call document exists in Firestore
- Check CallController can read the document
- Check offer/answer fields being written
- Check Firestore listeners are active
- Compare with working 1-to-1 call signaling

### Checkpoint D Failed
- Check ICE candidate exchange
- Check Firestore rules allow reading/writing candidates
- Check network connectivity between devices
- Check firewall settings
- Compare with working 1-to-1 ICE flow

### Checkpoint E Failed
- Check getUserMedia succeeded (local stream exists)
- Check peer connection has local tracks added
- Check offer includes track information
- Check onTrack callback is registered
- Check remote stream is not null

### Checkpoint F Failed (No Audio)
- Check microphone permissions
- Check speaker/audio output routing
- Check audio is not muted
- Check remote track is enabled
- Check AudioManager configuration

## COMMON ISSUES

### "Index out of bounds" Gradle Error
**Fixed** - Cleared Gradle cache and rebuild

### Both Devices Show "Connecting" Forever
- Checkpoint D (ICE) likely failed
- Collect logs from BOTH devices
- Check ICE candidate exchange in Firestore

### One Device Connects, Other Stuck
- Checkpoint B likely failed on stuck device
- That device never created CallController
- Check incoming call flow on that device

### Devices Connect But No Audio
- Checkpoint E likely failed
- onTrack never fired on one or both devices
- Check local stream exists before creating offer
- Check tracks were added to peer connection

## NEXT STEPS AFTER SUCCESS

**DO NOT proceed until Phase 2A succeeds completely.**

Once A hears B AND B hears A:
1. Document the successful flow
2. Take screenshots of Firestore documents
3. Save complete logs from both devices
4. Report success with all checkpoint confirmations

**Phase 2B** (after 2A success):
- Add third user (A ↔ B, A ↔ C)
- Host-only model
- Verify multiple peer connections coexist

**Phase 3** (after 2B success):
- Enable full mesh (A ↔ B, A ↔ C, B ↔ C)
- Every user hears every other user

**Phase 4** (after 3 success):
- Production UI improvements
- Call duration sync
- Connection quality indicators
- Participant avatars
