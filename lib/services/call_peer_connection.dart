import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// EXTRACTED FROM WORKING CallController
/// Reusable WebRTC peer connection component
/// NO group logic - pure 1-to-1 transport
/// 
/// This is the EXACT transport that works in single calls
/// It will be reused by both:
/// - CallController (existing 1-to-1)
/// - GroupCallController (orchestrating multiple peers)

class CallPeerConnection {
  final String callId;
  final String localUserId;
  final String remoteUserId;
  final bool isInitiator;
  final CollectionReference callsCollection; // Where to store signaling
  final String signalingDocPath; // e.g., "calls/{callId}" or "groupCalls/{callId}/peers/{pairId}"
  
  // WebRTC components (EXACT SAME as CallController)
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  // Firestore listeners
  StreamSubscription? _callDocListener;
  StreamSubscription? _iceCandidatesListener;
  
  // State (EXACT SAME as CallController)
  bool _isDisposed = false;
  bool _offerCreated = false;
  bool _answerCreated = false;
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _candidateBuffer = [];
  
  // EXACT SAME ICE configuration as CallController
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };
  
  final Map<String, dynamic> _sdpConstraints = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };
  
  // Callbacks (EXACT SAME as CallController)
  Function(MediaStream)? onRemoteStream;
  Function(String)? onConnectionStateChange;
  Function(RTCIceConnectionState)? onIceConnectionStateChange;
  
  CallPeerConnection({
    required this.callId,
    required this.localUserId,
    required this.remoteUserId,
    required this.isInitiator,
    required this.callsCollection,
    required this.signalingDocPath,
    this.onRemoteStream,
    this.onConnectionStateChange,
    this.onIceConnectionStateChange,
  });
  
  /// Initialize (EXACT SAME as CallController.initialize)
  Future<void> initialize(MediaStream? sharedLocalStream) async {
    if (_isDisposed) return;
    
    try {
      print('[CallPeerConnection] Initializing: $localUserId ↔ $remoteUserId');
      print('[CallPeerConnection] Role: ${isInitiator ? "INITIATOR" : "RECEIVER"}');
      
      // Get or reuse local media stream
      if (sharedLocalStream != null) {
        _localStream = sharedLocalStream;
        print('[CallPeerConnection] Using shared local stream');
      } else {
        await _getLocalStream();
      }
      
      // Create peer connection
      await _createPeerConnection();
      
      // Start listening to Firestore for signaling
      _listenToCallDocument();
      _listenToIceCandidates();
      
      // If initiator, create and send offer
      if (isInitiator) {
        await _createOffer();
      }
      
      print('[CallPeerConnection] Initialization complete');
    } catch (e) {
      print('[CallPeerConnection] ❌ Initialization error: $e');
      rethrow;
    }
  }
  
  /// Get local media stream (EXACT SAME as CallController)
  Future<void> _getLocalStream() async {
    print('[CallPeerConnection] Getting local audio stream...');
    
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      print('[CallPeerConnection] ✅ Local stream acquired: ${_localStream?.id}');
      
      final audioTracks = _localStream?.getAudioTracks().length ?? 0;
      print('[CallPeerConnection] Audio tracks: $audioTracks');
    } catch (e) {
      print('[CallPeerConnection] ❌ Media acquisition error: $e');
      rethrow;
    }
  }
  
  /// Create RTCPeerConnection (EXACT SAME as CallController)
  Future<void> _createPeerConnection() async {
    print('[CallPeerConnection] Creating peer connection...');
    
    _peerConnection = await createPeerConnection(_iceServers, _sdpConstraints);

    // Add local stream tracks (EXACT SAME as CallController)
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
      print('[CallPeerConnection] ✅ Local tracks added');
    }

    // Handle ICE candidates (EXACT SAME as CallController)
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        _sendIceCandidate(candidate);
      }
    };

    // Handle remote stream (EXACT SAME as CallController)
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      print('[CallPeerConnection] 🎯 onTrack fired: $remoteUserId → $localUserId');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        print('[CallPeerConnection] ✅ Remote stream received: ${_remoteStream?.id}');
        onRemoteStream?.call(_remoteStream!);
      }
    };

    // Handle connection state (EXACT SAME as CallController)
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      print('[CallPeerConnection] 🔗 Connection state: $state');
      onConnectionStateChange?.call(state.toString());
    };

    // Handle ICE connection state (EXACT SAME as CallController)
    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      print('[CallPeerConnection] 🧊 ICE state: $state');
      onIceConnectionStateChange?.call(state);
    };
  }
  
  /// Create offer (EXACT SAME as CallController)
  Future<void> _createOffer() async {
    if (_offerCreated || _isDisposed) return;
    
    print('[CallPeerConnection] Creating offer...');
    
    try {
      RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });

      await _peerConnection!.setLocalDescription(offer);
      _offerCreated = true;

      // Send offer to Firestore
      await callsCollection.doc(signalingDocPath).set({
        'offer': {
          'type': offer.type,
          'sdp': offer.sdp,
        },
      }, SetOptions(merge: true));

      print('[CallPeerConnection] ✅ Offer created and sent');
    } catch (e) {
      print('[CallPeerConnection] ❌ Offer error: $e');
      rethrow;
    }
  }
  
  /// Create answer (EXACT SAME as CallController)
  Future<void> _createAnswer(Map<String, dynamic> offerData) async {
    if (_answerCreated || _isDisposed) return;
    
    print('[CallPeerConnection] Creating answer...');
    
    try {
      RTCSessionDescription offer = RTCSessionDescription(
        offerData['sdp'],
        offerData['type'],
      );

      await _peerConnection!.setRemoteDescription(offer);
      _remoteDescriptionSet = true;
      print('[CallPeerConnection] Remote offer set');

      // Process buffered ICE candidates
      await _processBufferedCandidates();

      RTCSessionDescription answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });

      await _peerConnection!.setLocalDescription(answer);
      _answerCreated = true;

      // Send answer to Firestore
      await callsCollection.doc(signalingDocPath).set({
        'answer': {
          'type': answer.type,
          'sdp': answer.sdp,
        },
      }, SetOptions(merge: true));

      print('[CallPeerConnection] ✅ Answer created and sent');
    } catch (e) {
      print('[CallPeerConnection] ❌ Answer error: $e');
      rethrow;
    }
  }
  
  /// Handle received answer (EXACT SAME as CallController)
  Future<void> _handleAnswer(Map<String, dynamic> answerData) async {
    if (_isDisposed || _remoteDescriptionSet) return;
    
    print('[CallPeerConnection] Handling answer...');
    
    try {
      RTCSessionDescription answer = RTCSessionDescription(
        answerData['sdp'],
        answerData['type'],
      );

      await _peerConnection!.setRemoteDescription(answer);
      _remoteDescriptionSet = true;
      print('[CallPeerConnection] Remote answer set');

      // Process buffered ICE candidates
      await _processBufferedCandidates();
    } catch (e) {
      print('[CallPeerConnection] ❌ Answer handling error: $e');
      rethrow;
    }
  }
  
  /// Send ICE candidate (EXACT SAME as CallController)
  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    if (_isDisposed) return;
    
    try {
      await callsCollection.doc(signalingDocPath).set({
        'iceCandidates': FieldValue.arrayUnion([
          {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
            'from': isInitiator ? 'caller' : 'receiver',
          }
        ]),
      }, SetOptions(merge: true));
    } catch (e) {
      print('[CallPeerConnection] ❌ ICE send error: $e');
    }
  }
  
  /// Process buffered ICE candidates (EXACT SAME as CallController)
  Future<void> _processBufferedCandidates() async {
    if (_candidateBuffer.isEmpty) return;
    
    print('[CallPeerConnection] Processing ${_candidateBuffer.length} buffered ICE candidates...');
    
    for (var candidate in _candidateBuffer) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (e) {
        print('[CallPeerConnection] ❌ Buffered candidate error: $e');
      }
    }
    
    _candidateBuffer.clear();
  }
  
  /// Listen to call document for offer/answer (EXACT SAME as CallController)
  void _listenToCallDocument() {
    print('[CallPeerConnection] Starting call document listener...');
    
    _callDocListener = callsCollection.doc(signalingDocPath).snapshots().listen((snapshot) {
      if (_isDisposed || !snapshot.exists) return;
      
      final rawData = snapshot.data();
      if (rawData == null) return;
      
      final data = Map<String, dynamic>.from(rawData);

      // If receiver, look for offer
      if (!isInitiator && !_answerCreated && data.containsKey('offer')) {
        final offerData = data['offer'];
        if (offerData is Map) {
          final offer = Map<String, dynamic>.from(offerData as Map);
          if (offer['sdp'] != null) {
            print('[CallPeerConnection] Offer received from Firestore');
            _createAnswer(offer);
          }
        }
      }

      // If caller, look for answer
      if (isInitiator && !_remoteDescriptionSet && data.containsKey('answer')) {
        final answerData = data['answer'];
        if (answerData is Map) {
          final answer = Map<String, dynamic>.from(answerData as Map);
          if (answer['sdp'] != null) {
            print('[CallPeerConnection] Answer received from Firestore');
            _handleAnswer(answer);
          }
        }
      }
    });
  }
  
  /// Listen to ICE candidates (EXACT SAME as CallController)
  void _listenToIceCandidates() {
    print('[CallPeerConnection] Starting ICE candidates listener...');
    
    _iceCandidatesListener = callsCollection.doc(signalingDocPath).snapshots().listen((snapshot) {
      if (_isDisposed || !snapshot.exists) return;
      
      final rawData = snapshot.data();
      if (rawData == null) return;
      
      final data = Map<String, dynamic>.from(rawData);

      if (!data.containsKey('iceCandidates')) return;
      
      final candidatesData = data['iceCandidates'];
      if (candidatesData is! List) return;
      
      final candidates = List.from(candidatesData);
      if (candidates.isEmpty) return;

      // Filter candidates from the other party
      final otherRole = isInitiator ? 'receiver' : 'caller';

      for (var candidateData in candidates) {
        if (candidateData is! Map) continue;
        
        final candidateMap = Map<String, dynamic>.from(candidateData as Map);
        final from = candidateMap['from'] as String?;
        
        // Only process candidates from the other party
        if (from == otherRole) {
          final candidate = RTCIceCandidate(
            candidateMap['candidate'],
            candidateMap['sdpMid'],
            candidateMap['sdpMLineIndex'],
          );

          // If remote description not set yet, buffer the candidate
          if (!_remoteDescriptionSet) {
            _candidateBuffer.add(candidate);
            print('[CallPeerConnection] ICE candidate buffered (remote description not set yet)');
          } else {
            _peerConnection!.addCandidate(candidate).then((_) {
              print('[CallPeerConnection] ICE candidate added to peer connection');
            }).catchError((e) {
              print('[CallPeerConnection] ❌ ICE candidate error: $e');
            });
          }
        }
      }
    });
  }
  
  /// Toggle mute/unmute local audio (EXACT SAME as CallController)
  Future<void> toggleMute(bool mute) async {
    if (_localStream == null) return;
    
    _localStream!.getAudioTracks().forEach((track) {
      track.enabled = !mute;
    });
    
    print('[CallPeerConnection] Microphone ${mute ? "muted" : "unmuted"}');
  }
  
  /// Toggle speaker/earpiece (EXACT SAME as CallController)
  Future<void> toggleSpeaker(bool speaker) async {
    try {
      await Helper.setSpeakerphoneOn(speaker);
      print('[CallPeerConnection] ${speaker ? "🔊 LOUDSPEAKER" : "🎧 EARPIECE"} enabled');
    } catch (e) {
      print('[CallPeerConnection] ❌ Speaker toggle error: $e');
    }
  }
  
  /// Get remote stream
  MediaStream? get remoteStream => _remoteStream;
  
  /// Get local stream
  MediaStream? get localStream => _localStream;
  
  /// Dispose and cleanup (EXACT SAME as CallController)
  Future<void> dispose() async {
    if (_isDisposed) return;
    
    print('[CallPeerConnection] Disposing peer connection: $localUserId ↔ $remoteUserId');
    _isDisposed = true;

    // Cancel Firestore listeners
    await _callDocListener?.cancel();
    await _iceCandidatesListener?.cancel();

    // Stop local stream tracks ONLY if we own them (not shared)
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        track.stop();
      });
      await _localStream?.dispose();
      _localStream = null;
    }

    // Stop remote stream tracks
    if (_remoteStream != null) {
      _remoteStream!.getTracks().forEach((track) {
        track.stop();
      });
      await _remoteStream?.dispose();
      _remoteStream = null;
    }

    // Close peer connection
    if (_peerConnection != null) {
      await _peerConnection?.close();
      await _peerConnection?.dispose();
      _peerConnection = null;
    }

    print('[CallPeerConnection] ✅ Disposal complete');
  }
}
