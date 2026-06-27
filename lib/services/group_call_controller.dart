import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'firestore_service.dart';

/// PHASE 3: Group Audio Call Controller
/// 
/// Manages WebRTC mesh topology for group audio calls.
/// Each participant maintains N-1 peer connections (where N = total participants).
/// 
/// Reuses existing audio transport from CallController.
/// Signaling via Firestore peerConnections subcollection.
/// 
/// Maximum 8 participants (mesh topology limitation).
class GroupCallController {
  final String callId;
  final String currentUserId;
  
  final FirestoreService _firestoreService = FirestoreService();
  
  // WebRTC state
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, MediaStream> _remoteStreams = {};
  
  // Firestore listeners
  final Map<String, StreamSubscription> _peerListeners = {};
  StreamSubscription? _participantsListener;
  
  // PHASE 3.1: Speaking detection DISABLED (fake implementation removed)
  Timer? _speakingDetectionTimer; // Kept for future implementation
  
  // Callbacks
  Function(String userId, MediaStream stream)? onRemoteStream;
  Function(String userId)? onParticipantLeft;
  Function(List<String> speakingUserIds)? onSpeakingChanged;
  
  // State
  bool _isDisposed = false;
  bool _isInitialized = false;
  
  // PHASE 3.1: Reconnection state (reusing CallController architecture)
  final Map<String, Timer?> _reconnectionTimers = {};
  final Map<String, DateTime?> _reconnectionStartTimes = {};
  final Duration _reconnectionTimeout = Duration(seconds: 15);
  
  GroupCallController({
    required this.callId,
    required this.currentUserId,
    this.onRemoteStream,
    this.onParticipantLeft,
    this.onSpeakingChanged,
  });
  
  /// Initialize group call WebRTC
  /// 
  /// Steps:
  /// 1. Get local audio stream
  /// 2. Get list of joined participants
  /// 3. Create peer connection for each participant
  /// 4. Start listening for new participants
  /// 5. Start speaking detection
  Future<void> initialize() async {
    if (_isDisposed || _isInitialized) {
      print('[GroupCallController] Already initialized or disposed');
      return;
    }
    
    try {
      print('[GroupCallController] 🎤 Initializing group audio call: $callId');
      print('[GroupCallController] 👤 Current user: $currentUserId');
      
      // Step 1: Get local audio stream
      await _getLocalAudioStream();
      
      // Step 2: Get existing participants
      final existingParticipants = await _getJoinedParticipants();
      print('[GroupCallController] 👥 Existing participants: ${existingParticipants.length}');
      
      // Step 3: Create peer connections for existing participants
      for (var participantId in existingParticipants) {
        if (participantId != currentUserId) {
          await _createPeerConnection(participantId, initiator: true);
        }
      }
      
      // Step 4: Listen for new participants joining
      _listenToParticipantChanges();
      
      // Step 5: Start speaking detection
      _startSpeakingDetection();
      
      _isInitialized = true;
      print('[GroupCallController] ✅ Initialization complete');
    } catch (e) {
      print('[GroupCallController] ❌ Initialization error: $e');
      rethrow;
    }
  }
  
  /// Get local audio stream (no video)
  Future<void> _getLocalAudioStream() async {
    print('[GroupCallController] 🎙️ Getting local audio stream...');
    
    final constraints = {
      'audio': true,
      'video': false,
    };
    
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      print('[GroupCallController] ✅ Local audio stream acquired');
      
      // Set audio routing to earpiece for group audio calls
      await Helper.setSpeakerphoneOn(false);
      print('[GroupCallController] 🎧 Audio routed to EARPIECE');
    } catch (e) {
      print('[GroupCallController] ❌ Failed to get audio stream: $e');
      rethrow;
    }
  }
  
  /// Get list of joined participants from Firestore
  Future<List<String>> _getJoinedParticipants() async {
    try {
      final doc = await _firestoreService.groupCalls.doc(callId).get();
      if (!doc.exists) return [];
      
      final data = doc.data();
      if (data == null) return [];
      
      final joined = List<String>.from(data['joinedParticipants'] as List? ?? []);
      return joined;
    } catch (e) {
      print('[GroupCallController] Error getting participants: $e');
      return [];
    }
  }
  
  /// Create peer connection with another participant
  /// 
  /// Mesh topology: Each user connects to every other user
  Future<void> _createPeerConnection(String participantId, {required bool initiator}) async {
    if (_peerConnections.containsKey(participantId)) {
      print('[GroupCallController] Peer connection already exists for $participantId');
      return;
    }
    
    print('[GroupCallController] 🔗 Creating peer connection: $currentUserId ↔ $participantId (initiator: $initiator)');
    
    try {
      // Create peer connection with STUN server
      final configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      };
      
      final constraints = {
        'mandatory': {},
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
        ],
      };
      
      final peerConnection = await createPeerConnection(configuration, constraints);
      
      // Add local audio tracks
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          peerConnection.addTrack(track, _localStream!);
        });
        print('[GroupCallController] ➕ Local audio track added');
      }
      
      // Handle ICE candidates
      peerConnection.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
          _sendIceCandidate(participantId, candidate);
        }
      };
      
      // Handle remote stream
      peerConnection.onTrack = (event) {
        print('[GroupCallController] 🎯 Remote track received from $participantId');
        if (event.streams.isNotEmpty) {
          _remoteStreams[participantId] = event.streams[0];
          onRemoteStream?.call(participantId, event.streams[0]);
        }
      };
      
      // PHASE 3.1: Handle connection state with reconnection logic
      peerConnection.onConnectionState = (state) {
        print('[GroupCallController] 🔗 Connection state with $participantId: $state');
        
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          print('[GroupCallController] ❌ Connection failed with $participantId');
          _closePeerConnection(participantId);
        }
      };
      
      // PHASE 3.1: Monitor ICE connection state for reconnection
      peerConnection.onIceConnectionState = (iceState) {
        print('[GroupCallController] 🧊 ICE state with $participantId: $iceState');
        
        if (iceState == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
            iceState == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _handlePeerDisconnection(participantId);
        } else if (iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                   iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _handlePeerReconnected(participantId);
        }
      };
      
      _peerConnections[participantId] = peerConnection;
      
      // If initiator, create and send offer
      if (initiator) {
        await _createAndSendOffer(participantId, peerConnection);
      }
      
      // Start listening to signaling for this peer
      _listenToPeerSignaling(participantId);
      
      print('[GroupCallController] ✅ Peer connection created');
    } catch (e) {
      print('[GroupCallController] ❌ Failed to create peer connection: $e');
    }
  }
  
  /// Create and send SDP offer
  Future<void> _createAndSendOffer(String participantId, RTCPeerConnection pc) async {
    try {
      print('[GroupCallController] 📤 Creating offer for $participantId');
      
      final offer = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      
      await pc.setLocalDescription(offer);
      
      // Send offer to Firestore
      final pairId = _getPairId(currentUserId, participantId);
      await _firestoreService.groupCalls.doc(callId)
          .collection('peerConnections')
          .doc(pairId)
          .set({
        'offer': {
          'type': offer.type,
          'sdp': offer.sdp,
        },
        'from': currentUserId,
        'to': participantId,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      print('[GroupCallController] ✅ Offer sent to Firestore');
    } catch (e) {
      print('[GroupCallController] ❌ Failed to create offer: $e');
    }
  }
  
  /// Handle received SDP offer
  Future<void> _handleOffer(String participantId, Map<String, dynamic> offerData) async {
    try {
      print('[GroupCallController] 📥 Received offer from $participantId');
      
      var peerConnection = _peerConnections[participantId];
      
      // Create peer connection if doesn't exist
      if (peerConnection == null) {
        await _createPeerConnection(participantId, initiator: false);
        peerConnection = _peerConnections[participantId];
        if (peerConnection == null) return;
      }
      
      final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
      await peerConnection.setRemoteDescription(offer);
      
      // Create and send answer
      final answer = await peerConnection.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      
      await peerConnection.setLocalDescription(answer);
      
      // Send answer to Firestore
      final pairId = _getPairId(currentUserId, participantId);
      await _firestoreService.groupCalls.doc(callId)
          .collection('peerConnections')
          .doc(pairId)
          .set({
        'answer': {
          'type': answer.type,
          'sdp': answer.sdp,
        },
      }, SetOptions(merge: true));
      
      print('[GroupCallController] ✅ Answer sent');
    } catch (e) {
      print('[GroupCallController] ❌ Failed to handle offer: $e');
    }
  }
  
  /// Handle received SDP answer
  Future<void> _handleAnswer(String participantId, Map<String, dynamic> answerData) async {
    try {
      print('[GroupCallController] 📥 Received answer from $participantId');
      
      final peerConnection = _peerConnections[participantId];
      if (peerConnection == null) {
        print('[GroupCallController] ⚠️ No peer connection found for $participantId');
        return;
      }
      
      final answer = RTCSessionDescription(answerData['sdp'], answerData['type']);
      await peerConnection.setRemoteDescription(answer);
      
      print('[GroupCallController] ✅ Answer processed');
    } catch (e) {
      print('[GroupCallController] ❌ Failed to handle answer: $e');
    }
  }
  
  /// Send ICE candidate to Firestore
  Future<void> _sendIceCandidate(String participantId, RTCIceCandidate candidate) async {
    try {
      final pairId = _getPairId(currentUserId, participantId);
      
      await _firestoreService.groupCalls.doc(callId)
          .collection('peerConnections')
          .doc(pairId)
          .set({
        'iceCandidates': FieldValue.arrayUnion([
          {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'from': currentUserId,
          }
        ]),
      }, SetOptions(merge: true));
      
      print('[GroupCallController] 📤 ICE candidate sent');
    } catch (e) {
      print('[GroupCallController] ❌ Failed to send ICE candidate: $e');
    }
  }
  
  /// Listen to signaling data for a peer
  void _listenToPeerSignaling(String participantId) {
    final pairId = _getPairId(currentUserId, participantId);
    
    print('[GroupCallController] 👂 Listening to signaling: $pairId');
    
    final listener = _firestoreService.groupCalls.doc(callId)
        .collection('peerConnections')
        .doc(pairId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists || _isDisposed) return;
      
      final data = snapshot.data();
      if (data == null) return;
      
      // Handle offer (if we're the receiver)
      if (data['offer'] != null && data['from'] != currentUserId) {
        final offerData = data['offer'] as Map<String, dynamic>;
        await _handleOffer(participantId, offerData);
      }
      
      // Handle answer (if we're the initiator)
      if (data['answer'] != null && data['to'] == currentUserId) {
        final answerData = data['answer'] as Map<String, dynamic>;
        await _handleAnswer(participantId, answerData);
      }
      
      // Handle ICE candidates
      if (data['iceCandidates'] != null) {
        final candidates = List<Map<String, dynamic>>.from(data['iceCandidates'] as List);
        
        for (var candidateData in candidates) {
          if (candidateData['from'] != currentUserId) {
            final candidate = RTCIceCandidate(
              candidateData['candidate'],
              candidateData['sdpMid'],
              candidateData['sdpMLineIndex'],
            );
            
            final pc = _peerConnections[participantId];
            if (pc != null) {
              await pc.addCandidate(candidate);
              print('[GroupCallController] ➕ ICE candidate added');
            }
          }
        }
      }
    });
    
    _peerListeners[participantId] = listener;
  }
  
  /// Listen to participant changes (join/leave)
  void _listenToParticipantChanges() {
    print('[GroupCallController] 👂 Listening to participant changes');
    
    _participantsListener = _firestoreService.groupCalls.doc(callId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists || _isDisposed) return;
      
      final data = snapshot.data();
      if (data == null) return;
      
      final currentParticipants = List<String>.from(data['joinedParticipants'] as List? ?? []);
      
      // Detect new participants (create connections)
      for (var participantId in currentParticipants) {
        if (participantId != currentUserId && !_peerConnections.containsKey(participantId)) {
          print('[GroupCallController] 👤 New participant detected: $participantId');
          
          // Determine who should initiate (lower userId initiates)
          final shouldInitiate = currentUserId.compareTo(participantId) < 0;
          await _createPeerConnection(participantId, initiator: shouldInitiate);
        }
      }
      
      // Detect participants who left (close connections)
      final leftParticipants = _peerConnections.keys.where(
        (id) => !currentParticipants.contains(id),
      ).toList();
      
      for (var participantId in leftParticipants) {
        print('[GroupCallController] 🚪 Participant left: $participantId');
        _closePeerConnection(participantId);
        onParticipantLeft?.call(participantId);
      }
      
      // Update speaking participants
      final speakingIds = List<String>.from(data['speakingParticipants'] as List? ?? []);
      onSpeakingChanged?.call(speakingIds);
    });
  }
  
  /// PHASE 3.1: Handle peer disconnection - start reconnection process
  void _handlePeerDisconnection(String participantId) {
    if (_reconnectionTimers[participantId] != null || _isDisposed) {
      print('[GroupCallController] ⚠️ RECONNECTION_SKIP: Already reconnecting or disposed for $participantId');
      return;
    }
    
    print('[GroupCallController] 🔄 RECONNECTION_START: Peer $participantId disconnected, starting timer...');
    _reconnectionStartTimes[participantId] = DateTime.now();
    
    _reconnectionTimers[participantId] = Timer(_reconnectionTimeout, () {
      if (!_isDisposed) {
        final elapsed = DateTime.now().difference(_reconnectionStartTimes[participantId]!).inSeconds;
        print('[GroupCallController] ❌ RECONNECTION_TIMEOUT: Failed to reconnect to $participantId after ${elapsed}s');
        _closePeerConnection(participantId);
        onParticipantLeft?.call(participantId);
      }
    });
  }
  
  /// PHASE 3.1: Handle successful peer reconnection
  void _handlePeerReconnected(String participantId) {
    final timer = _reconnectionTimers[participantId];
    if (timer == null) {
      return; // Not in reconnection state, ignore
    }
    
    final startTime = _reconnectionStartTimes[participantId];
    if (startTime != null) {
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      print('[GroupCallController] ✅ RECONNECTION_SUCCESS: Peer $participantId reconnected after ${elapsed}s');
    }
    
    // Cancel reconnection timer
    timer.cancel();
    _reconnectionTimers.remove(participantId);
    _reconnectionStartTimes.remove(participantId);
  }
  
  /// Close peer connection with a participant
  void _closePeerConnection(String participantId) {
    print('[GroupCallController] 🔌 Closing connection with $participantId');
    
    // Cancel any ongoing reconnection timer
    _reconnectionTimers[participantId]?.cancel();
    _reconnectionTimers.remove(participantId);
    _reconnectionStartTimes.remove(participantId);
    
    _peerConnections[participantId]?.close();
    _peerConnections[participantId]?.dispose();
    _peerConnections.remove(participantId);
    
    _remoteStreams[participantId]?.dispose();
    _remoteStreams.remove(participantId);
    
    _peerListeners[participantId]?.cancel();
    _peerListeners.remove(participantId);
  }
  
  /// Get pair ID for signaling document (alphabetically sorted)
  String _getPairId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }
  
  /// PHASE 3.1: Speaking detection DISABLED
  /// 
  /// The previous implementation was fake - it only checked audioTrack.enabled,
  /// not actual audio levels. Real speaking detection requires platform-specific
  /// audio analysis which is not yet implemented.
  /// 
  /// This method is kept as a placeholder for future implementation.
  void _startSpeakingDetection() {
    print('[GroupCallController] ⚠️ Speaking detection DISABLED (awaiting proper audio level monitoring)');
    
    // DISABLED: Fake speaking detection removed
    // TODO: Implement real audio level monitoring using platform-specific APIs
    // _speakingDetectionTimer = Timer.periodic(
    //   Duration(milliseconds: 100),
    //   (_) => _checkAudioLevel(),
    // );
  }
  
  // DISABLED: Fake audio level check removed
  // Future<void> _checkAudioLevel() async { ... }
  
  // DISABLED: Fake speaking state updates removed
  // Future<void> _updateSpeakingState(bool speaking) async { ... }
  
  /// Toggle mute/unmute local audio
  Future<void> toggleMute(bool mute) async {
    if (_localStream == null) return;
    
    _localStream!.getAudioTracks().forEach((track) {
      track.enabled = !mute;
    });
    
    print('[GroupCallController] Microphone ${mute ? "muted" : "unmuted"}');
    
    // PHASE 3.1: Speaking state updates disabled (fake implementation removed)
  }
  
  /// Toggle speaker/earpiece
  Future<void> toggleSpeaker(bool speaker) async {
    try {
      await Helper.setSpeakerphoneOn(speaker);
      print('[GroupCallController] ${speaker ? "🔊 LOUDSPEAKER" : "🎧 EARPIECE"}');
    } catch (e) {
      print('[GroupCallController] Error toggling speaker: $e');
    }
  }
  
  /// Get remote streams
  Map<String, MediaStream> get remoteStreams => Map.unmodifiable(_remoteStreams);
  
  /// Get number of active connections
  int get connectionCount => _peerConnections.length;
  
  /// Dispose and cleanup all resources
  Future<void> dispose() async {
    if (_isDisposed) return;
    
    print('[GroupCallController] 🧹 Disposing group call controller');
    _isDisposed = true;
    
    // PHASE 3.1: Cancel all reconnection timers
    for (var timer in _reconnectionTimers.values) {
      timer?.cancel();
    }
    _reconnectionTimers.clear();
    _reconnectionStartTimes.clear();
    
    // Stop speaking detection (disabled in Phase 3.1)
    _speakingDetectionTimer?.cancel();
    _speakingDetectionTimer = null;
    
    // Cancel all listeners
    _participantsListener?.cancel();
    _participantsListener = null;
    
    for (var listener in _peerListeners.values) {
      listener.cancel();
    }
    _peerListeners.clear();
    
    // Close all peer connections
    for (var entry in _peerConnections.entries) {
      print('[GroupCallController] Closing connection: ${entry.key}');
      entry.value.close();
      entry.value.dispose();
    }
    _peerConnections.clear();
    
    // Dispose remote streams
    for (var stream in _remoteStreams.values) {
      stream.dispose();
    }
    _remoteStreams.clear();
    
    // Stop local stream
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        track.stop();
      }
      await _localStream?.dispose();
      _localStream = null;
    }
    
    print('[GroupCallController] ✅ Disposed');
  }
}
