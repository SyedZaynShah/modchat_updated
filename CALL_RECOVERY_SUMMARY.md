# CALL RECOVERY INVESTIGATION - SUMMARY

**Date**: 2026-06-28  
**Status**: LOGGING ADDED - READY FOR TESTING  
**Issue**: "Finish call first" error after abnormal termination

---

## PROBLEM

After app killed/crashed during call, user gets "Finish call first" error when trying to make new call, even though no call is visible in UI.

---

## ROOT CAUSE (HYPOTHESIS)

**Stale Firestore documents** in `calls/` collection:
- Status = 'accepted'
- endedAt = null
- Document never cleaned up when app died

**Why**: All cleanup logic runs in app code, which doesn't execute when app is killed/crashed.

---

## INVESTIGATION ADDED

### 1. Diagnostic Logging in CallService

**File**: `lib/services/call_service.dart`  
**Method**: `checkActiveCall()`

**Logs**:
- `[CALL_RECOVERY] Checking active calls for user: X`
- `[CALL_RECOVERY] 🚨 ACTIVE CALL FOUND (as caller/receiver)`
- `[CALL_RECOVERY] Call ID: X`
- `[CALL_RECOVERY] Status: X`
- `[CALL_RECOVERY] Call age: X minutes, Y seconds`
- `[CALL_RECOVERY] ⚠️ WARNING: Call is > 5 minutes old - likely stale`

---

### 2. Disposal Tracking in Call Screens

**Files**: 
- `lib/screens/chat/call_screen.dart`
- `lib/screens/chat/video_call_screen.dart`

**Logs**:
- `[CALL_RECOVERY] CallScreen.dispose() called`
- `[CALL_RECOVERY] Will dispose WebRTC controller: true/false`
- `[CALL_RECOVERY] CallScreen.dispose() complete`

**Purpose**: Verify whether dispose() runs before app dies (it shouldn't on abnormal termination)

---

## TESTING REQUIRED

**Test 1**: Normal call end (baseline)
- Call → Accept → End → Try new call
- Should work ✅

**Test 2**: App kill during call
- Call → Accept → Force stop app → Reopen → Try new call
- Should fail with "Finish call first" 🚨

**Test 3**: Check Firestore for stale document
- After Test 2, check `calls/` collection
- Should see document with status='accepted', endedAt=null

---

## EXPECTED LOG OUTPUT

### Test 1 (Normal - Works)
```
[CALL_RECOVERY] CallScreen.dispose() called
[CALL_RECOVERY] CallScreen.dispose() complete
[CALL_RECOVERY] Checking active calls for user: ...
[CALL_RECOVERY] ✅ No active calls found
```

### Test 2 (App Kill - Fails)
```
[No dispose logs - app killed before dispose ran]

[After reopen, trying new call:]
[CALL_RECOVERY] Checking active calls for user: ...
[CALL_RECOVERY] 🚨 ACTIVE CALL FOUND (as caller)
[CALL_RECOVERY] Call ID: abc123
[CALL_RECOVERY] Status: accepted
[CALL_RECOVERY] Call age: 2 minutes, 15 seconds
[CALL_RECOVERY] ⚠️ WARNING: Call is > 5 minutes old - likely stale
```

Then user sees: "Finish call first" error

---

## FILES MODIFIED

### 1. `lib/services/call_service.dart`
- Added comprehensive logging to `checkActiveCall()` method
- Logs call details, age, and stale warning
- NO behavior changes - logging only

### 2. `lib/screens/chat/call_screen.dart`
- Added logging to `dispose()` method
- Tracks when disposal happens (or doesn't)
- NO behavior changes - logging only

### 3. `lib/screens/chat/video_call_screen.dart`
- Added logging to `dispose()` method
- Same as call_screen.dart
- NO behavior changes - logging only

---

## DOCUMENTS CREATED

1. **`CALL_RECOVERY_INVESTIGATION.md`** (18 KB)
   - Full technical analysis
   - Root cause explanation
   - Gap analysis
   - All scenarios documented
   - **Use for**: Deep technical understanding

2. **`CALL_RECOVERY_TEST_GUIDE.md`** (6 KB)
   - Step-by-step testing procedure
   - 5 tests with expected results
   - Log extraction instructions
   - **Use for**: Running the tests

3. **`CALL_RECOVERY_SUMMARY.md`** (this doc - 2 KB)
   - Quick overview
   - Key findings
   - Next steps
   - **Use for**: Quick reference

---

## KEY FINDINGS FROM INVESTIGATION

### Where Error Originates
1. User tries to start call
2. `CallService._startCall()` called
3. Checks `checkActiveCall(userId)`
4. Finds Firestore doc with status='accepted'
5. Throws: `Exception('You are already on a call')`
6. UI translates to: "Finish call first"

### Why Stale Calls Exist
1. Call accepted (status → 'accepted')
2. App killed/crashed/restarted
3. `dispose()` never runs → Firestore never updated
4. Document stuck with status='accepted' forever
5. No timeout for accepted calls (only for unanswered)
6. No cleanup on app launch
7. No server-side cleanup

### Current System Gaps
- ❌ No timeout for accepted calls
- ❌ No cleanup on abnormal termination
- ❌ No stale detection on app launch
- ❌ No lifecycle observer in call screens
- ✅ Timeout works for unanswered calls (30s)

---

## NEXT STEPS

### Immediate (User)
1. Run Test 2 (app kill test) - 5 minutes
2. Collect console logs with `[CALL_RECOVERY]` marker
3. Take Firestore screenshot of stale document
4. Send logs + screenshot

### After Test Results (Me)
1. Confirm stale documents exist (5 min)
2. Design fix strategy (10 min)
3. Implement Phase 0.7 - Call Recovery Fixes (30 min):
   - Stale call detection on app launch
   - Auto-cleanup of calls > 5 minutes old
   - Optional: Lifecycle observer for graceful shutdown
   - Manual "Clear Call" button as fallback
4. User retests (10 min)

---

## FIX STRATEGY (Preview - Not Implemented Yet)

### Option 1: Cleanup on App Launch (Easiest)
On app startup, check for any calls with:
- My user ID in callerId/receiverId
- Status = 'accepted'
- Age > 5 minutes
→ Auto-update to 'ended'

### Option 2: Lifecycle Observer (Better)
Add `WidgetsBindingObserver` to call screens:
- On `AppLifecycleState.detached`
- Try to update Firestore (have ~1 second)
- Mark call as 'ended'

### Option 3: Server-Side Cleanup (Best)
Cloud Function or Firestore TTL:
- Runs every minute
- Finds calls with status='accepted' and age > 5 min
- Auto-updates to 'ended'

### Option 4: Manual Fallback (Always)
Add button in UI:
- "Clear Call State"
- Force-ends any stale calls
- User-initiated recovery

**Likely Implementation**: Combination of Option 1 + Option 4

---

## VERIFICATION STATUS

✅ **Compilation**: All files compile successfully  
✅ **Diagnostics**: No errors found  
✅ **Logging Added**: Ready to collect evidence  
⏸️ **Testing**: Waiting for user test results  
🔜 **Fix Implementation**: After root cause confirmed  

---

## LOG MARKERS

Filter console output for:
- `[CALL_RECOVERY]` - All call recovery investigation logs
- `[ECHO_TEST]` - Echo investigation logs (separate issue)

---

## QUICK ACTION

**If you just want to see the issue**:
1. Call someone
2. Accept
3. Force stop app
4. Reopen
5. Try to call again
6. Error: "Finish call first"

That's the bug! Now collect logs and send them.

---

**STATUS**: Ready for testing  
**Priority**: High (blocks users after crashes)  
**Estimated Fix Time**: 30 minutes after confirmation  
**User Action Required**: Run Test 2 and send logs
