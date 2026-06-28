# GHOST CALL BUG - FORENSIC AUDIT REPORT

**Date**: 2026-06-28  
**Type**: READ-ONLY INVESTIGATION  
**NO CODE MODIFICATIONS**

---

## EXECUTIVE SUMMARY

**Problem 1**: Users receive "Finish current call first" even when no call is active  
**Problem 2**: Caller can create calls but receiver never receives incoming call UI

**Root Causes Identified**:
1. ✅ **Stale Firestore documents** with status='accepted' block new calls
2. ✅ **Strict incoming call filter** only shows status='ringing', missing other cases
3. ✅ **No crash recovery** mechanism to clean up stale calls
4. ⚠️ **Potential race condition** in call state transitions

---

## PART 1: ACTIVE CALL DETECTION

### 1.1 WHERE Active Calls Are Checked

**File**: `lib/services/call_service.dart`  
**Method**: `checkActiveCall(String userId)` (Lines 21-122)

**Called From**: `_startCall()` method (Lines 185-192)

```dart
// Line 185-188: Check caller
final callerActiveCall = await checkActiveCall(callerId);
if (callerActiveCall['hasActiveCall'] == true) {
  throw Exception('You are already on a call');
}

// Line 191-194: Check receiver
final receiverActiveCall = await checkActiveCall(receiverId);
if (receiverActiveCall['hasActiveCall'] == true) {
  throw Exception('User is already on another call');
}
```

---

### 1.2 Firestore Queries for Active Calls

**Query 1**: Check as CALLER (Lines 28-32)
```dart
final asCallerQuery = await _firestoreService.calls
    .where('callerId', isEqualTo: userId)
    .where('status', whereIn: ['calling', 'ringing', 'accepted'])  // ← ACTIVE STATUSES
    .limit(1)
    .get();
```

**Query 2**: Check as RECEIVER (Lines 71-75)
```dart
final asReceiverQuery = await _firestoreService.calls
    .where('receiverId', isEqualTo: userId)
    .where('status', whereIn: ['calling', 'ringing', 'accepted'])  // ← ACTIVE STATUSES
    .limit(1)
    .get();
```

**Return Values**:
- If document found: `{hasActiveCall: true, callId: X, role: 'caller'/'receiver', data: {...}}`
- If no document found: `{hasActiveCall: false}`

---

### 1.3 Active Call Status Definition

**File**: `lib/models/call_state.dart` (Lines 32-34)

```dart
bool get isActive => this == calling || 
                     this == ringing || 
                     this == accepted;
```

**ACTIVE STATUSES** (will block new calls):
- ✅ `calling` - Call being initiated
- ✅ `ringing` - Call ringing on receiver
- ✅ `accepted` - Call answered and in progress

**TERMINAL STATUSES** (will NOT block):
- ❌ `declined` - Receiver declined
- ❌ `missed` - No answer (timeout)
- ❌ `cancelled` - Caller cancelled
- ❌ `ended` - Normal end
- ❌ `failed` - Error

---

### 1.4 Status Conversion to Firestore

**File**: `lib/models/call_state.dart` (Line 94)

```dart
String toFirestore() => name;
```

**Firestore Values**:
- CallState.calling → `"calling"`
- CallState.ringing → `"ringing"`
- CallState.accepted → `"accepted"`
- CallState.ended → `"ended"`
- (etc., lowercase enum name)

---

## PART 2: CALL CREATION FLOW

### 2.1 Entry Points

**Voice Call**:
- File: `lib/services/call_service.dart`
- Method: `startVoiceCall()` (Lines 140-148)
- Calls: `_startCall(..., type: 'voice')`

**Video Call**:
- File: `lib/services/call_service.dart`
- Method: `startVideoCall()` (Lines 150-158)
- Calls: `_startCall(..., type: 'video')`

---

### 2.2 Call Creation Logic

**File**: `lib/services/call_service.dart`  
**Method**: `_startCall()` (Lines 160-230)

**Step-by-Step**:

**1. Check Caller Active Call** (Lines 185-188)
```dart
final callerActiveCall = await checkActiveCall(callerId);
if (callerActiveCall['hasActiveCall'] == true) {
  throw Exception('You are already on a call');  // ← BLOCKS HERE
}
```

**2. Check Receiver Active Call** (Lines 191-194)
```dart
final receiverActiveCall = await checkActiveCall(receiverId);
if (receiverActiveCall['hasActiveCall'] == true) {
  throw Exception('User is already on another call');  // ← BLOCKS HERE
}
```

**3. Create Firestore Document** (Lines 196-216)
```dart
final callData = {
  'callerId': callerId,
  'callerName': callerName,
  'receiverId': receiverId,
  'type': type, // 'voice' or 'video'
  'status': CallState.calling.toFirestore(),  // ← Initial: 'calling'
  'createdAt': FieldValue.serverTimestamp(),
  'answeredAt': null,
  'endedAt': null,
};

final docRef = await _firestoreService.calls.add(callData);
```

**4. Start Timeout Timer** (Line 221)
```dart
_startCallTimeout(callId);
```

**5. Update to Ringing** (Lines 224-227)
```dart
Future.delayed(const Duration(milliseconds: 500), () {
  _updateCallState(callId, CallState.ringing);
});
```

---

### 2.3 Status Transition Flow

```
creating → calling (document created)
       ↓
    ringing (after 500ms delay)
       ↓
   [User accepts/declines/timeout]
       ↓
   accepted / declined / missed
       ↓
     ended
```

---

## PART 3: INCOMING CALL DETECTION

### 3.1 Incoming Call Stream

**File**: `lib/providers/call_providers.dart` (Lines 9-12)

```dart
final incomingCallsStreamProvider = StreamProvider<QuerySnapshot<Map<String, dynamic>>>((ref) {
  final callService = ref.watch(callServiceProvider);
  return callService.listenToIncomingCalls();
});
```

**File**: `lib/services/call_service.dart`  
**Method**: `listenToIncomingCalls()` (Lines 436-446)

```dart
Stream<QuerySnapshot<Map<String, dynamic>>> listenToIncomingCalls() {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  if (currentUserId == null) {
    return const Stream.empty();
  }

  return _firestoreService.calls
      .where('receiverId', isEqualTo: currentUserId)
      .where('status', isEqualTo: CallState.ringing.toFirestore())  // ← ONLY 'ringing'
      .snapshots();
}
```

**🚨 CRITICAL FINDING #1: Strict Filter**
- **Only returns calls with status = 'ringing'**
- **Does NOT return 'calling' or 'accepted'**
- **If call document created with status='calling' and never transitions to 'ringing', receiver will NEVER see it**

---

### 3.2 Incoming Call Listener

**File**: `lib/widgets/incoming_call_listener.dart`

**Duplicate Protection** (Lines 21, 54-59):
```dart
String? _currentCallId;  // State variable

// Inside stream listener:
if (_currentCallId == callId) {
  return;  // ← Skip if already showing
}

_currentCallId = callId;
```

**Status Filtering** (Lines 41-51):
```dart
// Parse call state
final statusStr = data['status'] as String?;
final state = CallState.fromString(statusStr);

// NEVER show popup for missed calls
if (state == CallState.missed) {
  return;
}

// Only show for ringing calls
if (state != CallState.ringing) {
  return;  // ← STRICT: Only 'ringing' allowed
}
```

**Navigation** (Lines 64-78):
```dart
// Only show if not already on incoming call screen
if (ModalRoute.of(context)?.settings.name != IncomingCallScreen.routeName) {
  Navigator.of(context).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: IncomingCallScreen.routeName),
      builder: (_) => IncomingCallScreen(
        callId: callId,
        callerId: callerId,
        callerName: callerName,
        callType: callType,
      ),
    ),
  ).then((_) {
    _currentCallId = null;  // ← Reset on dismiss
  });
}
```

---

## PART 4: CRASH RECOVERY ANALYSIS

### 4.1 Normal Call End

**File**: `lib/services/call_service.dart`  
**Method**: `endCall(String callId)` (Lines 248-282)

```dart
Future<void> endCall(String callId) async {
  // Get current call state
  final doc = await _firestoreService.calls.doc(callId).get();
  final currentStateStr = doc.data()?['status'] as String?;
  final currentState = CallState.fromString(currentStateStr);
  
  // Determine new state
  final newState = (currentState == CallState.calling || currentState == CallState.ringing)
      ? CallState.cancelled  // ← Pre-answer
      : CallState.ended;     // ← Post-answer
  
  // Update Firestore
  await _firestoreService.calls.doc(callId).update({
    'status': newState.toFirestore(),
    'endedAt': FieldValue.serverTimestamp(),
  });
  
  // Save call log
  await Future.delayed(const Duration(milliseconds: 500));
  await saveCallLog(callId);
}
```

**✅ Works**: Document updated to terminal state ('ended' or 'cancelled')

---

### 4.2 Abnormal Termination (App Kill/Crash)

**Scenario**:
1. Call status = 'accepted'
2. App killed (force stop) or crashed
3. User reopens app
4. Tries to make new call

**What Happens**:
1. `dispose()` methods **NEVER RUN** (app killed before disposal)
2. Firestore document **REMAINS** with status = 'accepted'
3. New call attempt → `checkActiveCall()` finds document
4. Throws: `"You are already on a call"`

**🚨 CRITICAL FINDING #2: No Cleanup Mechanism**

**Files Checked**:
- `lib/screens/chat/call_screen.dart` (dispose on Lines 250-264)
- `lib/screens/chat/video_call_screen.dart` (dispose on Lines 198-206)
- `lib/services/call_controller.dart` (dispose on Lines 817-928)

**None of these run on abnormal termination!**

---

### 4.3 Timeout Mechanism

**File**: `lib/services/call_service.dart`  
**Method**: `_startCallTimeout()` (Lines 322-367)

```dart
static const Duration callTimeout = Duration(seconds: 30);

void _startCallTimeout(String callId) {
  _callTimeouts[callId] = Timer(callTimeout, () async {
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

**✅ Works For**: Unanswered calls (calling/ringing)  
**❌ Does NOT Work For**: Accepted calls (status='accepted')

**🚨 CRITICAL FINDING #3: No Timeout for Accepted Calls**
- Timeout only applies to unanswered calls
- **Accepted calls have NO timeout**
- If app dies during accepted call → **stuck forever**

---

### 4.4 App Lifecycle Monitoring

**Files Checked**:
- `lib/screens/chat/call_screen.dart` - ❌ No `WidgetsBindingObserver`
- `lib/screens/chat/video_call_screen.dart` - ❌ No `WidgetsBindingObserver`

**🚨 CRITICAL FINDING #4: No Lifecycle Awareness**
- Call screens don't observe app lifecycle
- No chance to update Firestore before app dies
- No `didChangeAppLifecycleState()` handler

---

## PART 5: FIRESTORE SECURITY RULES

**File**: `firebase/firestore.rules` (Lines 198-247)

### 5.1 Call Document Rules

**Create** (Lines 228-235):
```
allow create: if authed() 
  && isCallerInNew()
  && request.resource.data.receiverId != request.auth.uid
  && request.resource.data.type in ['voice', 'video']
  && request.resource.data.status in ['calling', 'ringing']  // ← Must be calling/ringing
  && request.resource.data.createdAt is timestamp;
```

**Read** (Line 238):
```
allow read: if isCallerOrReceiver();  // ← Caller or receiver can read
```

**Update** (Lines 241-244):
```
allow update: if isCallerOrReceiver()
  && callerIdImmutable()      // ← Cannot change caller ID
  && receiverIdImmutable()    // ← Cannot change receiver ID
  && request.resource.data.type == resource.data.type;  // ← Cannot change type
```

**Delete** (Line 247):
```
allow delete: if false;  // ← CANNOT DELETE CALLS (audit trail)
```

**✅ Security is correct**  
**⚠️ No cleanup mechanism** - documents cannot be deleted

---

## PART 6: ROOT CAUSE ANALYSIS

### 6.1 Problem 1: "Finish current call first" When No Call Active

**Cause**: Stale Firestore documents

**How It Happens**:
1. User in call (status='accepted')
2. App killed/crashed/phone restarted
3. `dispose()` never runs
4. Firestore document **never updated** to terminal state
5. Document remains with status='accepted'
6. Next call attempt finds stale document
7. `checkActiveCall()` returns `hasActiveCall: true`
8. `_startCall()` throws exception
9. User sees "Finish current call first"

**Evidence**:
- Line 29: `where('status', whereIn: ['calling', 'ringing', 'accepted'])`
- Line 186: `if (callerActiveCall['hasActiveCall'] == true) throw Exception(...)`
- No cleanup mechanism for stale 'accepted' documents

---

### 6.2 Problem 2: Receiver Never Receives Incoming Call UI

**Possible Causes**:

**Cause A: Race Condition in Status Transition**

The call flow is:
1. Document created with status='calling' (Line 208)
2. After 500ms delay, updated to status='ringing' (Lines 224-227)

The incoming call stream only listens for status='ringing' (Line 444).

**🚨 POTENTIAL BUG**: If receiver's app loads and subscribes to stream **BEFORE** the 500ms delay completes, the document has status='calling', which **does not match the query**.

**Timeline**:
```
T+0ms:    Caller creates document (status='calling')
T+100ms:  Receiver opens app, subscribes to stream
T+200ms:  Stream query executes: where('status', '==', 'ringing')
T+300ms:  No matching documents (status still 'calling')
T+500ms:  Caller updates to 'ringing'
T+???:    Stream MAY OR MAY NOT fire update (depends on Firestore real-time behavior)
```

**Firestore Behavior**:
- Stream queries DO receive updates for documents that later match the query
- **HOWEVER**: Initial snapshot may be empty
- UI depends on `snapshot.docs.isEmpty` check (Line 30 in listener)

**Conclusion**: This is **unlikely** to cause total failure, but could cause **delay**.

---

**Cause B: Status Never Transitions to 'Ringing'**

**File**: `lib/services/call_service.dart` (Lines 224-227)

```dart
Future.delayed(const Duration(milliseconds: 500), () {
  _updateCallState(callId, CallState.ringing);
});
```

**🚨 POTENTIAL BUG**: This is a fire-and-forget delayed call.

**What Could Go Wrong**:
1. Caller's app killed **before** 500ms elapses
2. `_updateCallState()` never executes
3. Document stuck with status='calling'
4. Receiver's stream query doesn't match (requires 'ringing')
5. **Receiver never sees call**

**Evidence**: No error handling, no await, no verification

---

**Cause C: Firestore Permission Denied**

**Check**: Lines 238 in firestore.rules
```
allow read: if isCallerOrReceiver();
```

**Requires**:
- `resource.data.callerId == request.auth.uid` OR
- `resource.data.receiverId == request.auth.uid`

**✅ This is correct** - receiver can read

**Conclusion**: Permissions are fine

---

**Cause D: Duplicate Protection Blocking**

**File**: `lib/widgets/incoming_call_listener.dart` (Lines 54-59)

```dart
if (_currentCallId == callId) {
  return;  // Skip if already showing
}

_currentCallId = callId;
```

**🚨 POTENTIAL BUG**: `_currentCallId` persists in state

**Scenario**:
1. Call 1 arrives, `_currentCallId = 'abc'`
2. User declines, screen pops
3. `_currentCallId` reset to null (Line 78)
4. **BUT** what if screen doesn't pop properly?
5. Call 2 arrives with same ID (reused document?)
6. Blocked by `if (_currentCallId == callId)`

**Conclusion**: Unlikely, but possible if Firestore document IDs collide or screen navigation fails

---

**Cause E: Modal Route Check Blocking**

**File**: `lib/widgets/incoming_call_listener.dart` (Line 64)

```dart
if (ModalRoute.of(context)?.settings.name != IncomingCallScreen.routeName) {
  // Show incoming call screen
}
```

**🚨 POTENTIAL BUG**: If already on incoming call screen, new call won't show

**Scenario**:
1. Call 1 arrives, screen opens
2. User on IncomingCallScreen
3. Call 2 arrives (different call)
4. Blocked by modal route check
5. **User never sees Call 2**

**Conclusion**: This is **intentional behavior** to prevent multiple popups, but could cause missed calls if multiple people call simultaneously

---

## PART 7: SUMMARY OF FINDINGS

### 7.1 Confirmed Bugs

**BUG #1: Stale 'Accepted' Documents Block New Calls**
- **Severity**: HIGH
- **Frequency**: Happens every time app is killed during call
- **Location**: No crash recovery mechanism
- **Impact**: User cannot make new calls until manual intervention

**BUG #2: No Timeout for Accepted Calls**
- **Severity**: HIGH
- **Frequency**: Every abnormal termination during active call
- **Location**: `_startCallTimeout()` only handles unanswered calls
- **Impact**: Stale documents accumulate forever

**BUG #3: Strict 'Ringing' Filter for Incoming Calls**
- **Severity**: MEDIUM
- **Frequency**: Rare (requires app kill within 500ms window)
- **Location**: `listenToIncomingCalls()` - Line 444
- **Impact**: Receiver might not see call if status stuck at 'calling'

---

### 7.2 Potential Race Conditions

**RACE #1: Status Transition Delay**
- **File**: `call_service.dart` - Lines 224-227
- **Issue**: 500ms delay before 'calling' → 'ringing'
- **Risk**: If caller app killed in this window, status never updates
- **Impact**: Receiver never sees call (stream requires 'ringing')

**RACE #2: Fire-and-Forget Status Update**
- **File**: `call_service.dart` - Line 226
- **Issue**: `Future.delayed()` with no await or error handling
- **Risk**: Update may never execute if app dies
- **Impact**: Status stuck at 'calling'

---

### 7.3 Architecture Gaps

**GAP #1: No App Launch Cleanup**
- **Missing**: Check for stale calls on app startup
- **Impact**: Stale documents persist across app restarts

**GAP #2: No Lifecycle Observer**
- **Missing**: `WidgetsBindingObserver` in call screens
- **Impact**: No chance to cleanup before app dies

**GAP #3: No Server-Side Cleanup**
- **Missing**: Cloud Function or Firestore TTL
- **Impact**: Client-side state management only

**GAP #4: No Manual Recovery UI**
- **Missing**: "Clear Call" button for users
- **Impact**: Users stuck, must contact support

---

## PART 8: EXACT LINES OF CODE

### 8.1 Where Blocking Happens

**File**: `lib/services/call_service.dart`

**Line 186**: Caller check
```dart
if (callerActiveCall['hasActiveCall'] == true) {
  throw Exception('You are already on a call');  // ← USER BLOCKED HERE
}
```

**Line 192**: Receiver check
```dart
if (receiverActiveCall['hasActiveCall'] == true) {
  throw Exception('User is already on another call');  // ← USER BLOCKED HERE
}
```

---

### 8.2 Where Stale Documents Are Detected

**File**: `lib/services/call_service.dart`

**Lines 28-32**: Caller query
```dart
final asCallerQuery = await _firestoreService.calls
    .where('callerId', isEqualTo: userId)
    .where('status', whereIn: ['calling', 'ringing', 'accepted'])  // ← STALE 'accepted' FOUND HERE
    .limit(1)
    .get();
```

**Lines 71-75**: Receiver query
```dart
final asReceiverQuery = await _firestoreService.calls
    .where('receiverId', isEqualTo: userId)
    .where('status', whereIn: ['calling', 'ringing', 'accepted'])  // ← STALE 'accepted' FOUND HERE
    .limit(1)
    .get();
```

---

### 8.3 Where Incoming Calls Are Filtered

**File**: `lib/services/call_service.dart`

**Lines 443-444**: Stream query
```dart
return _firestoreService.calls
    .where('receiverId', isEqualTo: currentUserId)
    .where('status', isEqualTo: CallState.ringing.toFirestore())  // ← ONLY 'ringing', NOT 'calling'
    .snapshots();
```

**File**: `lib/widgets/incoming_call_listener.dart`

**Lines 47-51**: Additional filtering
```dart
// Only show for ringing calls
if (state != CallState.ringing) {
  return;  // ← BLOCKS non-ringing calls
}
```

---

### 8.4 Where Status Transition Happens

**File**: `lib/services/call_service.dart`

**Lines 224-227**: Delayed transition
```dart
Future.delayed(const Duration(milliseconds: 500), () {
  _updateCallState(callId, CallState.ringing);  // ← MAY NOT EXECUTE if app dies
});
```

---

## PART 9: VERIFICATION CHECKLIST

### 9.1 Can Old 'Ended' Documents Block Calls?

**Answer**: ❌ NO

**Reason**: Lines 29 and 72 filter for `whereIn: ['calling', 'ringing', 'accepted']`

Terminal states ('ended', 'declined', 'cancelled', 'missed', 'failed') are **NOT** in this list, so they will **NOT** match the query.

**Conclusion**: Only active-status documents can block calls.

---

### 9.2 What Happens After App Crash During Accepted Call?

**Step-by-Step**:
1. Call accepted (status='accepted')
2. App crashes
3. **No code executes** (dispose never runs)
4. Firestore document **unchanged**: status='accepted', endedAt=null
5. User reopens app
6. User tries new call
7. `checkActiveCall()` queries Firestore
8. Finds document: `{callerId: X, status: 'accepted', ...}`
9. Returns: `{hasActiveCall: true, ...}`
10. `_startCall()` throws: `Exception('You are already on a call')`
11. UI catches exception, shows: "Finish current call first"

**Conclusion**: ✅ Confirmed - stale 'accepted' documents block new calls

---

### 9.3 Why Doesn't Timeout Clean It Up?

**Answer**: Timeout only applies to **unanswered** calls

**File**: `lib/services/call_service.dart` (Lines 350-358)

```dart
// Only timeout if still calling/ringing
if (status == CallState.calling || status == CallState.ringing) {
  await _firestoreService.calls.doc(callId).update({
    'status': CallState.missed.toFirestore(),
    ...
  });
} else {
  print('[CallService] Call already in state ${status.name}, not timing out');
}
```

**Logic**: If status is 'accepted', timeout does **nothing**.

**Reason**: Active calls should NOT timeout (user is talking).

**Problem**: If app crashes, active call becomes stale, but timeout won't clean it up.

**Conclusion**: ✅ Confirmed - no cleanup for accepted calls

---

## PART 10: DELIVERABLES

### 10.1 Root Cause of Problem 1

**Problem**: "Finish current call first" when no call active

**Root Cause**: 
- Stale Firestore documents with status='accepted'
- Created when app dies during active call
- No cleanup mechanism on app restart
- No timeout for accepted calls

**Exact Lines**:
- Detection: `call_service.dart:29,72` (query includes 'accepted')
- Blocking: `call_service.dart:186,192` (throws exception)
- No Cleanup: No code exists to clean stale calls on app launch

---

### 10.2 Root Cause of Problem 2

**Problem**: Receiver never receives incoming call UI

**Most Likely Cause**: 
- Status transition race condition
- Document created with status='calling'
- Caller app dies before 500ms delay completes
- Status never updates to 'ringing'
- Receiver's stream requires status='ringing'
- Query doesn't match → no UI shown

**Exact Lines**:
- Race Condition: `call_service.dart:224-227` (delayed, no await)
- Strict Filter: `call_service.dart:444` (only 'ringing')
- Additional Filter: `incoming_call_listener.dart:47-51` (only 'ringing')

**Alternative Causes**:
- Firestore real-time lag
- Duplicate protection blocking (`_currentCallId`)
- Modal route check blocking simultaneous calls

---

### 10.3 Status Definitions

**Active Statuses** (block new calls):
- `calling` - Initial state
- `ringing` - Ringing on receiver
- `accepted` - Call in progress

**Terminal Statuses** (do NOT block):
- `declined` - Receiver declined
- `missed` - Timeout
- `cancelled` - Caller cancelled
- `ended` - Normal end
- `failed` - Error

**Source**: `lib/models/call_state.dart:32-34,27-31`

---

### 10.4 Recommendations

**Priority 1 - HIGH**: Fix stale 'accepted' documents
- Add cleanup on app launch
- Detect calls with status='accepted' and age > 5 minutes
- Auto-update to 'ended'

**Priority 2 - HIGH**: Remove race condition
- Make status transition synchronous
- Change Line 224: Remove `Future.delayed()`
- Update to 'ringing' immediately after document creation
- Or add proper error handling and await

**Priority 3 - MEDIUM**: Relax incoming call filter
- Change Line 444: Include 'calling' status
- Or handle 'calling' status in listener
- Or guarantee 'ringing' transition completes

**Priority 4 - LOW**: Add lifecycle observer
- Implement `WidgetsBindingObserver` in call screens
- On `AppLifecycleState.detached`, try to end call
- Limited usefulness (~1 second before death)

**Priority 5 - LOW**: Add manual recovery
- "Clear Call" button in settings
- Force-end any stale calls
- User-initiated fallback

---

## CONCLUSION

**NO CODE WAS MODIFIED**  
**This is a READ-ONLY audit report**

**Confirmed Ghost Call Sources**:
1. ✅ Stale 'accepted' documents from app crashes
2. ✅ No timeout for accepted calls
3. ✅ No cleanup on app launch
4. ⚠️ Race condition in status transition

**Next Steps**: Implement fixes in Phase 0.7

---

**END OF AUDIT REPORT**
