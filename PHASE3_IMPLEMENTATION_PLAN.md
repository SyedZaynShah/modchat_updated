# Phase 3: Video Calling - Implementation Plan

**Status:** Specification Complete, Awaiting Approval  
**Created:** 2026-06-20

---

## 📋 SPECIFICATION SUMMARY

### Documents Created
1. ✅ **PHASE3_VIDEO_CALLING_SPEC.md** - Technical specification
2. ✅ **PHASE3_ARCHITECTURE_DIAGRAM.md** - Visual architecture
3. ✅ **PHASE3_IMPLEMENTATION_PLAN.md** - This document

### What Phase 3 Adds
- 1-to-1 video calling (720p @ 30fps target)
- Camera controls (toggle on/off, switch front/back)
- Video call UI (full-screen remote, floating local preview)
- Unified CallController (supports both voice and video)
- Call type field in Firestore (`"voice"` | `"video"`)

### What Phase 3 Preserves
- ✅ All existing voice call functionality
- ✅ Firestore signaling architecture (offer/answer/ICE)
- ✅ Call state machine (calling/ringing/accepted/ended)
- ✅ Timeout handling
- ✅ Resource cleanup patterns
- ✅ Audio routing (earpiece/speaker)

---

## 🗂️ FILES TO BE MODIFIED

### New Files (3 files)
```
lib/screens/chat/video_call_screen.dart           (UI for video calls)
PHASE3_VIDEO_IMPLEMENTATION.md                    (Technical documentation)
PHASE3_TESTING_GUIDE.md                           (Testing procedures)
```

### Modified Files (6 files)
```
lib/services/call_controller.dart                 (Add video support)
lib/services/call_service.dart                    (Add startVideoCall)
lib/screens/chat/chat_detail_screen.dart          (Add video button)
lib/screens/chat/incoming_call_screen.dart        (Show call type)
lib/widgets/incoming_call_listener.dart           (Route by type)
firebase/firestore.rules                          (Validate type field)
```

### Unchanged Files (Preserved)
```
lib/screens/chat/call_screen.dart                 (Voice call UI)
lib/models/call_state.dart                        (Shared states)
lib/providers/call_providers.dart                 (Existing providers)
lib/widgets/call_status_overlay.dart              (Terminal states)
```

**Total:** 3 new + 6 modified = **9 files affected**

---

## 🚀 IMPLEMENTATION PHASES

### Phase 3.1: Core Video Stream Support (2-3 hours)
**Goal:** Enable video in CallController

**Tasks:**
- [ ] Add `isVideoCall` parameter to CallController constructor
- [ ] Update `_getLocalStream()` with video constraints
- [ ] Add `localRenderer` and `remoteRenderer` properties
- [ ] Initialize renderers in `initialize()` method
- [ ] Update offer/answer to include video
- [ ] Attach video tracks in `onTrack` callback
- [ ] Test: Local video stream acquired
- [ ] Test: Remote video stream received

**Files:** `call_controller.dart`

---

### Phase 3.2: Video Call UI (3-4 hours)
**Goal:** Create VideoCallScreen with premium layout

**Tasks:**
- [ ] Create `video_call_screen.dart` file
- [ ] Implement full-screen remote video (RTCVideoView)
- [ ] Implement floating local preview (top-right)
- [ ] Add bottom control buttons (mute, camera, switch, end)
- [ ] Add call state handling (calling/ringing/accepted)
- [ ] Add call duration timer
- [ ] Style controls (WhatsApp/FaceTime standard)
- [ ] Test: UI renders correctly on multiple screen sizes

**Files:** `video_call_screen.dart` (new)

---

### Phase 3.3: Camera Controls (2-3 hours)
**Goal:** Implement camera toggle and switching

**Tasks:**
- [ ] Add `toggleCamera()` method to CallController
- [ ] Add `switchCamera()` method to CallController
- [ ] Wire camera toggle button in VideoCallScreen
- [ ] Wire switch camera button in VideoCallScreen
- [ ] Handle camera off state (show placeholder)
- [ ] Update mirror state for front camera
- [ ] Test: Camera toggle works
- [ ] Test: Camera switching works without reconnection

**Files:** `call_controller.dart`, `video_call_screen.dart`

---

### Phase 3.4: Call Service Integration (2-3 hours)
**Goal:** Support video call type throughout system

**Tasks:**
- [ ] Add `startVideoCall()` method to CallService
- [ ] Update call creation to accept `type` parameter
- [ ] Add video call button to chat detail screen
- [ ] Update incoming call popup to show call type
- [ ] Update IncomingCallListener to route by type
- [ ] Update Firestore rules for type field
- [ ] Test: Video calls create correct Firestore document
- [ ] Test: Incoming video calls route to VideoCallScreen

**Files:** `call_service.dart`, `chat_detail_screen.dart`, `incoming_call_screen.dart`, `incoming_call_listener.dart`, `firestore.rules`

---

### Phase 3.5: Cleanup & Polish (2-3 hours)
**Goal:** Ensure quality and stability

**Tasks:**
- [ ] Verify renderer disposal on call end
- [ ] Verify track stopping on call end
- [ ] Run memory profiler (check for leaks)
- [ ] Add camera permission error handling
- [ ] Add loading states during connection
- [ ] Polish animations and transitions
- [ ] Test regression: Voice calls work unchanged
- [ ] Test: No memory leaks after 10+ calls

**Files:** `call_controller.dart`, `video_call_screen.dart`

---

### Phase 3.6: Documentation (1-2 hours)
**Goal:** Document implementation

**Tasks:**
- [ ] Create PHASE3_VIDEO_IMPLEMENTATION.md
- [ ] Create PHASE3_TESTING_GUIDE.md
- [ ] Update README.md with video features
- [ ] Document camera control APIs
- [ ] Document video quality settings

**Files:** Documentation files

---

## 📊 ESTIMATED TIMELINE

| Phase | Tasks | Time | Priority |
|-------|-------|------|----------|
| 3.1   | Core Video | 2-3 hours | MUST HAVE |
| 3.2   | Video UI | 3-4 hours | MUST HAVE |
| 3.3   | Camera Controls | 2-3 hours | SHOULD HAVE |
| 3.4   | Integration | 2-3 hours | MUST HAVE |
| 3.5   | Polish | 2-3 hours | SHOULD HAVE |
| 3.6   | Documentation | 1-2 hours | NICE TO HAVE |
| **TOTAL** | **All Phases** | **12-18 hours** | - |

**Recommended approach:** Implement over 2-3 days, testing after each phase.

---

## ✅ TESTING STRATEGY

### After Phase 3.1 (Core)
- [ ] Local video stream displays in debug UI
- [ ] Remote video stream received
- [ ] No crashes on video initialization

### After Phase 3.2 (UI)
- [ ] VideoCallScreen renders correctly
- [ ] Remote video fills screen
- [ ] Local preview positioned correctly
- [ ] Controls visible and styled

### After Phase 3.3 (Controls)
- [ ] Camera toggle works
- [ ] Camera switch works
- [ ] Mute works during video call

### After Phase 3.4 (Integration)
- [ ] Video call button appears in chat
- [ ] Video calls create correct Firestore doc
- [ ] Incoming video calls route correctly
- [ ] **Voice calls still work** (regression test)

### After Phase 3.5 (Polish)
- [ ] No memory leaks (profiler)
- [ ] Error handling works
- [ ] 10+ consecutive calls work
- [ ] Voice calls unchanged

---

## 🎯 SUCCESS CRITERIA

### Functional Requirements
- ✅ Users can initiate video calls
- ✅ Both users see each other's video
- ✅ Audio works during video calls
- ✅ Camera can toggle on/off
- ✅ Camera can switch front/back
- ✅ Call states work correctly
- ✅ Cleanup works properly

### Quality Requirements
- ✅ Premium UI (FaceTime/WhatsApp standard)
- ✅ No memory leaks
- ✅ Proper error handling
- ✅ No regressions in voice calls
- ✅ Cross-platform (Android + iOS)

### Performance Requirements
- ✅ Video quality: 720p @ 30fps target
- ✅ Acceptable latency (<500ms)
- ✅ No UI lag
- ✅ Battery drain acceptable

---

## 🚨 CRITICAL RULES

### During Implementation

**DO:**
- ✅ Test voice calls after each change
- ✅ Use memory profiler regularly
- ✅ Dispose resources in correct order
- ✅ Handle permission denials gracefully
- ✅ Test on real devices (not just emulator)

**DON'T:**
- ❌ Break existing voice call functionality
- ❌ Create separate VideoCallController
- ❌ Duplicate signaling logic
- ❌ Skip cleanup verification
- ❌ Ignore memory leaks

---

## 🔒 RISK MITIGATION

### High Risk: Breaking Voice Calls
**Mitigation:**
- Test voice calls after every change
- Keep voice and video logic separated
- Use feature flags if needed

### High Risk: Memory Leaks
**Mitigation:**
- Profile memory after each phase
- Verify renderer disposal
- Test 10+ consecutive calls

### Medium Risk: iOS Camera Issues
**Mitigation:**
- Test on iOS device early
- Document platform differences
- Add platform-specific handling

---

## 📚 REFERENCE DOCUMENTS

### Specification
- `PHASE3_VIDEO_CALLING_SPEC.md` - Technical requirements
- `PHASE3_ARCHITECTURE_DIAGRAM.md` - Visual architecture

### Phase 2 Reference (Voice Calls)
- `PHASE2_WEBRTC_IMPLEMENTATION.md` - Existing implementation
- `PHASE2_TESTING_GUIDE.md` - Testing procedures
- `lib/services/call_controller.dart` - Current controller

### flutter_webrtc
- [Package Documentation](https://pub.dev/packages/flutter_webrtc)
- [Camera Switching API](https://github.com/flutter-webrtc/flutter-webrtc/wiki)
- [Video Rendering](https://pub.dev/documentation/flutter_webrtc/latest/)

---

## 🎬 GETTING STARTED

### Prerequisites
- ✅ Phase 2 voice calling stable and tested
- ✅ All Phase 2 features working (audio, timeout, cleanup)
- ✅ No known bugs in Phase 2
- ✅ Specification approved

### Step 1: Review Specification
1. Read `PHASE3_VIDEO_CALLING_SPEC.md` thoroughly
2. Review `PHASE3_ARCHITECTURE_DIAGRAM.md`
3. Ask questions if anything unclear
4. Get specification approved

### Step 2: Set Up Environment
1. Ensure flutter_webrtc is up to date
2. Test camera permissions on device
3. Set up memory profiler
4. Create feature branch: `feature/phase3-video-calling`

### Step 3: Begin Implementation
1. Start with Phase 3.1 (Core Video)
2. Test after each phase
3. Commit frequently
4. Document as you go

---

## ✅ APPROVAL CHECKLIST

Before proceeding with implementation:

- [ ] Specification reviewed and approved
- [ ] Architecture understood
- [ ] Files to modify identified
- [ ] Timeline acceptable
- [ ] Testing strategy agreed
- [ ] Success criteria clear
- [ ] Phase 2 confirmed stable

---

## 🚦 STATUS

**Specification:** ✅ COMPLETE  
**Architecture:** ✅ COMPLETE  
**Implementation Plan:** ✅ COMPLETE  
**Approval:** ⏳ PENDING  
**Implementation:** ⏸️ NOT STARTED

---

**Ready to begin implementation upon approval.**

