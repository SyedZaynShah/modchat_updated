# GHOST CALL - FINDINGS SUMMARY

**Date**: 2026-06-28  
**Type**: READ-ONLY AUDIT (NO CODE CHANGES)

---

## PROBLEMS INVESTIGATED

1. ❌ Users get "Finish current call first" when no call is active
2. ❌ Caller creates call but receiver never receives incoming UI

---

## ROOT CAUSES IDENTIFIED

### Problem 1: Ghost "Active Call" Block

**Cause**: Stale Firestore documents with status='accepted'

**How It Happens**:
1. User in active call (status='accepted')
2. App killed/crashed during call
3. `dispose()` never runs (app died before cleanup)
4. Firestore document remains: `{status: 'accepted', endedAt: null}`
5. User reopens app, tries to make new call
6. System checks: "Does user have active call?"
7. Query finds stale document with status='accepted'
8. Blocks with: "You are already on a call"

**Exact Code**:
- **Query**: `call_service.dart:29,72`
  ```dart
  .where('status', whereIn: ['calling', 'ringing', 'accepted'])
  ```
- **Block**: `call_service.dart:186`
  ```dart
  if (callerActiveCall['hasActiveCall'] == true) {
    throw Exception('You are already on a call');
  }
  ```

**Why No Cleanup**:
- ❌ No stale call detection on app launch
- ❌ No timeout for 'accepted' calls (only for unanswered)
- ❌ No lifecycle observer to catch app death
- ❌ No server-side cleanup

---

### Problem 2: Receiver Never Sees Call

**Cause**: Race condition + strict filter

**Race Condition** (Most Likely):
1. Caller creates document with status='calling'
2. After 500ms delay, updates to status='ringing'
3. **IF** caller app dies before 500ms → status stuck at 'calling'
4. Receiver's stream only listens for status='ringing'
5. Query doesn't match → no UI shown

**Exact Code**:
- **Race**: `call_service.dart:224-227`
  ```dart
  Future.delayed(const Duration(milliseconds: 500), () {
    _updateCallState(callId, CallState.ringing);  // May never execute
  });
  ```
- **Strict Filter**: `call_service.dart:444`
  ```dart
  .where('status', isEqualTo: CallState.ringing.toFirestore())  // ONLY 'ringing'
  ```

**Alternative Causes**:
- Firestore real-time lag
- Duplicate call ID blocking
- Already on incoming call screen (blocks second call)

---

## KEY FINDINGS

### Active Call Detection

**File**: `lib/services/call_service.dart`  
**Method**: `checkActiveCall(userId)`

**Queries**:
1. Caller check: `where('callerId', '==', userId) && where('status', 'in', ['calling', 'ringing', 'accepted'])`
2. Receiver check: `where('receiverId', '==', userId) && where('status', 'in', ['calling', 'ringing', 'accepted'])`

**Returns**:
- If found: `{hasActiveCall: true, callId: X, role: 'caller'/'receiver'}`
- If not found: `{hasActiveCall: false}`

---

### Status Definitions

**Active Statuses** (block new calls):
- ✅ `calling` - Being initiated
- ✅ `ringing` - Ringing on receiver
- ✅ `accepted` - Call in progress

**Terminal Statuses** (do NOT block):
- ❌ `declined` - Declined by receiver
- ❌ `missed` - Timed out (30s)
- ❌ `cancelled` - Cancelled by caller
- ❌ `ended` - Normally ended
- ❌ `failed` - Error

**Source**: `lib/models/call_state.dart:32-34`

---

### Incoming Call Stream

**File**: `lib/services/call_service.dart`  
**Method**: `listenToIncomingCalls()`

**Query**:
```dart
.where('receiverId', isEqualTo: currentUserId)
.where('status', isEqualTo: 'ringing')  // ← ONLY 'ringing'
```

**Additional Filtering**: `lib/widgets/incoming_call_listener.dart:47-51`
```dart
if (state != CallState.ringing) {
  return;  // Skip non-ringing calls
}
```

**Duplicate Protection**: Uses `_currentCallId` state variable to prevent showing same call twice

---

### Timeout Mechanism

**File**: `lib/services/call_service.dart`  
**Method**: `_startCallTimeout()`

**Duration**: 30 seconds

**Logic**:
```dart
if (status == CallState.calling || status == CallState.ringing) {
  // Update to 'missed'
} else {
  // Do nothing - already answered/ended
}
```

**✅ Works For**: Unanswered calls (calling/ringing)  
**❌ Does NOT Work For**: Answered calls (accepted)

---

## CONFIRMED BUGS

### BUG #1: Stale 'Accepted' Documents
- **Severity**: HIGH
- **Trigger**: App kill/crash during active call
- **Impact**: User permanently blocked from making calls
- **Location**: No cleanup mechanism exists
- **Evidence**: Lines 29, 72, 186 in call_service.dart

### BUG #2: No Timeout for Accepted Calls
- **Severity**: HIGH
- **Trigger**: Every abnormal termination during call
- **Impact**: Stale documents accumulate forever
- **Location**: `_startCallTimeout()` only handles unanswered
- **Evidence**: Lines 350-358 in call_service.dart

### BUG #3: Race Condition in Status Transition
- **Severity**: MEDIUM
- **Trigger**: Caller app dies within 500ms of call creation
- **Impact**: Receiver never sees call
- **Location**: Fire-and-forget delayed update
- **Evidence**: Lines 224-227 in call_service.dart

---

## ARCHITECTURE GAPS

1. ❌ No stale call detection on app launch
2. ❌ No lifecycle observer in call screens
3. ❌ No server-side cleanup (Cloud Functions/TTL)
4. ❌ No manual recovery UI ("Clear Call" button)
5. ❌ Strict 'ringing' filter (doesn't handle 'calling')

---

## FIRESTORE SECURITY RULES

**File**: `firebase/firestore.rules:198-247`

**Create**: ✅ Requires auth, caller must be creator, status must be 'calling' or 'ringing'  
**Read**: ✅ Caller or receiver can read  
**Update**: ✅ Caller or receiver can update, IDs immutable  
**Delete**: ❌ Prevented (audit trail) - **NO CLEANUP POSSIBLE VIA DELETE**

---

## EXACT BLOCKING POINTS

### Where "Finish call first" Error Originates

**File**: `lib/services/call_service.dart`

**Line 186** (Caller):
```dart
if (callerActiveCall['hasActiveCall'] == true) {
  throw Exception('You are already on a call');  // ← ERROR HERE
}
```

**Line 192** (Receiver):
```dart
if (receiverActiveCall['hasActiveCall'] == true) {
  throw Exception('User is already on another call');
}
```

### Where UI Displays Error

**File**: `lib/screens/chat/chat_detail_screen.dart`

**Lines 862-864, 935-937**:
```dart
if (errorMessage.contains('already on a call')) {
  displayMessage = 'Finish current call first';  // ← USER SEES THIS
}
```

---

## VERIFICATION RESULTS

### Q: Can old 'ended' documents block calls?
**A**: ❌ NO - Query only matches ['calling', 'ringing', 'accepted']

### Q: What happens after crash during accepted call?
**A**: ✅ Document remains with status='accepted', blocks all future calls

### Q: Why doesn't timeout clean it up?
**A**: ✅ Timeout only applies to unanswered calls (calling/ringing)

### Q: Why doesn't receiver see incoming call?
**A**: ⚠️ Most likely: Status stuck at 'calling', stream requires 'ringing'

---

## RECOMMENDED FIXES

### Priority 1 - Stale Call Cleanup (HIGH)
**Where**: Add to app initialization  
**What**: On app launch, detect calls with:
- User ID in callerId/receiverId
- Status = 'accepted'
- Age > 5 minutes
→ Auto-update to 'ended'

### Priority 2 - Remove Race Condition (HIGH)
**Where**: `call_service.dart:224-227`  
**What**: 
- Remove `Future.delayed()` 
- Update to 'ringing' synchronously
- Or add proper await + error handling

### Priority 3 - Relax Incoming Filter (MEDIUM)
**Where**: `call_service.dart:444`  
**What**: Include 'calling' status in query  
**Or**: Handle 'calling' in listener

### Priority 4 - Add Manual Recovery (LOW)
**Where**: Settings screen  
**What**: "Clear Call" button to force-end stale calls

---

## TESTING RECOMMENDATIONS

### Test 1: Reproduce Stale Call Block
1. Start call, accept
2. Force stop app
3. Reopen app
4. Try new call
5. **Expected**: "Finish call first" error
6. Check Firestore for document with status='accepted'

### Test 2: Check for Race Condition
1. Start call (don't accept)
2. Within 500ms, force stop caller app
3. Check receiver - does incoming UI appear?
4. Check Firestore - what is status? ('calling' or 'ringing')

### Test 3: Verify Timeout Works
1. Start call, don't answer
2. Wait 30 seconds
3. Check Firestore - status should be 'missed'
4. Try new call - should work ✅

---

## DOCUMENTS CREATED

1. **`GHOST_CALL_AUDIT_REPORT.md`** (35 KB) - Full forensic analysis
2. **`GHOST_CALL_FINDINGS_SUMMARY.md`** (this doc - 7 KB) - Quick reference

---

## NO CODE WAS MODIFIED

This is a READ-ONLY investigation as requested.  
All findings documented for Phase 0.7 implementation.

---

**END OF SUMMARY**
