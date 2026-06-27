# TEST GROUP CALL SIGNALING - STEP BY STEP

**Purpose**: Diagnose why receivers don't see incoming group call notifications

---

## PREREQUISITE

Before testing, **add enhanced logging** to verify each step of the signaling flow.

### Quick Logging Additions

Add these 3 print statements:

#### 1. In `group_call_service.dart:_createInvitations()` (around line 75)
```dart
for (var targetUserId in invitedUserIds) {
  try {
    // ADD THIS:
    print('[GROUP_SIGNAL] 🔔 Creating invitation for $targetUserId');
    
    final invitationData = {
      // ... existing code
    };
    
    await _firestoreService.firestore
        .collection('groupCallInvitations')
        .add(invitationData);
    
    // ADD THIS:
    print('[GROUP_SIGNAL] ✅ Invitation created successfully');
```

#### 2. In `incoming_group_call_listener.dart:build()` (around line 45)
```dart
return StreamBuilder(
  stream: _callService.listenToIncomingGroupCallInvitations(),
  builder: (context, snapshot) {
    // ADD THIS:
    print('[GROUP_SIGNAL] 📡 Stream update - hasData: ${snapshot.hasData}, docCount: ${snapshot.data?.docs.length ?? 0}');
    
    if (snapshot.hasData && snapshot.data != null) {
      // ... existing code
```

#### 3. In `incoming_group_call_listener.dart:_handleInvitation()` (around line 63)
```dart
void _handleInvitation(BuildContext context, doc) {
  try {
    // ADD THIS:
    print('[GROUP_SIGNAL] 🎯 Processing invitation document');
    
    final invitation = GroupCallInvitation.fromFirestore(doc);
    
    // ADD THIS:
    print('[GROUP_SIGNAL] ✉️ Invitation: callId=${invitation.callId}, target=${invitation.targetUserId}');
```

---

## TEST 1: VERIFY INVITATIONS ARE CREATED

### Device A (Caller)

1. Open the app
2. Login as User A
3. Open a group chat with at least 2 members
4. Start a group call

### Expected Console Output (Device A)

```
[GROUP_SIGNAL] 🔔 Creating invitation for userB_uid
[GROUP_SIGNAL] ✅ Invitation created successfully
[GROUP_SIGNAL] 🔔 Creating invitation for userC_uid
[GROUP_SIGNAL] ✅ Invitation created successfully
```

### Verify in Firestore Console

1. Open Firebase Console → Firestore
2. Navigate to `groupCallInvitations` collection
3. Should see 1 document per invited user

**Example Document**:
```json
{
  "callId": "abc123xyz",
  "groupId": "group789",
  "inviterId": "userA_uid",
  "targetUserId": "userB_uid",
  "status": "pending",
  "createdAt": Timestamp,
  "expiresAt": Timestamp
}
```

### ❌ IF TEST 1 FAILS

**No console logs**:
- Check: Is `_createInvitations()` being called?
- Check: Line 166 in `group_call_service.dart`

**No documents in Firestore**:
- Check: Firestore write rules allow invitation creation
- Check: `invitedUserIds` array is not empty
- Check: Console for permission errors

---

## TEST 2: VERIFY LISTENER IS ACTIVE

### Device B (Receiver)

1. Open the app
2. Login as User B (one of the invited members)
3. Wait for app to fully load

### Expected Console Output (Device B - On App Start)

```
[GROUP_SIGNAL] 👂 Listening for invitations -> userB_uid
```

### Verify Widget is Mounted

Check `lib/app.dart` lines 113-122:

```dart
home: const SignalTestWidget(
  child: IncomingGroupCallListener(  // ✅ Must be here
    child: IncomingCallListener(child: ModChatSplashScreen()),
  ),
),
```

### ❌ IF TEST 2 FAILS

**No "Listening for invitations" log**:
- Check: Is user logged in? (`FirebaseAuth.instance.currentUser != null`)
- Check: Is `IncomingGroupCallListener` widget mounted in app.dart?
- Check: Did the app rebuild after login?

**Log shows "NO USER - CANNOT START LISTENER"**:
- User is not authenticated
- Wait for login to complete before checking

---

## TEST 3: VERIFY STREAM RECEIVES DATA

### Devices: A (Caller), B (Receiver)

1. Device B is already open and logged in
2. Device A starts a group call (including User B)
3. Watch Device B console

### Expected Console Output (Device B - When Call Starts)

```
[GROUP_SIGNAL] 📡 Stream update - hasData: true, docCount: 1
[GROUP_SIGNAL] 🎯 Processing invitation document
[GROUP_SIGNAL] ✉️ Invitation: callId=abc123, target=userB_uid
[GROUP_SIGNAL] INVITATION_RECEIVED -> userB_uid
[GROUP_SIGNAL] Invitation ID: inv123
[GROUP_SIGNAL] Call ID: abc123
[GROUP_SIGNAL] From: userA_uid
```

### Expected on Device B Screen

**Incoming call dialog should appear**:
- Shows group name
- Shows caller name
- "Accept" and "Decline" buttons

### ❌ IF TEST 3 FAILS

**Stream never fires (no "Stream update" log)**:

1. **Check Firestore Query**:
   ```dart
   // In group_call_service.dart:listenToIncomingGroupCallInvitations()
   .where('targetUserId', isEqualTo: currentUserId)  // ✅ Correct
   .where('status', isEqualTo: 'pending')  // ✅ Lowercase 'pending'
   ```

2. **Check Firestore Rules**:
   - Rules must allow read for `targetUserId == auth.uid`
   - See `firebase/firestore.rules` line 360-362
   - If rules were just deployed, wait 60 seconds

3. **Check Document Fields**:
   - Open Firestore Console
   - Find invitation document
   - Verify `targetUserId` matches receiver's UID exactly
   - Verify `status` is lowercase `'pending'`

**Stream fires but docCount is 0**:
- No matching documents in Firestore
- Re-run TEST 1 to create invitations
- Check if invitation expired (1 minute timeout)

**Stream fires, docCount > 0, but no processing log**:
- Stream received data but loop didn't execute
- Check: Is `docs` list empty? Add debug: `print(snapshot.data!.docs);`

**Processing starts but invitation parsing fails**:
- Error in `GroupCallInvitation.fromFirestore()`
- Check console for exception stack trace
- Verify document has all required fields

---

## TEST 4: VERIFY DIALOG CAN SHOW

### Scenario: Stream fires, invitation parsed, but no dialog

### Check 1: Duplicate Protection

```dart
// In incoming_group_call_listener.dart
if (_shownInvitationIds.contains(invitation.invitationId)) {
  print('[GROUP_SIGNAL] ⚠️ Already shown - ignoring');
  return;  // ← Dialog blocked
}
```

**Solution**: Restart Device B app to clear `_shownInvitationIds`

### Check 2: Expiration

```dart
if (invitation.expiresAt.toDate().isBefore(DateTime.now())) {
  print('[GROUP_SIGNAL] ⚠️ Invitation expired - ignoring');
  return;  // ← Dialog blocked
}
```

**Solution**: Start call immediately (< 1 minute old)

### Check 3: Context Validity

```dart
showDialog(
  context: context,  // ← Must be valid MaterialApp context
  barrierDismissible: false,
  builder: (dialogContext) => IncomingGroupCallDialog(...)
);
```

**Check**: Is `IncomingGroupCallListener` below `MaterialApp` in widget tree?

**Current structure in app.dart** (✅ Correct):
```dart
MaterialApp(
  home: SignalTestWidget(
    child: IncomingGroupCallListener(  // ✅ Below MaterialApp
      child: IncomingCallListener(...)
    )
  )
)
```

### Check 4: Dialog Widget Exists

Verify file exists:
```
lib/screens/calls/incoming_group_call_dialog.dart
```

If missing, the import will fail and widget won't show.

---

## TEST 5: END-TO-END FLOW

### Complete Test with 2 Devices

**Device A (User A - Caller)**:
1. Open app, login
2. Open group chat with User B
3. Tap "Start Call" button
4. Wait for call screen to open

**Device B (User B - Receiver)**:
1. Open app, login
2. Stay on any screen (home, chat, etc.)
3. Wait for incoming call dialog

### Expected Console Output (Full Flow)

**Device A**:
```
[GROUP_SIGNAL] Creating 2 invitation documents
[GROUP_SIGNAL] 🔔 Creating invitation for userB_uid
[GROUP_SIGNAL] ✅ Invitation created successfully
[GROUP_SIGNAL] ROOM_CREATED: abc123
```

**Device B**:
```
[GROUP_SIGNAL] 👂 Listening for invitations -> userB_uid
[GROUP_SIGNAL] 📡 Stream update - hasData: true, docCount: 1
[GROUP_SIGNAL] 🎯 Processing invitation document
[GROUP_SIGNAL] ✉️ Invitation: callId=abc123, target=userB_uid
[GROUP_SIGNAL] INVITATION_RECEIVED -> userB_uid
[GROUP_SIGNAL] ✅ SHOWING INCOMING CALL DIALOG
```

**Device B Screen**:
- Incoming call dialog appears
- Shows: "Group Name" calling
- Shows: "User A" started the call
- Buttons: Accept / Decline

### Success Criteria

✅ **All pass**:
1. Invitations created in Firestore
2. Receiver listener active
3. Stream receives documents
4. Invitation processed
5. Dialog appears on screen
6. User can accept/decline

---

## COMMON ISSUES & FIXES

### Issue 1: No Invitations Created

**Symptoms**:
- No logs on Device A
- Firestore `groupCallInvitations` collection empty

**Causes**:
- `invitedUserIds` array is empty
- Firestore permission denied
- `_createInvitations()` not called

**Fixes**:
```dart
// In group_call_service.dart:startGroupAudioCall()
print('[DEBUG] All members: $allMembers');  // Should have 2+ members
print('[DEBUG] Invited: $invited');  // Should have 1+ (excluding initiator)
```

---

### Issue 2: Listener Never Starts

**Symptoms**:
- No "Listening for invitations" log on Device B

**Causes**:
- User not logged in
- Widget not mounted
- App didn't rebuild after login

**Fixes**:
1. Check Firebase auth state:
```dart
print('[DEBUG] Current user: ${FirebaseAuth.instance.currentUser?.uid}');
```

2. Verify widget mounting in `lib/app.dart`

3. Hot restart app after login

---

### Issue 3: Stream Never Fires

**Symptoms**:
- Listener active but no "Stream update" logs
- Invitations exist in Firestore

**Causes**:
- Query doesn't match documents
- Firestore rules deny read
- Status value mismatch

**Fixes**:
1. Test query manually in Firestore Console:
   - Collection: `groupCallInvitations`
   - Filter: `targetUserId == userB_uid`
   - Filter: `status == pending` (lowercase!)
   
2. Check rules allow read (line 360-362 in firestore.rules)

3. Verify document fields exactly match query

---

### Issue 4: Dialog Doesn't Show

**Symptoms**:
- Stream fires
- Invitation received
- No dialog on screen

**Causes**:
- Already shown (duplicate protection)
- Invitation expired (> 1 minute old)
- Context invalid
- Dialog widget missing

**Fixes**:
1. Restart app to clear duplicate tracking
2. Start call immediately (< 60 seconds)
3. Verify widget structure in app.dart
4. Verify dialog file exists

---

## DEBUGGING COMMANDS

### Check Firestore from CLI

```bash
# List all invitations
firebase firestore:get groupCallInvitations

# List invitations for specific user
firebase firestore:query groupCallInvitations --where targetUserId==userB_uid
```

### Check Firestore Rules

```bash
# Deploy rules
firebase deploy --only firestore:rules

# Test rules in Firebase Console
# Go to: Firestore → Rules → Rules Playground
# Test: read on groupCallInvitations/{id} where targetUserId == auth.uid
```

### Check Authentication

```dart
// Add to app.dart or any screen
print('[DEBUG] Current user: ${FirebaseAuth.instance.currentUser?.uid}');
print('[DEBUG] Email verified: ${FirebaseAuth.instance.currentUser?.emailVerified}');
```

---

## SUCCESS CHECKLIST

Use this to verify each component:

- [ ] ✅ Invitations created in Firestore
- [ ] ✅ Receiver listener starts on app launch
- [ ] ✅ Stream receives document updates
- [ ] ✅ Invitation successfully parsed
- [ ] ✅ Dialog appears on screen
- [ ] ✅ Accept button works
- [ ] ✅ Decline button works
- [ ] ✅ Call screen opens after accept
- [ ] ✅ WebRTC negotiation begins

---

## NEXT STEPS

Once signaling works:

1. ✅ Test with 3+ participants
2. ✅ Test simultaneous calls
3. ✅ Test accept/decline flow
4. ✅ Test invitation expiration (wait 61 seconds)
5. ✅ Test WebRTC audio connection
6. ✅ Test reconnection logic
7. ✅ Test rejoin after leaving

**But first**: Fix signaling so incoming calls appear!

---

**Status**: READY FOR TESTING  
**Time Required**: ~10 minutes for full test  
**Devices Needed**: 2 (caller + receiver)
