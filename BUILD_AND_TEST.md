# Phase 2A - Build & Test Instructions

## ✅ COMPLETED

- [x] Firestore rules deployed
- [x] Code compiled successfully
- [x] Checkpoint logging added
- [x] Test plan created

## 📱 BUILD INSTRUCTIONS

### Option 1: Debug APK (Recommended for testing)

```bash
cd c:\Users\PMLS\Downloads\modchat_updated
flutter build apk --debug
```

The APK will be at:
```
build\app\outputs\flutter-apk\app-debug.apk
```

### Option 2: Run directly on connected device

```bash
flutter run
```

## 🧪 TESTING PROCEDURE

### Prerequisites
- 2 Android devices
- Both devices connected to internet
- Microphone permissions granted
- Users in same group chat

### Test Steps

1. **Install app on both devices**
   - Transfer `app-debug.apk` to both devices
   - Install and open app
   - Sign in as different users

2. **Device A (Initiator)**
   - Open group chat with 2+ members
   - Tap call button
   - Start group audio call
   - **Watch logcat for CHECKPOINT logs**

3. **Device B (Receiver)**
   - Accept incoming group call
   - **Watch logcat for CHECKPOINT logs**

### Collecting Logs

**Device A:**
```bash
adb -s <device_A_serial> logcat | findstr "PHASE2A CallController"
```

**Device B:**
```bash
adb -s <device_B_serial> logcat | findstr "PHASE2A CallController"
```

Or use Android Studio Logcat filter: `PHASE2A|CallController`

## ✅ CHECKPOINT VERIFICATION

### Must See on BOTH Devices:

**Checkpoint A: Document Creation**
```
[PHASE2A] CHECKPOINT A: Creating virtual call document
[PHASE2A] ✅ CHECKPOINT A: Virtual call document created
[PHASE2A] ✅ CHECKPOINT A: Document verified in Firestore
```

**Checkpoint B: CallController Init**
```
[PHASE2A] CHECKPOINT B: Creating CallController
[PHASE2A] ✅ CHECKPOINT B: CallController instance created
[PHASE2A] CHECKPOINT B: Initializing CallController...
[CallController] Initializing WebRTC
[CallController] Getting local stream
[CallController] ✅ Local stream acquired
[CallController] Creating peer connection
[CallController] Local tracks added
[PHASE2A] ✅ CHECKPOINT B: CallController.initialize() completed
```

**Checkpoint C: Signaling (Device A - Initiator)**
```
[CallController] Creating offer...
[CallController] ✅ Offer created and sent
[CallController] Answer received from Firestore
[CallController] Remote answer set
```

**Checkpoint C: Signaling (Device B - Receiver)**
```
[CallController] Offer received from Firestore
[CallController] Creating answer...
[CallController] Remote offer set
[CallController] ✅ Answer created and sent
```

**Checkpoint D: ICE Connected**
```
[CallController] 🧊 ICE_CONNECTION_STATE: Connected
```

**Checkpoint E: Track Received**
```
[CallController] 🎯 TRACK_RECEIVED: audio track
[PHASE2A] ✅ CHECKPOINT C: onRemoteStream callback fired
[PHASE2A] Audio tracks: 1
```

**Checkpoint F: Audio Test**
- User A speaks → User B hears
- User B speaks → User A hears

## 🐛 TROUBLESHOOTING

### If Checkpoint A Fails
- Check Firestore console: `calls` collection
- Check user authenticated
- Check network connection

### If Only One Device Shows Logs
- Check both users in `joinedParticipants`
- Check group call listener working
- Check app not crashed

### If Checkpoint B Fails
- Check microphone permissions
- Check no other app using mic
- Check CallController initialization error

### If Offer/Answer Not Exchanged
- Check Firestore document: `calls/group_xxx_userA_userB`
- Check `offer` field exists
- Check `answer` field exists
- Check listeners active

### If ICE Doesn't Connect
- Check network can reach STUN server
- Check `iceCandidates` array in Firestore
- Check both devices have network

### If onTrack Doesn't Fire
- Check ICE connected first
- Check local tracks added
- Check peer connection state

### If Audio Doesn't Work (But All Checkpoints Pass)
- Check speaker/earpiece routing
- Check mute state
- Check track enabled state
- Check microphone working in other apps

## 📊 SUCCESS CRITERIA

**ALL must pass:**
- ✅ Both devices: Checkpoint A
- ✅ Both devices: Checkpoint B
- ✅ Device A: Offer created
- ✅ Device B: Answer created
- ✅ Both devices: ICE Connected
- ✅ Both devices: onTrack fired
- ✅ Both devices: Remote audio tracks = 1
- ✅ **A speaks → B hears**
- ✅ **B speaks → A hears**

## 📝 REPORTING RESULTS

When reporting issues, provide:
1. **Full logs from BOTH devices**
2. **Which checkpoint failed**
3. **Firestore document screenshot** (`calls/group_xxx_userA_userB`)
4. **Device models** and Android versions
5. **Network type** (WiFi/Mobile data)

---

**Ready to test!** Follow `PHASE2A_TEST.md` for detailed checkpoint descriptions.
