# GROUP AUDIO CALLING - SIGNALING FAILURE DIAGNOSTIC

**Date**: 2026-06-27  
**Issue**: Receiver devices never ring when group call is initiated

---

## CURRENT BEHAVIOR

✅ **Caller Side (Working)**:
- Caller can initiate group call
- Caller UI opens correctly
- Group call document created in Firestore

❌ **Receiver Side (FAILING)**:
- Receiver devices never ring
- Incoming call screen never appears
- Receiver cannot accept or decline

**Root Cause**: SIGNALING FAILURE (not WebRTC)

---

## SIGNALING ARCHITECTURE OVERVIEW

```
Caller (Device A)
   ↓
1. Creates groupCalls/{callId} document
   ↓
2. Creates groupCallInvitations/{invitationId} for each invited user
   ↓
3. Firestore real-time listener on Device B triggers
   ↓
4. IncomingGroupCallListener widget receives snapshot
   ↓
5. IncomingGroupCallDialog appears
   ↓
6. User accepts → WebRTC negotiation begins
```

**Current Issue**: Signaling breaks somewhere between steps 2-5

---

## DIAGNOSTIC CHECKLIST

### ✅ STEP 1: Verify Invitation Documents Created

**Location**: `lib/services/group_call_service.dart:62-98`

**What to Check**:
1. Open Firestore console after starting a call
2. Navigate to `groupCallInvitations` collection
3. Verify documents exist for each invited user

**Expected Document Structure**:
```json
{
  "callId": "abc123",
  "groupId": "xyz789",
  "inviterId": "userA_uid",
  "targetUserId": "userB_uid",
  "status": "pending",
  "createdAt": Timestamp,
  "expiresAt": Timestamp (createdAt + 1 minute)
}
```

**Logs to Check (Caller Console)**:
```
[GROUP_SIGNAL] Creating 2 invitation documents
[GROUP_SIGNAL] INVITATION_CREATED -> userB_uid
[GROUP_SIGNAL] INVITATION_CREATED -> userC_uid
```

**⚠️ If Invitations NOT Created**:
- Problem: `_createInvitations()` failing silently
- Check: Does `startGroupAudioCall()` actually call `_createInvitations()`?
- Check: Line 166-172 in `group_call_service.dart`
- Check: Are invitedUserIds empty?

---

### ✅ STEP 2: Verify Listener is Active on Receiver

**Location**: `lib/services/group_call_service.dart:185-199`

**Expected Logs (Receiver Console on App Start)**:
```
[GROUP_SIGNAL] 👂 Listening for invitations -> userB_uid
```

**What to Check**:
1. Does log appear when receiver app starts?
2. Does log show correct userId?
3. Does listener start before or after login?

**⚠️ If Log NOT Appearing**:
- Problem: `listenToIncomingGroupCallInvitations()` never called
- Check: Is `IncomingGroupCallListener` widget mounted?
- Check: `lib/app.dart` lines 113-122

**Current Implementation**:
```dart
home: const SignalTestWidget(
  child: IncomingGroupCallListener(  // ✅ Mounted globally
    child: IncomingCallListener(child: ModChatSplashScreen()),
  ),
),
routes: {
  "/home": (context) => const SignalTestWidget(
    child: IncomingGroupCallListener(  // ✅ Mounted on home route
      child: IncomingCallListener(child: AuthGate()),
    ),
  ),
}
```

**⚠️ If Widget IS Mounted but Log Missing**:
- Problem: StreamBuilder not building
- Check: Is user logged in? (`FirebaseAuth.instance.currentUser?.uid`)
- Check: Line 34 in `incoming_group_call_listener.dart`

---

### ✅ STEP 3: Verify Firestore Query is Correct

**Location**: `lib/services/group_call_service.dart:194-199`

**Current Query**:
```dart
return _firestoreService.firestore
    .collection('groupCallInvitations')
    .where('targetUserId', isEqualTo: currentUserId)
    .where('status', isEqualTo: 'pending')
    .snapshots();
```

**What to Verify**:
1. **Collection Name**: Must be `groupCallInvitations` (exact match)
2. **Field Name**: Must be `targetUserId` (exact match, case-sensitive)
3. **Status Value**: Must be `'pending'` (exact match, lowercase)

**⚠️ Common Mistakes**:
- ❌ Collection: `groupInvitations` (wrong name)
- ❌ Field: `userId` or `receiverId` (wrong field)
- ❌ Status: `'Pending'` or `'PENDING'` (wrong case)

**How to Test**:
1. Start group call
2. Open Firestore Console
3. Go to `groupCallInvitations` collection
4. Find document where `targetUserId == receiverUserId`
5. Verify `status == 'pending'` (lowercase)

---

### ✅ STEP 4: Verify Firestore Rules Allow Read

**Location**: `firebase/firestore.rules`

**Required Rule**:
```javascript
match /groupCallInvitations/{invitationId} {
  // Users can read their own invitations
  allow read: if request.auth != null && 
              resource.data.targetUserId == request.auth.uid;
              
  // Users can update their own invitations (accept/decline)
  allow update: if request.auth != null && 
                resource.data.targetUserId == request.auth.uid &&
                request.resource.data.status in ['accepted', 'declined'];
}
```

**⚠️ If Rules Missing or Wrong**:
- Symptom: No error in console, but stream never fires
- Symptom: Firestore permission denied error
- Fix: Add rules to `firestore.rules`
- Deploy: `firebase deploy --only firestore:rules`

**How to Test**:
```javascript
// Test in Firestore Rules Playground
match /groupCallInvitations/test123
Auth: Authenticated as userB_uid
Read: 
  resource.data.targetUserId = 'userB_uid'
  
Expected: ALLOW
```

---

### ✅ STEP 5: Verify Listener Receives Snapshots

**Location**: `lib/widgets/incoming_group_call_listener.dart:45-58`

**Expected Logs (Receiver Console When Call Comes In)**:
```
[GROUP_SIGNAL] INVITATION_RECEIVED -> userB_uid
[GROUP_SIGNAL] Invitation ID: abc123
[GROUP_SIGNAL] Call ID: xyz789
[GROUP_SIGNAL] From: userA_uid
[GROUP_SIGNAL] INCOMING_SCREEN_SHOWN
```

**What to Check**:
1. Do logs appear when call is started?
2. Does `snapshot.hasData` return true?
3. Does `snapshot.data!.docs` contain documents?

**⚠️ If No Logs**:
- Problem: StreamBuilder not receiving data
- Check: Add debug log in builder:
```dart
builder: (context, snapshot) {
  print('[DEBUG] Snapshot state: ${snapshot.connectionState}');
  print('[DEBUG] Has data: ${snapshot.hasData}');
  print('[DEBUG] Doc count: ${snapshot.data?.docs.length ?? 0}');
  
  if (snapshot.hasData && snapshot.data != null) {
    // ...
  }
  return widget.child;
}
```

---

### ✅ STEP 6: Verify Dialog Can Show

**Location**: `lib/widgets/incoming_group_call_listener.dart:84-96`

**Required Conditions**:
1. ✅ `context` must be valid
2. ✅ Not already shown (`_shownInvitationIds`)
3. ✅ Not already active (`_activeInvitationId`)
4. ✅ Not expired (`expiresAt > DateTime.now()`)
5. ✅ `IncomingGroupCallDialog` widget exists

**⚠️ If Dialog Not Appearing**:
- Check: Does `IncomingGroupCallDialog` file exist?
  - `lib/screens/calls/incoming_group_call_dialog.dart`
- Check: Is dialog correctly imported?
  - Line 6: `import '../screens/calls/incoming_group_call_dialog.dart';`
- Check: Is context valid for showDialog?
  - Must be below MaterialApp in widget tree

---

## ENHANCED LOGGING FOR DEBUGGING

### Add to `group_call_service.dart:_createInvitations()`

```dart
Future<void> _createInvitations({
  required String callId,
  required String groupId,
  required String inviterId,
  required List<String> invitedUserIds,
}) async {
  print('[GROUP_SIGNAL] ========================================');
  print('[GROUP_SIGNAL] CREATING INVITATIONS');
  print('[GROUP_SIGNAL] Call ID: $callId');
  print('[GROUP_SIGNAL] Group ID: $groupId');
  print('[GROUP_SIGNAL] Inviter ID: $inviterId');
  print('[GROUP_SIGNAL] Invited Users: $invitedUserIds');
  print('[GROUP_SIGNAL] Invitation Count: ${invitedUserIds.length}');
  print('[GROUP_SIGNAL] ========================================');
  
  // ... rest of implementation
  
  for (var targetUserId in invitedUserIds) {
    try {
      // ... create invitation
      
      print('[GROUP_SIGNAL] ✅ INVITATION_CREATED');
      print('[GROUP_SIGNAL]    Target: $targetUserId');
      print('[GROUP_SIGNAL]    Status: pending');
      print('[GROUP_SIGNAL]    Expires: ${expiresAt.toDate()}');
      
    } catch (e) {
      print('[GROUP_SIGNAL] ❌ INVITATION_FAILED');
      print('[GROUP_SIGNAL]    Target: $targetUserId');
      print('[GROUP_SIGNAL]    Error: $e');
    }
  }
  
  print('[GROUP_SIGNAL] ========================================');
  print('[GROUP_SIGNAL] INVITATION CREATION COMPLETE');
  print('[GROUP_SIGNAL] ========================================');
}
```

### Add to `group_call_service.dart:listenToIncomingGroupCallInvitations()`

```dart
Stream<QuerySnapshot<Map<String, dynamic>>> listenToIncomingGroupCallInvitations() {
  final currentUserId = _auth.currentUser?.uid;
  
  print('[GROUP_SIGNAL] ========================================');
  print('[GROUP_SIGNAL] STARTING INVITATION LISTENER');
  print('[GROUP_SIGNAL] User ID: $currentUserId');
  print('[GROUP_SIGNAL] ========================================');
  
  if (currentUserId == null) {
    print('[GROUP_SIGNAL] ❌ NO USER - CANNOT START LISTENER');
    return const Stream.empty();
  }

  print('[GROUP_SIGNAL] 👂 LISTENER ACTIVE');
  print('[GROUP_SIGNAL] Collection: groupCallInvitations');
  print('[GROUP_SIGNAL] Query: targetUserId == $currentUserId');
  print('[GROUP_SIGNAL] Query: status == pending');

  return _firestoreService.firestore
      .collection('groupCallInvitations')
      .where('targetUserId', isEqualTo: currentUserId)
      .where('status', isEqualTo: 'pending')
      .snapshots();
}
```

### Add to `incoming_group_call_listener.dart:build()`

```dart
return StreamBuilder(
  stream: _callService.listenToIncomingGroupCallInvitations(),
  builder: (context, snapshot) {
    print('[GROUP_SIGNAL] ========================================');
    print('[GROUP_SIGNAL] STREAM BUILDER UPDATE');
    print('[GROUP_SIGNAL] Connection State: ${snapshot.connectionState}');
    print('[GROUP_SIGNAL] Has Data: ${snapshot.hasData}');
    print('[GROUP_SIGNAL] Has Error: ${snapshot.hasError}');
    if (snapshot.hasError) {
      print('[GROUP_SIGNAL] Error: ${snapshot.error}');
    }
    print('[GROUP_SIGNAL] ========================================');
    
    if (snapshot.hasData && snapshot.data != null) {
      final docs = snapshot.data!.docs;
      
      print('[GROUP_SIGNAL] 📬 DOCUMENTS RECEIVED: ${docs.length}');
      
      for (var doc in docs) {
        print('[GROUP_SIGNAL] Document ID: ${doc.id}');
        print('[GROUP_SIGNAL] Document Data: ${doc.data()}');
        _handleInvitation(context, doc);
      }
    }
    
    return widget.child;
  },
);
```

### Add to `incoming_group_call_listener.dart:_handleInvitation()`

```dart
void _handleInvitation(BuildContext context, doc) {
  try {
    print('[GROUP_SIGNAL] ========================================');
    print('[GROUP_SIGNAL] PROCESSING INVITATION');
    
    final invitation = GroupCallInvitation.fromFirestore(doc);
    
    print('[GROUP_SIGNAL] Invitation ID: ${invitation.invitationId}');
    print('[GROUP_SIGNAL] Call ID: ${invitation.callId}');
    print('[GROUP_SIGNAL] Group ID: ${invitation.groupId}');
    print('[GROUP_SIGNAL] Inviter ID: ${invitation.inviterId}');
    print('[GROUP_SIGNAL] Target ID: ${invitation.targetUserId}');
    print('[GROUP_SIGNAL] Status: ${invitation.status}');
    print('[GROUP_SIGNAL] Created: ${invitation.createdAt.toDate()}');
    print('[GROUP_SIGNAL] Expires: ${invitation.expiresAt.toDate()}');
    
    // Duplicate check
    if (_shownInvitationIds.contains(invitation.invitationId)) {
      print('[GROUP_SIGNAL] ⚠️ DUPLICATE - Already shown');
      return;
    }
    
    if (_activeInvitationId == invitation.invitationId) {
      print('[GROUP_SIGNAL] ⚠️ DUPLICATE - Currently active');
      return;
    }
    
    // Expiration check
    final now = DateTime.now();
    final expiresAt = invitation.expiresAt.toDate();
    if (expiresAt.isBefore(now)) {
      print('[GROUP_SIGNAL] ⚠️ EXPIRED');
      print('[GROUP_SIGNAL]    Now: $now');
      print('[GROUP_SIGNAL]    Expires: $expiresAt');
      return;
    }
    
    // Mark as shown
    _shownInvitationIds.add(invitation.invitationId);
    _activeInvitationId = invitation.invitationId;
    
    print('[GROUP_SIGNAL] ✅ SHOWING INCOMING CALL DIALOG');
    print('[GROUP_SIGNAL] ========================================');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => IncomingGroupCallDialog(
        invitation: invitation,
        onDismiss: () {
          _activeInvitationId = null;
          print('[GROUP_SIGNAL] Dialog dismissed: ${invitation.invitationId}');
        },
      ),
    );
    
  } catch (e, stackTrace) {
    print('[GROUP_SIGNAL] ❌ ERROR HANDLING INVITATION');
    print('[GROUP_SIGNAL] Error: $e');
    print('[GROUP_SIGNAL] Stack: $stackTrace');
    print('[GROUP_SIGNAL] ========================================');
  }
}
```

---

## TESTING PROCEDURE

### Test 1: Verify Invitation Creation

1. **Device A**: Start group call
2. **Firestore Console**: Check `groupCallInvitations` collection
3. **Expected**: Documents created for all invited users

**Device A Logs**:
```
[GROUP_SIGNAL] ========================================
[GROUP_SIGNAL] CREATING INVITATIONS
[GROUP_SIGNAL] Call ID: abc123
[GROUP_SIGNAL] Invited Users: [userB, userC]
[GROUP_SIGNAL] Invitation Count: 2
[GROUP_SIGNAL] ========================================
[GROUP_SIGNAL] ✅ INVITATION_CREATED
[GROUP_SIGNAL]    Target: userB
[GROUP_SIGNAL] ✅ INVITATION_CREATED
[GROUP_SIGNAL]    Target: userC
[GROUP_SIGNAL] ========================================
[GROUP_SIGNAL] INVITATION CREATION COMPLETE
[GROUP_SIGNAL] ========================================
```

**⚠️ If Failed**: Problem in `_createInvitations()` method

---

### Test 2: Verify Listener Startup

1. **Device B**: Open app and login
2. **Device B Console**: Check for listener startup logs

**Device B Logs (On App Start)**:
```
[GROUP_SIGNAL] ========================================
[GROUP_SIGNAL] STARTING INVITATION LISTENER
[GROUP_SIGNAL] User ID: userB
[GROUP_SIGNAL] ========================================
[GROUP_SIGNAL] 👂 LISTENER ACTIVE
[GROUP_SIGNAL] Collection: groupCallInvitations
[GROUP_SIGNAL] Query: targetUserId == userB
[GROUP_SIGNAL] Query: status == pending
```

**⚠️ If Failed**: `IncomingGroupCallListener` widget not mounted

---

### Test 3: Verify Stream Receives Data

1. **Device A**: Start group call
2. **Device B Console**: Check for stream builder updates

**Device B Logs (When Call Starts)**:
```
[GROUP_SIGNAL] ========================================
[GROUP_SIGNAL] STREAM BUILDER UPDATE
[GROUP_SIGNAL] Connection State: active
[GROUP_SIGNAL] Has Data: true
[GROUP_SIGNAL] Has Error: false
[GROUP_SIGNAL] ========================================
[GROUP_SIGNAL] 📬 DOCUMENTS RECEIVED: 1
[GROUP_SIGNAL] Document ID: xyz789
[GROUP_SIGNAL] Document Data: {callId: abc123, ...}
```

**⚠️ If Failed**: 
- Check Firestore rules
- Check query matches document fields
- Check user authentication

---

### Test 4: Verify Dialog Appears

1. **Device A**: Start group call
2. **Device B**: Wait for dialog

**Device B Logs (When Invitation Processed)**:
```
[GROUP_SIGNAL] ========================================
[GROUP_SIGNAL] PROCESSING INVITATION
[GROUP_SIGNAL] Invitation ID: xyz789
[GROUP_SIGNAL] Call ID: abc123
[GROUP_SIGNAL] Status: pending
[GROUP_SIGNAL] ✅ SHOWING INCOMING CALL DIALOG
[GROUP_SIGNAL] ========================================
```

**Device B Screen**: Incoming call dialog should appear

**⚠️ If Failed**:
- Check if invitation expired
- Check if dialog widget exists
- Check if context is valid

---

## COMMON FAILURE SCENARIOS

### Scenario 1: No Invitations Created
**Symptoms**: 
- Firestore `groupCallInvitations` collection empty
- No `INVITATION_CREATED` logs on caller

**Root Causes**:
- `invitedUserIds` array empty
- `_createInvitations()` not called
- Firestore write permission denied

**Fix**:
- Check `_getGroupMembers()` returns correct members
- Verify line 166-172 calls `_createInvitations()`
- Check Firestore rules allow write

---

### Scenario 2: Listener Not Starting
**Symptoms**:
- No `LISTENER ACTIVE` log on receiver
- No stream builder updates

**Root Causes**:
- User not logged in (`currentUserId == null`)
- `IncomingGroupCallListener` widget not mounted
- Widget mounted after login but before auth state loads

**Fix**:
- Verify `FirebaseAuth.instance.currentUser != null`
- Check `lib/app.dart` wraps with `IncomingGroupCallListener`
- Ensure widget rebuilds after login

---

### Scenario 3: Stream Never Fires
**Symptoms**:
- Listener active but no stream updates
- Documents exist in Firestore

**Root Causes**:
- Firestore rules deny read
- Query doesn't match document fields
- Status value mismatch (`'Pending'` vs `'pending'`)

**Fix**:
- Deploy correct Firestore rules
- Verify field names exact match (case-sensitive)
- Verify status value lowercase `'pending'`

---

### Scenario 4: Dialog Doesn't Appear
**Symptoms**:
- Stream fires, invitation received
- No dialog on screen

**Root Causes**:
- Invitation expired (created > 1 minute ago)
- Already shown (duplicate protection)
- `IncomingGroupCallDialog` widget missing
- Context invalid for showDialog

**Fix**:
- Test immediately after call created
- Clear `_shownInvitationIds` on app restart
- Verify dialog file exists
- Ensure widget below MaterialApp

---

## FIRESTORE RULES (REQUIRED)

Add these rules to `firebase/firestore.rules`:

```javascript
// Group Call Invitations
match /groupCallInvitations/{invitationId} {
  // Users can read their own invitations
  allow read: if request.auth != null && 
              resource.data.targetUserId == request.auth.uid;
  
  // System can create invitations (server-side or caller)
  allow create: if request.auth != null;
  
  // Users can update their own invitations (accept/decline)
  allow update: if request.auth != null && 
                resource.data.targetUserId == request.auth.uid &&
                request.resource.data.status in ['accepted', 'declined'];
}
```

**Deploy Rules**:
```bash
firebase deploy --only firestore:rules
```

---

## SUCCESS CRITERIA

✅ **Complete Signaling Flow**:
1. Caller starts group call
2. `groupCalls/{callId}` document created
3. `groupCallInvitations/{invitationId}` documents created
4. Receiver listener detects invitations
5. Incoming group call dialog appears
6. Receiver accepts
7. WebRTC negotiation begins

**Expected Logs (End-to-End)**:

**Device A (Caller)**:
```
[GROUP_SIGNAL] Creating 2 invitation documents
[GROUP_SIGNAL] ✅ INVITATION_CREATED -> userB
[GROUP_SIGNAL] ✅ INVITATION_CREATED -> userC
```

**Device B (Receiver)**:
```
[GROUP_SIGNAL] 👂 LISTENER ACTIVE
[GROUP_SIGNAL] 📬 DOCUMENTS RECEIVED: 1
[GROUP_SIGNAL] PROCESSING INVITATION
[GROUP_SIGNAL] ✅ SHOWING INCOMING CALL DIALOG
```

**Device B (Screen)**:
- Incoming call dialog visible
- Shows group name
- Shows caller name
- Accept and Decline buttons

---

## NEXT STEPS

1. ✅ Add enhanced logging (copy code from above)
2. ✅ Deploy Firestore rules (if not already deployed)
3. ✅ Test invitation creation (verify in Firestore console)
4. ✅ Test listener startup (check receiver console)
5. ✅ Test stream updates (check receiver console when call starts)
6. ✅ Test dialog display (verify incoming call screen appears)
7. ✅ Share logs from both devices for analysis

---

**Status**: DIAGNOSTIC GUIDE READY  
**Action Required**: Add enhanced logging and test with 2 devices
