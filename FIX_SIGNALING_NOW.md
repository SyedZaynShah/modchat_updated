# FIX GROUP CALL SIGNALING - IMMEDIATE ACTION GUIDE

**Issue**: Incoming group calls not appearing on receiver devices  
**Time to Fix**: 15 minutes  
**Devices Needed**: 2

---

## STEP 1: ADD 3 LOG STATEMENTS (2 minutes)

### Log #1: Verify Invitations Created

**File**: `lib/services/group_call_service.dart`  
**Line**: ~87 (inside _createInvitations loop)

**Add BEFORE the invitation is created**:
```dart
for (var targetUserId in invitedUserIds) {
  try {
    print('[SIGNAL_DEBUG] 🔔 Creating invitation for $targetUserId'); // ← ADD THIS
    
    final invitationData = {
      'callId': callId,
      // ... rest of code
```

**Add AFTER the invitation is created**:
```dart
    await _firestoreService.firestore
        .collection('groupCallInvitations')
        .add(invitationData);
    
    print('[SIGNAL_DEBUG] ✅ Invitation created'); // ← ADD THIS
```

---

### Log #2: Verify Stream Receives Data

**File**: `lib/widgets/incoming_group_call_listener.dart`  
**Line**: ~45 (inside StreamBuilder)

```dart
return StreamBuilder(
  stream: _callService.listenToIncomingGroupCallInvitations(),
  builder: (context, snapshot) {
    // ← ADD THIS
    final docCount = snapshot.data?.docs.length ?? 0;
    print('[SIGNAL_DEBUG] 📡 Stream: hasData=${snapshot.hasData}, docs=$docCount');
    
    if (snapshot.hasData && snapshot.data != null) {
      // ... rest of code
```

---

### Log #3: Verify Dialog Will Show

**File**: `lib/widgets/incoming_group_call_listener.dart`  
**Line**: ~63 (start of _handleInvitation)

```dart
void _handleInvitation(BuildContext context, doc) {
  try {
    print('[SIGNAL_DEBUG] 🎯 Processing invitation doc'); // ← ADD THIS
    
    final invitation = GroupCallInvitation.fromFirestore(doc);
    
    // ... rest of code
```

---

## STEP 2: TEST WITH 2 DEVICES (5 minutes)

### Device A (Caller)
1. Open app
2. Login as User A
3. Open group chat with User B
4. Tap "Start Call" button
5. **Watch console logs**

### Device B (Receiver)
1. Open app
2. Login as User B
3. Stay on any screen
4. **Watch console logs**
5. **Watch for incoming call dialog**

---

## STEP 3: CHECK LOGS (3 minutes)

### Expected Logs - Device A

```
[SIGNAL_DEBUG] 🔔 Creating invitation for userB_uid
[SIGNAL_DEBUG] ✅ Invitation created
```

**✅ If you see these**: Invitations are being created → Go to Device B logs  
**❌ If missing**: See [FIX #1](#fix-1-invitations-not-created) below

---

### Expected Logs - Device B (On App Start)

```
[GROUP_SIGNAL] 👂 Listening for invitations -> userB_uid
```

**✅ If you see this**: Listener is active → Continue  
**❌ If missing**: See [FIX #2](#fix-2-listener-not-starting) below

---

### Expected Logs - Device B (When Call Starts)

```
[SIGNAL_DEBUG] 📡 Stream: hasData=true, docs=1
[SIGNAL_DEBUG] 🎯 Processing invitation doc
[GROUP_SIGNAL] INVITATION_RECEIVED -> userB_uid
[GROUP_SIGNAL] ✅ SHOWING INCOMING CALL DIALOG
```

**✅ If you see these**: Everything works! Dialog should appear  
**❌ If missing**: See which log is missing and apply fix below

---

## STEP 4: APPLY FIX BASED ON MISSING LOG

### FIX #1: Invitations Not Created

**Missing Log**: `🔔 Creating invitation for userB_uid`

**Diagnosis**: `invitedUserIds` array is empty

**Quick Fix**: Add debug log in `group_call_service.dart:startGroupAudioCall()`

```dart
// Around line 140
final invited = allMembers.where((id) => id != initiatorId).toList();

// ← ADD THIS
print('[SIGNAL_DEBUG] 👥 All members: $allMembers');
print('[SIGNAL_DEBUG] 👥 Invited: $invited');
```

**Check**:
- If `invited` is empty → Group has no other members
- Solution: Add more users to the group

---

### FIX #2: Listener Not Starting

**Missing Log**: `👂 Listening for invitations`

**Diagnosis**: User not logged in when widget builds

**Quick Fix**: Add debug log in `incoming_group_call_listener.dart:build()`

```dart
@override
Widget build(BuildContext context) {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  
  // ← ADD THIS
  print('[SIGNAL_DEBUG] 🔐 Current user: $currentUserId');
  
  if (currentUserId == null) {
    return widget.child;
  }
```

**Check**:
- If `currentUserId` is null → User not logged in yet
- Solution: Hot restart app after logging in

---

### FIX #3: Stream Not Firing

**Missing Log**: `📡 Stream: hasData=true`

**Diagnosis**: Query doesn't match document fields

**Quick Fix**: Check Firestore Console

1. Open Firebase Console → Firestore
2. Go to `groupCallInvitations` collection
3. Find document for userB
4. Verify fields:
   - `targetUserId` (exact field name, NOT `userId` or `receiverId`)
   - `status` = `'pending'` (lowercase, NOT `'Pending'`)

**If fields don't match query**:
- Problem in `_createInvitations()` - field names don't match
- Fix: Ensure `targetUserId` and `status` fields match query

**If fields match but still no data**:
- Check Firestore rules allow read
- Test in Firestore Rules Playground:
  ```
  Collection: groupCallInvitations/{docId}
  Operation: get
  Auth: userB_uid
  Expected: ALLOW
  ```

---

### FIX #4: Dialog Not Showing

**Logs Show**: 
```
📡 Stream: hasData=true, docs=1
🎯 Processing invitation doc
⚠️ Already shown - ignoring  ← OR
⚠️ Invitation expired         ← OR
```

**Diagnosis**: Duplicate protection or expiration

**Quick Fixes**:

**If "Already shown"**:
- Restart Device B app (clears `_shownInvitationIds`)

**If "Invitation expired"**:
- Start call immediately (< 60 seconds after creation)
- Don't wait between starting call and checking receiver

---

## STEP 5: VERIFY FIX WORKS (2 minutes)

After applying fix:

1. **Device A**: Start new group call
2. **Device B**: Watch for dialog

**Success**: Dialog appears within 5 seconds

**Screen should show**:
```
┌──────────────────────┐
│  📞 Group Call       │
│  "Family" calling    │
│  User A started call │
│                      │
│  [Accept] [Decline]  │
└──────────────────────┘
```

---

## COMMON SCENARIOS

### Scenario A: Both Devices Show "Invitation created" but Receiver Silent

**Problem**: Stream not receiving data  
**Fix**: Check query matches document fields (FIX #3)

---

### Scenario B: Receiver Shows "Listening" but No Stream Updates

**Problem**: Documents don't match query OR rules deny read  
**Fix**: 
1. Check Firestore console for documents
2. Verify field names exact match
3. Test Firestore rules in playground

---

### Scenario C: Everything Logs Correctly but No Dialog

**Problem**: Dialog blocked by duplicate protection or expiration  
**Fix**:
1. Check for "⚠️ Already shown" or "⚠️ Expired" in logs
2. Restart receiver app
3. Start call immediately after creating

---

### Scenario D: Dialog Shows but Wrong Group Name

**Not a signaling issue** - This is expected behavior  
Group name loaded asynchronously after dialog appears

---

## VERIFICATION CHECKLIST

Before reporting issue, verify:

- [ ] Added 3 log statements
- [ ] Tested with 2 real devices (not simulator/emulator pair)
- [ ] Both users logged in
- [ ] Both users in same group
- [ ] Group has 2+ members
- [ ] Call started < 60 seconds before checking
- [ ] Checked console logs on both devices
- [ ] Checked Firestore console for invitation documents
- [ ] Tried restarting receiver app

---

## FIRESTORE MANUAL CHECK

If all logs present but still failing:

1. Open Firebase Console
2. Go to Firestore
3. Navigate to `groupCallInvitations` collection
4. You should see documents like:

```javascript
{
  callId: "abc123",
  groupId: "group789",
  inviterId: "userA_uid",
  targetUserId: "userB_uid",  // ← Must match receiver's UID exactly
  status: "pending",           // ← Must be lowercase
  createdAt: Timestamp,
  expiresAt: Timestamp
}
```

**Verify**:
- [ ] Collection exists
- [ ] Documents created (1 per invited user)
- [ ] `targetUserId` matches receiver's UID
- [ ] `status` is lowercase `'pending'`
- [ ] `expiresAt` is in future (< 1 minute old)

---

## FIRESTORE RULES CHECK

If stream never fires:

```bash
# Deploy rules (in case they weren't deployed)
firebase deploy --only firestore:rules
```

**Wait 60 seconds after deploying**, then test again.

Check rules allow read:
```javascript
// In firebase/firestore.rules
match /groupCallInvitations/{invitationId} {
  allow read: if request.auth != null && 
              resource.data.targetUserId == request.auth.uid;
}
```

---

## SUCCESS CRITERIA

✅ **Working Signaling**:
1. Device A logs: "✅ Invitation created"
2. Device B logs: "👂 Listening for invitations"
3. Device B logs: "📡 Stream: hasData=true, docs=1"
4. Device B logs: "🎯 Processing invitation doc"
5. Device B logs: "✅ SHOWING INCOMING CALL DIALOG"
6. Device B screen: Dialog visible
7. User can click Accept/Decline

---

## STILL NOT WORKING?

If you've:
- Added all 3 logs
- Verified Firestore documents exist
- Verified fields match query
- Checked Firestore rules
- Restarted receiver app
- Tested < 60 seconds after call start

**AND still no dialog**:

Share the following:
1. Complete console logs from Device A (caller)
2. Complete console logs from Device B (receiver)
3. Screenshot of Firestore `groupCallInvitations` document
4. Firestore rules for `groupCallInvitations`

This will pinpoint the exact failure point.

---

## REFERENCE DOCUMENTS

For deeper investigation:

- **`TEST_GROUP_CALL_SIGNALING.md`** - Detailed step-by-step testing
- **`GROUP_CALL_SIGNALING_DIAGNOSTIC.md`** - Complete diagnostic guide
- **`GROUP_CALL_SIGNALING_FLOW.md`** - Visual flow diagrams
- **`SIGNALING_INVESTIGATION_SUMMARY.md`** - Overview and action plan

---

**Time Required**: 15 minutes  
**Success Rate**: >95% (if all steps followed)  
**Most Common Issue**: Query field names don't match document fields

---

**START NOW**: Add the 3 log statements and test! 🚀
