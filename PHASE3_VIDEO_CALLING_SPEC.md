# Phase 3: Video Calling - Technical Specification

**Status:** Specification Phase  
**Version:** 1.0  
**Date:** 2026-06-20  
**Dependencies:** Phase 2 Voice Calling (Complete ✅)

---

## 🎯 GOALS

### Primary Objectives
1. **Extend** existing Phase 2 voice calling system to support video
2. **Add** premium 1-to-1 video calling comparable to WhatsApp/FaceTime
3. **Reuse** existing Firestore signaling architecture (no redesign)
4. **Preserve** existing voice call functionality (zero regressions)
5. **Maintain** single unified call system (no duplication)

### Success Criteria
- ✅ Users can initiate video calls
- ✅ Both users see each other's video
- ✅ Audio continues to work during video calls
- ✅ Camera can be toggled on/off
- ✅ Camera can switch front/back
- ✅ Existing voice calls continue working unchanged
- ✅ No performance regressions
- ✅ Clean resource management

---

## 🏗️ ARCHITECTURE

### Core Principle: Unified Call System

```
SINGLE CallController
        ↓
    Supports TWO modes:
        ↓
    ┌───────┴───────┐
    ↓               ↓
Voice Mode      Video Mode
audio: true     audio: true
video: false    video: true
```

**Why Single Controller:**
- Reuses proven signaling logic
- Shares state management
- Avoids code duplication
- Simplifies Phase 4 (group calls)
- Reduces maintenance burden

### Architecture Layers

```
┌─────────────────────────────────────────┐
│           UI Layer                      │
│  ┌──────────────┐  ┌─────────────────┐ │
│  │ CallScreen   │  │ VideoCallScreen │ │
│  │ (Voice)      │  │ (Video)         │ │
│  └──────┬───────┘  └────────┬────────┘ │
└─────────┼──────────────────┼───────────┘
          │                  │
          └────────┬─────────┘
                   ↓
┌─────────────────────────────────────────┐
│      CallController (Unified)           │
│  - Media constraints (voice/video)      │
│  - Video renderers (when video mode)    │
│  - Camera controls (when video mode)    │
│  - Reuses: signaling, state, cleanup    │
└─────────────────┬───────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│      Firestore Signaling Layer          │
│  - offer/answer (unchanged)             │
│  - ICE candidates (unchanged)           │
│  - status (unchanged)                   │
│  - type: "voice" | "video" (NEW)        │
└─────────────────┬───────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│         WebRTC Media Layer              │
│  - Audio tracks (both modes)            │
│  - Video tracks (video mode only)       │
│  - Peer connection (shared)             │
└─────────────────────────────────────────┘
```

---

## 🗄️ FIRESTORE SCHEMA CHANGES

### Current Schema (Phase 2)
```javascript
calls/{callId}
{
  "callerId": "string",
  "callerName": "string",
  "receiverId": "string",
  "type": "voice",  // ← Always "voice"
  "status": "calling" | "ringing" | "accepted" | ...,
  "createdAt": Timestamp,
  "answeredAt": Timestamp?,
  "endedAt": Timestamp?,
  "offer": { "type": string, "sdp": string },
  "answer": { "type": string, "sdp": string },
  "iceCandidates": Array<ICECandidate>
}
```

### Phase 3 Schema (Enhanced)
```javascript
calls/{callId}
{
  "callerId": "string",
  "callerName": "string",
  "receiverId": "string",
  "type": "voice" | "video",  // ← NEW: Determines media type
  "status": "calling" | "ringing" | "accepted" | ...,
  "createdAt": Timestamp,
  "answeredAt": Timestamp?,
  "endedAt": Timestamp?,
  "offer": { "type": string, "sdp": string },
  "answer": { "type": string, "sdp": string },
  "iceCandidates": Array<ICECandidate>
}
```

**Changes:**
- ✅ `type` field now accepts `"voice"` OR `"video"`
- ✅ All other fields remain unchanged
- ✅ Signaling logic unchanged
- ✅ Backwards compatible (existing voice calls use `type: "voice"`)

**No Additional Fields Required:**
- Video negotiation happens via SDP in offer/answer
- Video tracks communicated through existing ICE flow
- No separate video-specific metadata needed

---

## 🎨 UI DESIGN

### VideoCallScreen Layout

```
┌─────────────────────────────────────────┐
│                                         │
│                                         │
│          Remote Video Stream            │
│          (Full Screen)                  │
│                                         │
│                          ┌──────────┐   │
│                          │  Local   │   │
│                          │  Preview │   │
│                          └──────────┘   │
│                                         │
│                                         │
│         ┌─┐  ┌─┐  ┌─┐  ┌──┐           │
│         │M│  │C│  │S│  │E │           │
│         └─┘  └─┘  └─┘  └──┘           │
└─────────────────────────────────────────┘

M = Mute/Unmute | C = Camera On/Off | S = Switch Camera | E = End Call
```

**Design Specifications:**

**Remote Video:**
- Full screen background
- Covers entire screen (with SafeArea)
- Uses `RTCVideoView` widget
- Scales to fill (aspect ratio maintained)
- Black background when no video

**Local Preview:**
- Floating overlay (top-right corner)
- Size: 120x160 (portrait aspect)
- Rounded corners (12px radius)
- Positioned: 16px from top, 16px from right
- Shows local camera feed
- Mirror effect for front camera
- Draggable: NOT required in Phase 3

**Bottom Controls:**
- Centered horizontally
- 50px from bottom
- 4 circular buttons
- Spacing: 24px between buttons
- Button size: 56x56
- Active state: Green (#34C759)
- Inactive state: Dark (#1C2630)
- End call button: Red (#FF3B30), 72x72

**Visual Quality:**
- Premium feel (FaceTime/WhatsApp standard)
- Smooth transitions
- No lag in UI responsiveness
- Dark theme consistent with CallScreen

---

## 🎥 MEDIA FLOW

### Stream Acquisition

**Voice Call (Existing):**
```dart
mediaConstraints = {
  'audio': true,
  'video': false,
}
```

**Video Call (New):**
```dart
mediaConstraints = {
  'audio': true,
  'video': {
    'facingMode': 'user',  // Front camera default
    'width': { 'ideal': 1280 },
    'height': { 'ideal': 720 },
    'frameRate': { 'ideal': 30 },
  },
}
```

**Fallback Strategy:**
- Try 720p @ 30fps first
- Auto-fallback to lower resolutions if unsupported
- Maintain aspect ratio
- Never crash on constraint failure

### Renderer Initialization

**Create Renderers:**
```dart
final RTCVideoRenderer localRenderer = RTCVideoRenderer();
final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

await localRenderer.initialize();
await remoteRenderer.initialize();
```

**Lifecycle:**
1. Create before acquiring media stream
2. Initialize before attaching stream
3. Dispose when call ends
4. Re-create for each new call (no reuse)

### Track Attachment

**Local Stream:**
```dart
localRenderer.srcObject = _localStream;
```

**Remote Stream:**
```dart
_peerConnection.onTrack = (RTCTrackEvent event) {
  if (event.streams.isNotEmpty) {
    remoteRenderer.srcObject = event.streams[0];
  }
};
```

**Track Types:**
- Audio tracks: Always present (both modes)
- Video tracks: Only in video mode


### Video Rendering

**RTCVideoView Widget:**
```dart
RTCVideoView(
  remoteRenderer,
  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
  mirror: false,  // Don't mirror remote
)

RTCVideoView(
  localRenderer,
  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
  mirror: true,  // Mirror local preview (front camera)
)
```

---

## 🔐 PERMISSIONS

### Android Permissions (Required)

**Already Present:**
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

**Permission Flow:**
1. Request CAMERA permission on video call initiation
2. If granted → proceed with video call
3. If denied → show error, fall back to voice call option

**Error Handling:**
```dart
try {
  localStream = await getUserMedia(constraints);
} catch (e) {
  if (e is PermissionDeniedError) {
    // Show: "Camera permission required for video calls"
    // Offer: "Switch to voice call" button
  }
}
```

**Permission States:**
- Granted: Proceed normally
- Denied: Show error + voice call fallback
- Permanently denied: Direct to app settings

---

## 📊 STATE MANAGEMENT

### Reuse Existing Call States

```dart
enum CallState {
  calling,
  ringing,
  accepted,
  declined,
  missed,
  cancelled,
  ended,
  failed,
}
```

**No New States Required:**
- Voice and video share the same state machine
- State transitions identical for both types
- Timeout logic unchanged
- Terminal states unchanged

**Call Type Determines UI Only:**
- `type: "voice"` → Open `CallScreen`
- `type: "video"` → Open `VideoCallScreen`
- State management remains identical

---

## 🧹 CLEANUP LIFECYCLE

### Resource Disposal Order

**When Call Ends:**
```
1. Stop video tracks
   - localStream.getVideoTracks().forEach(track => track.stop())
   - remoteStream.getVideoTracks().forEach(track => track.stop())

2. Stop audio tracks
   - localStream.getAudioTracks().forEach(track => track.stop())
   - remoteStream.getAudioTracks().forEach(track => track.stop())

3. Dispose renderers
   - await localRenderer.dispose()
   - await remoteRenderer.dispose()

4. Dispose streams
   - await localStream.dispose()
   - await remoteStream.dispose()

5. Close peer connection
   - await peerConnection.close()
   - await peerConnection.dispose()

6. Cancel Firestore listeners
   - await callDocListener.cancel()
   - await iceCandidatesListener.cancel()
```

**Critical Rules:**
- ✅ Stop tracks BEFORE disposing streams
- ✅ Dispose renderers BEFORE closing peer connection
- ✅ Cancel listeners LAST
- ✅ No memory leaks
- ✅ Microphone/camera released for other apps

**Disposal Verification:**
```dart
assert(_localStream == null);
assert(_remoteStream == null);
assert(_peerConnection == null);
assert(_callDocListener == null);
```

---

## 🎮 CAMERA CONTROLS

### Toggle Camera On/Off

**Implementation:**
```dart
bool _isCameraEnabled = true;

void toggleCamera() {
  _isCameraEnabled = !_isCameraEnabled;
  
  localStream.getVideoTracks().forEach((track) {
    track.enabled = _isCameraEnabled;
  });
  
  // UI updates automatically
}
```

**UI Behavior:**
- Camera OFF: Show placeholder (user avatar or black screen)
- Camera ON: Show live video feed
- Remote user sees your camera state
- Button turns green when camera OFF (like mute)

### Switch Camera (Front ↔ Back)

**Implementation:**
```dart
Future<void> switchCamera() async {
  final videoTrack = localStream.getVideoTracks().first;
  await Helper.switchCamera(videoTrack);
  
  // Mirror state update
  setState(() {
    _isFrontCamera = !_isFrontCamera;
  });
}
```

**Requirements:**
- Must work without reconnecting call
- No interruption to remote user
- Smooth transition (no black screen)
- Update mirror state for local preview


**Edge Cases:**
- Device has no front camera → disable switch button
- Device has no back camera → disable switch button
- Single camera device → hide switch button

### Mute Audio (Existing)

**Unchanged from Phase 2:**
```dart
void toggleMute() {
  _isMuted = !_isMuted;
  
  localStream.getAudioTracks().forEach((track) {
    track.enabled = !_isMuted;
  });
}
```

**Audio works in video calls exactly as in voice calls.**

---

## ✅ TESTING CHECKLIST

### Phase 3.1: Core Video Streaming
- [ ] Caller can initiate video call
- [ ] Receiver sees video call notification
- [ ] Caller sees local preview on call screen
- [ ] Receiver sees local preview after accepting
- [ ] Caller sees receiver's video after connection
- [ ] Receiver sees caller's video after connection
- [ ] Video quality acceptable (720p target)
- [ ] Audio works during video call
- [ ] No echo in audio

### Phase 3.2: Video UI
- [ ] Remote video fills screen properly
- [ ] Local preview positioned correctly (top-right)
- [ ] Local preview aspect ratio maintained
- [ ] Control buttons visible and responsive
- [ ] Call duration counter works
- [ ] Status text updates correctly
- [ ] Terminal states display properly
- [ ] No layout issues on different screen sizes

### Phase 3.3: Camera Controls
- [ ] Camera toggle works (on/off)
- [ ] Camera off shows placeholder
- [ ] Remote user sees camera state
- [ ] Switch camera works (front ↔ back)
- [ ] Switch maintains connection
- [ ] Mirror state updates correctly
- [ ] Mute works during video call
- [ ] All controls responsive

### Phase 3.4: Regression Testing
- [ ] **Voice calls still work** (CRITICAL)
- [ ] Voice call UI unchanged
- [ ] Voice call audio quality unchanged
- [ ] Call states work for both types
- [ ] Timeout works for both types
- [ ] Cleanup works for both types
- [ ] No performance degradation

### Phase 3.5: Error Handling
- [ ] Camera permission denied → graceful error
- [ ] No camera available → error message
- [ ] Network failure → proper cleanup
- [ ] Call decline works
- [ ] Call timeout works
- [ ] End call cleanup complete
- [ ] No crashes on edge cases

### Phase 3.6: Platform Testing
- [ ] Android: Video works
- [ ] Android: Camera switching works
- [ ] Android: Permissions flow works
- [ ] iOS: Video works (needs testing)
- [ ] iOS: Camera switching works (needs testing)
- [ ] iOS: Permissions flow works (needs testing)

---

## 🚀 IMPLEMENTATION BREAKDOWN

### Phase 3.1: Core Video Stream Support ⭐ START HERE

**Goal:** Get basic video streaming working between two users

**Success Criterion:**
- ✅ Caller sees receiver's video
- ✅ Receiver sees caller's video
- ✅ Audio still works
- ✅ No UI polish needed yet

**What to Implement:**
1. Camera permission handling
2. Local camera stream acquisition
3. Remote camera stream reception
4. Video renderer setup
5. Video stream attachment

**What NOT to Implement:**
- ❌ Premium UI (use simple debug layout)
- ❌ Camera switching
- ❌ Camera toggle
- ❌ Animations
- ❌ Polish

**Tasks:**
1. Add `isVideoCall` parameter to CallController
2. Update `_getLocalStream()` to use video constraints when video mode
3. Add `localRenderer` and `remoteRenderer` properties
4. Initialize renderers in `initialize()` method
5. Attach local stream to local renderer
6. Update offer/answer constraints for video
7. Attach remote stream in `onTrack` callback
8. Create simple VideoCallScreen (basic RTCVideoView only)
9. Test: Caller sees receiver video
10. Test: Receiver sees caller video
11. Test: Audio still works

**Files Modified:**
- `lib/services/call_controller.dart`
- `lib/screens/chat/video_call_screen.dart` (new - minimal)

**Estimated Time:** 2-3 hours

**Why This Order:**
If video doesn't render, you'll know it's WebRTC/media issue, not UI/controls/permissions confusion.

---

### Phase 3.2: Video Call UI ⏸️ AFTER 3.1 WORKS

**Goal:** Create premium VideoCallScreen layout

**Prerequisites:** Phase 3.1 working (video visible on both sides)

**Tasks:**
1. Redesign VideoCallScreen with proper layout
2. Full-screen remote video (RTCVideoView)
3. Floating local preview (top-right)
4. Bottom control buttons (styled)
5. Call state handling
6. Call duration timer
7. Premium styling (WhatsApp/FaceTime standard)

**Files:** `video_call_screen.dart`

**Estimated Time:** 3-4 hours

---

### Phase 3.3: Camera Controls ⏸️ AFTER 3.2 COMPLETE

**Goal:** Implement camera toggle and switching

**Prerequisites:** Phase 3.2 working (premium UI complete)

**Tasks:**
1. Add `toggleCamera()` method
2. Add `switchCamera()` method
3. Wire up buttons
4. Handle camera off state
5. Test controls

**Files:** `call_controller.dart`, `video_call_screen.dart`

**Estimated Time:** 2-3 hours

---

### Phase 3.4: Integration & Polish ⏸️ FINAL PHASE


**Tasks:**
1. Add `startVideoCall()` method to CallService
2. Update call creation to accept `type` parameter
3. Add video call button to chat screen
4. Update incoming call popup to show call type
5. Route to correct screen based on call type
6. Test: Video calls create correct Firestore doc
7. Test: Incoming video calls route correctly

**Files Modified:**
- `lib/services/call_service.dart`
- `lib/screens/chat/chat_detail_screen.dart`
- `lib/screens/chat/incoming_call_screen.dart`
- `lib/widgets/incoming_call_listener.dart`

**Estimated Time:** 2-3 hours

---

### Phase 3.5: Cleanup & Polish

**Goal:** Ensure proper resource management and polish

**Tasks:**
1. Verify renderer disposal on call end
2. Verify track stopping on call end
3. Test memory leaks (profiler)
4. Add error handling for permission denial
5. Add loading states
6. Polish animations and transitions
7. Test regression: Voice calls still work
8. Test: No memory leaks

**Files Modified:**
- `lib/services/call_controller.dart`
- `lib/screens/chat/video_call_screen.dart`

**Estimated Time:** 2-3 hours

---

### Phase 3.6: Documentation

**Goal:** Document Phase 3 implementation

**Tasks:**
1. Create `PHASE3_VIDEO_IMPLEMENTATION.md`
2. Create `PHASE3_TESTING_GUIDE.md`
3. Update `README.md` with video call features
4. Document camera control APIs
5. Document video quality settings

**Files Created:**
- `PHASE3_VIDEO_IMPLEMENTATION.md`
- `PHASE3_TESTING_GUIDE.md`

**Estimated Time:** 1-2 hours

---

## 📋 TOTAL IMPLEMENTATION ESTIMATE

**Total Time:** 12-18 hours (spread across phases)

**Phase Priority:**
1. Phase 3.1 (Core) - MUST HAVE
2. Phase 3.2 (UI) - MUST HAVE
3. Phase 3.4 (Integration) - MUST HAVE
4. Phase 3.3 (Controls) - SHOULD HAVE
5. Phase 3.5 (Polish) - SHOULD HAVE
6. Phase 3.6 (Docs) - NICE TO HAVE

---

## 📦 FILES TO BE MODIFIED

### New Files (Created)
```
lib/screens/chat/video_call_screen.dart
PHASE3_VIDEO_IMPLEMENTATION.md
PHASE3_TESTING_GUIDE.md
```

### Existing Files (Modified)
```
lib/services/call_controller.dart
  - Add isVideoCall parameter
  - Add video constraints
  - Add video renderers
  - Add camera controls
  - Update cleanup for video

lib/services/call_service.dart
  - Add startVideoCall() method
  - Update call creation with type parameter

lib/screens/chat/chat_detail_screen.dart
  - Add video call button next to voice call button

lib/screens/chat/incoming_call_screen.dart
  - Show call type (voice/video) in popup
  - Update accept flow for video calls

lib/widgets/incoming_call_listener.dart
  - Route to VideoCallScreen for video calls
  - Route to CallScreen for voice calls

lib/models/call_state.dart
  - No changes (reused as-is)

firebase/firestore.rules
  - Verify type field validation
  - Ensure accepts "voice" | "video"
```

### No Changes Required
```
lib/screens/chat/call_screen.dart (voice call UI)
lib/providers/call_providers.dart
lib/widgets/call_status_overlay.dart
```

**Total Files:**
- **3 new files**
- **6 modified files**
- **3 unchanged files**

---

## 🎯 IMPLEMENTATION ORDER

### Recommended Sequence

**Step 1: CallController Enhancement**
```
1. Add isVideoCall flag
2. Update media constraints
3. Add renderer initialization
4. Test with simple debug UI
```

**Step 2: CallService Integration**
```
1. Add startVideoCall() method
2. Update Firestore creation with type
3. Test Firestore document creation
```

**Step 3: VideoCallScreen UI**
```
1. Create basic layout
2. Add RTCVideoView widgets
3. Add control buttons (non-functional)
4. Test layout on different screens
```

**Step 4: Connect UI to Controller**
```
1. Wire CallController to VideoCallScreen
2. Attach renderers to video views
3. Wire button callbacks
4. Test end-to-end video call
```

**Step 5: Camera Controls**
```
1. Implement toggle camera
2. Implement switch camera
3. Wire to UI buttons
4. Test controls
```

**Step 6: Integration & Routing**
```
1. Add video call button to chat
2. Update incoming call routing
3. Test both call types
4. Verify no regressions
```

**Step 7: Polish & Cleanup**
```
1. Error handling
2. Loading states
3. Animations
4. Memory profiling
5. Documentation
```

---

## 🎨 ARCHITECTURE DIAGRAM

```
┌─────────────────────────────────────────────────────────────┐
│                      USER INITIATES CALL                    │
│                  (Voice Button | Video Button)              │
└────────────────────────────┬────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │  CallService    │
                    │  startVoiceCall │
                    │  startVideoCall │
                    └────────┬────────┘
                             │
                    ┌────────▼────────────────────┐
                    │ Create Firestore Document   │
                    │   type: "voice" | "video"   │
                    │   status: "calling"         │
                    └────────┬────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
        type="voice"                  type="video"
              │                             │
              ▼                             ▼
    ┌─────────────────┐         ┌──────────────────────┐
    │  CallScreen     │         │  VideoCallScreen     │
    │  (Existing)     │         │  (New)               │
    └────────┬────────┘         └──────────┬───────────┘
             │                             │
             └──────────────┬──────────────┘
                            │
                   ┌────────▼──────────┐
                   │  CallController   │
                   │  (Enhanced)       │
                   │                   │
                   │  if (isVideoCall) │
                   │    video: true    │
                   │    renderers      │
                   │  else             │
                   │    video: false   │
                   └────────┬──────────┘
                            │
                   ┌────────▼──────────┐
                   │  WebRTC Media     │
                   │  - Audio tracks   │
                   │  - Video tracks   │
                   │  - Peer conn      │
                   └────────┬──────────┘
                            │
                   ┌────────▼──────────┐
                   │  Firestore        │
                   │  - Signaling      │
                   │  - State sync     │
                   └───────────────────┘
```

---

## 🔒 RISK ASSESSMENT

### Low Risk ✅
- Media constraint changes (well-documented)
- UI layout (isolated component)
- Renderer lifecycle (clear API)
- Camera controls (flutter_webrtc supports)

### Medium Risk ⚠️
- Video quality on low-end devices
- Memory usage with video rendering
- iOS camera permission flow (needs testing)
- Battery drain during video calls

### High Risk 🔴
- Breaking existing voice calls (MUST TEST)
- Memory leaks from renderer disposal
- Race conditions in renderer initialization
- Platform-specific camera switching bugs

### Mitigation Strategies

**For High Risks:**
1. Comprehensive regression testing
2. Memory profiler analysis
3. Renderer disposal verification
4. Test on multiple devices

**For Medium Risks:**
1. Adaptive quality settings
2. Monitor memory usage
3. iOS testing plan
4. Battery profiling

---

## 📝 ACCEPTANCE CRITERIA

### Phase 3 Complete When:

**Core Functionality:**
- ✅ Video calls can be initiated
- ✅ Both users see each other's video
- ✅ Audio works during video calls
- ✅ Video quality acceptable (720p target)
- ✅ Call duration displays correctly

**Camera Controls:**
- ✅ Camera can be toggled on/off
- ✅ Camera can switch front/back
- ✅ Remote user sees camera state
- ✅ Controls are responsive

**Regression Testing:**
- ✅ Voice calls work unchanged
- ✅ Call states work for both types
- ✅ Timeout works for both types
- ✅ Cleanup works for both types
- ✅ No performance degradation

**Quality:**
- ✅ Premium UI (FaceTime standard)
- ✅ No memory leaks
- ✅ Proper error handling
- ✅ Cross-platform support (Android + iOS)

---

## 🎓 TECHNICAL NOTES

### Why Single CallController?

**Advantages:**
- Reuses proven signaling logic (offer/answer/ICE)
- Shares state management (calling/ringing/accepted)
- Avoids code duplication
- Simplifies testing (one system to test)
- Easier maintenance (one place to fix bugs)
- Prepares for Phase 4 (group calls need unified system)

**Implementation:**
```dart
class CallController {
  final bool isVideoCall;
  
  RTCVideoRenderer? localRenderer;  // null if voice
  RTCVideoRenderer? remoteRenderer; // null if voice
  
  Future<void> _getLocalStream() {
    if (isVideoCall) {
      // Get audio + video
    } else {
      // Get audio only
    }
  }
}
```

### Video Quality Trade-offs

**Target: 720p @ 30fps**
- Good balance of quality and bandwidth
- Works on most 4G connections
- Acceptable battery drain
- Comparable to WhatsApp/FaceTime

**Fallback Strategy:**
- Auto-reduce if bandwidth insufficient
- Maintain aspect ratio
- Never crash on constraint failure

### Renderer Memory Management

**Critical:**
- Create → Initialize → Attach → Dispose
- Never reuse renderers across calls
- Always dispose in correct order
- Monitor for memory leaks

---

## 📚 REFERENCES

### flutter_webrtc Documentation
- [Video Rendering](https://pub.dev/packages/flutter_webrtc)
- [Camera Switching](https://github.com/flutter-webrtc/flutter-webrtc/wiki)
- [Helper APIs](https://pub.dev/documentation/flutter_webrtc/latest/)

### WebRTC Standards
- [getUserMedia Constraints](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia)
- [RTCPeerConnection](https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection)
- [Video Constraints](https://w3c.github.io/mediacapture-main/#def-constraint-facingMode)

---

## ✅ SPECIFICATION STATUS

**Status:** ✅ COMPLETE  
**Ready for Review:** YES  
**Ready for Implementation:** PENDING APPROVAL

---

## 🚦 NEXT STEPS

1. **Review this specification**
2. **Approve or request changes**
3. **Proceed with implementation** (Phase 3.1 → 3.6)

---

**END OF SPECIFICATION**

