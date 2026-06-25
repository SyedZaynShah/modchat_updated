# Phase 1.5 Call State Diagram

## Complete State Machine Flow

```
                            USER A (CALLER)                    USER B (RECEIVER)
                            ===============                    =================

START: A presses call button
         │
         ├─> Create call document
         │   status = "calling"
         │
         ▼
    ┌─────────┐
    │ CALLING │                                          (No UI shown yet)
    └────┬────┘
         │
         │ 500ms auto transition
         │
         ▼
    ┌─────────┐                                      ┌──────────────────────┐
    │ RINGING │────────────────────────────────────>│  INCOMING CALL       │
    └────┬────┘                                      │  White screen        │
         │                                           │  - Accept button     │
         │                                           │  - Decline button    │
         │                                           └──────────┬───────────┘
         │                                                      │
         │                                   ┌─────────────────┼─────────────────┐
         │                                   │                 │                 │
         │                       ┌───────────▼─────┐  ┌────────▼──────┐  ┌──────▼──────┐
         │                       │  ACCEPT PRESSED │  │ DECLINE PRESS │  │  30s PASS   │
         │                       └───────────┬─────┘  └────────┬──────┘  └──────┬──────┘
         │                                   │                 │                 │
         │                                   │                 │                 │
    ┌────┴──────────────────────────────────┼─────────────────┼─────────────────┤
    │                                        │                 │                 │
    │                                        ▼                 ▼                 ▼
    │                                   ┌─────────┐      ┌──────────┐     ┌─────────┐
    ├──────────────────────────────────>│ACCEPTED │      │ DECLINED │     │ MISSED  │
    │                                   └────┬────┘      └────┬─────┘     └────┬────┘
    │                                        │                │                │
    │                                        │                │                │
    │                                        │                │                │
    │  A CALLER CANCELS (END BUTTON)        │                │                │
    │  BEFORE ANSWER                         │                │                │
    ▼                                        ▼                ▼                ▼
┌────────┐                              ┌────────┐      ┌────────┐      ┌────────┐
│ ENDED  │◄─────────────────────────────│ ENDED  │      │ ENDED  │      │ ENDED  │
└────┬───┘                              └───┬────┘      └───┬────┘      └───┬────┘
     │                                      │               │               │
     │                                      │               │               │
     └──────────────────────────────────────┴───────────────┴───────────────┘
                                            │
                                            ▼
                                    TERMINAL STATE OVERLAY
                                    Display for 2 seconds
                                    Auto-close screen
```

---

## State Transition Details

### 1. CALLING → RINGING
```
Trigger:    Automatic after 500ms
Caller UI:  "Calling..." → "Ringing..."
Receiver:   Incoming call popup appears
Firestore:  status: "calling" → "ringing"
Log:        CALL STATE [id]: calling -> ringing
```

### 2. RINGING → ACCEPTED
```
Trigger:    Receiver presses Accept button
Caller UI:  Navigate to CallScreen, show "Connected"
Receiver:   Navigate to CallScreen, show "Connected"
Firestore:  status: "ringing" → "accepted"
            answeredAt: Timestamp
Log:        CALL STATE [id]: ringing -> accepted
```

### 3. RINGING → DECLINED
```
Trigger:    Receiver presses Decline button
Caller UI:  Show "Call Declined" overlay for 2s → Auto-close
Receiver:   Close screen immediately (no overlay)
Firestore:  status: "ringing" → "declined"
            endedAt: Timestamp
Log:        CALL STATE [id]: ringing -> declined
```

### 4. RINGING → MISSED
```
Trigger:    30-second timeout (no answer)
Caller UI:  Show "No Answer" overlay for 2s → Auto-close
Receiver:   Incoming popup closes, NO notification shown
Firestore:  status: "ringing" → "missed"
            endedAt: Timestamp
Log:        CALL STATE [id]: ringing -> missed
```

### 5. RINGING → ENDED (Caller Cancels)
```
Trigger:    Caller presses End Call before answer
Caller UI:  Show "Call Ended" overlay for 2s → Auto-close
Receiver:   Incoming popup closes immediately
Firestore:  status: "ringing" → "ended"
            endedAt: Timestamp
Log:        CALL STATE [id]: ringing -> ended
```

### 6. ACCEPTED → ENDED
```
Trigger:    Either party presses End Call
Caller UI:  Show "Call Ended" overlay for 2s → Auto-close
Receiver:   Show "Call Ended" overlay for 2s → Auto-close
Firestore:  status: "accepted" → "ended"
            endedAt: Timestamp
Log:        CALL STATE [id]: accepted -> ended
```

---

## UI State Breakdown

### Caller UI States

#### CALLING
```
┌─────────────────────────┐
│    CallScreen           │
│                         │
│    [User Avatar]        │
│                         │
│    John Doe             │
│    Calling...           │
│                         │
│                         │
│    [End Call]           │
└─────────────────────────┘
```

#### RINGING
```
┌─────────────────────────┐
│    CallScreen           │
│                         │
│    [User Avatar]        │
│                         │
│    John Doe             │
│    Ringing...           │
│                         │
│                         │
│    [End Call]           │
└─────────────────────────┘
```

#### ACCEPTED
```
┌─────────────────────────┐
│    CallScreen           │
│                         │
│    [User Avatar]        │
│                         │
│    John Doe             │
│    Connected            │
│                         │
│  [Mute]  [Speaker]      │
│                         │
│    [End Call]           │
└─────────────────────────┘
```

#### TERMINAL STATE (Declined/Missed/Ended)
```
┌─────────────────────────┐
│ ◄ Call Declined        │ ← Overlay, 2s display
└─────────────────────────┘
       ↓ After 2s
  [Screen closes]
```

---

### Receiver UI States

#### INCOMING CALL
```
┌─────────────────────────┐
│  IncomingCallScreen     │
│  (White background)     │
│                         │
│    [User Avatar]        │
│                         │
│    Jane Smith           │
│  Incoming Voice Call    │
│                         │
│                         │
│  [Decline]   [Accept]   │
└─────────────────────────┘
```

#### ACCEPTED
```
┌─────────────────────────┐
│    CallScreen           │
│  (Dark background)      │
│                         │
│    [User Avatar]        │
│                         │
│    Jane Smith           │
│    Connected            │
│                         │
│  [Mute]  [Speaker]      │
│                         │
│    [End Call]           │
└─────────────────────────┘
```

#### DECLINED (Receiver Side)
```
[Screen closes immediately]
(No overlay shown)
```

#### MISSED (Receiver Side)
```
[Incoming popup closes]
(NO notification shown)
```

#### ENDED (Receiver Side)
```
┌─────────────────────────┐
│ ◄ Call Ended           │ ← Overlay, 2s display
└─────────────────────────┘
       ↓ After 2s
  [Screen closes]
```

---

## Timer Flow

```
Call Created
    │
    ├─> Start 30-second timeout timer
    │
    ▼
Timer Running
    │
    ├──► Status changes to ACCEPTED/DECLINED/ENDED
    │    └─> Cancel timer ✓
    │
    └──► 30 seconds pass with status = CALLING/RINGING
         └─> Timer fires
             └─> Update status to MISSED
                 └─> Cancel timer ✓
```

---

## Listener Behavior

### Incoming Call Listener (Receiver Side)

```
Listen to: calls where receiverId == currentUserId

For each call update:
    │
    ├─> Parse status to CallState enum
    │
    ├─> IF status == MISSED
    │   └─> RETURN (do nothing) ❌
    │
    ├─> IF status != RINGING
    │   └─> RETURN (do nothing) ❌
    │
    └─> IF status == RINGING
        └─> Show IncomingCallScreen ✓
```

**Critical:** Missed calls NEVER trigger incoming call popup for receiver.

---

## Offline Detection Flow

```
User A presses call button
    │
    ├─> Check User B's document
    │   - Read isOnline field
    │   - Read lastSeen field
    │
    ├─> IF isOnline == false
    │   └─> Show snackbar: "User is Offline. Call will timeout if not answered."
    │       Wait 500ms
    │
    └─> Proceed with call creation
        │
        ├─> Create call document (status = calling)
        │
        └─> IF User B doesn't answer in 30s
            └─> Status becomes MISSED
                └─> Caller sees "No Answer"
```

---

## Firestore Updates Timeline

### Normal Accept → End Flow

```
t=0ms:      Call created
            { status: "calling", createdAt: Timestamp }

t=500ms:    Auto transition
            { status: "ringing" }

t=2000ms:   Receiver accepts
            { status: "accepted", answeredAt: Timestamp }

t=15000ms:  Caller ends
            { status: "ended", endedAt: Timestamp }
```

### Decline Flow

```
t=0ms:      Call created
            { status: "calling", createdAt: Timestamp }

t=500ms:    Auto transition
            { status: "ringing" }

t=3000ms:   Receiver declines
            { status: "declined", endedAt: Timestamp }
```

### Timeout Flow

```
t=0ms:      Call created
            { status: "calling", createdAt: Timestamp }

t=500ms:    Auto transition
            { status: "ringing" }

t=30500ms:  Timeout timer fires
            { status: "missed", endedAt: Timestamp }
```

---

## Console Log Examples

### Successful Call
```
CALL STATE [abc123]: -> calling
CALL STATE [abc123]: calling -> ringing
CALL STATE [abc123]: ringing -> accepted
CALL STATE [abc123]: accepted -> ended
```

### Declined Call
```
CALL STATE [xyz789]: -> calling
CALL STATE [xyz789]: calling -> ringing
CALL STATE [xyz789]: ringing -> declined
```

### Missed Call (Timeout)
```
CALL STATE [def456]: -> calling
CALL STATE [def456]: calling -> ringing
CALL STATE [def456]: ringing -> missed
```

---

## Error States

### Failed State (Future Use)
```
IF error occurs during call setup:
    │
    └─> Update status to "failed"
        └─> Show "Call Failed" overlay
            └─> Auto-close after 2s
```

---

## Memory Management

```
Call Service Lifecycle:
    │
    ├─> Call created
    │   └─> Start timeout timer
    │       └─> Store in _callTimeouts map
    │
    ├─> Call reaches terminal state
    │   └─> Cancel timeout timer
    │       └─> Remove from _callTimeouts map
    │
    └─> Service disposed
        └─> Cancel all remaining timers
            └─> Clear _callTimeouts map
```

---

## Testing Decision Tree

```
Testing Phase 1.5?
    │
    ├─> Test basic accept → end flow
    │   ├─> Pass? ✓ → Continue
    │   └─> Fail? ✗ → Debug state transitions
    │
    ├─> Test decline flow
    │   ├─> Pass? ✓ → Continue
    │   └─> Fail? ✗ → Check terminal state overlay
    │
    ├─> Test timeout flow
    │   ├─> Pass? ✓ → Continue
    │   └─> Fail? ✗ → Verify timer setup
    │
    ├─> Test missed call filtering
    │   ├─> Pass? ✓ → Continue
    │   └─> Fail? ✗ → Check listener logic
    │
    └─> All tests pass?
        ├─> YES ✓ → Ready for Phase 2
        └─> NO ✗ → Review test scenarios
```

---

## Key Takeaways

1. **Automatic Transition:** calling → ringing happens automatically after 500ms
2. **Terminal States:** All terminal states display overlay for exactly 2 seconds
3. **Missed Calls:** Receiver NEVER sees missed call popup
4. **Offline Detection:** Warning shown but call proceeds
5. **Timeout:** Exactly 30 seconds from ringing state
6. **Cleanup:** All timers cancelled on terminal states
7. **Logging:** Every transition logged to console
8. **Back Button:** Disabled during terminal state display

---

**Visual State Machine Complete** ✅

This diagram shows the complete flow from call initiation to termination with all possible paths and UI states.
