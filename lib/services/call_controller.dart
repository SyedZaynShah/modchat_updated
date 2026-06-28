import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'firestore_service.dart';

/// Media State Machine for production stability
enum MediaState {
  idle,           // Not initialized
  connecting,     // Getting media streams
  audioReady,     // Audio track acquired
  mediaReady,     // Audio + Video (if video call) ready
  connected,      // Peer connection established
  failed,         // Media acquisition failed
}

/// WebRTC Call Controller
/// Handles peer-to-peer audio/video streaming using Firestore for signaling
/// Supports both voice-only and video calls
class CallController {
  final String callId;
  final bool isInitiator; // true if caller, false if receiver
  final bool isVideoCall; // true if video call, false if voice only
  
  final FirestoreService _firestoreService = FirestoreService();
  
  // WebRTC components
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  // Video renderers (only used for video calls)
  RTCVideoRenderer? localRenderer;
  RTCVideoRenderer? remoteRenderer;
  
  // Firestore listeners
  StreamSubscription? _callDocListener;
  StreamSubscription? _iceCandidatesListener;
  
  // Callbacks
  Function(MediaStream)? onRemoteStream;
  Function(String)? onConnectionStateChange;
  Function(bool)? onReconnectionStateChange; // true = reconnecting, false = connected
  
  // State
  bool _isDisposed = false;
  bool _offerCreated = false;
  bool _answerCreated = false;
  
  // Reconnection state
  bool _isReconnecting = false;
  DateTime? _reconnectionStartTime;
  Timer? _reconnectionTimer;
  static const Duration _reconnectionTimeout = Duration(seconds: 15);
  
  // ICE candidate buffer (store candidates received before remote description is set)
  final List<RTCIceCandidate> _candidateBuffer = [];
  bool _remoteDescriptionSet = false;

  // PRODUCTION HARDENING: Media state machine
  MediaState _mediaState = MediaState.idle;
  bool _localRendererReady = false;
  bool _remoteRendererReady = false;
  bool _isSwitchingCamera = false; // Race condition guard

  CallController({
    required this.callId,
    required this.isInitiator,
    this.isVideoCall = false, // Default to voice call
    this.onRemoteStream,
    this.onConnectionStateChange,
    this.onReconnectionStateChange,
  });

  // PHASE 0.5: ECHO INVESTIGATION - Tracking initialization
  static int _initializeCallCount = 0;
  int _myInitializeCount = 0;

  /// Initialize WebRTC peer connection
  Future<void> initialize() async {
    if (_isDisposed) {
      print('[CallController] Already disposed, cannot initialize');
      return;
    }

    _initializeCallCount++;
    _myInitializeCount++;
    print('[ECHO_TEST] ========================================');
    print('[ECHO_TEST] INITIALIZE called (Global: $_initializeCallCount, This instance: $_myInitializeCount)');
    print('[ECHO_TEST] CallId: $callId');
    print('[ECHO_TEST] IsInitiator: $isInitiator');
    print('[ECHO_TEST] IsVideoCall: $isVideoCall');
    print('[ECHO_TEST] ========================================');

    try {
      print('[CallController] Initializing WebRTC for call: $callId (initiator: $isInitiator, video: $isVideoCall)');
      
      // Initialize video renderers if video call
      if (isVideoCall) {
        await _initializeRenderers();
      }
      
      // Get local media stream (audio or audio+video)
      await _getLocalStream();
      
      // Attach local stream to renderer if video call
      if (isVideoCall && localRenderer != null) {
        localRenderer!.srcObject = _localStream;
        print('[CallController] 📹 Local stream attached to renderer');
      }
      
      // Create peer connection
      await _createPeerConnection();
      
      // Set audio routing (earpiece for voice, speaker for video)
      if (isVideoCall) {
        await Helper.setSpeakerphoneOn(true); // Video calls use speaker by default
        print('[CallController] 🔊 Video call: Audio routed to SPEAKER');
      } else {
        await setEarpieceAudio(); // Voice calls use earpiece
      }
      
      // Start listening to Firestore for signaling
      _listenToCallDocument();
      _listenToIceCandidates();
      
      // If initiator (caller), create and send offer
      if (isInitiator) {
        await _createOffer();
      } else {
        // If receiver, wait for offer then create answer
        _waitForOfferAndCreateAnswer();
      }
      
      print('[CallController] WebRTC initialization complete');
    } catch (e) {
      print('[CallController] ERROR initializing: $e');
      rethrow;
    }
  }

  /// Initialize video renderers (video calls only)
  Future<void> _initializeRenderers() async {
    print('[CallController] ⏳ RENDERER_INIT_START: Initializing video renderers...');
    final startTime = DateTime.now();
    
    try {
      localRenderer = RTCVideoRenderer();
      remoteRenderer = RTCVideoRenderer();
      
      await localRenderer!.initialize();
      _localRendererReady = true;
      print('[CallController] ✅ RENDERER_INIT: Local renderer ready');
      
      await remoteRenderer!.initialize();
      _remoteRendererReady = true;
      print('[CallController] ✅ RENDERER_INIT: Remote renderer ready');
      
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      print('[CallController] ✅ RENDERER_INIT_COMPLETE: Both renderers initialized in ${duration}ms');
    } catch (e) {
      _mediaState = MediaState.failed;
      print('[CallController] ❌ RENDERER_INIT_ERROR: $e');
      rethrow;
    }
  }

  /// Get local media stream (audio or audio+video)
  Future<void> _getLocalStream() async {
    print('[CallController] ⏳ MEDIA_ACQUISITION_START: Getting local media stream (video: $isVideoCall)...');
    _mediaState = MediaState.connecting;
    final startTime = DateTime.now();
    
    final Map<String, dynamic> mediaConstraints = isVideoCall
        ? {
            'audio': true,
            'video': {
              'facingMode': 'user', // Front camera default
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
              'frameRate': {'ideal': 30},
            },
          }
        : {
            'audio': true,
            'video': false,
          };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      print('[CallController] ✅ MEDIA_ACQUIRED: Local stream acquired in ${duration}ms: ${_localStream?.id}');
      
      final audioTracks = _localStream?.getAudioTracks().length ?? 0;
      final videoTracks = _localStream?.getVideoTracks().length ?? 0;
      
      print('[CallController] 📊 TRACK_COUNT: Audio=$audioTracks, Video=$videoTracks');
      
      // PHASE 0.5: ECHO INVESTIGATION
      print('[ECHO_TEST] ========================================');
      print('[ECHO_TEST] LOCAL STREAM ACQUIRED');
      print('[ECHO_TEST] Stream ID: ${_localStream?.id}');
      print('[ECHO_TEST] Local audio tracks: $audioTracks');
      print('[ECHO_TEST] Local video tracks: $videoTracks');
      if (audioTracks > 0) {
        final track = _localStream!.getAudioTracks().first;
        print('[ECHO_TEST] Audio track ID: ${track.id}');
        print('[ECHO_TEST] Audio track enabled: ${track.enabled}');
      }
      print('[ECHO_TEST] ========================================');
      
      if (audioTracks > 0) {
        _mediaState = MediaState.audioReady;
        print('[CallController] ✅ MEDIA_STATE: audioReady');
      }
      
      if (isVideoCall) {
        if (videoTracks > 0) {
          _mediaState = MediaState.mediaReady;
          print('[CallController] ✅ MEDIA_STATE: mediaReady (audio + video)');
        } else {
          print('[CallController] ⚠️ MEDIA_WARNING: Video call but no video tracks!');
        }
      } else if (audioTracks > 0) {
        _mediaState = MediaState.mediaReady;
        print('[CallController] ✅ MEDIA_STATE: mediaReady (audio only)');
      }
    } catch (e) {
      _mediaState = MediaState.failed;
      print('[CallController] ❌ MEDIA_ACQUISITION_ERROR: $e');
      rethrow;
    }
  }

  /// Create RTCPeerConnection with STUN server
  Future<void> _createPeerConnection() async {
    print('[CallController] Creating peer connection...');
    
    final Map<String, dynamic> configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

    final Map<String, dynamic> constraints = {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    };

    _peerConnection = await createPeerConnection(configuration, constraints);
    print('[CallController] Peer connection created');

    // Add local stream tracks to peer connection
    if (_localStream != null) {
      final tracks = _localStream!.getTracks();
      print('[ECHO_TEST] ========================================');
      print('[ECHO_TEST] ADDING LOCAL TRACKS TO PEER CONNECTION');
      print('[ECHO_TEST] Total tracks to add: ${tracks.length}');
      
      int addTrackCount = 0;
      tracks.forEach((track) {
        addTrackCount++;
        print('[ECHO_TEST] addTrack() call #$addTrackCount - Track kind: ${track.kind}, ID: ${track.id}, enabled: ${track.enabled}');
        _peerConnection!.addTrack(track, _localStream!);
      });
      
      print('[ECHO_TEST] Total addTrack() calls: $addTrackCount');
      print('[ECHO_TEST] ========================================');
      print('[CallController] Local tracks added to peer connection');
    }

    // Handle ICE candidates
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        print('[CallController] New ICE candidate: ${candidate.candidate}');
        _sendIceCandidate(candidate);
      }
    };

    // Handle remote stream
    // PHASE 0.5: ECHO INVESTIGATION - Tracking onTrack callbacks
    int onTrackCallCount = 0;
    final Set<String> seenStreamIds = {};
    final Set<String> seenTrackIds = {};
    int rendererAssignmentCount = 0;
    int callbackInvocationCount = 0;
    
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      onTrackCallCount++;
      print('[ECHO_TEST] ========================================');
      print('[ECHO_TEST] ONTRACK FIRED #$onTrackCallCount');
      print('[ECHO_TEST] Track kind: ${event.track.kind}');
      print('[ECHO_TEST] Track ID: ${event.track.id ?? "null"}');
      print('[ECHO_TEST] Track enabled: ${event.track.enabled}');
      print('[ECHO_TEST] Number of streams in event: ${event.streams.length}');
      
      final trackId = event.track.id ?? 'unknown-${DateTime.now().millisecondsSinceEpoch}';
      if (seenTrackIds.contains(trackId)) {
        print('[ECHO_TEST] ⚠️ WARNING: Track ID $trackId seen before!');
      } else {
        seenTrackIds.add(trackId);
        print('[ECHO_TEST] ✅ New track ID (total unique tracks: ${seenTrackIds.length})');
      }
      
      print('[CallController] 🎯 TRACK_RECEIVED: ${event.track.kind} track (ID: ${event.track.id}, enabled: ${event.track.enabled})');
      if (event.streams.isNotEmpty) {
        final streamId = event.streams[0].id;
        
        print('[ECHO_TEST] Stream ID: $streamId');
        if (seenStreamIds.contains(streamId)) {
          print('[ECHO_TEST] ⚠️ WARNING: Stream ID $streamId seen before!');
        } else {
          seenStreamIds.add(streamId);
          print('[ECHO_TEST] ✅ New stream ID (total unique streams: ${seenStreamIds.length})');
        }
        
        _remoteStream = event.streams[0];
        
        final audioTracks = _remoteStream!.getAudioTracks().length;
        final videoTracks = _remoteStream!.getVideoTracks().length;
        print('[ECHO_TEST] Remote audio tracks: $audioTracks');
        print('[ECHO_TEST] Remote video tracks: $videoTracks');
        
        print('[CallController] 📡 REMOTE_STREAM: Stream received (ID: ${_remoteStream?.id})');
        
        // Attach remote stream to renderer if video call
        if (isVideoCall && remoteRenderer != null && _remoteRendererReady) {
          rendererAssignmentCount++;
          print('[ECHO_TEST] RENDERER ASSIGNMENT #$rendererAssignmentCount');
          print('[ECHO_TEST] Assigning stream $streamId to remoteRenderer');
          remoteRenderer!.srcObject = _remoteStream;
          print('[CallController] ✅ RENDERER_ATTACH: Remote stream attached to renderer');
        } else if (isVideoCall && !_remoteRendererReady) {
          print('[CallController] ⚠️ RENDERER_WARNING: Remote renderer not ready, cannot attach stream');
        }
        
        callbackInvocationCount++;
        print('[ECHO_TEST] CALLBACK INVOCATION #$callbackInvocationCount');
        print('[ECHO_TEST] Invoking onRemoteStream callback');
        onRemoteStream?.call(_remoteStream!);
        print('[CallController] ✅ REMOTE_STREAM: Callback invoked');
        
        print('[ECHO_TEST] ========================================');
        print('[ECHO_TEST] SUMMARY SO FAR:');
        print('[ECHO_TEST] - Total onTrack calls: $onTrackCallCount');
        print('[ECHO_TEST] - Unique tracks: ${seenTrackIds.length}');
        print('[ECHO_TEST] - Unique streams: ${seenStreamIds.length}');
        print('[ECHO_TEST] - Renderer assignments: $rendererAssignmentCount');
        print('[ECHO_TEST] - Callback invocations: $callbackInvocationCount');
        print('[ECHO_TEST] ========================================');
      } else {
        print('[ECHO_TEST] ⚠️ NO STREAMS in event!');
        print('[ECHO_TEST] ========================================');
        print('[CallController] ⚠️ TRACK_WARNING: Track received but no streams!');
      }
    };

    // Handle connection state changes
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      print('[CallController] 🔗 CONNECTION_STATE: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _mediaState = MediaState.connected;
        print('[CallController] ✅ MEDIA_STATE: connected');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _mediaState = MediaState.failed;
        print('[CallController] ❌ MEDIA_STATE: failed');
      }
      onConnectionStateChange?.call(state.toString());
    };

    // Handle ICE connection state
    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      print('[CallController] 🧊 ICE_CONNECTION_STATE: $state');
      
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        print('[CallController] ❌ ICE_FAILED: Connection cannot be established');
        _handleConnectionFailure();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        print('[CallController] ⚠️ ICE_DISCONNECTED: Connection lost, starting reconnection...');
        _handleDisconnection();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        print('[CallController] ✅ ICE_CONNECTED: Peer connection established');
        _handleReconnected();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        print('[CallController] ✅ ICE_COMPLETED: All candidates processed');
        _handleReconnected();
      }
    };

    // Handle signaling state
    _peerConnection!.onSignalingState = (RTCSignalingState state) {
      print('[CallController] 📡 SIGNALING_STATE: $state');
    };
  }

  /// Create offer (caller side)
  Future<void> _createOffer() async {
    if (_offerCreated || _isDisposed) return;
    
    print('[CallController] Creating offer...');
    
    try {
      RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': isVideoCall,
      });

      await _peerConnection!.setLocalDescription(offer);
      _offerCreated = true;

      // Send offer to Firestore
      await _firestoreService.calls.doc(callId).update({
        'offer': {
          'type': offer.type,
          'sdp': offer.sdp,
        },
      });

      print('[CallController] Offer created and sent to Firestore');
    } catch (e) {
      print('[CallController] ERROR creating offer: $e');
      rethrow;
    }
  }

  /// Wait for offer and create answer (receiver side)
  Future<void> _waitForOfferAndCreateAnswer() async {
    print('[CallController] Waiting for offer...');
    // The offer will be received via _listenToCallDocument
    // Once received, _createAnswer will be called
  }

  /// Create answer (receiver side)
  Future<void> _createAnswer(Map<String, dynamic> offerData) async {
    if (_answerCreated || _isDisposed) return;
    
    print('[CallController] Creating answer...');
    
    try {
      RTCSessionDescription offer = RTCSessionDescription(
        offerData['sdp'],
        offerData['type'],
      );

      await _peerConnection!.setRemoteDescription(offer);
      _remoteDescriptionSet = true;
      print('[CallController] Remote offer set');

      // Process buffered ICE candidates
      await _processBufferedCandidates();

      RTCSessionDescription answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': isVideoCall,
      });

      await _peerConnection!.setLocalDescription(answer);
      _answerCreated = true;

      // Send answer to Firestore
      await _firestoreService.calls.doc(callId).update({
        'answer': {
          'type': answer.type,
          'sdp': answer.sdp,
        },
      });

      print('[CallController] Answer created and sent to Firestore');
    } catch (e) {
      print('[CallController] ERROR creating answer: $e');
      rethrow;
    }
  }

  /// Handle received answer (caller side)
  Future<void> _handleAnswer(Map<String, dynamic> answerData) async {
    if (_isDisposed || _remoteDescriptionSet) return;
    
    print('[CallController] Handling answer...');
    
    try {
      RTCSessionDescription answer = RTCSessionDescription(
        answerData['sdp'],
        answerData['type'],
      );

      await _peerConnection!.setRemoteDescription(answer);
      _remoteDescriptionSet = true;
      print('[CallController] Remote answer set');

      // Process buffered ICE candidates
      await _processBufferedCandidates();
    } catch (e) {
      print('[CallController] ERROR handling answer: $e');
      rethrow;
    }
  }

  /// Send ICE candidate to Firestore
  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    if (_isDisposed) return;
    
    try {
      await _firestoreService.calls.doc(callId).update({
        'iceCandidates': FieldValue.arrayUnion([
          {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'from': isInitiator ? 'caller' : 'receiver',
          }
        ]),
      });
      print('[CallController] ICE candidate sent to Firestore');
    } catch (e) {
      print('[CallController] ERROR sending ICE candidate: $e');
    }
  }

  /// Process buffered ICE candidates
  Future<void> _processBufferedCandidates() async {
    if (_candidateBuffer.isEmpty) return;
    
    print('[CallController] Processing ${_candidateBuffer.length} buffered ICE candidates...');
    
    for (var candidate in _candidateBuffer) {
      try {
        await _peerConnection!.addCandidate(candidate);
        print('[CallController] Buffered candidate added');
      } catch (e) {
        print('[CallController] ERROR adding buffered candidate: $e');
      }
    }
    
    _candidateBuffer.clear();
  }

  /// Listen to call document for offer/answer
  void _listenToCallDocument() {
    print('[CallController] Starting call document listener...');
    
    _callDocListener = _firestoreService.calls.doc(callId).snapshots().listen((snapshot) {
      if (_isDisposed || !snapshot.exists) return;
      
      final data = snapshot.data();
      if (data == null) return;

      // If receiver, look for offer
      if (!isInitiator && !_answerCreated) {
        final offer = data['offer'] as Map<String, dynamic>?;
        if (offer != null && offer['sdp'] != null) {
          print('[CallController] Offer received from Firestore');
          _createAnswer(offer);
        }
      }

      // If caller, look for answer
      if (isInitiator && !_remoteDescriptionSet) {
        final answer = data['answer'] as Map<String, dynamic>?;
        if (answer != null && answer['sdp'] != null) {
          print('[CallController] Answer received from Firestore');
          _handleAnswer(answer);
        }
      }
    });
  }

  /// Listen to ICE candidates
  void _listenToIceCandidates() {
    print('[CallController] Starting ICE candidates listener...');
    
    _iceCandidatesListener = _firestoreService.calls.doc(callId).snapshots().listen((snapshot) {
      if (_isDisposed || !snapshot.exists) return;
      
      final data = snapshot.data();
      if (data == null) return;

      final candidates = data['iceCandidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return;

      // Filter candidates from the other party
      final myRole = isInitiator ? 'caller' : 'receiver';
      final otherRole = isInitiator ? 'receiver' : 'caller';

      for (var candidateData in candidates) {
        if (candidateData is Map<String, dynamic>) {
          final from = candidateData['from'] as String?;
          
          // Only process candidates from the other party
          if (from == otherRole) {
            final candidate = RTCIceCandidate(
              candidateData['candidate'],
              candidateData['sdpMid'],
              candidateData['sdpMLineIndex'],
            );

            // If remote description not set yet, buffer the candidate
            if (!_remoteDescriptionSet) {
              _candidateBuffer.add(candidate);
              print('[CallController] ICE candidate buffered (remote description not set yet)');
            } else {
              _peerConnection!.addCandidate(candidate).then((_) {
                print('[CallController] ICE candidate added to peer connection');
              }).catchError((e) {
                print('[CallController] ERROR adding ICE candidate: $e');
              });
            }
          }
        }
      }
    });
  }

  /// Set audio routing to earpiece (default for voice calls)
  Future<void> setEarpieceAudio() async {
    try {
      await Helper.setSpeakerphoneOn(false);
      print('[CallController] 🎧 Audio routed to EARPIECE');
    } catch (e) {
      print('[CallController] ERROR setting earpiece audio: $e');
    }
  }

  /// Toggle mute/unmute local audio
  Future<void> toggleMute(bool mute) async {
    if (_localStream == null) return;
    
    _localStream!.getAudioTracks().forEach((track) {
      track.enabled = !mute;
    });
    
    print('[CallController] Microphone ${mute ? "muted" : "unmuted"}');
  }

  /// Toggle speaker/earpiece (platform-specific)
  Future<void> toggleSpeaker(bool speaker) async {
    try {
      await Helper.setSpeakerphoneOn(speaker);
      print('[CallController] ${speaker ? "🔊 LOUDSPEAKER" : "🎧 EARPIECE"} ${speaker ? "enabled" : "enabled"}');
    } catch (e) {
      print('[CallController] ERROR toggling speaker: $e');
    }
  }

  /// Toggle camera on/off (video calls only)
  /// Does NOT stop the call, only disables/enables the video track
  /// PRODUCTION HARDENING: Explicit UI state management
  Future<void> toggleCamera(bool enabled) async {
    if (!isVideoCall || _localStream == null) {
      print('[CallController] ⚠️ CAMERA_TOGGLE_SKIP: not in video call');
      return;
    }
    
    try {
      print('[CallController] 🎬 CAMERA_TOGGLE: ${enabled ? "enabling" : "disabling"} camera...');
      
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isEmpty) {
        print('[CallController] ⚠️ CAMERA_TOGGLE_ERROR: No video tracks!');
        return;
      }
      
      for (var track in videoTracks) {
        track.enabled = enabled;
        print('[CallController] 🎬 TRACK_STATE: ${track.kind} track (ID: ${track.id}) enabled=${track.enabled}');
      }
      
      print('[CallController] ✅ CAMERA_TOGGLE: Camera ${enabled ? "enabled" : "disabled"}');
    } catch (e) {
      print('[CallController] ❌ CAMERA_TOGGLE_ERROR: $e');
    }
  }

  /// Get current media state (for UI state management)
  MediaState get mediaState => _mediaState;

  /// Check if renderers are ready (for safe UI rendering)
  bool get localRendererReady => _localRendererReady;
  bool get remoteRendererReady => _remoteRendererReady;
  
  /// Get reconnection state
  bool get isReconnecting => _isReconnecting;

  /// Switch camera between front and back (video calls only)
  /// Does NOT renegotiate peer connection - replaces track only
  /// PRODUCTION HARDENING: Race condition protection + detailed logging
  Future<void> switchCamera() async {
    if (!isVideoCall || _localStream == null || _peerConnection == null) {
      print('[CallController] ⚠️ CAMERA_SWITCH_SKIP: not in video call (video=$isVideoCall, stream=${_localStream != null}, pc=${_peerConnection != null})');
      return;
    }

    // RACE CONDITION GUARD: Prevent multiple simultaneous switches
    if (_isSwitchingCamera) {
      print('[CallController] ⚠️ CAMERA_SWITCH_BLOCKED: Already switching camera (race condition prevented)');
      return;
    }

    _isSwitchingCamera = true;
    final startTime = DateTime.now();
    
    try {
      print('[CallController] ⏳ CAMERA_SWITCH_START: Switching camera...');
      
      // Get current video track
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isEmpty) {
        print('[CallController] ❌ CAMERA_SWITCH_ERROR: No video tracks to switch');
        return;
      }

      final currentTrack = videoTracks.first;
      print('[CallController] 📹 CAMERA_SWITCH_TRACK: Current track ID: ${currentTrack.id}, enabled: ${currentTrack.enabled}');

      // Switch camera using Helper API
      await Helper.switchCamera(currentTrack);
      
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      print('[CallController] ✅ CAMERA_SWITCH_SUCCESS: Camera switched in ${duration}ms');
      
      // Verify track still exists and is enabled
      final newVideoTracks = _localStream!.getVideoTracks();
      if (newVideoTracks.isNotEmpty) {
        final newTrack = newVideoTracks.first;
        print('[CallController] 📹 CAMERA_SWITCH_VERIFY: New track ID: ${newTrack.id}, enabled: ${newTrack.enabled}');
        
        if (!newTrack.enabled) {
          print('[CallController] ⚠️ CAMERA_SWITCH_WARNING: Track exists but disabled!');
        }
      } else {
        print('[CallController] ❌ CAMERA_SWITCH_ERROR: No video tracks after switch!');
      }
    } catch (e) {
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      print('[CallController] ❌ CAMERA_SWITCH_ERROR: Failed after ${duration}ms: $e');
      // Don't rethrow - camera switch failure shouldn't crash the call
    } finally {
      _isSwitchingCamera = false;
      print('[CallController] 🔓 CAMERA_SWITCH_UNLOCK: Switch operation complete');
    }
  }

  /// Handle disconnection - start reconnection process
  void _handleDisconnection() {
    if (_isReconnecting || _isDisposed) {
      print('[CallController] ⚠️ RECONNECTION_SKIP: Already reconnecting or disposed');
      return;
    }
    
    print('[CallController] 🔄 RECONNECTION_START: Network dropped, starting reconnection timer...');
    _isReconnecting = true;
    _reconnectionStartTime = DateTime.now();
    onReconnectionStateChange?.call(true);
    
    _startReconnectionTimer();
  }

  /// Start reconnection timeout timer
  void _startReconnectionTimer() {
    _reconnectionTimer?.cancel();
    
    print('[CallController] ⏱️ RECONNECTION_TIMER: Starting ${_reconnectionTimeout.inSeconds}s timeout');
    
    _reconnectionTimer = Timer(_reconnectionTimeout, () {
      if (_isReconnecting && !_isDisposed) {
        final elapsed = DateTime.now().difference(_reconnectionStartTime!).inSeconds;
        print('[CallController] ❌ RECONNECTION_TIMEOUT: Failed to reconnect after ${elapsed}s');
        _handleConnectionFailure();
      }
    });
  }

  /// Handle successful reconnection
  void _handleReconnected() {
    if (!_isReconnecting) {
      return; // Not in reconnection state, ignore
    }
    
    final elapsed = DateTime.now().difference(_reconnectionStartTime!).inSeconds;
    print('[CallController] ✅ RECONNECTION_SUCCESS: Connection restored after ${elapsed}s');
    
    _cancelReconnectionTimer();
    _isReconnecting = false;
    _reconnectionStartTime = null;
    onReconnectionStateChange?.call(false);
  }

  /// Handle connection failure (permanent)
  void _handleConnectionFailure() {
    print('[CallController] ❌ CONNECTION_FAILURE: Network issue could not be resolved');
    
    _cancelReconnectionTimer();
    _isReconnecting = false;
    _reconnectionStartTime = null;
    
    // Notify UI through connection state change
    onConnectionStateChange?.call('failed');
  }

  /// Cancel reconnection timer
  void _cancelReconnectionTimer() {
    if (_reconnectionTimer != null) {
      print('[CallController] 🛑 RECONNECTION_TIMER: Cancelling timer');
      _reconnectionTimer?.cancel();
      _reconnectionTimer = null;
    }
  }

  /// Dispose and cleanup all resources
  /// PRODUCTION HARDENING: Comprehensive cleanup with detailed logging
  Future<void> dispose() async {
    if (_isDisposed) {
      print('[CallController] ⚠️ DISPOSE_SKIP: Already disposed');
      return;
    }
    
    print('[ECHO_TEST] ========================================');
    print('[ECHO_TEST] DISPOSE CALLED');
    print('[ECHO_TEST] This instance initialized: $_myInitializeCount times');
    print('[ECHO_TEST] ========================================');
    
    print('[CallController] ⏳ DISPOSE_START: Disposing CallController (video: $isVideoCall)...');
    final startTime = DateTime.now();
    _isDisposed = true;
    _mediaState = MediaState.idle;

    // Cancel reconnection timer
    _cancelReconnectionTimer();
    _isReconnecting = false;
    _reconnectionStartTime = null;

    // Cancel Firestore listeners
    try {
      print('[CallController] 🔌 DISPOSE_LISTENERS: Cancelling Firestore listeners...');
      await _callDocListener?.cancel();
      await _iceCandidatesListener?.cancel();
      print('[CallController] ✅ DISPOSE_LISTENERS: Listeners cancelled');
    } catch (e) {
      print('[CallController] ⚠️ DISPOSE_LISTENERS_ERROR: $e');
    }

    // Stop local stream tracks
    try {
      if (_localStream != null) {
        print('[CallController] 🛑 DISPOSE_LOCAL_TRACKS: Stopping local stream tracks...');
        final tracks = _localStream!.getTracks();
        print('[CallController] 📊 DISPOSE_LOCAL_TRACKS: ${tracks.length} tracks to stop');
        
        for (var track in tracks) {
          print('[CallController] 🛑 TRACK_STOP: ${track.kind} track (ID: ${track.id})');
          track.stop();
        }
        
        await _localStream?.dispose();
        _localStream = null;
        print('[CallController] ✅ DISPOSE_LOCAL_STREAM: Local stream disposed');
      }
    } catch (e) {
      print('[CallController] ⚠️ DISPOSE_LOCAL_ERROR: $e');
    }

    // Stop remote stream tracks
    try {
      if (_remoteStream != null) {
        print('[CallController] 🛑 DISPOSE_REMOTE_TRACKS: Stopping remote stream tracks...');
        final tracks = _remoteStream!.getTracks();
        print('[CallController] 📊 DISPOSE_REMOTE_TRACKS: ${tracks.length} tracks to stop');
        
        for (var track in tracks) {
          print('[CallController] 🛑 TRACK_STOP: ${track.kind} track (ID: ${track.id})');
          track.stop();
        }
        
        await _remoteStream?.dispose();
        _remoteStream = null;
        print('[CallController] ✅ DISPOSE_REMOTE_STREAM: Remote stream disposed');
      }
    } catch (e) {
      print('[CallController] ⚠️ DISPOSE_REMOTE_ERROR: $e');
    }

    // Dispose video renderers if video call
    if (isVideoCall) {
      try {
        print('[CallController] 🎬 DISPOSE_RENDERERS: Disposing video renderers...');
        
        if (localRenderer != null) {
          print('[CallController] 🎬 DISPOSE_RENDERER: Local renderer (ready: $_localRendererReady)');
          await localRenderer?.dispose();
          localRenderer = null;
          _localRendererReady = false;
        }
        
        if (remoteRenderer != null) {
          print('[CallController] 🎬 DISPOSE_RENDERER: Remote renderer (ready: $_remoteRendererReady)');
          await remoteRenderer?.dispose();
          remoteRenderer = null;
          _remoteRendererReady = false;
        }
        
        print('[CallController] ✅ DISPOSE_RENDERERS: Video renderers disposed');
      } catch (e) {
        print('[CallController] ⚠️ DISPOSE_RENDERERS_ERROR: $e');
      }
    }

    // Close peer connection
    try {
      if (_peerConnection != null) {
        print('[CallController] 🔌 DISPOSE_PEER_CONNECTION: Closing peer connection...');
        await _peerConnection?.close();
        await _peerConnection?.dispose();
        _peerConnection = null;
        print('[CallController] ✅ DISPOSE_PEER_CONNECTION: Peer connection closed');
      }
    } catch (e) {
      print('[CallController] ⚠️ DISPOSE_PEER_CONNECTION_ERROR: $e');
    }

    final duration = DateTime.now().difference(startTime).inMilliseconds;
    print('[CallController] ✅ DISPOSE_COMPLETE: CallController disposed in ${duration}ms');
    print('[CallController] 📊 DISPOSE_FINAL_STATE: Tracks stopped, renderers disposed, connection closed');
  }

  /// Get local stream (for UI display if needed)
  MediaStream? get localStream => _localStream;

  /// Get remote stream (for UI display if needed)
  MediaStream? get remoteStream => _remoteStream;
}
