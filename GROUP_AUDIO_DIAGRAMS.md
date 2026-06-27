# GROUP AUDIO CALLING - VISUAL DIAGRAMS

## Quick Reference Visual Guide

---

## 📊 CALL LIFECYCLE DIAGRAM

```
┌─────────────────────────────────────────────────────────────────────┐
│                        GROUP AUDIO CALL FLOW                        │
└─────────────────────────────────────────────────────────────────────┘

        HOST                    FIRESTORE                  PARTICIPANTS
         │                          │                            │
         │ 1. startGroupAudioCall() │                            │
         ├─────────────────────────>│                            │
         │                          │                            │
         │    groupCalls/{callId}   │                            │
         │    status: "ringing"     │                            │
         │    joinedParticipants:   │                            │
         │      [host_uid]          │                            │
         │    invitedParticipants:  │                            │
         │      [user2, user3...]   │                            │
         │                          │                            │
         │                          │ 2. Push Invitations        │
         │                          │    (one per participant)   │
         │                          ├───────────────────────────>│
         │                          │                            │
         │                          │   groupCallInvitations/    │
         │                          │     {invitationId}         │
         │                          │     targetUserId: user2    │
         │                          │     status: "pending"      │
         │                          │                            │
         │                          │ 3. User Accepts            │
         │                          <────────────────────────────┤
         │                          │   acceptInvitation()       │
         │                          │                            │
         │                          │ 4. Update Call             │
         │                          │   status: "active"         │
         │<─────────────────────────┤   joinedParticipants:      │
         │                          │     [host_uid, user2]      │
         │                          │   invitedParticipants:     │
         │                          │     [user3...]             │
         │                          │                            │
         │ 5. WebRTC Setup          │                            │
         │    - Create peers        │                            │
         │    - Exchange SDP        │                            │
         │    - Collect ICE         │                            │
         ├◄────────────────────────►┼◄───────────────────────────►
         │                          │                            │
         │    peerConnections/      │                            │
         │      host_user2/         │                            │
         │        offer: {...}      │                            │
         │        answer: {...}     │                            │
         │        iceCandidates     │                            │
         │                          │                            │
         │ 6. Direct P2P Audio      │                            │
         ├◄─────────────────────────┼─────────────────────────────►
         │    Audio streams         │    (Firestore only for    │
         │    bypass Firestore      │     signaling, not data)   │
         │                          │                            │
         │ 7. Speaking Detection    │                            │
         │    speakingParticipants: │                            │
         │      [host_uid]          │                            │
         ├─────────────────────────>│                            │
         │<─────────────────────────┤                            │
         │                          │                            │
         │ 8. User Leaves           │                            │
         │                          <────────────────────────────┤
         │                          │   leaveGroupCall()         │
         │                          │                            │
         │                          │   joinedParticipants:      │
         │                          │     [host_uid]             │
         │<─────────────────────────┤   leftParticipants:        │
         │                          │     [user2]                │
         │                          │                            │
         │ 9. Host Ends Call        │                            │
         ├─────────────────────────>│                            │
         │    endGroupCall()        │                            │
         │                          │                            │
         │                          │   status: "ended"          │
         │                          │   joinedParticipants: []   │
         │                          │   endedAt: timestamp       │
         │<─────────────────────────┼────────────────────────────┤
         │                          │                            │
         │   All peer connections   │                            │
         │   closed                 │                            │
         │                          │                            │
```

---

## 🕸️ WEBRTC MESH TOPOLOGY

### 2 Participants (Simple)

```
    Alice ↔ Bob
    
Total connections: 1
Alice maintains: 1 peer connection (to Bob)
Bob maintains: 1 peer connection (to Alice)
```

### 3 Participants

```
       Alice
        / \
       /   \
      /     \
    Bob ← → Charlie
    
Total connections: 3
Alice maintains: 2 peer connections (Bob, Charlie)
Bob maintains: 2 peer connections (Alice, Charlie)
Charlie maintains: 2 peer connections (Alice, Bob)
```

### 4 Participants (Full Mesh)

```
    Alice ↔ Bob
      ↕       ↕
  Charlie ↔ David
    
Total connections: 6
Each participant maintains: 3 peer connections
Connection pairs:
  - Alice ↔ Bob
  - Alice ↔ Charlie
  - Alice ↔ David
  - Bob ↔ Charlie
  - Bob ↔ David
  - Charlie ↔ David
```

### 8 Participants (Maximum)

```
         A ↔ B
        ↕ ✖ ↕
       C ↔ D ↔ E
        ↕ ✖ ↕ ✖ ↕
         F ↔ G ↔ H
    
Total connections: 28
Each participant maintains: 7 peer connections
Formula: N × (N-1) / 2 where N = 8
```

---

## 🗂️ FIRESTORE DATA STRUCTURE

```
firestore/
│
├── groupCalls/
│   │
│   └── {callId}/                          # Single call document
│       │
│       ├── type: "group_audio"            # Call type
│       ├── groupId: "group123"            # Parent group
│       ├── initiatorId: "alice_uid"       # Host
│       ├── status: "active"               # ringing | active | ended
│       │
│       ├── invitedParticipants: []        # Not yet responded
│       │   └── ["bob_uid", "charlie_uid"]
│       │
│       ├── joinedParticipants: []         # Currently in call
│       │   └── ["alice_uid", "david_uid"]
│       │
│       ├── declinedParticipants: []       # Declined invitation
│       │   └── ["eve_uid"]
│       │
│       ├── leftParticipants: []           # Left the call
│       │   └── ["frank_uid"]
│       │
│       ├── speakingParticipants: []       # Currently speaking
│       │   └── ["alice_uid"]
│       │
│       ├── maxParticipants: 8             # Limit enforced
│       │
│       ├── createdAt: Timestamp           # Call initiated
│       ├── startedAt: Timestamp           # First join
│       └── endedAt: Timestamp             # Call ended
│
│       └── peerConnections/               # WebRTC signaling
│           │
│           ├── alice_bob/                 # Sorted UIDs
│           │   ├── offer: {type, sdp}
│           │   ├── answer: {type, sdp}
│           │   ├── iceCandidates: [...]
│           │   ├── from: "alice_uid"
│           │   ├── to: "bob_uid"
│           │   └── createdAt: Timestamp
│           │
│           ├── alice_charlie/
│           │   └── ...
│           │
│           └── bob_charlie/
│               └── ...
│
└── groupCallInvitations/
    │
    ├── {invitationId_1}/                  # One per invited user
    │   ├── callId: "call123"
    │   ├── groupId: "group123"
    │   ├── inviterId: "alice_uid"
    │   ├── targetUserId: "bob_uid"        # Specific recipient
    │   ├── status: "pending"              # pending | accepted | declined
    │   ├── createdAt: Timestamp
    │   └── expiresAt: Timestamp           # Auto-expire after 1 min
    │
    ├── {invitationId_2}/
    │   └── targetUserId: "charlie_uid"
    │
    └── {invitationId_3}/
        └── targetUserId: "david_uid"
```

---

## 🎯 PARTICIPANT STATE MACHINE

```
                    ┌─────────────┐
                    │   INVITED   │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │                         │
              ▼                         ▼
       ┌─────────────┐           ┌─────────────┐
       │  DECLINED   │           │   JOINING   │
       └─────────────┘           └──────┬──────┘
                                        │
                                        ▼
                                 ┌─────────────┐
                                 │  CONNECTED  │
                                 └──────┬──────┘
                                        │
                           ┌────────────┼────────────┐
                           │            │            │
                           ▼            ▼            ▼
                    ┌─────────┐  ┌──────────┐  ┌────────┐
                    │  MUTED  │  │ SPEAKING │  │  LEFT  │
                    └─────────┘  └──────────┘  └────────┘
                           │            │
                           └────────────┘
                                  │
                                  ▼
                           ┌─────────────┐
                           │ RECONNECTING│
                           └──────┬──────┘
                                  │
                      ┌───────────┼───────────┐
                      ▼                       ▼
               ┌─────────────┐         ┌─────────┐
               │  CONNECTED  │         │ DROPPED │
               └─────────────┘         └─────────┘
```

---

## 🎨 UI COMPONENT HIERARCHY

```
GroupAudioCallScreen
│
├── Header
│   ├── Group Avatar (Icon)
│   ├── Group Name (Text)
│   └── Call Info (Duration • Participants)
│
├── Participant Grid (Scrollable)
│   ├── ParticipantTile (User 1 - Host)
│   │   ├── Avatar
│   │   ├── Speaking Border (Conditional)
│   │   ├── Name Label
│   │   └── Muted Icon (Conditional)
│   │
│   ├── ParticipantTile (User 2)
│   ├── ParticipantTile (User 3)
│   └── ...
│
└── Controls Panel
    ├── Control Buttons Row
    │   ├── Mute Button
    │   │   ├── Icon (mic / mic_off)
    │   │   └── Label
    │   └── Speaker Button
    │       ├── Icon (hearing / volume_up)
    │       └── Label
    │
    └── Leave Button (Full Width)
        ├── Icon (call_end)
        └── Text ("Leave Call" / "End Call")
```

---

## 📱 SCREEN FLOW DIAGRAM

```
┌──────────────────┐
│   Group Chat     │
│   [Call Button]  │
└────────┬─────────┘
         │
         │ Tap Call
         ▼
┌──────────────────┐
│  Starting Call   │
│  [Loading...]    │
└────────┬─────────┘
         │
         │ Auto
         ▼
┌──────────────────┐
│  Group Call      │◄─────┐
│  Screen          │      │
│  [Grid + Ctrls]  │      │
└────────┬─────────┘      │
         │                 │
         │ Leave           │ Rejoin
         ▼                 │
┌──────────────────┐      │
│   Group Chat     │      │
│ [Join Ongoing]   ├──────┘
└──────────────────┘


        PARTICIPANT FLOW:

┌──────────────────┐
│   Group Chat     │
│   [Normal UI]    │
└────────┬─────────┘
         │
         │ Invitation
         ▼
┌──────────────────┐
│  Incoming Call   │
│  Dialog          │
│  [Accept/Decline]│
└────────┬─────────┘
         │
    ┌────┼────┐
    │         │
 Decline    Accept
    │         │
    ▼         ▼
┌─────┐  ┌──────────────────┐
│Close│  │  Group Call      │
└─────┘  │  Screen          │
         │  [Grid + Ctrls]  │
         └──────────────────┘
```

---

## 🔐 SECURITY RULES LOGIC

```
groupCalls/{callId}

  ┌─────────────────────────────────────────┐
  │         PERMISSION CHECKS               │
  └─────────────────────────────────────────┘
  
  CREATE:
    ✓ User is authenticated
    ✓ User is initiator (initiatorId == auth.uid)
    ✓ User is group member
    ✓ Valid structure (all required fields)
    
  READ:
    ✓ User is authenticated
    ✓ User is involved (invited, joined, declined, left, or initiator)
    
  UPDATE:
    ✓ User is authenticated
    ✓ User is/will be involved
    ✓ groupId immutable
    ✓ initiatorId immutable
    ✓ joinedParticipants.length <= 8 ⚠️ ENFORCED
    
  DELETE:
    ✗ FORBIDDEN (preserve audit trail)


  peerConnections/{pairId}

    READ/WRITE:
      ✓ User is in call (joinedParticipants)
      ✓ User is in this pair (pairId contains auth.uid)
```

---

## ⚡ PERFORMANCE CHARACTERISTICS

```
┌─────────────────────────────────────────────────────────┐
│              SCALABILITY BY PARTICIPANT COUNT            │
└─────────────────────────────────────────────────────────┘

Participants    Connections/User    Total Connections    Quality
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    2                  1                     1            ★★★★★
    3                  2                     3            ★★★★★
    4                  3                     6            ★★★★★
    5                  4                    10            ★★★★☆
    6                  5                    15            ★★★★☆
    7                  6                    21            ★★★☆☆
    8                  7                    28            ★★★☆☆
    9+            NOT ALLOWED          LIMIT ENFORCED         ✗

Formula: Total = N × (N-1) / 2

Recommended: ≤ 6 participants for best quality
Maximum: 8 participants (hard limit)
Future (SFU): 50+ participants

┌─────────────────────────────────────────────────────────┐
│                  LATENCY EXPECTATIONS                    │
└─────────────────────────────────────────────────────────┘

Metric                    Target        Acceptable    Poor
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Call Setup Time           < 2s          < 5s          > 5s
Audio Latency (2 users)   < 200ms       < 500ms       > 1s
Audio Latency (8 users)   < 500ms       < 1s          > 2s
Speaking Detection        < 100ms       < 300ms       > 500ms
UI Update Frequency       60 FPS        30 FPS        < 30 FPS
```

---

## 🔄 ERROR RECOVERY FLOW

```
┌──────────────────┐
│  WebRTC Error    │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Is Recoverable?  │
└────────┬─────────┘
         │
    ┌────┼────┐
    │         │
   Yes        No
    │         │
    ▼         ▼
┌─────────┐  ┌──────────────────┐
│ Attempt │  │ Show Error       │
│ Reconnect│  │ Exit Call        │
└────┬────┘  └──────────────────┘
     │
     │ Retry (15s timeout)
     ▼
┌──────────────────┐
│  Connected?      │
└────────┬─────────┘
         │
    ┌────┼────┐
    │         │
   Yes        No
    │         │
    ▼         ▼
┌─────────┐  ┌──────────────────┐
│ Resume  │  │ Show "Network    │
│ Call    │  │  Issue" → Exit   │
└─────────┘  └──────────────────┘
```

---

## 📊 MONITORING DASHBOARD LAYOUT

```
┌─────────────────────────────────────────────────────────┐
│              GROUP AUDIO CALL METRICS                    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────┐  ┌─────────────────────┐
│  Active Calls       │  │  Total Participants │
│      12             │  │       48            │
└─────────────────────┘  └─────────────────────┘

┌─────────────────────┐  ┌─────────────────────┐
│  Avg Call Duration  │  │  Completion Rate    │
│    8:32             │  │      87%            │
└─────────────────────┘  └─────────────────────┘

┌──────────────────────────────────────────────┐
│         Calls by Participant Count           │
│                                              │
│  2 users: ████████░░░ 42%                   │
│  3 users: ██████░░░░░ 28%                   │
│  4 users: ████░░░░░░░ 18%                   │
│  5 users: ██░░░░░░░░░  8%                   │
│  6+ users: █░░░░░░░░░  4%                   │
└──────────────────────────────────────────────┘

┌──────────────────────────────────────────────┐
│           Quality Metrics                    │
│                                              │
│  Audio Quality:  ★★★★☆ 4.2/5                │
│  Connection:     ★★★★★ 4.8/5                │
│  UI Experience:  ★★★★☆ 4.3/5                │
└──────────────────────────────────────────────┘
```

---

## 🎯 QUICK REFERENCE CHEAT SHEET

```
┌─────────────────────────────────────────────────────────┐
│              GROUP AUDIO CALL CHEAT SHEET               │
└─────────────────────────────────────────────────────────┘

START CALL:
  groupCallService.startGroupAudioCall(groupId, initiatorId)
  → Returns callId
  → Creates groupCalls/{callId} with status "ringing"
  → Sends invitations to all group members

ACCEPT CALL:
  groupCallService.acceptInvitation(invitationId, callId)
  → Updates invitation status to "accepted"
  → Joins call (adds to joinedParticipants)
  → Status becomes "active"

DECLINE CALL:
  groupCallService.declineInvitation(invitationId, callId)
  → Updates invitation status to "declined"
  → Adds to declinedParticipants

LEAVE CALL:
  groupCallService.leaveGroupCall(callId, userId)
  → Removes from joinedParticipants
  → Adds to leftParticipants
  → Auto-ends if last participant

END CALL (HOST):
  groupCallService.endGroupCall(callId)
  → Sets status to "ended"
  → Clears joinedParticipants
  → Records endedAt timestamp

MUTE/UNMUTE:
  groupCallController.toggleMute(true/false)
  → Disables/enables local audio track
  → Updates UI immediately

SPEAKER TOGGLE:
  groupCallController.toggleSpeaker(true/false)
  → Routes audio to speaker/earpiece
  → Updates icon

SPEAKING DETECTION:
  Automatic via groupCallController
  → Updates speakingParticipants array
  → UI shows green glow on speaking tiles

LIMITS:
  Max Participants: 8 (enforced in Firestore rules)
  Max Connections: 28 (for 8 participants)
  Invitation Expiry: 1 minute
  Reconnection Timeout: 15 seconds

FIRESTORE PATHS:
  groupCalls/{callId}
  groupCalls/{callId}/peerConnections/{pairId}
  groupCallInvitations/{invitationId}
```

---

**Diagrams Version**: 1.0  
**Last Updated**: [Current Date]  
**Purpose**: Visual reference for Group Audio Calling architecture
