# GROUP CALL SIGNALING FLOW - VISUAL GUIDE

**Purpose**: Visual representation of how group call signaling should work

---

## COMPLETE SIGNALING FLOW

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         GROUP CALL SIGNALING FLOW                        │
└─────────────────────────────────────────────────────────────────────────┘

DEVICE A (CALLER)                                    DEVICE B (RECEIVER)
──────────────────                                   ───────────────────

1. User taps "Start Call"                           (App running, logged in)
   │                                                 │
   │                                                 │ ┌─────────────────┐
   ↓                                                 │ │ Listener Active │
2. Create groupCalls/{callId}                        │ │ Waiting...      │
   status: 'ringing'                                 │ └─────────────────┘
   joinedParticipants: [userA]                       │
   invitedParticipants: [userB, userC]               │
   │                                                 │
   │                                                 │
   ↓                                                 │
3. Create groupCallInvitations                       │
   │                                                 │
   ├─► invitation1                                   │
   │   targetUserId: userB ─────────────────────────┼─► Firestore Real-time
   │   status: 'pending'                             │   Listener Triggers
   │                                                 │   │
   ├─► invitation2                                   │   ↓
   │   targetUserId: userC                           │ 4. StreamBuilder receives
   │   status: 'pending'                             │    snapshot.data
   │                                                 │    docs.length = 1
   ↓                                                 │    │
4. Open GroupAudioCallScreen                         │    ↓
   (Caller hears ringing tone)                       │ 5. Parse invitation
                                                     │    callId: abc123
                                                     │    targetUserId: userB
                                                     │    status: pending
                                                     │    │
                                                     │    ↓
                                                     │ 6. Show Dialog
                                                     │    ┌──────────────────┐
                                                     │    │  📞 Group Call   │
                                                     │    │  "Family" group  │
                                                     │    │  User A calling  │
                                                     │    │                  │
                                                     │    │  [Accept][Decline]│
                                                     │    └──────────────────┘
                                                     │    │
                                                     │    ↓
                                                     │ User clicks "Accept"
                                                     │    │
                                                     ↓    ↓
                                                  7. Update invitation
                                                     status: 'accepted'
                                                     │
                                                     ↓
                                                  8. Join call
                                                     joinedParticipants: [userA, userB]
                                                     │
                                                     ↓
                                                  9. Open GroupAudioCallScreen
                                                     WebRTC negotiation begins
                                                     │
                                                     ↓
                                                  10. Audio streaming starts
```

---

## DATA FLOW DIAGRAM

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           FIRESTORE COLLECTIONS                           │
└──────────────────────────────────────────────────────────────────────────┘

groupCalls/
  └── {callId}                              ← Created by caller
        ├── groupId: "group123"
        ├── initiatorId: "userA"
        ├── status: "ringing"
        ├── invitedParticipants: [userB, userC]
        ├── joinedParticipants: [userA]
        └── createdAt: Timestamp
        
        
groupCallInvitations/                      ← Created by caller (1 per user)
  ├── {invitation1}                         ← For userB
  │     ├── callId: "callId"
  │     ├── groupId: "group123"
  │     ├── inviterId: "userA"
  │     ├── targetUserId: "userB"           ← Receiver listens for this!
  │     ├── status: "pending"               ← Query filters for this!
  │     ├── createdAt: Timestamp
  │     └── expiresAt: Timestamp (now + 1min)
  │     
  └── {invitation2}                         ← For userC
        ├── callId: "callId"
        ├── targetUserId: "userC"
        └── status: "pending"


REAL-TIME LISTENER (Device B):
┌────────────────────────────────────────────┐
│ Query: groupCallInvitations                │
│   .where('targetUserId', '==', 'userB')   │  ← Exact match required!
│   .where('status', '==', 'pending')       │  ← Lowercase!
│   .snapshots()                             │
└────────────────────────────────────────────┘
```

---

## WIDGET TREE

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              APP WIDGET TREE                              │
└──────────────────────────────────────────────────────────────────────────┘

MaterialApp                               ← Provides context for dialogs
  │
  └─ home: SignalTestWidget
       │
       └─ IncomingGroupCallListener      ← ✅ GLOBAL LISTENER (Phase 1.1)
            │                             ← Wraps entire app
            │                             ← Listens for invitations
            │                             ← Shows incoming call dialog
            │
            └─ IncomingCallListener        ← 1-to-1 call listener
                 │
                 └─ ModChatSplashScreen / AuthGate
                      │
                      └─ HomeScreen / ChatScreen / etc.


LISTENER FLOW:

IncomingGroupCallListener
  │
  ├─ StreamBuilder
  │    │
  │    └─ stream: listenToIncomingGroupCallInvitations()
  │         │
  │         └─ Firestore query:
  │              collection('groupCallInvitations')
  │              .where('targetUserId', '==', currentUserId)
  │              .where('status', '==', 'pending')
  │
  ├─ On snapshot received:
  │    │
  │    └─ For each doc:
  │         │
  │         └─ _handleInvitation(context, doc)
  │              │
  │              ├─ Parse GroupCallInvitation.fromFirestore(doc)
  │              ├─ Check duplicate protection
  │              ├─ Check expiration
  │              │
  │              └─ showDialog(
  │                   context: context,
  │                   builder: (ctx) => IncomingGroupCallDialog(
  │                     invitation: invitation,
  │                     onDismiss: () { ... }
  │                   )
  │                 )
  │
  └─ Return widget.child                  ← App continues normally
```

---

## LOGGING FLOW

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         CONSOLE LOG SEQUENCE                              │
└──────────────────────────────────────────────────────────────────────────┘

DEVICE A (Caller)                          DEVICE B (Receiver)
─────────────────                          ───────────────────

[APP START]                                [APP START]
                                           │
                                           ↓
                                           [GROUP_SIGNAL] 👂 Listening for invitations -> userB

[USER TAPS START CALL]
│
↓
[GROUP_SIGNAL] 📞 Starting group call
[GROUP_SIGNAL] 👥 Group: group123
[GROUP_SIGNAL] 🎤 Initiator: userA
│
↓
[GROUP_SIGNAL] Creating 2 invitation documents
│
├─► [GROUP_SIGNAL] 🔔 Creating invitation for userB
│   [GROUP_SIGNAL] ✅ Invitation created
│                                          ↓
│                                          [FIRESTORE REAL-TIME UPDATE]
│                                          │
│                                          ↓
│                                          [GROUP_SIGNAL] 📡 Stream update
│                                          [GROUP_SIGNAL]    hasData: true
│                                          [GROUP_SIGNAL]    docCount: 1
│                                          │
│                                          ↓
│                                          [GROUP_SIGNAL] 🎯 Processing invitation
│                                          [GROUP_SIGNAL] ✉️ callId=abc123
│                                          [GROUP_SIGNAL]    target=userB
│                                          │
│                                          ↓
│                                          [GROUP_SIGNAL] ✅ SHOWING DIALOG
│                                          │
│                                          ↓
│                                          [DIALOG APPEARS ON SCREEN]
│                                          User sees: 📞 Family calling...
│
└─► [GROUP_SIGNAL] 🔔 Creating invitation for userC
    [GROUP_SIGNAL] ✅ Invitation created
│
↓
[GROUP_SIGNAL] ROOM_CREATED: abc123
[GROUP_SIGNAL] ✅ Call setup complete
│
↓
[Navigate to GroupAudioCallScreen]
                                           [USER TAPS ACCEPT]
                                           │
                                           ↓
                                           [GROUP_SIGNAL] User accepting
                                           [GROUP_SIGNAL] Updating invitation
                                           [GROUP_SIGNAL] Joining call
                                           │
                                           ↓
                                           [Navigate to GroupAudioCallScreen]
                                           [GroupCallController] 🎤 Initializing
                                           [GroupCallController] 🔗 Creating peer connections
```

---

## FAILURE POINTS

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     WHERE SIGNALING CAN FAIL                              │
└──────────────────────────────────────────────────────────────────────────┘

Point 1: INVITATION CREATION FAILURE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Caller: startGroupAudioCall()
  ↓
  _createInvitations() ❌ FAILS
  │
  └─ Causes:
       • invitedUserIds array is empty
       • Firestore write permission denied
       • Network error
       
  └─ Symptoms:
       • No logs: "Invitation created"
       • Firestore collection empty


Point 2: LISTENER NOT STARTING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IncomingGroupCallListener builds
  ↓
  currentUserId == null ❌ FAILS
  │
  └─ Causes:
       • User not logged in
       • Widget mounted before auth completes
       
  └─ Symptoms:
       • No logs: "Listening for invitations"
       • Stream never fires


Point 3: STREAM NOT FIRING
━━━━━━━━━━━━━━━━━━━━━━━━━━
Firestore query:
  .where('targetUserId', '==', 'userB')
  .where('status', '==', 'pending')
  ↓
  No matching documents ❌ FAILS
  │
  └─ Causes:
       • Query field names don't match document
       • Status value mismatch (case-sensitive)
       • Firestore rules deny read
       
  └─ Symptoms:
       • Logs: "Stream update - hasData: false"
       • Or no stream logs at all


Point 4: DIALOG NOT SHOWING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
_handleInvitation() receives doc
  ↓
  showDialog() ❌ FAILS
  │
  └─ Causes:
       • Already shown (duplicate protection)
       • Invitation expired (> 1 minute)
       • Invalid context
       • Dialog widget missing
       
  └─ Symptoms:
       • Logs: "⚠️ Already shown" or "⚠️ Expired"
       • Stream fires but no dialog


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DIAGNOSIS STRATEGY:

Add logs at each point:

[1] After _createInvitations(): "✅ Invitation created"
[2] On listener start: "👂 Listening for invitations"
[3] On stream update: "📡 Stream update - hasData: true"
[4] Before showDialog(): "✅ SHOWING DIALOG"

Missing log = failure point found!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## QUERY MATCHING VISUALIZATION

```
┌──────────────────────────────────────────────────────────────────────────┐
│                  FIRESTORE QUERY MATCHING LOGIC                           │
└──────────────────────────────────────────────────────────────────────────┘

QUERY (What receiver is looking for):
┌────────────────────────────────────┐
│ collection: groupCallInvitations   │
│ where: targetUserId == 'userB'     │  ← Must match EXACTLY
│ where: status == 'pending'         │  ← Must match EXACTLY (lowercase!)
└────────────────────────────────────┘

DOCUMENT (What caller created):
┌────────────────────────────────────┐
│ callId: "abc123"                   │
│ groupId: "group789"                │
│ inviterId: "userA"                 │
│ targetUserId: "userB"              │  ← ✅ MATCHES query!
│ status: "pending"                  │  ← ✅ MATCHES query! (lowercase)
│ createdAt: Timestamp               │
│ expiresAt: Timestamp               │
└────────────────────────────────────┘

RESULT: ✅ MATCH! Document returned in snapshot.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

COMMON MISMATCH SCENARIOS:

❌ Wrong field name:
   Query:    targetUserId == 'userB'
   Document: userId: 'userB'          ← Field name doesn't match!
   Result:   No documents returned

❌ Wrong case:
   Query:    status == 'pending'
   Document: status: 'Pending'        ← Capital P!
   Result:   No documents returned

❌ Wrong user:
   Query:    targetUserId == 'userB'
   Document: targetUserId: 'userC'    ← Different user!
   Result:   No documents returned (correct behavior)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## FIRESTORE RULES VISUALIZATION

```
┌──────────────────────────────────────────────────────────────────────────┐
│                       FIRESTORE RULES FLOW                                │
└──────────────────────────────────────────────────────────────────────────┘

USER READS INVITATION:
┌─────────────────────────────────────────────┐
│ User B reads: groupCallInvitations/inv123   │
│ Request: GET                                │
│ Auth: userB                                 │
└─────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────┐
│ FIRESTORE RULES CHECK:                      │
│                                             │
│ allow read: if isTargetUser()               │
│   ↓                                         │
│   Check: resource.data.targetUserId         │
│           == request.auth.uid               │
│   ↓                                         │
│   resource.data.targetUserId = "userB"      │
│   request.auth.uid = "userB"                │
│   ↓                                         │
│   "userB" == "userB" ✅ TRUE                │
└─────────────────────────────────────────────┘
         │
         ↓
    ✅ ALLOWED
    Document returned


WRONG USER TRIES TO READ:
┌─────────────────────────────────────────────┐
│ User C reads: groupCallInvitations/inv123   │
│ (invitation is for User B)                  │
└─────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────┐
│ FIRESTORE RULES CHECK:                      │
│                                             │
│ resource.data.targetUserId = "userB"        │
│ request.auth.uid = "userC"                  │
│ ↓                                           │
│ "userB" == "userC" ❌ FALSE                 │
└─────────────────────────────────────────────┘
         │
         ↓
    ❌ DENIED
    Permission error (silent in UI, shows in console)
```

---

## TIMING DIAGRAM

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    CALL INITIATION TIMELINE                               │
└──────────────────────────────────────────────────────────────────────────┘

Time  Device A (Caller)                     Device B (Receiver)
────  ─────────────────                     ───────────────────
T=0s  User taps "Start Call"               (Waiting, listener active)
      │
T=1s  Create groupCalls doc                (Still waiting...)
      │
T=2s  Create invitation docs               (Still waiting...)
      ├─► invitation for userB
      │   Written to Firestore ────────────┐
      │                                     │
T=3s  Open call screen                     │ Firestore propagates...
      (Hears ringing tone)                  │
                                            ↓
T=4s                                       Listener receives snapshot!
                                           │
                                           ↓
T=5s                                       Parse invitation
                                           │
                                           ↓
T=6s                                       Dialog appears 🎉
                                           User sees incoming call!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EXPECTED DELAY: 2-6 seconds (Firestore real-time is near-instant)

IF DELAY > 10 SECONDS:
  • Check network connectivity
  • Check Firestore region/latency
  • Check for query performance issues

IF NO DIALOG EVER APPEARS:
  • Signaling is broken (use diagnostic guide)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## SUMMARY

**Signaling works when**:
1. ✅ Invitations created with correct field names
2. ✅ Receiver listener starts (user logged in)
3. ✅ Query matches document fields exactly
4. ✅ Firestore rules allow read
5. ✅ Invitation not expired
6. ✅ Dialog widget exists and context is valid

**Debug by**:
- Adding 3 log statements (see testing guide)
- Testing with 2 devices
- Comparing logs to expected flow above
- Finding which step fails
- Using diagnostic guide to fix

**Visual Aids**:
- Use this document as reference
- Follow the arrows to understand flow
- Compare your logs to "CONSOLE LOG SEQUENCE"
- Match your Firestore docs to "DATA FLOW DIAGRAM"

---

**Status**: VISUAL REFERENCE READY  
**Use With**: `TEST_GROUP_CALL_SIGNALING.md` and `GROUP_CALL_SIGNALING_DIAGNOSTIC.md`
