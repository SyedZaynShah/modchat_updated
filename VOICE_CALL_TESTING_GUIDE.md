# Voice Call Phase 1 - Testing Guide

## Prerequisites

### 1. Setup Requirements
- Two test devices (or one device + one emulator)
- Both devices logged into different user accounts
- Active internet connection on both devices
- Firestore security rules configured to allow calls collection access

### 2. Firestore Security Rules
Add these rules to allow call operations:

```javascript
// Add to your firestore.rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Existing rules...
    
    // Calls collection rules
    match /calls/{callId} {
      // Allow users to create calls where they are the caller
      allow create: if request.auth != null 
                    && request.resource.data.callerId == request.auth.uid;
      
      // Allow caller and receiver to read the call
      allow read: if request.auth != null 
                  && (resource.data.callerId == request.auth.uid 
                      || resource.data.receiverId == request.auth.uid);
      
      // Allow caller and receiver to update the call
      allow update: if request.auth != null 
                    && (resource.data.callerId == request.auth.uid 
                        || resource.data.receiverId == request.auth.uid);
      
      // Prevent deletion (for audit trail)
      allow delete: if false;
    }
  }
}
```

### 3. Test User Setup
Create two test accounts:
- **User A** (Caller): test-user-a@example.com
- **User B** (Receiver): test-user-b@example.com

Ensure both users:
- Have display names set in their user profile
- Are contacts/friends (if your app requires this)
- Have an active DM chat between them

## Test Scenarios

### Test 1: Basic Outgoing Call
**Device**: User A's device

**Steps**:
1. Open the app and log in as User A
2. Navigate to the DM chat with User B
3. Tap the call button (phone icon) in the AppBar
4. Verify the call screen opens
5. Verify the status shows "Ringing..."
6. Verify User B's name is displayed correctly
7. Verify the "End Call" button is visible and functional

**Expected Results**:
- ✅ Call screen opens immediately
- ✅ Status: "Ringing..."
- ✅ User B's name displayed
- ✅ Mute and Speaker buttons are visible but disabled (grayed out)
- ✅ End Call button is active

**Firestore Verification**:
```
Collection: calls
Document ID: [auto-generated]
Data: {
  callerId: "user_a_uid",
  callerName: "User A Name",
  receiverId: "user_b_uid",
  type: "voice",
  status: "ringing",
  createdAt: [server timestamp],
  answeredAt: null,
  endedAt: null
}
```

---

### Test 2: Incoming Call Notification
**Device**: User B's device

**Prerequisites**: Test 1 must be running (User A calling User B)

**Steps**:
1. Ensure User B is logged in and app is in foreground
2. Wait for incoming call screen to appear automatically
3. Verify incoming call screen displays correctly

**Expected Results**:
- ✅ Incoming call screen pops up within 1-2 seconds
- ✅ Large avatar displayed (blue circle with person icon)
- ✅ Caller name shows "User A Name"
- ✅ Text shows "Incoming Voice Call"
- ✅ Two buttons visible: "Decline" (red) and "Accept" (green)
- ✅ Screen has white background with dark navy text

---

### Test 3: Decline Call
**Device**: User B's device

**Prerequisites**: Test 2 incoming call screen is showing

**Steps**:
1. On User B's incoming call screen, tap "Decline" button
2. Verify the incoming call screen closes
3. Check User A's device

**Expected Results on User B**:
- ✅ Incoming call screen closes immediately
- ✅ Returns to previous screen (home or chat)

**Expected Results on User A**:
- ✅ Call screen closes automatically within 1-2 seconds
- ✅ Returns to chat screen

**Firestore Verification**:
```
status: "declined"
endedAt: [server timestamp]
```

---

### Test 4: Accept Call
**Device**: User B's device

**Prerequisites**: 
- User A initiates a new call
- User B's incoming call screen appears

**Steps**:
1. On User B's incoming call screen, tap "Accept" button
2. Verify navigation to call screen
3. Verify call status updates
4. Check User A's device

**Expected Results on User B**:
- ✅ Navigates to call screen
- ✅ Shows User A's name
- ✅ Status shows "Connected"
- ✅ Mute and Speaker buttons visible but disabled
- ✅ End Call button is active

**Expected Results on User A**:
- ✅ Status changes from "Ringing..." to "Connected"
- ✅ Screen updates automatically (no manual refresh needed)

**Firestore Verification**:
```
status: "accepted"
answeredAt: [server timestamp]
endedAt: null
```

---

### Test 5: End Call (Caller)
**Device**: User A's device

**Prerequisites**: Call is accepted and both users are on call screen

**Steps**:
1. On User A's call screen, tap "End Call" button
2. Verify screen closes
3. Check User B's device

**Expected Results on User A**:
- ✅ Call screen closes immediately
- ✅ Returns to chat screen

**Expected Results on User B**:
- ✅ Call screen closes automatically within 1-2 seconds
- ✅ Returns to previous screen

**Firestore Verification**:
```
status: "ended"
endedAt: [server timestamp]
```

---

### Test 6: End Call (Receiver)
**Device**: User B's device

**Prerequisites**: Call is accepted and both users are on call screen

**Steps**:
1. On User B's call screen, tap "End Call" button
2. Verify screen closes
3. Check User A's device

**Expected Results**:
Same as Test 5, but initiated by User B

---

### Test 7: No Duplicate Incoming Calls
**Devices**: User A and User B

**Steps**:
1. User A starts a call to User B
2. User B sees incoming call screen
3. While incoming call screen is showing, User A ends the call
4. Immediately after (within 1 second), User A starts another call
5. Observe User B's screen

**Expected Results**:
- ✅ First incoming call screen closes when User A ends call
- ✅ Second incoming call screen opens for the new call
- ✅ No duplicate/overlapping screens
- ✅ Only one incoming call screen visible at a time

---

### Test 8: Call While App in Background
**Device**: User B's device

**Prerequisites**: User A is ready to call

**Steps**:
1. User B minimizes the app (press home button)
2. User A initiates call
3. Wait 5 seconds
4. User B opens the app again

**Expected Results**:
- ⚠️ **Known Limitation**: Incoming call screen will NOT appear when app is in background
- ✅ When app is reopened, incoming call screen should appear if call is still ringing
- 📝 **Note**: Push notifications will be added in Phase 3

---

### Test 9: Network Delay Handling
**Devices**: Both

**Steps**:
1. Enable airplane mode on User B's device
2. User A initiates call
3. Wait 3 seconds
4. Disable airplane mode on User B's device
5. Observe behavior

**Expected Results**:
- ✅ User A's call screen shows "Ringing..." (doesn't error out)
- ✅ When User B comes online, incoming call screen appears
- ✅ No crashes or frozen UI
- ⚠️ If too much time passes, call may time out (no timeout implemented yet)

---

### Test 10: Rapid Call Actions
**Device**: User A

**Steps**:
1. Tap call button rapidly 5 times in succession
2. Observe behavior

**Expected Results**:
- ✅ Only one call document is created
- ✅ Navigation happens only once
- ✅ No duplicate call screens
- ⚠️ Multiple Firestore writes may occur (optimization needed in future)

---

## Edge Cases to Test

### Edge Case 1: User Not Found
**Steps**:
1. Modify code temporarily to use a non-existent receiver ID
2. Attempt to make a call

**Expected Result**:
- ✅ Error is caught gracefully
- ✅ User sees error message via SnackBar

### Edge Case 2: No Internet Connection
**Steps**:
1. Turn off WiFi and mobile data
2. Attempt to make a call

**Expected Result**:
- ✅ Firestore operation queues offline
- ✅ No crash
- ⚠️ Call may not go through until connection restored

### Edge Case 3: User Logs Out During Call
**Steps**:
1. Accept a call
2. While on call screen, force logout (via settings or Firebase console)

**Expected Result**:
- ✅ App handles authentication state change
- ✅ Call screen closes or redirects to login

---

## Debugging Tools

### Check Firestore in Firebase Console
1. Open Firebase Console
2. Navigate to Firestore Database
3. Open `calls` collection
4. Verify document structure and status updates in real-time

### Flutter DevTools
```bash
flutter run --verbose
```

Look for:
- Stream subscription logs
- Navigation logs
- Firestore read/write logs

### Common Issues and Fixes

#### Issue: Incoming call screen doesn't appear
**Possible Causes**:
1. Firestore rules blocking read access
2. Stream subscription not active
3. User B not logged in
4. Network connectivity issue

**Debug Steps**:
```dart
// Add to incoming_call_listener.dart temporarily
print('Incoming calls stream: ${snapshot.docs.length} calls');
print('Call data: ${snapshot.docs.first.data()}');
```

#### Issue: Call status doesn't update
**Possible Causes**:
1. Firestore rules blocking write access
2. Stream not listening to changes
3. Document ID mismatch

**Debug Steps**:
```dart
// Add to call_screen.dart temporarily
print('Call status updated: $status');
```

#### Issue: Multiple incoming call screens
**Possible Causes**:
1. `_currentCallId` state not persisting
2. Stream emitting duplicate events

**Debug Steps**:
```dart
// Add to incoming_call_listener.dart
print('Current call ID: $_currentCallId, New call ID: $callId');
```

---

## Performance Testing

### Memory Usage
- Monitor memory before and after multiple calls
- Check for memory leaks after 10+ calls

### Firestore Reads/Writes
Track number of operations:
- 1 write to create call
- 1 write to accept/decline/end
- Continuous reads via snapshots (expected)

### Battery Usage
- Monitor battery drain during 5-minute test session
- Should be minimal (no audio/video processing in Phase 1)

---

## Regression Testing Checklist

After any code changes, verify:
- [ ] Existing chat functionality still works
- [ ] Message sending not affected
- [ ] Home screen loads normally
- [ ] Authentication flow unchanged
- [ ] No new crashes in existing features

---

## Sign-Off Criteria

Phase 1 is complete when:
- ✅ All 10 main test scenarios pass
- ✅ All 3 edge cases handled gracefully
- ✅ No critical bugs found
- ✅ Firestore structure matches specification
- ✅ Navigation flow is smooth and intuitive
- ✅ UI matches design requirements (white background, navy text, blue accents)
- ✅ Both devices handle call lifecycle correctly
- ✅ No memory leaks detected
- ✅ Code passes `flutter analyze` with no errors

---

## Next Phase Preview

**Phase 2 will add**:
- Agora SDK integration
- Actual audio streaming
- Working mute/unmute
- Working speaker toggle
- Call quality indicators
- Connection state handling

**Do NOT proceed to Phase 2 until**:
- All Phase 1 tests pass
- Product owner/stakeholder approval received
- Any Phase 1 bugs are fixed
