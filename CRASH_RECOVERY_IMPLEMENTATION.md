# CRASH RECOVERY - IMPLEMENTATION COMPLETE

**Date**: 2026-06-28  
**Priority**: CRITICAL - Must work before building group calls  
**Status**: ✅ IMPLEMENTED - Ready for testing

---

## WHAT WAS IMPLEMENTED

### Fix 1: Cleanup Stale Accepted Calls (CRITICAL) ✅

**Problem**: App crashes during active call → document stuck with status='accepted' → blocks all future calls

**Solution**: On app startup after login, automatically clean up stale calls

**Logic**:
```dart
Find calls where:
  - (callerId == currentUser OR receiverId == currentUser)
  - status == 'accepted'
  - age > 5 minutes

Mark them:
  - status = 'ended'
  - endedAt = serverTimestamp
```

**Why 5 minutes**: Normal calls should have ended before this. 5+ minutes = definitely stale.

---

### Fix 2: Cleanup Stale Ringing Calls ✅

**Problem**: Unanswered calls stuck in 'calling'/'ringing' state (missed by timeout mechanism)

**Solution**: Clean up old ringing calls on app startup

**Logic**:
```dart
Find calls where:
  - (callerId == currentUser OR receiverId == currentUser)
  - status == 'calling' OR status == 'ringing'
  - age > 60 seconds

Mark them:
  - status = 'missed'
  - endedAt = serverTimestamp
```

**Why 60 seconds**: Normal timeout is 30s. 60s catches anything that slipped through.

---

### Fix 3: Debug Screen ✅

**Problem**: Need visibility into active calls during development

**Solution**: Created `CallDebugScreen` accessible from Settings

**Features**:
- Shows all active calls for current user
- Displays: status, type, age, role (caller/receiver)
- Highlights stale calls in red
- "Force End" button per call
- "Run Cleanup" button
- Real-time refresh

**Access**: Settings → "Call Debug (Dev)"

---

## FILES CREATED

### 1. `lib/services/call_recovery_service.dart` (210 lines)

**Purpose**: Service for cleaning up stale calls

**Public Methods**:

**`cleanupStaleCalls()`**
- Runs both cleanup operations
- Called automatically on app login
- Logs detailed info to console

**`getActiveCallsForDebug()`**
- Returns list of active calls for current user
- Used by debug screen

**`forceEndCall(callId)`**
- Force-ends a specific call
- Used by debug screen

**Console Logs** (with marker `[CallRecovery]`):
```
[CallRecovery] Starting stale call cleanup for user: xyz
[CallRecovery] 🔍 Checking for stale ACCEPTED calls...
[CallRecovery] 🚨 Found 2 stale accepted call(s)
[CallRecovery] 📞 Call abc123:
[CallRecovery]    Status: accepted
[CallRecovery]    Age: 120 minutes
[CallRecovery]    🧹 Cleaning up (older than 5 minutes)...
[CallRecovery]    ✅ Marked as ended
[CallRecovery] ✅ Cleaned up 2 stale accepted call(s)
[CallRecovery] ✅ Cleanup complete
```

---

### 2. `lib/screens/debug/call_debug_screen.dart` (430 lines)

**Purpose**: Visual debug tool for viewing/managing active calls

**UI Features**:
- Summary card showing total active calls + stale count
- List of all active calls with detailed info
- Color-coded status (blue=calling, orange=ringing, green=accepted, red=stale)
- Age formatted nicely (2d 3h, 5h 20m, 3m 45s, etc.)
- "Force End" button per call
- "Run Cleanup" button in app bar
- Refresh button

**Stale Detection**:
- Accepted calls > 5 minutes = STALE (red background)
- Calling/ringing > 60 seconds = STALE (red background)

**Empty State**: Shows green checkmark + "No active calls found 🎉"

---

## FILES MODIFIED

### 3. `lib/app.dart` (Modified)

**Changes**:
1. Added import: `services/call_recovery_service.dart`
2. Changed `AuthGate` from `ConsumerWidget` to `ConsumerStatefulWidget`
3. Added state variables to track cleanup status
4. Added `_runCleanupIfNeeded()` method
5. Calls cleanup when user logs in and email is verified

**Logic**:
```dart
- Only runs once per login session
- Tracks last user ID to prevent duplicate runs
- Runs asynchronously (doesn't block UI)
- Logs to console: "[AuthGate] User logged in, running stale call cleanup..."
```

---

### 4. `lib/screens/settings/settings_screen.dart` (Modified)

**Changes**:
1. Added import: `../debug/call_debug_screen.dart`
2. Added new `_SettingsTile` before logout button:
   - Icon: bug_report
   - Title: "Call Debug (Dev)"
   - Subtitle: "View and force-end active calls"
   - Navigation to CallDebugScreen

---

## HOW IT WORKS

### Automatic Cleanup Flow

```
1. User opens app
   ↓
2. Firebase Auth stream emits user
   ↓
3. AuthGate detects login
   ↓
4. Calls _runCleanupIfNeeded()
   ↓
5. CallRecoveryService.cleanupStaleCalls() executes
   ↓
6. Queries Firestore for stale calls
   ↓
7. Updates stale calls to terminal states
   ↓
8. Logs results to console
   ↓
9. User can now make calls ✅
```

**Timing**: Runs in background, doesn't block UI

---

### Manual Cleanup (Debug Screen)

```
1. User opens Settings
   ↓
2. Taps "Call Debug (Dev)"
   ↓
3. CallDebugScreen loads active calls
   ↓
4. User sees list of active calls
   ↓
5. User taps "Run Cleanup" OR "Force End"
   ↓
6. Confirmation dialog
   ↓
7. Cleanup executes
   ↓
8. Results logged to console
   ↓
9. Screen refreshes automatically
```

---

## TESTING PROCEDURE

### Test 1: Reproduce Stale Call Block

**Goal**: Verify the bug exists before fix

**Steps**:
1. Device A: Call Device B
2. Device B: Accept call
3. Talk for 10 seconds
4. **Device A: Force stop app** (Settings → Force Stop)
5. **Device A: Check Firestore** - should see document with status='accepted'
6. **Device A: Reopen app** (DON'T login yet)
7. Check console - should see:
   ```
   [AuthGate] User logged in, running stale call cleanup...
   [CallRecovery] Starting stale call cleanup...
   [CallRecovery] 🚨 Found 1 stale accepted call(s)
   [CallRecovery] ✅ Cleaned up 1 stale accepted call(s)
   ```
8. **Device A: Try to make new call**
9. **Expected Result**: ✅ Call works (no "Finish call first" error)

---

### Test 2: Verify Debug Screen

**Goal**: Ensure debug screen works

**Steps**:
1. Device A: Start call but don't accept (leave ringing)
2. Device A: Open Settings → Call Debug (Dev)
3. **Expected**: See 1 active call listed
4. **Check**:
   - Status: ringing
   - Type: voice/video
   - Age: X seconds
   - Role: caller
5. Tap "Force End"
6. Confirm
7. **Expected**: Call ends, screen refreshes, shows "No active calls"

---

### Test 3: Verify Stale Detection

**Goal**: Ensure stale calls are highlighted

**Steps**:
1. Create a stale accepted call (force stop during call)
2. Reopen app
3. **Immediately** open Call Debug screen (before 5 minutes pass)
4. **Expected**: See call listed (green background)
5. Wait 5+ minutes
6. Refresh debug screen
7. **Expected**: Call now has RED background + warning message

---

### Test 4: Verify Cleanup on Login

**Goal**: Ensure automatic cleanup works

**Steps**:
1. Create 3 stale calls:
   - 1 accepted (> 5 minutes old)
   - 1 ringing (> 60 seconds old)
   - 1 calling (> 60 seconds old)
2. Force close app completely
3. Reopen app
4. **Immediately** check console
5. **Expected**:
   ```
   [CallRecovery] 🚨 Found 1 stale accepted call(s)
   [CallRecovery] ✅ Cleaned up 1 stale accepted call(s)
   [CallRecovery] 🚨 Found 2 stale calling/ringing call(s)
   [CallRecovery] ✅ Cleaned up 2 stale calling/ringing call(s)
   ```
6. Open debug screen
7. **Expected**: All calls cleaned up, shows "No active calls"

---

## CONSOLE LOG EXAMPLES

### Successful Cleanup (No Stale Calls)
```
[AuthGate] 🧹 User logged in, running stale call cleanup...
[CallRecovery] ========================================
[CallRecovery] Starting stale call cleanup for user: user123
[CallRecovery] ========================================
[CallRecovery] 🔍 Checking for stale ACCEPTED calls...
[CallRecovery] ✅ No stale accepted calls found
[CallRecovery] 🔍 Checking for stale CALLING/RINGING calls...
[CallRecovery] ✅ No stale calling/ringing calls found
[CallRecovery] ========================================
[CallRecovery] ✅ Cleanup complete
[CallRecovery] ========================================
```

---

### Cleanup with Stale Calls Found
```
[AuthGate] 🧹 User logged in, running stale call cleanup...
[CallRecovery] ========================================
[CallRecovery] Starting stale call cleanup for user: user123
[CallRecovery] ========================================
[CallRecovery] 🔍 Checking for stale ACCEPTED calls...
[CallRecovery] 🚨 Found 2 stale accepted call(s)
[CallRecovery] 📞 Call abc123:
[CallRecovery]    Status: accepted
[CallRecovery]    Age: 120 minutes
[CallRecovery]    Caller: user123
[CallRecovery]    Receiver: user456
[CallRecovery]    🧹 Cleaning up (older than 5 minutes)...
[CallRecovery]    ✅ Marked as ended
[CallRecovery] 📞 Call def456:
[CallRecovery]    Status: accepted
[CallRecovery]    Age: 45 minutes
[CallRecovery]    Caller: user789
[CallRecovery]    Receiver: user123
[CallRecovery]    🧹 Cleaning up (older than 5 minutes)...
[CallRecovery]    ✅ Marked as ended
[CallRecovery] ✅ Cleaned up 2 stale accepted call(s)
[CallRecovery] 🔍 Checking for stale CALLING/RINGING calls...
[CallRecovery] ✅ No stale calling/ringing calls found
[CallRecovery] ========================================
[CallRecovery] ✅ Cleanup complete
[CallRecovery] ========================================
```

---

## EDGE CASES HANDLED

### Case 1: Multiple Logins
**Scenario**: User logs out and logs back in  
**Handled**: Cleanup runs again for new session  
**Logic**: Tracks `_lastUserId` and `_cleanupDone` flag

### Case 2: App Restart
**Scenario**: App completely closed and reopened  
**Handled**: Cleanup runs fresh on startup  
**Logic**: State variables reset

### Case 3: Recent Calls
**Scenario**: Active call < 5 minutes old  
**Handled**: NOT cleaned up (considered legitimate)  
**Logic**: Age check before cleanup

### Case 4: No User Logged In
**Scenario**: Auth stream emits null  
**Handled**: Cleanup skipped  
**Logic**: Early return if `currentUserId == null`

### Case 5: Firestore Errors
**Scenario**: Network issue during cleanup  
**Handled**: Errors logged, cleanup continues  
**Logic**: Try-catch per call, doesn't stop on first error

---

## CONFIGURATION

### Cleanup Thresholds

**Can be adjusted** in `call_recovery_service.dart`:

```dart
// Accepted call threshold
if (ageMinutes > 5) {  // ← Change this value
  // Cleanup
}

// Ringing call threshold
if (ageSeconds > 60) {  // ← Change this value
  // Cleanup
}
```

**Recommendations**:
- **Accepted**: 5 minutes (current) is good balance
- **Ringing**: 60 seconds (current) is safe (2x normal timeout)

---

## VERIFICATION CHECKLIST

Before considering this complete:

- [ ] Test 1: Reproduce + verify cleanup works
- [ ] Test 2: Debug screen shows active calls
- [ ] Test 3: Stale calls highlighted in red
- [ ] Test 4: Automatic cleanup on login works
- [ ] Console logs appear correctly
- [ ] No "Finish call first" errors after crashes
- [ ] Can make new calls after app restart

---

## WHAT THIS DOESN'T FIX (YET)

### 1. Status Transition Race Condition
- **Issue**: `Future.delayed(500ms)` before 'calling' → 'ringing'
- **Impact**: Receiver might not see call if caller app dies within 500ms
- **Fix**: Separate task (don't touch until this is stable)

### 2. Echo with Speakerphone
- **Issue**: Echo occurs with speakerphone enabled
- **Impact**: Poor call quality
- **Fix**: Separate investigation (Phase 0.5)

### 3. Server-Side Cleanup
- **Issue**: Still client-side only
- **Impact**: If all devices offline, stale calls persist
- **Fix**: Future enhancement (Cloud Functions)

---

## NEXT STEPS

1. ✅ **Implemented** - Stale call cleanup
2. ✅ **Implemented** - Debug screen
3. 🔥 **User Testing** - Verify recovery works
4. 🔥 **Verify** - 1-to-1 calls survive crashes
5. 🔥 **Verify** - Incoming call reliability
6. 🔥 **Eliminate** - Remaining echo
7. 🔥 **Re-audit** - Architecture after all fixes
8. 🔜 **Build** - Group calling on stable foundation

---

## SUCCESS CRITERIA

**BEFORE** considering group calls:

✅ Stale calls automatically cleaned on app startup  
✅ Users can make calls after crashes  
✅ Debug screen shows accurate call state  
✅ No "ghost" calls blocking new calls  
✅ Console logs provide clear diagnostics  
✅ Manual recovery available via debug screen  

**ALL** tests passing consistently

---

**END OF IMPLEMENTATION DOCUMENT**

**Status**: READY FOR USER TESTING  
**Priority**: CRITICAL - Test before proceeding to group calls  
**Time to Test**: ~15 minutes
