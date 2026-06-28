# CALL RECOVERY INVESTIGATION

**Date**: 2026-06-28  
**Status**: INVESTIGATION - NO FIXES YET  
**Issue**: After abnormal call termination, new calls blocked with "Finish call first"

---

## PROBLEM STATEMENT

**Symptoms**:
1. Call terminates abnormally (app kill, freeze, crash, phone hang)
2. User reopens app
3. Attempts to make new call
4. Gets error: "Finish call first"
5. No visible active call in UI

**Impact**: User cannot make calls until stale call state is cleared

---

## ROOT CAUSE ANALYSIS

### 1. Error Message Flow

**User sees**: `"Finish call first"`

**Actual error**: `"You are already on a call"` (from CallService)

**Error translation happens in**: `lib/screens/chat/chat_detail_screen.dart`

```dart
// Lines 862-864 and 935-937
if (errorMessage.contains('already on a call')) {
  displayMessage = 'Finish current call first';
}
```

---

### 2. Active Call Detection Logic

**File**: `lib/services/call_service.dart`  
**Method**: `checkActiveCall(String userId)` (Lines 19-58)

**How it works**:
```dart
// Check if user is CALLER in active call
final asCallerQuery = await _firestoreService.calls
    .where('callerId', isEqualTo: userId)
    .where('status', whereIn: ['calling', 'ringing', 'accepted'])
    .limit(1)
    .get();

if (asCallerQuery.docs.isNotEmpty) {
  return {'hasActiveCall': true, 'callId': ..., 'role': 'caller'};
}

// Check if user is RECEIVER in active call
final asReceiverQuery = await _firestoreService.calls
    .where('receiverId', isEqualTo: userId)
    .where('status', whereIn: ['calling', 'ringing', 'accepted'])
    .limit(1)
    .get();

if (asReceiverQuery.docs.isNotEmpty) {
  return {'hasActiveCall': true, 'callId': ..., 'role': 'receiver'};
}
```

**KEY FINDING**: 
- Checks Firestore `calls` collection for documents with:
  - `callerId` or `receiverId` = current user
  - `status` = 'calling', 'ringing', or 'accepted'
- **If ANY such document exists → call is blocked**

---

### 3. Call Creation Blocking Logic

**File**: `lib/services/call_service.dart`  
**Method**: `_startCall()` (Lines 120-133)

```dart
// Check if caller already has an active call
final callerActiveCall = await checkActiveCall(callerId);
if (callerActiveCall['hasActiveCall'] == true) {
  throw Exception('You are already on a call');  // ← THIS BLOCKS NEW CALLS
}

// Check if receiver already has an active call
final receiverActiveCall = await checkActiveCall(receiverId);
if (receiverActiveCall['hasActiveCall'] == true) {
  throw Exception('User is already on another call');
}
```

**KEY FINDING**:
- Before creating any call, checks both caller and receiver
- If either has active call document → **throws exception**
- Exception propagates to UI → user sees "Finish call first"

---

## ABNORMAL TERMINATION SCENARIOS

### Scenario A: App Kill (Force Stop)

**What happens**:
1. User in active call (status = 'accepted')
2. User force-stops app (Settings → Force Stop)
3. App process killed immediately
4. **`dispose()` methods NEVER RUN**
5. Call document remains in Firestore with status = 'accepted'

**Result**: Stale call document blocks new calls

---

### Scenario B: App Crash

**What happens**:
1. User in active call (status = 'accepted')
2. App crashes (exception, null pointer, etc.)
3. App process terminated
4. **`dispose()` methods MAY NOT RUN** (depends on crash severity)
5. Call document remains in Firestore with status = 'accepted'

**Result**: Stale call document blocks new calls

---

### Scenario C: Phone Hang / Freeze

**What happens**:
1. User in active call (status = 'accepted')
2. Phone freezes (low memory, system issue)
3. User force-restarts phone
4. **`dispose()` methods NEVER RUN**
5. Call document remains in Firestore with status = 'accepted'

**Result**: Stale call document blocks new calls

---

### Scenario D: App Background (Normal)

**What happens**:
1. User in active call (status = 'accepted')
2. User presses home button (app goes to background)
3. App paused but NOT killed
4. **`dispose()` NOT called** (app still in memory)
5. Call continues normally

**Result**: ✅ No issue - call document still valid

---

### Scenario E: Normal Call End (Healthy)

**What happens**:
1. User in active call (status = 'accepted')
2. User taps "End Call" button
3. `_endCall()` called → `callService.endCall(callId)`
4. Firestore updated: status = 'ended', endedAt = timestamp
5. Navigator pops screen
6. `dispose()` called → `_callController?.dispose()`

**Result**: ✅ No issue - call document marked 'ended'

---

## DISPOSAL FLOW ANALYSIS

### CallScreen Disposal (Voice Calls)

**File**: `lib/screens/chat/call_screen.dart` (Lines 250-264)

```dart
@override
void dispose() {
  _callSubscription?.cancel();
  _pulseController.dispose();
  _callDurationTimer?.cancel();
  _dotTimer?.cancel();
  
  // Dispose WebRTC controller
  _callController?.dispose();
  
  super.dispose();
}
```

**What gets cleaned up**:
- ✅ Firestore listener subscription
- ✅ UI animation controllers
- ✅ Timers
- ✅ WebRTC controller (RTCPeerConnection, MediaStream)

**What DOES NOT get cleaned up**:
- ❌ Firestore call document (remains with status = 'accepted')
- ❌ CallService timers (but these are in-memory only)

**KEY FINDING**:
- `dispose()` only runs when screen is properly popped from navigator
- On app kill/crash, `dispose()` NEVER RUNS
- Firestore call document **never updated to terminal state**

---

### VideoCallScreen Disposal (Video Calls)

**File**: `lib/screens/chat/video_call_screen.dart` (Lines 198-206)

```dart
@override
void dispose() {
  _durationTimer?.cancel();
  _callSubscription?.cancel();
  _callController?.dispose();
  super.dispose();
}
```

**Same issues as CallScreen**: 
- ❌ Firestore document not updated on abnormal termination

---

### CallController Disposal (WebRTC)

**File**: `lib/services/call_controller.dart` (Lines 817-928)

```dart
Future<void> dispose() async {
  if (_isDisposed) return;
  
  _isDisposed = true;
  _mediaState = MediaState.idle;
  
  // Cancel listeners
  await _callDocListener?.cancel();
  await _iceCandidatesListener?.cancel();
  
  // Stop tracks
  _localStream!.getTracks().forEach((track) => track.stop());
  _remoteStream!.getTracks().forEach((track) => track.stop());
  
  // Dispose streams
  await _localStream?.dispose();
  await _remoteStream?.dispose();
  
  // Dispose renderers (video only)
  await localRenderer?.dispose();
  await remoteRenderer?.dispose();
  
  // Close peer connection
  await _peerConnection?.close();
  await _peerConnection?.dispose();
}
```

**What gets cleaned up**:
- ✅ WebRTC peer connection
- ✅ Media streams
- ✅ Video renderers
- ✅ Firestore listeners

**What DOES NOT get cleaned up**:
- ❌ Firestore call document (not CallController's responsibility)

**KEY FINDING**:
- CallController is responsible for WebRTC, not Firestore state
- On abnormal termination, this disposal NEVER RUNS
- Results in media leaks + stale Firestore documents

---

## STALE DOCUMENT INVESTIGATION

### Where Call Documents Are Created

**File**: `lib/services/call_service.dart` (Lines 144-154)

```dart
final callData = {
  'callerId': callerId,
  'callerName': callerName,
  'receiverId': receiverId,
  'type': type, // 'voice' or 'video'
  'status': CallState.calling.toFirestore(),  // Initial: 'calling'
  'createdAt': FieldValue.serverTimestamp(),
  'answeredAt': null,
  'endedAt': null,
};

final docRef = await _firestoreService.calls.add(callData);
```

**Status progression**:
1. `calling` → document created
2. `ringing` → after 500ms delay
3. `accepted` → when receiver accepts
4. `ended` / `missed` / `declined` / `cancelled` → terminal states

---

### Where Call Documents Are Updated to Terminal State

**1. Normal End Call**:
- `endCall()` method (Lines 248-282)
- Updates status to `ended` or `cancelled`
- Sets `endedAt` timestamp

**2. Decline Call**:
- `declineCall()` method (Lines 234-246)
- Updates status to `declined`
- Sets `endedAt` timestamp

**3. Timeout (Missed)**:
- `_startCallTimeout()` method (Lines 322-367)
- After 30 seconds, updates status to `missed`
- Sets `endedAt` timestamp

**4. Fail Call**:
- `failCall()` method (Lines 285-293)
- Updates status to `failed`
- Sets `endedAt` timestamp

---

### Gap Analysis: What's Missing

**Problem**: All terminal state updates require **active running code**

**Scenarios where code doesn't run**:
- ❌ App killed
- ❌ App crashed
- ❌ Phone restarted
- ❌ Network disconnected during call

**Result**: Call document stuck in 'accepted' state forever

---

## TIMEOUT MECHANISM ANALYSIS

### Call Timeout (Unanswered Calls Only)

**File**: `lib/services/call_service.dart` (Lines 322-367)

```dart
static const Duration callTimeout = Duration(seconds: 30);

void _startCallTimeout(String callId) {
  _callTimeouts[callId] = Timer(callTimeout, () async {
    // Check current status
    final doc = await _firestoreService.calls.doc(callId).get();
    final status = CallState.fromString(doc.data()?['status']);
    
    // Only timeout if still calling/ringing
    if (status == CallState.calling || status == CallState.ringing) {
      await _firestoreService.calls.doc(callId).update({
        'status': CallState.missed.toFirestore(),
        'endedAt': FieldValue.serverTimestamp(),
      });
    }
  });
}
```

**What it handles**:
- ✅ Unanswered calls (calling/ringing) → auto-timeout after 30 seconds

**What it DOES NOT handle**:
- ❌ Accepted calls (status = 'accepted') → NO TIMEOUT
- ❌ Timer exists in-memory only → lost on app kill

**KEY FINDING**:
- Timeout only applies to unanswered calls
- **Accepted calls have NO timeout mechanism**
- If call accepted and app killed → **document never cleaned up**

---

## FIRESTORE SECURITY RULES

**File**: `firebase/firestore.rules`

Let me check if there are any TTL or cleanup rules...

**Assumption**: Likely no automatic cleanup rules (need to verify)

---

## CRITICAL GAPS IDENTIFIED

### Gap 1: No Cleanup on Abnormal Termination
- **Issue**: Call document status never updated when app killed/crashed
- **Impact**: Stale 'accepted' documents block new calls indefinitely
- **Root Cause**: All cleanup logic runs in app code, not in Firestore

### Gap 2: No Timeout for Accepted Calls
- **Issue**: Timeout only applies to unanswered calls (calling/ringing)
- **Impact**: Accepted calls stuck forever if app dies
- **Root Cause**: No server-side or cloud function cleanup

### Gap 3: No Stale Document Detection on App Launch
- **Issue**: App doesn't check for stale calls on startup
- **Impact**: User must manually clear state or wait (no wait exists)
- **Root Cause**: No initialization logic to detect/clean stale calls

### Gap 4: No Lifecycle Awareness
- **Issue**: Call screens don't observe app lifecycle (background, kill, etc.)
- **Impact**: No chance to update Firestore before app dies
- **Root Cause**: No `WidgetsBindingObserver` in call screens

### Gap 5: No Server-Side Validation
- **Issue**: Firestore rules don't prevent/clean stale documents
- **Impact**: No automatic cleanup mechanism
- **Root Cause**: Client-side state management only

---

## INVESTIGATION TASKS

### Task 1: Add Diagnostic Logging ✅

Add logging to identify stale calls:

**File**: `lib/services/call_service.dart`  
**Method**: `checkActiveCall()`

```dart
Future<Map<String, dynamic>> checkActiveCall(String userId) async {
  print('[CALL_RECOVERY] ========================================');
  print('[CALL_RECOVERY] Checking active calls for user: $userId');
  
  try {
    // Check as caller
    final asCallerQuery = await _firestoreService.calls
        .where('callerId', isEqualTo: userId)
        .where('status', whereIn: ['calling', 'ringing', 'accepted'])
        .limit(1)
        .get();

    print('[CALL_RECOVERY] Caller query results: ${asCallerQuery.docs.length} docs');
    
    if (asCallerQuery.docs.isNotEmpty) {
      final doc = asCallerQuery.docs.first;
      final data = doc.data();
      
      print('[CALL_RECOVERY] 🚨 ACTIVE CALL FOUND (as caller)');
      print('[CALL_RECOVERY] Call ID: ${doc.id}');
      print('[CALL_RECOVERY] Status: ${data['status']}');
      print('[CALL_RECOVERY] Caller ID: ${data['callerId']}');
      print('[CALL_RECOVERY] Receiver ID: ${data['receiverId']}');
      print('[CALL_RECOVERY] Created At: ${data['createdAt']}');
      print('[CALL_RECOVERY] Answered At: ${data['answeredAt']}');
      print('[CALL_RECOVERY] Type: ${data['type']}');
      
      // Calculate age
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt != null) {
        final age = DateTime.now().difference(createdAt.toDate());
        print('[CALL_RECOVERY] Call age: ${age.inMinutes} minutes, ${age.inSeconds % 60} seconds');
        
        if (age.inMinutes > 5) {
          print('[CALL_RECOVERY] ⚠️ WARNING: Call is > 5 minutes old - likely stale');
        }
      }
      
      print('[CALL_RECOVERY] ========================================');
      
      return {
        'hasActiveCall': true,
        'callId': doc.id,
        'role': 'caller',
        'data': data,
      };
    }

    // Check as receiver
    final asReceiverQuery = await _firestoreService.calls
        .where('receiverId', isEqualTo: userId)
        .where('status', whereIn: ['calling', 'ringing', 'accepted'])
        .limit(1)
        .get();

    print('[CALL_RECOVERY] Receiver query results: ${asReceiverQuery.docs.length} docs');

    if (asReceiverQuery.docs.isNotEmpty) {
      final doc = asReceiverQuery.docs.first;
      final data = doc.data();
      
      print('[CALL_RECOVERY] 🚨 ACTIVE CALL FOUND (as receiver)');
      print('[CALL_RECOVERY] Call ID: ${doc.id}');
      print('[CALL_RECOVERY] Status: ${data['status']}');
      print('[CALL_RECOVERY] Caller ID: ${data['callerId']}');
      print('[CALL_RECOVERY] Receiver ID: ${data['receiverId']}');
      print('[CALL_RECOVERY] Created At: ${data['createdAt']}');
      print('[CALL_RECOVERY] Answered At: ${data['answeredAt']}');
      print('[CALL_RECOVERY] Type: ${data['type']}');
      
      // Calculate age
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt != null) {
        final age = DateTime.now().difference(createdAt.toDate());
        print('[CALL_RECOVERY] Call age: ${age.inMinutes} minutes, ${age.inSeconds % 60} seconds');
        
        if (age.inMinutes > 5) {
          print('[CALL_RECOVERY] ⚠️ WARNING: Call is > 5 minutes old - likely stale');
        }
      }
      
      print('[CALL_RECOVERY] ========================================');

      return {
        'hasActiveCall': true,
        'callId': doc.id,
        'role': 'receiver',
        'data': data,
      };
    }

    print('[CALL_RECOVERY] ✅ No active calls found');
    print('[CALL_RECOVERY] ========================================');

    return {'hasActiveCall': false};
  } catch (e) {
    print('[CALL_RECOVERY] ❌ ERROR checking active call: $e');
    print('[CALL_RECOVERY] ========================================');
    return {'hasActiveCall': false, 'error': e};
  }
}
```

---

### Task 2: Log Disposal Events

Add logging to track when disposal happens (or doesn't):

**File**: `lib/screens/chat/call_screen.dart`  
**Method**: `dispose()`

```dart
@override
void dispose() {
  print('[CALL_RECOVERY] ========================================');
  print('[CALL_RECOVERY] CallScreen.dispose() called');
  print('[CALL_RECOVERY] Call ID: ${widget.callId}');
  print('[CALL_RECOVERY] Will dispose WebRTC controller: ${_callController != null}');
  
  _callSubscription?.cancel();
  _pulseController.dispose();
  _callDurationTimer?.cancel();
  _dotTimer?.cancel();
  
  // Dispose WebRTC controller
  _callController?.dispose();
  
  print('[CALL_RECOVERY] CallScreen.dispose() complete');
  print('[CALL_RECOVERY] ========================================');
  
  super.dispose();
}
```

---

### Task 3: Add Lifecycle Observer

Add app lifecycle tracking to detect when app goes to background/killed:

**File**: `lib/screens/chat/call_screen.dart`

```dart
class _CallScreenState extends ConsumerState<CallScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {  // ADD THIS
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);  // ADD THIS
    // ... existing code
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);  // ADD THIS
    // ... existing code
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[CALL_RECOVERY] ========================================');
    print('[CALL_RECOVERY] App lifecycle state changed: $state');
    print('[CALL_RECOVERY] Call ID: ${widget.callId}');
    print('[CALL_RECOVERY] Call state: $_currentState');
    
    if (state == AppLifecycleState.paused) {
      print('[CALL_RECOVERY] App paused (home button or switched apps)');
    } else if (state == AppLifecycleState.detached) {
      print('[CALL_RECOVERY] ⚠️ App detached (about to be killed)');
      print('[CALL_RECOVERY] This is last chance to cleanup!');
      // NOTE: On detached, we have ~1 second before app dies
      // May not be enough time for async Firestore updates
    } else if (state == AppLifecycleState.resumed) {
      print('[CALL_RECOVERY] App resumed');
    }
    
    print('[CALL_RECOVERY] ========================================');
  }
}
```

---

## TESTING PROCEDURE

### Test 1: Normal Call End (Baseline)
1. Device A calls Device B
2. Device B accepts
3. Talk for 10 seconds
4. Device A ends call
5. Check console logs on Device A

**Expected Logs**:
```
[CALL_RECOVERY] CallScreen.dispose() called
[CALL_RECOVERY] Will dispose WebRTC controller: true
[CALL_RECOVERY] CallScreen.dispose() complete
```

**Then try**:
6. Device A starts new call
7. Should work ✅

---

### Test 2: App Kill During Call
1. Device A calls Device B
2. Device B accepts
3. Talk for 10 seconds
4. **Device A: Force stop app** (Settings → Apps → ModChat → Force Stop)
5. **Device A: Reopen app**
6. Device A tries to start new call to Device B

**Expected Result**: 🚨 "Finish call first" error

**Check Console**:
```
[CALL_RECOVERY] 🚨 ACTIVE CALL FOUND (as caller)
[CALL_RECOVERY] Call ID: xyz
[CALL_RECOVERY] Status: accepted
[CALL_RECOVERY] Call age: X minutes
[CALL_RECOVERY] ⚠️ WARNING: Call is > 5 minutes old - likely stale
```

---

### Test 3: App Backgrounded During Call
1. Device A calls Device B
2. Device B accepts
3. Talk for 10 seconds
4. **Device A: Press home button** (don't force stop)
5. Wait 10 seconds
6. **Device A: Reopen app**

**Expected Result**: ✅ Call screen still visible, call continues

**Check Console**:
```
[CALL_RECOVERY] App lifecycle state changed: AppLifecycleState.paused
[CALL_RECOVERY] App paused (home button or switched apps)
...
[CALL_RECOVERY] App lifecycle state changed: AppLifecycleState.resumed
[CALL_RECOVERY] App resumed
```

---

### Test 4: Phone Restart During Call
1. Device A calls Device B
2. Device B accepts
3. Talk for 10 seconds
4. **Device A: Force restart phone** (hold power button → restart)
5. **Device A: Wait for boot, reopen app**
6. Device A tries to start new call

**Expected Result**: 🚨 "Finish call first" error

**Check Console** (same as Test 2):
```
[CALL_RECOVERY] 🚨 ACTIVE CALL FOUND (as caller)
[CALL_RECOVERY] Call age: X minutes
[CALL_RECOVERY] ⚠️ WARNING: Call is > 5 minutes old - likely stale
```

---

### Test 5: Network Disconnect During Call
1. Device A calls Device B (both on WiFi)
2. Device B accepts
3. **Device A: Turn off WiFi** (settings → WiFi off)
4. Wait 30 seconds
5. **Device A: Turn WiFi back on**
6. Check if call auto-recovers or needs manual end

---

## SUMMARY OF FINDINGS

### Root Cause
**Stale Firestore documents** in `calls/` collection with:
- `status` = 'accepted'
- `endedAt` = null
- Created > 5 minutes ago (or any age)

### Why It Happens
1. Call accepted (status → 'accepted')
2. App killed/crashed/phone restarted
3. `dispose()` never runs
4. Firestore document never updated to terminal state
5. Document blocks new calls indefinitely

### Why Current System Fails
- ✅ Timeout works for **unanswered calls** (calling/ringing)
- ❌ No timeout for **accepted calls**
- ❌ No cleanup on app kill/crash
- ❌ No stale document detection on app launch
- ❌ No lifecycle awareness in call screens
- ❌ No server-side cleanup mechanism

### Required Fixes (Phase 0.7 - Not Implemented Yet)
1. Add stale call detection on app launch
2. Add automatic cleanup of old 'accepted' calls
3. Add lifecycle observer to update Firestore before app dies
4. Consider Firestore TTL rules or Cloud Functions
5. Add manual "Clear Call" button as fallback

---

## NEXT STEPS

1. **User**: Run Tests 1-4 above and share console logs
2. **Me**: Confirm stale documents exist in Firestore
3. **Me**: Design fix strategy (Phase 0.7)
4. **Me**: Implement fixes
5. **User**: Retest all scenarios

---

**STATUS**: Investigation complete, waiting for test results to confirm findings

**Document Version**: 1.0  
**Last Updated**: 2026-06-28
