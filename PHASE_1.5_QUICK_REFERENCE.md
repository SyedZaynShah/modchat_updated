# Phase 1.5 Quick Reference Card

## Call States Cheat Sheet

```
ACTIVE STATES          TERMINAL STATES
----------------       ----------------
calling                declined
ringing                missed
accepted               ended
                       failed
```

## State Transition Flow

```
┌─────────┐
│ calling │ (created by caller)
└────┬────┘
     │ 500ms auto
     ▼
┌─────────┐
│ ringing │ (visible to receiver)
└────┬────┘
     │
     ├──► accepted ──► ended (normal end)
     ├──► declined (receiver declines)
     ├──► missed (30s timeout)
     └──► ended (caller cancels)
```

## User Experience Matrix

| Action | Caller Sees | Receiver Sees |
|--------|-------------|---------------|
| Call starts | "Calling..." → "Ringing..." | Incoming popup |
| Accept | "Connected" + controls | "Connected" + controls |
| Decline | "Call Declined" (2s) → Close | Closes immediately |
| Timeout (30s) | "No Answer" (2s) → Close | Nothing (popup closes) |
| Caller cancels | "Call Ended" (2s) → Close | Popup closes |
| Either ends | "Call Ended" (2s) → Close | "Call Ended" (2s) → Close |

## Key Functions

### Start a Call
```dart
final callId = await callService.startVoiceCall(
  callerId: currentUserId,
  callerName: 'John Doe',
  receiverId: peerId,
);
```

### Accept a Call
```dart
await callService.acceptCall(callId);
```

### Decline a Call
```dart
await callService.declineCall(callId);
```

### End a Call
```dart
await callService.endCall(callId);
```

### Check Online Status
```dart
final status = await callService.checkUserOnlineStatus(userId);
final isOnline = status['isOnline'] as bool;
```

### Show Terminal State Overlay
```dart
showCallStatusOverlay(context, CallState.ended);
```

## Console Log Format

```
CALL STATE [callId]: -> calling
CALL STATE [callId]: calling -> ringing
CALL STATE [callId]: ringing -> accepted
CALL STATE [callId]: accepted -> ended
```

## Important Rules

1. **NEVER show missed call popup to receiver** - only caller sees "No Answer"
2. **Terminal states ALWAYS display for 2 seconds** before auto-close
3. **Back button ALWAYS disabled** during terminal state display
4. **Receiver NEVER sees terminal overlay** for declined calls
5. **Timeout is ALWAYS 30 seconds** from ringing state
6. **State transitions ALWAYS logged** to console

## Critical Behavior

### For Caller:
- Sees all terminal states as overlays
- Screen auto-closes after 2 seconds
- Cannot dismiss with back button

### For Receiver:
- Sees overlay ONLY for accepted→ended
- NO overlay for declined (just closes)
- NO popup for missed calls ever
- Incoming popup closes on any terminal state

## Firestore Document

```javascript
{
  "callerId": "userA_id",
  "callerName": "User A Name",
  "receiverId": "userB_id",
  "type": "voice",
  "status": "ringing", // CallState enum value
  "createdAt": Timestamp,
  "answeredAt": Timestamp | null,
  "endedAt": Timestamp | null
}
```

## Test Scenarios (Quick)

1. ✅ A calls B → B accepts → A ends → Both see "Call Ended"
2. ✅ A calls B → B declines → A sees "Call Declined", B closes
3. ✅ A calls B → No answer 30s → A sees "No Answer", B never notified
4. ✅ A calls B → A cancels → A sees "Call Ended", B popup closes
5. ✅ A calls offline B → Warning shown → Call proceeds → Timeout

## Common Issues & Fixes

### Issue: Receiver doesn't see popup
**Check:** Status must be `ringing`, not `calling` or `missed`

### Issue: Terminal state doesn't show
**Check:** `isTerminal` property and overlay mounting

### Issue: Timeout doesn't trigger
**Check:** Timer not cancelled prematurely, 30s duration correct

### Issue: Duplicate popups
**Check:** `_currentCallId` tracking in listener

### Issue: Missed calls showing popup
**Check:** Listener filters out `CallState.missed`

## File Locations

```
lib/
├── models/
│   └── call_state.dart              # State enum
├── services/
│   └── call_service.dart            # Core call logic
├── widgets/
│   ├── call_status_overlay.dart     # Terminal state UI
│   └── incoming_call_listener.dart  # Global listener
└── screens/chat/
    ├── call_screen.dart             # Active call UI
    ├── incoming_call_screen.dart    # Incoming call UI
    └── chat_detail_screen.dart      # Call button
```

## Constants

```dart
// Timeout duration
callTimeout = Duration(seconds: 30)

// Terminal state display
displayDuration = Duration(seconds: 2)

// Ringing transition delay
ringingDelay = Duration(milliseconds: 500)
```

## What Phase 1.5 Does NOT Include

- ❌ Actual audio (use Phase 2)
- ❌ Video calls (use Phase 2)
- ❌ Mute/Speaker functionality (placeholders only)
- ❌ Call history/logs
- ❌ Push notifications
- ❌ Network quality indicators

## What Phase 1.5 DOES Include

- ✅ Complete call signaling
- ✅ All state transitions
- ✅ 30-second timeout
- ✅ Terminal state overlays
- ✅ Offline detection
- ✅ Proper cleanup
- ✅ Security rules
- ✅ State logging

## Ready for Phase 2 When...

- All test scenarios pass ✅
- State transitions logged correctly ✅
- No duplicate popups ✅
- Missed calls never show receiver popup ✅
- Terminal states display for 2 seconds ✅
- Offline detection works ✅
- Timers properly disposed ✅
- No memory leaks ✅

---

**Need Help?** See `PHASE_1.5_CALL_STATE_TESTING_GUIDE.md` for detailed testing instructions.
