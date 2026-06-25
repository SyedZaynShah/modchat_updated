# Phase 1.5: Call State Machine Testing Guide

## Overview
This guide covers all state transitions in the voice call signaling system. Phase 1.5 implements a complete state machine with proper terminal state handling, timeouts, and offline detection.

## Call States

### Active States
- `calling` - Call initiated by caller
- `ringing` - Call is ringing on receiver's device  
- `accepted` - Call has been accepted and is in progress

### Terminal States (Auto-close after 2 seconds)
- `declined` - Call was declined by receiver
- `missed` - Call was not answered (30-second timeout)
- `ended` - Call ended normally
- `failed` - Call failed due to error

---

## Test Scenarios

### Scenario 1: Normal Call Flow (Accept → End)

**Steps:**
1. Device A opens chat with Device B
2. Device A presses call button
3. Device B receives incoming call popup
4. Device B presses Accept
5. Both devices enter call screen showing "Connected"
6. Device A presses End Call

**Expected Results:**
- ✅ Device A sees "Calling..." → "Ringing..."
- ✅ Device B sees incoming call screen with Accept/Decline buttons
- ✅ After accept, both see "Connected" status
- ✅ Mute/Speaker buttons visible during accepted call
- ✅ After end, both see "Call Ended" overlay for 2 seconds
- ✅ Both screens auto-close after 2 seconds

**Console Logs to Verify:**
```
CALL STATE [callId]: -> calling
CALL STATE [callId]: calling -> ringing
CALL STATE [callId]: ringing -> accepted
CALL STATE [callId]: accepted -> ended
```

---

### Scenario 2: Call Declined by Receiver

**Steps:**
1. Device A opens chat with Device B
2. Device A presses call button
3. Device B receives incoming call popup
4. Device B presses Decline

**Expected Results:**
- ✅ Device A sees "Calling..." → "Ringing..."
- ✅ Device B sees incoming call screen
- ✅ After decline:
  - Device A sees "Call Declined" overlay for 2 seconds
  - Device A screen auto-closes after 2 seconds
  - Device B screen closes immediately (no terminal state shown to receiver)

**Console Logs to Verify:**
```
CALL STATE [callId]: -> calling
CALL STATE [callId]: calling -> ringing
CALL STATE [callId]: ringing -> declined
```

---

### Scenario 3: Call Timeout (No Answer)

**Steps:**
1. Device A opens chat with Device B
2. Device A presses call button
3. Device B does NOT answer
4. Wait 30+ seconds

**Expected Results:**
- ✅ Device A sees "Calling..." → "Ringing..." for 30 seconds
- ✅ After 30 seconds:
  - Device A sees "No Answer" overlay for 2 seconds
  - Device A screen auto-closes after 2 seconds
- ✅ **CRITICAL:** Device B NEVER sees a missed call popup
  - Receiver never gets popup for missed calls
  - Only caller sees "No Answer" terminal state

**Console Logs to Verify:**
```
CALL STATE [callId]: -> calling
CALL STATE [callId]: calling -> ringing
CALL STATE [callId]: ringing -> missed
```

---

### Scenario 4: Caller Cancels Before Answer

**Steps:**
1. Device A opens chat with Device B
2. Device A presses call button
3. Before Device B answers, Device A presses End Call

**Expected Results:**
- ✅ Device A sees "Calling..." → "Ringing..."
- ✅ Device A presses End Call
- ✅ Device A sees "Call Ended" overlay for 2 seconds
- ✅ Device A screen auto-closes
- ✅ Device B incoming call popup closes immediately

**Console Logs to Verify:**
```
CALL STATE [callId]: -> calling
CALL STATE [callId]: calling -> ringing
CALL STATE [callId]: ringing -> ended
```

---

### Scenario 5: Receiver Ends Accepted Call

**Steps:**
1. Device A calls Device B
2. Device B accepts
3. Both enter call screen showing "Connected"
4. Device B presses End Call

**Expected Results:**
- ✅ Both devices see "Connected" status
- ✅ After Device B ends:
  - Device B sees "Call Ended" overlay for 2 seconds
  - Device A sees "Call Ended" overlay for 2 seconds
- ✅ Both screens auto-close after 2 seconds

**Console Logs to Verify:**
```
CALL STATE [callId]: -> calling
CALL STATE [callId]: calling -> ringing
CALL STATE [callId]: ringing -> accepted
CALL STATE [callId]: accepted -> ended
```

---

### Scenario 6: Offline User Warning

**Steps:**
1. Device B logs out or closes app (goes offline)
2. Device A opens chat with Device B
3. Device A presses call button

**Expected Results:**
- ✅ Device A sees snackbar: "User is Offline. Call will timeout if not answered."
- ✅ Call still proceeds (status shows "Calling..." → "Ringing...")
- ✅ After 30 seconds, Device A sees "No Answer" overlay
- ✅ Device A screen auto-closes after 2 seconds

**Console Logs to Verify:**
```
CALL STATE [callId]: -> calling
CALL STATE [callId]: calling -> ringing
CALL STATE [callId]: ringing -> missed
```

---

## State Transition Matrix

| From State | To State | Triggered By | Caller Sees | Receiver Sees |
|------------|----------|--------------|-------------|---------------|
| calling | ringing | Auto (500ms) | "Ringing..." | Incoming popup |
| ringing | accepted | Accept button | "Connected" | "Connected" |
| ringing | declined | Decline button | "Call Declined" (2s) | Closes immediately |
| ringing | missed | 30s timeout | "No Answer" (2s) | Nothing |
| ringing | ended | Caller cancels | "Call Ended" (2s) | Closes immediately |
| accepted | ended | End button | "Call Ended" (2s) | "Call Ended" (2s) |

---

## UI Behavior Requirements

### Call Screen (call_screen.dart)
- ✅ Shows peer name and avatar
- ✅ Shows current call state in user-friendly text
- ✅ Mute/Speaker buttons ONLY visible when state = `accepted`
- ✅ End Call button HIDDEN on terminal states
- ✅ Terminal state overlay appears for 2 seconds
- ✅ Screen auto-closes after terminal state display
- ✅ Back button disabled during terminal state display

### Incoming Call Screen (incoming_call_screen.dart)
- ✅ Shows caller name and avatar
- ✅ Shows "Incoming Voice Call" text
- ✅ Accept/Decline buttons
- ✅ On Accept: Navigate to CallScreen
- ✅ On Decline: Close immediately (no overlay)
- ✅ If call ends/times out: Close immediately
- ✅ Back button disabled during terminal state display

### Incoming Call Listener (incoming_call_listener.dart)
- ✅ Listens to calls where `receiverId == currentUser`
- ✅ Only shows popup for calls with status = `ringing`
- ✅ **NEVER shows popup for status = `missed`**
- ✅ Prevents duplicate popups for same call ID
- ✅ Closes existing popup if call state changes

---

## Edge Cases to Test

### 1. Rapid Call Cancellation
- Caller presses call button then immediately cancels
- Expected: No popup appears on receiver's device

### 2. Multiple Incoming Calls
- Device A calls Device C
- Device B calls Device C simultaneously
- Expected: Device C sees popup for most recent call only

### 3. Network Disconnection During Call
- Device A and Device B in accepted call
- Device A loses network connection
- Expected: After timeout, both see "Call Ended" or "Call Failed"

### 4. App Backgrounding During Call
- Device A in accepted call
- Device A presses home button (app goes to background)
- Expected: Call state persists, call continues

### 5. Duplicate Call Button Presses
- Device A rapidly presses call button multiple times
- Expected: Only one call document created

---

## Firestore Data Verification

### Call Document Structure
```javascript
{
  "callerId": "userA_id",
  "callerName": "User A",
  "receiverId": "userB_id",
  "type": "voice",
  "status": "ringing", // or accepted, declined, missed, ended, failed
  "createdAt": Timestamp,
  "answeredAt": Timestamp | null,
  "endedAt": Timestamp | null
}
```

### Security Rules Verification
1. Users can only create calls where `callerId == auth.uid`
2. Users cannot call themselves (`receiverId != callerId`)
3. Only caller and receiver can read/update call document
4. Call IDs (`callerId`, `receiverId`) are immutable
5. `type` field is immutable
6. Calls cannot be deleted (audit trail)

---

## Success Criteria

### Must Pass ALL Tests:
- [ ] All 6 scenarios pass without errors
- [ ] Console logs show correct state transitions
- [ ] Terminal states display for exactly 2 seconds
- [ ] No duplicate popups appear
- [ ] Missed calls NEVER show popup to receiver
- [ ] Offline detection works and shows warning
- [ ] Back button disabled during terminal states
- [ ] All Firestore security rules enforced
- [ ] No memory leaks (timers properly disposed)
- [ ] UI updates are smooth and instant

---

## Known Limitations (Phase 1.5)

### NOT Implemented Yet:
- ❌ No actual audio (WebRTC) - Phase 2
- ❌ Mute/Speaker buttons disabled (placeholders only)
- ❌ No call history/logs - Future phase
- ❌ No push notifications - Future phase
- ❌ No network quality indicators - Future phase

### What IS Working:
- ✅ Complete signaling system
- ✅ All state transitions
- ✅ Timeout handling
- ✅ Offline detection
- ✅ Terminal state overlays
- ✅ Security rules
- ✅ Proper cleanup

---

## Debugging Tips

### If call doesn't appear on receiver:
1. Check Firestore console for call document
2. Verify `receiverId` matches user ID
3. Check `status` field is `ringing`
4. Verify incoming_call_listener is active
5. Check console for listener errors

### If terminal state doesn't show:
1. Check state transition logs in console
2. Verify CallState enum parsing
3. Check if `isTerminal` property is true
4. Verify overlay is mounted before showing

### If timeout doesn't work:
1. Check call_service.dart timer setup
2. Verify 30-second duration
3. Check if timer is cancelled prematurely
4. Look for "CALL STATE: ringing -> missed" log

---

## Next Steps

### After Phase 1.5 is verified:
1. All state transitions work correctly
2. All test scenarios pass
3. No bugs in state machine logic
4. Firestore rules enforced properly

### Then proceed to Phase 2:
- WebRTC integration
- Actual audio streaming
- Agora SDK setup
- Real-time audio quality
- Network quality indicators

**DO NOT START PHASE 2 UNTIL PHASE 1.5 IS FULLY TESTED AND VERIFIED.**

---

## File Summary

### Updated Files:
- `lib/models/call_state.dart` - Complete call state enum
- `lib/services/call_service.dart` - State management & timeout logic
- `lib/widgets/call_status_overlay.dart` - Terminal state display
- `lib/screens/chat/call_screen.dart` - Updated with state machine
- `lib/screens/chat/incoming_call_screen.dart` - Terminal state handling
- `lib/screens/chat/chat_detail_screen.dart` - Offline detection
- `lib/widgets/incoming_call_listener.dart` - Missed call filtering

### Testing Order:
1. Test basic flow (Scenario 1)
2. Test decline (Scenario 2)
3. Test timeout (Scenario 3)
4. Test caller cancel (Scenario 4)
5. Test receiver end (Scenario 5)
6. Test offline warning (Scenario 6)
7. Test edge cases
8. Verify Firestore security rules

---

**Phase 1.5 Complete: Full Call State Machine with Terminal States, Timeouts, and Offline Detection** ✅
