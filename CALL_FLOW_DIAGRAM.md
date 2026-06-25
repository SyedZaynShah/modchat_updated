# Voice Call Flow Diagram - Phase 1

## 📞 Complete Call Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           PHASE 1 CALL FLOW                             │
└─────────────────────────────────────────────────────────────────────────┘

USER A (Caller)                    FIRESTORE                    USER B (Receiver)
─────────────────                 ───────────                  ──────────────────

┌─────────────┐
│ChatDetailScr│
│   (DM Chat) │
└──────┬──────┘
       │
       │ [1] User taps 
       │     call button
       │     (Icons.call_rounded)
       ▼
┌──────────────┐
│_startVoiceCall│
│   method      │
└──────┬────────┘
       │
       │ [2] CallService.
       │     startVoiceCall()
       ▼
 ┌─────────────┐                 ┌──────────────┐
 │Get user info│────────────────▶│  CREATE DOC  │
 │from Firestore│                 │              │
 └─────────────┘                 │ calls/[id]   │
                                  │              │
                                  │ callerId     │
                                  │ callerName   │
                                  │ receiverId   │
                                  │ type: voice  │
                                  │ status:      │
                                  │  "ringing"   │
                                  │ createdAt    │
                                  └──────┬───────┘
                                         │
                                         │ [3] Snapshot
                                         │     triggers
                                         ▼
       │                                          ┌──────────────────┐
       │                                          │IncomingCallList. │
       │                                          │   (watching)     │
       │                                          └────────┬─────────┘
       │                                                   │
       │                                                   │ [4] Detects
       │                                                   │     new call
       │                                                   ▼
       │                                          ┌──────────────────┐
       │                                          │IncomingCallScr   │
       │                                          │  AUTO-OPENS      │
       │                                          │                  │
       │                                          │ ┌──────────────┐ │
       │                                          │ │ Caller Name  │ │
       │                                          │ │ Avatar       │ │
       │                                          │ │"Incoming     │ │
       │                                          │ │ Voice Call"  │ │
       │                                          │ └──────────────┘ │
       │                                          │                  │
       │                                          │ [Decline][Accept]│
       ▼                                          └────────┬─────────┘
┌──────────────┐                                          │
│  CallScreen  │                                          │
│              │                                          │
│ Status:      │                                          │
│ "Ringing..." │◀─────────────────────────────────────────┘
│              │         [5] Navigate to                   
│ [Mute] OFF   │             CallScreen                   
│ [Speaker] OFF│                                          
│              │                                          
│ [End Call]   │                                          
└──────┬───────┘                                          
       │                                                   
       │
       │
       │
─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
                         SCENARIO 1: USER B ACCEPTS
─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─

                                                          ┌──────────────────┐
                                                          │ User B taps      │
                                                          │ [Accept] button  │
                                                          └────────┬─────────┘
                                                                   │
                                  ┌────────────────────────────────┘
                                  │ [6] CallService.acceptCall()
                                  ▼
                                 ┌──────────────┐
                                 │  UPDATE DOC  │
                                 │              │
                                 │ status:      │
                                 │  "accepted"  │
                                 │ answeredAt:  │
                                 │  [timestamp] │
                                 └──────┬───────┘
                                        │
              ┌─────────────────────────┴─────────────────────────┐
              │ [7] Both devices listening to same call doc       │
              │     Stream triggers update on both                 │
              └─────────────────────────┬─────────────────────────┘
                                        │
              ┌─────────────────────────┴─────────────────────────┐
              ▼                                                    ▼
    ┌──────────────┐                                    ┌──────────────┐
    │  CallScreen  │                                    │  CallScreen  │
    │  (User A)    │                                    │  (User B)    │
    │              │                                    │              │
    │ Status:      │                                    │ Status:      │
    │ "Connected"  │◀───── Both see same status ──────▶│ "Connected"  │
    │              │                                    │              │
    │ [Mute] OFF   │                                    │ [Mute] OFF   │
    │ [Speaker] OFF│                                    │ [Speaker] OFF│
    │              │                                    │              │
    │ [End Call]   │                                    │ [End Call]   │
    └──────┬───────┘                                    └──────┬───────┘
           │                                                   │
           │                                                   │
           │ [8] Either user                                  │
           │     taps End Call                                 │
           └─────────────────────┬─────────────────────────────┘
                                 │
                                 ▼
                        ┌──────────────┐
                        │  UPDATE DOC  │
                        │              │
                        │ status:      │
                        │  "ended"     │
                        │ endedAt:     │
                        │  [timestamp] │
                        └──────┬───────┘
                               │
                               │ [9] Stream update
                               │     triggers on both
                               ▼
                    ┌──────────────────────┐
                    │ Both CallScreens     │
                    │ auto-close and       │
                    │ navigate back        │
                    └──────────────────────┘


─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
                        SCENARIO 2: USER B DECLINES
─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─

                                                          ┌──────────────────┐
                                                          │ User B taps      │
                                                          │ [Decline] button │
                                                          └────────┬─────────┘
                                                                   │
                                  ┌────────────────────────────────┘
                                  │ [6] CallService.declineCall()
                                  ▼
                                 ┌──────────────┐
                                 │  UPDATE DOC  │
                                 │              │
                                 │ status:      │
                                 │  "declined"  │
                                 │ endedAt:     │
                                 │  [timestamp] │
                                 └──────┬───────┘
                                        │
              ┌─────────────────────────┴─────────────────────────┐
              │ [7] User A's CallScreen listening to stream       │
              │     detects status change to "declined"           │
              └─────────────────────────┬─────────────────────────┘
                                        │
              ┌─────────────────────────┘
              ▼
    ┌──────────────┐                                    ┌──────────────────┐
    │  CallScreen  │                                    │IncomingCallScr   │
    │  (User A)    │                                    │  closes          │
    │              │                                    │                  │
    │ Auto-closes  │                                    │ Back to previous │
    │ Returns to   │                                    │ screen           │
    │ chat         │                                    │                  │
    └──────────────┘                                    └──────────────────┘


═══════════════════════════════════════════════════════════════════════════
                              KEY COMPONENTS
═══════════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────┐
│                         CallService Methods                             │
├─────────────────────────────────────────────────────────────────────────┤
│ startVoiceCall()  │ Creates call doc with status "ringing"              │
│ acceptCall()      │ Updates status to "accepted", sets answeredAt       │
│ declineCall()     │ Updates status to "declined", sets endedAt          │
│ endCall()         │ Updates status to "ended", sets endedAt             │
│ listenToIncoming()│ Stream of calls where receiverId = currentUser      │
│ listenToCall()    │ Stream of specific call for real-time updates       │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                         Riverpod Providers                              │
├─────────────────────────────────────────────────────────────────────────┤
│ callServiceProvider        │ Provides CallService instance              │
│ incomingCallsStreamProvider│ Stream of incoming calls for current user  │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                         UI Screens                                      │
├─────────────────────────────────────────────────────────────────────────┤
│ ChatDetailScreen       │ Has call button in AppBar                      │
│ IncomingCallScreen     │ Shows when call arrives, Accept/Decline        │
│ CallScreen             │ Shows during active call, End Call button      │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                         Global Listener                                 │
├─────────────────────────────────────────────────────────────────────────┤
│ IncomingCallListener   │ Wraps app, listens for incoming calls          │
│                        │ Auto-opens IncomingCallScreen                   │
│                        │ Prevents duplicate notifications                │
└─────────────────────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════
                            STATE MANAGEMENT
═══════════════════════════════════════════════════════════════════════════

Call Status State Machine:

    ┌─────────┐
    │ ringing │◀────────────────── Initial state when call created
    └────┬────┘
         │
         ├────────────────┬─────────────────────────┐
         │                │                         │
         ▼                ▼                         ▼
    ┌─────────┐      ┌──────────┐            ┌──────────┐
    │accepted │      │ declined │            │  ended   │
    └────┬────┘      └──────────┘            └──────────┘
         │                 │                       │
         │                 │                       │
         │                 └───────────┬───────────┘
         │                             │
         │                             ▼
         │                    ┌──────────────────┐
         └───────────────────▶│  Call complete   │
                              │  (terminal state)│
                              └──────────────────┘

Transition Rules:
• ringing → accepted  (only receiver can trigger)
• ringing → declined  (only receiver can trigger)
• ringing → ended     (only caller can trigger)
• accepted → ended    (either party can trigger)


═══════════════════════════════════════════════════════════════════════════
                           DATA FLOW PATTERNS
═══════════════════════════════════════════════════════════════════════════

Pattern 1: Write-then-Watch
┌──────────┐     write      ┌───────────┐     snapshot    ┌──────────┐
│  User A  │───────────────▶│ Firestore │────────────────▶│  User B  │
│ (caller) │                └───────────┘                 │(receiver)│
└──────────┘                                              └──────────┘

Pattern 2: Real-time Sync
┌──────────┐                ┌───────────┐                ┌──────────┐
│  User A  │◀──────stream───│ Firestore │───stream──────▶│  User B  │
│          │                │  (single  │                │          │
│          │                │   doc)    │                │          │
└──────────┘                └───────────┘                └──────────┘
     │                                                         │
     │  Both watching same document via snapshots()            │
     │  Status changes propagate to both instantly             │
     └─────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════
                         FIRESTORE QUERY FLOW
═══════════════════════════════════════════════════════════════════════════

User B's Incoming Call Listener:

    ┌────────────────────────────────────────────────────────┐
    │  Firestore Query (Real-time)                           │
    │                                                        │
    │  calls.where('receiverId', isEqualTo: currentUserId)   │
    │       .where('status', isEqualTo: 'ringing')           │
    │       .snapshots()                                      │
    └────────────────────────────────────────────────────────┘
                              │
                              │ Stream emits when:
                              │ • New call created
                              │ • Status changes to "ringing"
                              │
                              ▼
    ┌────────────────────────────────────────────────────────┐
    │  IncomingCallListener.build()                          │
    │                                                        │
    │  ref.listen(incomingCallsStreamProvider, ...)          │
    │                                                        │
    │  if (snapshot.docs.isNotEmpty) {                       │
    │    → Open IncomingCallScreen                           │
    │  }                                                     │
    └────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════
                        NAVIGATION ARCHITECTURE
═══════════════════════════════════════════════════════════════════════════

App Hierarchy:

MaterialApp
└── IncomingCallListener ◀────────────── Wraps entire app
    └── ModChatSplashScreen / AuthGate
        └── HomeScreen
            └── ChatDetailScreen
                ├── [Call Button Tap]
                │   └── CallScreen (pushed)
                │
                └── [Incoming Call Detected]
                    └── IncomingCallScreen (pushed)
                        └── [Accept]
                            └── CallScreen (replacement)


═══════════════════════════════════════════════════════════════════════════
                          ERROR HANDLING FLOW
═══════════════════════════════════════════════════════════════════════════

┌─────────────────┐
│  User Action    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  try {          │
│    await ...    │
│  }              │
└────────┬────────┘
         │
         ├─────── Success ──────▶ Continue flow
         │
         └─────── Catch Error
                     │
                     ▼
         ┌──────────────────────┐
         │ if (!mounted) return │
         └──────────┬───────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │ ScaffoldMessenger.   │
         │   showSnackBar()     │
         └──────────────────────┘
                    │
                    ▼
         User sees error message


═══════════════════════════════════════════════════════════════════════════
                        STREAM LIFECYCLE
═══════════════════════════════════════════════════════════════════════════

CallScreen Stream Management:

┌─────────────────┐
│ initState()     │
│                 │
│ _listenToCall   │──────┐
│  .listen(...)   │      │ Creates subscription
└─────────────────┘      │
                         ▼
                  ┌──────────────────┐
                  │ StreamSubscription│
                  │ _callSubscription │
                  └──────────┬────────┘
                             │
                             │ Listens continuously
                             │ for status changes
                             │
                             ▼
                  ┌──────────────────┐
                  │ Status update?   │
                  └──────────┬────────┘
                             │
                   ┌─────────┴─────────┐
                   │                   │
                   ▼                   ▼
           ┌──────────────┐   ┌──────────────┐
           │  Update UI   │   │ Auto-close   │
           │  setState()  │   │ if ended     │
           └──────────────┘   └──────────────┘
                             
┌─────────────────┐
│ dispose()       │
│                 │
│ _subscription   │
│ ?.cancel()      │──────▶ Cleanup
└─────────────────┘


═══════════════════════════════════════════════════════════════════════════
```

## Legend

- `┌─┐ └─┘` - Boxes represent components or states
- `│ ─` - Lines represent flow or connections
- `▼ ▶ ◀` - Arrows show direction of data/control flow
- `◀──▶` - Bidirectional communication
- `─ ─` - Dotted lines separate scenarios
- `═══` - Section dividers

## Notes

1. **All communication** between users goes through Firestore
2. **No direct peer-to-peer** connection in Phase 1
3. **Streams** provide real-time updates without polling
4. **State is source of truth** - Firestore document status
5. **Navigation is automatic** - based on status changes
