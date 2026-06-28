# CALL RECOVERY - QUICK TEST GUIDE

**Goal**: Reproduce "Finish call first" error and collect diagnostic logs  
**Time**: 20 minutes  
**Devices**: 2 devices required

---

## WHAT TO TEST

We're investigating why users get "Finish call first" error after:
- App killed during call
- Phone restarted during call
- App crashed during call

---

## TEST 1: Normal Call End (Baseline - 3 minutes)

**Purpose**: Verify normal flow works and logging is active

**Steps**:
1. Device A: Call Device B (voice call)
2. Device B: Accept call
3. Talk for 10 seconds
4. Device A: Tap "End Call" button
5. Device A: Try to call Device B again

**Expected Result**: ✅ Second call works normally

**Check Console Logs** (Device A):
```
[CALL_RECOVERY] CallScreen.dispose() called
[CALL_RECOVERY] Will dispose WebRTC controller: true
[CALL_RECOVERY] CallScreen.dispose() complete

[CALL_RECOVERY] Checking active calls for user: ...
[CALL_RECOVERY] Caller query results: 0 docs
[CALL_RECOVERY] Receiver query results: 0 docs
[CALL_RECOVERY] ✅ No active calls found
```

**Save**: Copy all `[CALL_RECOVERY]` lines → `test1_normal.txt`

---

## TEST 2: App Kill During Call (5 minutes)

**Purpose**: Reproduce the "Finish call first" error

**Steps**:
1. Device A: Call Device B (voice call)
2. Device B: Accept call
3. Talk for 10 seconds
4. **Device A: Force stop app**
   - Android: Settings → Apps → ModChat → Force Stop
   - iOS: Swipe up and remove from recent apps
5. Wait 5 seconds
6. **Device A: Reopen app**
7. Device A: Try to call Device B

**Expected Result**: 🚨 Error: "Finish call first"

**Check Console Logs** (Device A after reopening):
```
[CALL_RECOVERY] Checking active calls for user: ...
[CALL_RECOVERY] Caller query results: 1 docs
[CALL_RECOVERY] 🚨 ACTIVE CALL FOUND (as caller)
[CALL_RECOVERY] Call ID: abc123
[CALL_RECOVERY] Status: accepted
[CALL_RECOVERY] Caller ID: userA_id
[CALL_RECOVERY] Receiver ID: userB_id
[CALL_RECOVERY] Call age: X minutes, Y seconds
[CALL_RECOVERY] ⚠️ WARNING: Call is > 5 minutes old - likely stale
```

**Save**: Copy all `[CALL_RECOVERY]` lines → `test2_app_kill.txt`

**Critical Questions**:
- [ ] Did you see `dispose()` logs before app was killed? (You shouldn't)
- [ ] What is the call age when trying second call?
- [ ] What is the call status? (should be 'accepted')

---

## TEST 3: App Backgrounded (Not Killed) (3 minutes)

**Purpose**: Verify backgrounding doesn't cause issues

**Steps**:
1. Device A: Call Device B (voice call)
2. Device B: Accept call
3. Talk for 10 seconds
4. **Device A: Press home button** (DON'T force stop)
5. Wait 10 seconds
6. **Device A: Reopen app** (tap icon)

**Expected Result**: ✅ Call screen still visible, call continues normally

**Optional**:
7. Device A: End call normally
8. Device A: Try to call Device B again

**Expected**: ✅ Second call works

**Save**: Console logs → `test3_background.txt`

---

## TEST 4: Check Firestore Directly (2 minutes)

**Purpose**: See if stale documents exist

**Steps**:
1. After Test 2 (when error occurs)
2. Open Firebase Console
3. Go to Firestore Database
4. Navigate to `calls` collection
5. Look for documents with:
   - `status` = 'accepted'
   - `endedAt` = null
   - Your user ID in `callerId` or `receiverId`

**Screenshot**: Take screenshot showing the stale document

**Check**:
- [ ] Document exists? Yes/No
- [ ] Status field value: ___
- [ ] endedAt field value: ___
- [ ] createdAt timestamp: ___
- [ ] How old is the document: ___ minutes

---

## TEST 5: Phone Restart (Optional - 5 minutes)

**Purpose**: Test most severe abnormal termination

**Steps**:
1. Device A: Call Device B
2. Device B: Accept call
3. Talk for 10 seconds
4. **Device A: Force restart phone** (hold power → restart)
5. Wait for phone to boot
6. **Device A: Open app**
7. Device A: Try to call Device B

**Expected Result**: 🚨 Error: "Finish call first"

**Save**: Console logs after restart → `test5_restart.txt`

---

## WHAT TO SEND ME

### Required Files

1. **`test1_normal.txt`** - All `[CALL_RECOVERY]` logs from normal call
2. **`test2_app_kill.txt`** - All `[CALL_RECOVERY]` logs from app kill test
3. **Firestore screenshot** - Showing stale document (if exists)

### Optional Files

4. `test3_background.txt` - Background test logs
5. `test5_restart.txt` - Restart test logs

### Summary Info

```
TEST 2 RESULTS:
- Error appeared: Yes/No
- Error message: "___"
- Stale call found in Firestore: Yes/No
- Call age when error occurred: ___ minutes
- Call status: ___
- dispose() logged before app kill: Yes/No
```

---

## HOW TO EXTRACT LOGS

### Android (with USB debugging):
```bash
adb logcat | findstr "[CALL_RECOVERY]" > logs.txt
```

### Android (Flutter console):
```bash
flutter logs | findstr "[CALL_RECOVERY]" > logs.txt
```

### Manual Method:
1. Copy entire console output
2. Paste into text editor
3. Find all lines containing `[CALL_RECOVERY]`
4. Copy just those lines

---

## TROUBLESHOOTING

### "I don't see [CALL_RECOVERY] logs"
- Rebuild app: `flutter clean && flutter run`
- Make sure you're watching the correct device logs

### "Test 2 doesn't show error"
- Possible reasons:
  1. Call timed out (30 seconds) before you reopened app
  2. Firestore document was deleted manually
  3. Different user ID after reopen
- Try again with faster timing

### "Can't find stale document in Firestore"
- Check you're looking at correct project
- Verify user ID matches logged in user
- Try searching by call ID from console logs

---

## WHAT HAPPENS NEXT

After you send logs:

1. **I confirm root cause** (5 min)
   - Verify stale documents exist
   - Verify dispose() never ran
   - Verify call age > timeout

2. **I design fix** (15 min)
   - Stale call detection on app launch
   - Auto-cleanup of old calls
   - Optional: lifecycle observer

3. **I implement Phase 0.7** (30 min)
   - Add cleanup logic
   - Add detection logic
   - Add fallback UI

4. **You test again** (10 min)
   - Repeat Test 2
   - Verify error no longer occurs
   - Verify call recovers automatically

---

## QUICK START

If you just want to reproduce the issue fast:

1. Call someone
2. Accept
3. Force stop app (Settings → Force Stop)
4. Reopen app
5. Try to call again
6. See "Finish call first" error
7. Send me screenshot + console logs

That's it!

---

**STATUS**: Ready to test  
**Estimated Time**: 10-20 minutes  
**Priority**: High (blocks users from making calls after crashes)
