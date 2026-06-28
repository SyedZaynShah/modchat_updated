# PHASE 0.5 - ECHO INVESTIGATION STATUS

**Date**: 2026-06-28  
**Status**: LOGGING COMPLETE - READY FOR TESTING  
**Task**: Evidence collection only - NO FIXES

---

## SYMPTOMS (User Reported)

✅ Echo occurs ONLY when speakerphone is enabled  
✅ NO echo on earpiece  
✅ Phones tested in separate locations  
✅ Echo disappears when both users mute microphones  
✅ Occurs in both audio and video calls  

**Hypothesis**: Local audio is being played back through speaker, picked up by microphone, and transmitted to remote user

---

## WHAT WAS IMPLEMENTED

### Comprehensive Echo Investigation Logging

All logging added to: `lib/services/call_controller.dart`

#### 1. **Initialization Tracking** (Lines 79-88)
- Global counter: `_initializeCallCount` (tracks all instances)
- Instance counter: `_myInitializeCount` (tracks this instance)
- Logs every `initialize()` call with call details

**Purpose**: Verify `initialize()` is called exactly once per call

**Log Markers**:
```
[ECHO_TEST] ========================================
[ECHO_TEST] INITIALIZE called (Global: X, This instance: Y)
[ECHO_TEST] CallId: ...
[ECHO_TEST] IsInitiator: ...
[ECHO_TEST] IsVideoCall: ...
```

---

#### 2. **Local Stream Acquisition** (Lines 221-234)
- Logs local audio/video track counts
- Logs track IDs and enabled states
- Tracks media acquisition timing

**Purpose**: Verify exactly 1 audio track acquired

**Log Markers**:
```
[ECHO_TEST] ========================================
[ECHO_TEST] LOCAL STREAM ACQUIRED
[ECHO_TEST] Stream ID: ...
[ECHO_TEST] Local audio tracks: 1
[ECHO_TEST] Audio track ID: ...
[ECHO_TEST] Audio track enabled: true
```

---

#### 3. **Track Addition to Peer Connection** (Lines 266-278)
- Logs every `addTrack()` call
- Numbers each call (1, 2, etc.)
- Shows track kind, ID, and enabled state

**Purpose**: Verify `addTrack()` called exactly once per track

**Log Markers**:
```
[ECHO_TEST] ========================================
[ECHO_TEST] ADDING LOCAL TRACKS TO PEER CONNECTION
[ECHO_TEST] Total tracks to add: 1
[ECHO_TEST] addTrack() call #1 - Track kind: audio, ID: ...
[ECHO_TEST] Total addTrack() calls: 1
```

---

#### 4. **Remote Track Reception (onTrack)** (Lines 281-362)
- **Most Important Section** - Tracks duplicate detection
- Logs every `onTrack` callback firing
- Detects duplicate tracks (same track ID seen twice)
- Detects duplicate streams (same stream ID seen twice)
- Counts audio/video tracks in remote stream
- Counts renderer assignments
- Counts callback invocations
- Provides running summary after each callback

**Purpose**: 
- Find if `onTrack` fires multiple times for same track
- Find if `remoteRenderer.srcObject` assigned multiple times
- Find if `onRemoteStream` callback invoked multiple times

**Log Markers**:
```
[ECHO_TEST] ========================================
[ECHO_TEST] ONTRACK FIRED #1
[ECHO_TEST] Track kind: audio
[ECHO_TEST] Track ID: ...
[ECHO_TEST] Track enabled: true
[ECHO_TEST] ✅ New track ID (total unique tracks: 1)
[ECHO_TEST] Stream ID: ...
[ECHO_TEST] ✅ New stream ID (total unique streams: 1)
[ECHO_TEST] Remote audio tracks: 1
[ECHO_TEST] RENDERER ASSIGNMENT #1
[ECHO_TEST] CALLBACK INVOCATION #1
[ECHO_TEST] ========================================
[ECHO_TEST] SUMMARY SO FAR:
[ECHO_TEST] - Total onTrack calls: 1
[ECHO_TEST] - Unique tracks: 1
[ECHO_TEST] - Unique streams: 1
[ECHO_TEST] - Renderer assignments: 1
[ECHO_TEST] - Callback invocations: 1
```

**⚠️ Duplicate Detection**:
If same track/stream appears twice:
```
[ECHO_TEST] ⚠️ WARNING: Track ID xyz seen before!
[ECHO_TEST] ⚠️ WARNING: Stream ID abc seen before!
```

---

#### 5. **Disposal Tracking** (Lines 816-820)
- Logs when controller is disposed
- Shows how many times this instance was initialized

**Purpose**: Verify cleanup happens once per controller

**Log Markers**:
```
[ECHO_TEST] ========================================
[ECHO_TEST] DISPOSE CALLED
[ECHO_TEST] This instance initialized: 1 times
```

---

## EXPECTED RESULTS (Healthy Call)

### Audio Call (Voice Only)

**Device A Console** (Caller):
```
[ECHO_TEST] INITIALIZE called (Global: 1, This instance: 1)
[ECHO_TEST] Local audio tracks: 1
[ECHO_TEST] addTrack() call #1 - Track kind: audio
[ECHO_TEST] Total addTrack() calls: 1
[ECHO_TEST] ONTRACK FIRED #1
[ECHO_TEST] Track kind: audio
[ECHO_TEST] ✅ New track ID (total unique tracks: 1)
[ECHO_TEST] ✅ New stream ID (total unique streams: 1)
[ECHO_TEST] Remote audio tracks: 1
[ECHO_TEST] CALLBACK INVOCATION #1
[ECHO_TEST] - Total onTrack calls: 1
[ECHO_TEST] - Unique tracks: 1
[ECHO_TEST] - Unique streams: 1
[ECHO_TEST] - Callback invocations: 1
```

**Device B Console** (Receiver):
```
[ECHO_TEST] INITIALIZE called (Global: 1, This instance: 1)
[ECHO_TEST] Local audio tracks: 1
[ECHO_TEST] addTrack() call #1 - Track kind: audio
[ECHO_TEST] Total addTrack() calls: 1
[ECHO_TEST] ONTRACK FIRED #1
[ECHO_TEST] Track kind: audio
[ECHO_TEST] ✅ New track ID (total unique tracks: 1)
[ECHO_TEST] ✅ New stream ID (total unique streams: 1)
[ECHO_TEST] Remote audio tracks: 1
[ECHO_TEST] CALLBACK INVOCATION #1
[ECHO_TEST] - Total onTrack calls: 1
[ECHO_TEST] - Unique tracks: 1
[ECHO_TEST] - Unique streams: 1
[ECHO_TEST] - Callback invocations: 1
```

---

### Video Call

**Each Device Should Show**:
```
[ECHO_TEST] INITIALIZE called (Global: 1, This instance: 1)
[ECHO_TEST] Local audio tracks: 1
[ECHO_TEST] Local video tracks: 1
[ECHO_TEST] addTrack() call #1 - Track kind: audio
[ECHO_TEST] addTrack() call #2 - Track kind: video
[ECHO_TEST] Total addTrack() calls: 2

[ECHO_TEST] ONTRACK FIRED #1
[ECHO_TEST] Track kind: audio
[ECHO_TEST] ✅ New track ID (total unique tracks: 1)

[ECHO_TEST] ONTRACK FIRED #2
[ECHO_TEST] Track kind: video
[ECHO_TEST] ✅ New track ID (total unique tracks: 2)

[ECHO_TEST] - Total onTrack calls: 2
[ECHO_TEST] - Unique tracks: 2
[ECHO_TEST] - Unique streams: 1
[ECHO_TEST] - Renderer assignments: 2
[ECHO_TEST] - Callback invocations: 2
```

---

## PROBLEM INDICATORS

### 🚨 Problem #1: Multiple Initialize Calls
```
[ECHO_TEST] INITIALIZE called (Global: 2, This instance: 1)
```
**Meaning**: Controller created twice for same call  
**Impact**: Duplicate tracks, duplicate streams, echo

---

### 🚨 Problem #2: Duplicate Tracks
```
[ECHO_TEST] addTrack() call #2 - Track kind: audio
[ECHO_TEST] Total addTrack() calls: 2
```
**Meaning**: Same audio track added twice  
**Impact**: Remote user receives 2 copies of your audio

---

### 🚨 Problem #3: Duplicate onTrack Callbacks
```
[ECHO_TEST] ONTRACK FIRED #2
[ECHO_TEST] Track kind: audio
[ECHO_TEST] ⚠️ WARNING: Track ID xyz seen before!
```
**Meaning**: Same track processed twice  
**Impact**: Remote stream attached multiple times

---

### 🚨 Problem #4: Multiple Renderer Assignments
```
[ECHO_TEST] RENDERER ASSIGNMENT #2
```
**Meaning**: `remoteRenderer.srcObject` set twice  
**Impact**: Audio path duplicated

---

### 🚨 Problem #5: Multiple Callback Invocations
```
[ECHO_TEST] CALLBACK INVOCATION #2
[ECHO_TEST] - Callback invocations: 2
```
**Meaning**: `onRemoteStream` called multiple times  
**Impact**: UI may attach audio player twice

---

## TESTING PROCEDURE

### Prerequisites
- 2 physical devices (NOT emulators - audio required)
- Both devices logged into different accounts
- Both devices in same group or have 1-to-1 chat
- Quiet location (minimize background noise)

---

### Test 1: Audio Call with Earpiece (Baseline)

**Setup**:
1. Device A: Open app
2. Device B: Open app
3. Device A: Start audio call to Device B

**Test**:
1. Device B: Accept call
2. Device B: Ensure earpiece mode (speaker OFF)
3. Both devices: Speak alternately

**Expected Result**: ✅ No echo

**Console Logs to Check**:
- [ ] Initialize called once per device
- [ ] Local audio tracks: 1
- [ ] addTrack calls: 1
- [ ] onTrack fired: 1
- [ ] Unique tracks: 1
- [ ] Callback invocations: 1

**Save Console Output**: Copy all `[ECHO_TEST]` lines from both devices

---

### Test 2: Audio Call with Speakerphone (Echo Reproduction)

**Setup**:
1. Continue from Test 1
2. Device B: Toggle speakerphone ON

**Test**:
1. Device A: Speak ("Testing one two three")
2. Wait 1 second
3. Device A: Listen

**Expected Result**: 🚨 Echo heard on Device A

**Console Logs to Check**:
- [ ] Did any counters increase after enabling speaker?
- [ ] Any new `[ECHO_TEST]` logs after toggle?

**Save**: 
- Console output after enabling speaker
- Video recording of both screens (optional)

---

### Test 3: Video Call with Speaker (Default)

**Setup**:
1. End previous call
2. Device A: Start video call to Device B
3. Device B: Accept call
4. Both devices: Speaker is ON by default

**Test**:
1. Device A: Speak
2. Device B: Speak
3. Listen for echo

**Expected Result**: 🚨 Echo should occur (speaker enabled)

**Console Logs to Check**:
- [ ] Initialize called once per device
- [ ] Local audio tracks: 1
- [ ] Local video tracks: 1
- [ ] addTrack calls: 2 (audio + video)
- [ ] onTrack fired: 2 (audio + video)
- [ ] Unique tracks: 2
- [ ] Callback invocations: 2

**Save Console Output**: Copy all `[ECHO_TEST]` lines

---

### Test 4: Check for Duplicates

**During any call**:
- Search Device A console for: `⚠️ WARNING`
- Search Device B console for: `⚠️ WARNING`

**If Found**:
- Copy entire warning context
- Note which test produced the warning
- Check SUMMARY section counters

---

### Test 5: Disposal Verification

**After ending call**:
- Check both consoles for: `[ECHO_TEST] DISPOSE CALLED`
- Verify: `This instance initialized: 1 times`

**If shows 2+ times**: Controller leaked, not disposed properly

---

## DATA COLLECTION CHECKLIST

When you report back, provide:

### Required Console Logs
- [ ] Test 1 - Device A full `[ECHO_TEST]` output
- [ ] Test 1 - Device B full `[ECHO_TEST]` output
- [ ] Test 2 - Any new logs after enabling speaker
- [ ] Test 3 - Device A full `[ECHO_TEST]` output
- [ ] Test 3 - Device B full `[ECHO_TEST]` output
- [ ] Any warnings with full context

### Summary Counts (from SUMMARY sections)
- [ ] Total onTrack calls (per device)
- [ ] Unique tracks (per device)
- [ ] Unique streams (per device)
- [ ] Renderer assignments (per device)
- [ ] Callback invocations (per device)

### Observations
- [ ] Echo occurs: Yes/No
- [ ] Echo occurs only with speaker: Yes/No
- [ ] Echo disappears when both mute: Yes/No
- [ ] Any duplicate warnings: Yes/No
- [ ] Any unexpected behavior: Describe

---

## WHAT NOT TO DO

❌ **Do NOT modify the logging code**  
❌ **Do NOT attempt to fix the issue yet**  
❌ **Do NOT skip any tests**  
❌ **Do NOT use emulators** (real audio required)  
❌ **Do NOT test in noisy environment** (background noise will confuse results)

---

## NEXT STEPS AFTER TESTING

### Step 1: Share Console Logs
- Copy all `[ECHO_TEST]` output from both devices
- Paste into chat or create text file

### Step 2: Analysis
- I will analyze the counts and patterns
- Identify the root cause (based on evidence)

### Step 3: Create Fix Plan
- NO fixes implemented yet
- Will create detailed fix strategy based on findings

### Step 4: Implement Fix (Phase 0.6)
- Only after root cause confirmed
- Will modify specific sections of code
- Will add verification that fix worked

---

## FILES MODIFIED

### `lib/services/call_controller.dart`
**Lines Modified**:
- Lines 79-88: Initialization tracking
- Lines 221-234: Local stream logging
- Lines 266-278: addTrack logging
- Lines 281-362: onTrack comprehensive logging (MOST IMPORTANT)
- Lines 816-820: Disposal logging

**Total Changes**: ~100 lines of logging added  
**Code Behavior**: UNCHANGED (logs only)  
**Performance Impact**: Minimal (print statements)

---

## STATUS

✅ **Logging Complete**  
✅ **Ready for Testing**  
⏸️ **Waiting for Device Test Results**  
🔜 **Analysis Phase** (after logs received)  
🔜 **Fix Phase** (after root cause identified)

---

## QUESTIONS?

**Q**: Why so many logs?  
**A**: Need to track every point where duplication could occur. The SUMMARY section provides the smoking gun.

**Q**: Will this slow down calls?  
**A**: No. Print statements have negligible impact. Can be removed after fix.

**Q**: Can I test with emulators?  
**A**: No. Echo is an audio phenomenon - requires real speakers and microphones.

**Q**: What if logs are too long?  
**A**: Filter by `[ECHO_TEST]` only. Ignore other logs.

**Q**: Do I need both devices?  
**A**: Yes. Echo is a 2-party issue. Need logs from both sides.

---

**END OF DOCUMENT**  
**Ready to proceed with testing when user is ready**
