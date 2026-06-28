# ECHO TEST - QUICK GUIDE

**Goal**: Collect evidence to identify echo root cause  
**Time Required**: 15 minutes  
**Devices**: 2 physical devices required

---

## QUICK START

### Step 1: Setup (2 minutes)
1. Open app on Device A (your phone)
2. Open app on Device B (test phone)
3. Open Chrome Developer Tools on both (if using Flutter web)
   - OR use `flutter logs` if using physical devices
   - OR use Android Studio / Xcode console

---

### Step 2: Test Audio Call - Earpiece (5 minutes)

**Device A**:
1. Start voice call to Device B
2. Wait for acceptance

**Device B**:
1. Accept call
2. **IMPORTANT**: Make sure speaker is OFF (earpiece mode)

**Both Devices**:
1. Take turns speaking
2. Listen for echo (should be none)

**Collect Logs**:
- Copy ALL lines containing `[ECHO_TEST]` from Device A console
- Copy ALL lines containing `[ECHO_TEST]` from Device B console
- Save to file: `test1_earpiece.txt`

---

### Step 3: Test Audio Call - Speakerphone (5 minutes)

**Continue from Step 2**:

**Device B**:
1. Toggle speakerphone ON (tap speaker icon)

**Both Devices**:
1. Device A: Say "Testing one two three"
2. Wait 1 second
3. Device A: Listen (should hear echo)

**Collect Logs**:
- Copy ANY new `[ECHO_TEST]` lines that appeared after toggling speaker
- Save to file: `test2_speaker.txt`

**End Call**:
- Tap end call button on either device

---

### Step 4: Test Video Call (5 minutes)

**Device A**:
1. Start video call to Device B

**Device B**:
1. Accept call
2. Speaker is ON by default (video calls use speaker)

**Both Devices**:
1. Take turns speaking
2. Listen for echo (should occur)

**Collect Logs**:
- Copy ALL lines containing `[ECHO_TEST]` from Device A console
- Copy ALL lines containing `[ECHO_TEST]` from Device B console
- Save to file: `test3_video.txt`

**End Call**:
- Tap end call button

---

### Step 5: Check for Problems

Search all log files for these patterns:

**Pattern 1**: Multiple Initializations
```
[ECHO_TEST] INITIALIZE called (Global: 2, This instance: 1)
```
If Global > 1 → PROBLEM

**Pattern 2**: Duplicate Tracks
```
[ECHO_TEST] ⚠️ WARNING: Track ID xyz seen before!
```
If found → PROBLEM

**Pattern 3**: Duplicate Streams
```
[ECHO_TEST] ⚠️ WARNING: Stream ID abc seen before!
```
If found → PROBLEM

**Pattern 4**: Multiple Callbacks
Look for SUMMARY section:
```
[ECHO_TEST] - Callback invocations: 2
```
If > 1 for audio calls → PROBLEM

---

## WHAT TO SEND ME

### Option A: Full Console Output (Preferred)
Send me the 3 files:
- `test1_earpiece.txt` (all `[ECHO_TEST]` lines from both devices)
- `test2_speaker.txt` (any new `[ECHO_TEST]` lines)
- `test3_video.txt` (all `[ECHO_TEST]` lines from both devices)

---

### Option B: Summary Only (If logs are huge)
Fill out this template:

```
TEST 1 - AUDIO CALL EARPIECE
Device A:
- Initialize called: X times (Global: Y, This instance: Z)
- Local audio tracks: X
- addTrack calls: X
- onTrack fired: X times
- Unique tracks: X
- Unique streams: X
- Renderer assignments: X (if video)
- Callback invocations: X
- Warnings: Yes/No (copy warning if yes)

Device B:
[Same info as Device A]

Echo occurred: Yes/No
---

TEST 2 - AUDIO CALL SPEAKERPHONE
Any new logs after enabling speaker: Yes/No
(If yes, copy them)

Echo occurred: Yes/No
---

TEST 3 - VIDEO CALL
Device A:
[Same structure as Test 1]

Device B:
[Same structure as Test 1]

Echo occurred: Yes/No
```

---

## HOW TO FILTER LOGS

### If using Flutter console:
Your console will have MANY lines. You need to extract only `[ECHO_TEST]` lines.

**Windows**:
```cmd
flutter logs > full_logs.txt
findstr "[ECHO_TEST]" full_logs.txt > echo_logs.txt
```

**Mac/Linux**:
```bash
flutter logs > full_logs.txt
grep "[ECHO_TEST]" full_logs.txt > echo_logs.txt
```

**Manual** (if commands don't work):
1. Copy entire console output to text editor
2. Use Find/Replace:
   - Find: lines NOT containing `[ECHO_TEST]`
   - Replace: (delete them)

---

## EXPECTED OUTPUT EXAMPLE

### Healthy Audio Call (No Problems)

**Device A**:
```
[ECHO_TEST] ========================================
[ECHO_TEST] INITIALIZE called (Global: 1, This instance: 1)
[ECHO_TEST] CallId: abc123
[ECHO_TEST] IsInitiator: true
[ECHO_TEST] IsVideoCall: false
[ECHO_TEST] ========================================
[ECHO_TEST] ========================================
[ECHO_TEST] LOCAL STREAM ACQUIRED
[ECHO_TEST] Stream ID: local-stream-1
[ECHO_TEST] Local audio tracks: 1
[ECHO_TEST] Audio track ID: audio-track-1
[ECHO_TEST] Audio track enabled: true
[ECHO_TEST] ========================================
[ECHO_TEST] ========================================
[ECHO_TEST] ADDING LOCAL TRACKS TO PEER CONNECTION
[ECHO_TEST] Total tracks to add: 1
[ECHO_TEST] addTrack() call #1 - Track kind: audio, ID: audio-track-1, enabled: true
[ECHO_TEST] Total addTrack() calls: 1
[ECHO_TEST] ========================================
[ECHO_TEST] ========================================
[ECHO_TEST] ONTRACK FIRED #1
[ECHO_TEST] Track kind: audio
[ECHO_TEST] Track ID: remote-audio-1
[ECHO_TEST] Track enabled: true
[ECHO_TEST] Number of streams in event: 1
[ECHO_TEST] ✅ New track ID (total unique tracks: 1)
[ECHO_TEST] Stream ID: remote-stream-1
[ECHO_TEST] ✅ New stream ID (total unique streams: 1)
[ECHO_TEST] Remote audio tracks: 1
[ECHO_TEST] CALLBACK INVOCATION #1
[ECHO_TEST] Invoking onRemoteStream callback
[ECHO_TEST] ========================================
[ECHO_TEST] SUMMARY SO FAR:
[ECHO_TEST] - Total onTrack calls: 1
[ECHO_TEST] - Unique tracks: 1
[ECHO_TEST] - Unique streams: 1
[ECHO_TEST] - Renderer assignments: 0
[ECHO_TEST] - Callback invocations: 1
[ECHO_TEST] ========================================
```

Device B should show similar output (with IsInitiator: false)

---

### Problematic Call (Duplicates)

If you see THIS instead:
```
[ECHO_TEST] ONTRACK FIRED #2
[ECHO_TEST] ⚠️ WARNING: Track ID remote-audio-1 seen before!
[ECHO_TEST] ⚠️ WARNING: Stream ID remote-stream-1 seen before!
[ECHO_TEST] RENDERER ASSIGNMENT #2
[ECHO_TEST] CALLBACK INVOCATION #2
[ECHO_TEST] SUMMARY SO FAR:
[ECHO_TEST] - Total onTrack calls: 2
[ECHO_TEST] - Unique tracks: 1
[ECHO_TEST] - Unique streams: 1
[ECHO_TEST] - Renderer assignments: 2
[ECHO_TEST] - Callback invocations: 2
```

This is the smoking gun! It shows:
- `onTrack` fired twice
- Same track/stream processed twice
- Renderer assigned twice
- Callback invoked twice
→ This WILL cause echo

---

## TROUBLESHOOTING

### "I don't see any [ECHO_TEST] logs"
**Cause**: App not rebuilt after adding logs  
**Fix**: 
```bash
flutter clean
flutter pub get
flutter run
```

---

### "Logs appear on one device but not the other"
**Cause**: One device not connected to console  
**Fix**: Connect both devices before testing

---

### "Too many logs, can't find [ECHO_TEST]"
**Fix**: Use filter commands above, or Ctrl+F in console to search for `[ECHO_TEST]`

---

### "Echo test logs appear but call doesn't connect"
**Cause**: Network issue, not related to logging  
**Fix**: Check internet connection, Firestore rules, call service

---

## WHAT HAPPENS NEXT

After you send the logs:

1. **I analyze the counts** (5 minutes)
   - Check if initialize() called once
   - Check if addTrack() called once per track
   - Check if onTrack fired correct number of times
   - Check if any duplicates detected

2. **I identify root cause** (5 minutes)
   - Based on which counter is wrong
   - Based on which warnings appeared

3. **I create fix plan** (10 minutes)
   - Document the exact problem
   - Propose specific code changes
   - Create Phase 0.6 implementation doc

4. **I implement fix** (15 minutes)
   - Modify specific code sections
   - Add verification that fix worked
   - Keep echo test logs for comparison

5. **You test again** (10 minutes)
   - Same 3 tests
   - Compare before/after logs
   - Verify echo is gone

---

## READY TO START?

When you're ready:
1. Grab 2 devices
2. Run through 3 tests (15 minutes)
3. Send me the logs
4. I'll analyze and create fix

---

**END OF QUICK GUIDE**
