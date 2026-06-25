# Phase 3: Video Calling - Architecture Diagrams

## 🎯 System Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    PHASE 3: VIDEO CALLING                    │
│                  Extends Phase 2 Architecture                │
└──────────────────────────────────────────────────────────────┘
                              ↓
                    ┌─────────────────┐
                    │  Single System  │
                    │  Two Call Types │
                    └─────────────────┘
                              ↓
                  ┌──────────┴──────────┐
                  ↓                     ↓
            Voice Calls            Video Calls
            (Phase 2)              (Phase 3)
            audio: true            audio: true
            video: false           video: true
```

---

## 🏗️ Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       UI LAYER                               │
├─────────────────────────┬───────────────────────────────────┤
│   CallScreen (Voice)    │   VideoCallScreen (Video)         │
│   - Avatar              │   - Remote Video (full screen)    │
│   - Status text         │   - Local Preview (floating)      │
│   - Mute/Speaker        │   - Mute/Camera/Switch            │
│   - End call            │   - End call                      │
└─────────────────────────┴───────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              CALLCONTROLLER (Unified)                        │
├─────────────────────────────────────────────────────────────┤
│  Constructor Parameters:                                    │
│    - callId: String                                         │
│    - isInitiator: bool                                      │
│    - isVideoCall: bool ← NEW                                │
│                                                             │
│  Components (Conditional):                                  │
│    if (isVideoCall):                                        │
│      - localRenderer: RTCVideoRenderer                      │
│      - remoteRenderer: RTCVideoRenderer                     │
│      - toggleCamera()                                       │
│      - switchCamera()                                       │
│                                                             │
│  Shared Components:                                         │
│    - _peerConnection: RTCPeerConnection                     │
│    - _localStream: MediaStream                              │
│    - _remoteStream: MediaStream                             │
│    - toggleMute()                                           │
│    - toggleSpeaker()                                        │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                 WEBRTC MEDIA LAYER                           │
├─────────────────────────────────────────────────────────────┤
│  Voice Mode:                │  Video Mode:                  │
│  ┌────────────────┐         │  ┌────────────────────────┐  │
│  │ Audio Track    │         │  │ Audio Track            │  │
│  │ (Microphone)   │         │  │ (Microphone)           │  │
│  └────────────────┘         │  └────────────────────────┘  │
│                             │  ┌────────────────────────┐  │
│                             │  │ Video Track            │  │
│                             │  │ (Camera - 720p)        │  │
│                             │  └────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              FIRESTORE SIGNALING LAYER                       │
├─────────────────────────────────────────────────────────────┤
│  calls/{callId}                                             │
│  {                                                          │
│    "type": "voice" | "video",  ← NEW FIELD                 │
│    "status": "calling" | "ringing" | "accepted" | ...,     │
│    "offer": { sdp, type },                                 │
│    "answer": { sdp, type },                                │
│    "iceCandidates": [...]                                  │
│  }                                                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔄 Call Flow Comparison

### Voice Call Flow (Phase 2 - Existing)

```
User A                                    User B
  │                                         │
  │ Presses Voice Call Button              │
  │────────────────────────────────────────▶│
  │                                         │
  │ CallService.startVoiceCall()           │
  │   type: "voice"                        │
  │                                         │
  │ Opens CallScreen                        │
  │ ┌─────────────┐                        │
  │ │   Avatar    │                        │
  │ │   Status    │                        │
  │ │   Controls  │                        │
  │ └─────────────┘                        │
  │                                         │
  │ CallController(isVideoCall: false)     │
  │   audio: true, video: false            │
  │                                         │
  │◄────────────────────────────────────────│
  │        Incoming Voice Call Popup        │
  │                                         │
  │        Receiver Accepts                 │
  │◄────────────────────────────────────────│
  │                                         │
  │       Audio Stream Connected            │
  │◄───────────────────────────────────────▶│
  │                                         │
  🎧 Earpiece Audio        🎧 Earpiece Audio
```

### Video Call Flow (Phase 3 - New)

```
User A                                    User B
  │                                         │
  │ Presses Video Call Button              │
  │────────────────────────────────────────▶│
  │                                         │
  │ CallService.startVideoCall()           │
  │   type: "video"                        │
  │                                         │
  │ Opens VideoCallScreen                  │
  │ ┌─────────────────────────┐            │
  │ │ Remote Video (waiting)  │            │
  │ │          ┌────┐         │            │
  │ │          │ Me │         │            │
  │ │          └────┘         │            │
  │ │    [M] [C] [S] [E]     │            │
  │ └─────────────────────────┘            │
  │                                         │
  │ CallController(isVideoCall: true)      │
  │   audio: true, video: true             │
  │   Initialize video renderers           │
  │                                         │
  │◄────────────────────────────────────────│
  │        Incoming Video Call Popup        │
  │                                         │
  │        Receiver Accepts                 │
  │◄────────────────────────────────────────│
  │                                         │
  │ Opens VideoCallScreen                  │
  │                   ┌─────────────────────┐
  │                   │ Remote Video        │
  │                   │ (User A)   ┌────┐  │
  │                   │            │ Me │  │
  │                   │            └────┘  │
  │                   │    [M] [C] [S] [E] │
  │                   └─────────────────────┘
  │                                         │
  │   Audio + Video Streams Connected       │
  │◄───────────────────────────────────────▶│
  │                                         │
  📹 See Each Other's Video 📹
  🎧 Hear Each Other's Audio 🎧
```

---

## 🎨 VideoCallScreen Layout

```
┌─────────────────────────────────────────┐ ◄─ SafeArea Top
│                                         │
│                                         │
│                                         │
│          REMOTE VIDEO STREAM            │
│          (RTCVideoView)                 │
│          Full Screen Background         │
│          objectFit: cover               │
│                                         │
│                          ┌──────────┐   │ ◄─ 16px from top
│                          │  LOCAL   │   │    16px from right
│                          │  PREVIEW │   │    120x160
│                          │(RTCVideo)│   │    Rounded: 12px
│                          │  Mirror  │   │    Z-index: high
│                          └──────────┘   │
│                                         │
│                                         │
│                                         │
│         ┌──┐  ┌──┐  ┌──┐  ┌───┐       │
│         │🎤│  │📷│  │🔄│  │ X │       │ ◄─ 50px from bottom
│         └──┘  └──┘  └──┘  └───┘       │    Centered
│         56x56 56x56 56x56 72x72        │    Spacing: 24px
│                                         │
└─────────────────────────────────────────┘ ◄─ SafeArea Bottom

Legend:
🎤 = Mute/Unmute (green when muted)
📷 = Camera On/Off (green when off)
🔄 = Switch Camera (front ↔ back)
X  = End Call (red)
```

---

## 🔌 Media Stream Flow

### Voice Call (Phase 2)

```
getUserMedia({ audio: true, video: false })
           ↓
    ┌─────────────┐
    │MediaStream  │
    │ - audioTrack│
    └──────┬──────┘
           │
           ↓
    addTrack(audioTrack)
           ↓
    RTCPeerConnection
           ↓
    offer/answer/ICE
           ↓
    Remote receives audioTrack
           ↓
    onTrack event
           ↓
    Play audio through
    earpiece/speaker
```

### Video Call (Phase 3)

```
getUserMedia({ audio: true, video: true })
           ↓
    ┌─────────────┐
    │MediaStream  │
    │ - audioTrack│
    │ - videoTrack│
    └──────┬──────┘
           │
           ├─────────────────┐
           │                 │
           ↓                 ↓
    addTrack(audio)   addTrack(video)
           │                 │
           └────────┬────────┘
                    ↓
            RTCPeerConnection
                    ↓
            offer/answer/ICE
                    ↓
    Remote receives audio + video
                    ↓
              onTrack event
                    ↓
           ┌────────┴────────┐
           ↓                 ↓
    Play audio        Render video
    (earpiece)      (RTCVideoView)
```

---

## 🎮 Control Button States

```
┌────────────────────────────────────────────────────────┐
│                 CONTROL STATES                         │
├────────────┬─────────────┬─────────────┬──────────────┤
│   Button   │   Default   │   Active    │     Icon     │
├────────────┼─────────────┼─────────────┼──────────────┤
│   Mute     │   Dark      │   Green     │  🎤 / 🎤̸    │
│            │   Unmuted   │   Muted     │              │
├────────────┼─────────────┼─────────────┼──────────────┤
│  Camera    │   Dark      │   Green     │  📷 / 📷̸    │
│            │   On        │   Off       │              │
├────────────┼─────────────┼─────────────┼──────────────┤
│  Switch    │   Dark      │   N/A       │  🔄          │
│  Camera    │   Always    │   (no toggle│              │
│            │   Available │    state)   │              │
├────────────┼─────────────┼─────────────┼──────────────┤
│  End Call  │   Red       │   N/A       │  ☎️̸          │
│            │   Always    │             │              │
└────────────┴─────────────┴─────────────┴──────────────┘

Colors:
- Dark:  #1C2630 (inactive)
- Green: #34C759 (active/enabled)
- Red:   #FF3B30 (end call)
```

---

## 🔄 Camera Switching Mechanism

```
┌──────────────────────────────────────────────────────┐
│            CAMERA SWITCHING FLOW                     │
└──────────────────────────────────────────────────────┘

User Presses Switch Button
           ↓
    switchCamera()
           ↓
    Get current video track
           ↓
    Helper.switchCamera(videoTrack)
           ↓
    WebRTC switches camera source
    (NO peer connection reset)
           ↓
    Update UI state: _isFrontCamera
           ↓
    Update mirror state for preview
           ↓
    ┌──────────┴───────────┐
    ↓                      ↓
Front Camera          Back Camera
mirror: true          mirror: false
```

---

## 🧹 Cleanup Sequence

```
Call Ends (User presses End or timeout)
                ↓
         endCall() called
                ↓
┌───────────────────────────────────────┐
│         CLEANUP SEQUENCE              │
├───────────────────────────────────────┤
│ 1. Stop Video Tracks                 │
│    localStream.getVideoTracks()      │
│      .forEach(track => track.stop()) │
│                                       │
│ 2. Stop Audio Tracks                 │
│    localStream.getAudioTracks()      │
│      .forEach(track => track.stop()) │
│                                       │
│ 3. Dispose Local Renderer             │
│    await localRenderer?.dispose()    │
│                                       │
│ 4. Dispose Remote Renderer            │
│    await remoteRenderer?.dispose()   │
│                                       │
│ 5. Dispose Streams                    │
│    await localStream?.dispose()      │
│    await remoteStream?.dispose()     │
│                                       │
│ 6. Close Peer Connection              │
│    await peerConnection?.close()     │
│    await peerConnection?.dispose()   │
│                                       │
│ 7. Cancel Firestore Listeners         │
│    await callDocListener?.cancel()   │
│    await iceCandListener?.cancel()   │
└───────────────────────────────────────┘
                ↓
         Resources Released
         Camera/Mic Available
         No Memory Leaks
```

---

## 📊 State Machine (Unchanged)

```
┌─────────────────────────────────────────────────────┐
│     CALL STATE MACHINE (Voice + Video Shared)       │
└─────────────────────────────────────────────────────┘

    calling
       │
       ↓
    ringing ──────────────┐
       │                  │
       ├──────┐           │ (30s timeout)
       ↓      ↓           ↓
   accepted  declined   missed
       │
       ↓
     ended

Terminal States: declined, missed, ended, cancelled, failed
Active States: calling, ringing, accepted

Note: Video and voice calls use IDENTICAL state machine
Only difference: UI rendered (CallScreen vs VideoCallScreen)
```

---

**Architecture Status:** ✅ COMPLETE  
**Ready for Implementation:** PENDING APPROVAL

