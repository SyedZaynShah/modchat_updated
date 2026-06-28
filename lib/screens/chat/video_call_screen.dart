import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../providers/call_providers.dart';
import '../../models/call_state.dart';
import '../../services/call_controller.dart';

/// Video Call Screen - Premium UI (Phase 3.5)
/// Production-grade 1-to-1 video calling
/// FaceTime/WhatsApp/Telegram-level quality
class VideoCallScreen extends ConsumerStatefulWidget {
  static const routeName = '/video-call';

  final String callId;
  final String peerId;
  final String peerName;
  final bool isIncoming;

  const VideoCallScreen({
    super.key,
    required this.callId,
    required this.peerId,
    required this.peerName,
    this.isIncoming = false,
  });

  @override
  ConsumerState<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends ConsumerState<VideoCallScreen> {
  CallState _currentState = CallState.calling;
  StreamSubscription? _callSubscription;
  Timer? _durationTimer;
  
  // WebRTC controller
  CallController? _callController;
  bool _webrtcInitialized = false;

  // Call duration
  Duration _callDuration = Duration.zero;
  DateTime? _connectedAt;

  // Media state - PRODUCTION HARDENING: Explicit UI state management
  bool _isCameraEnabled = true;
  bool _isFrontCamera = true;
  bool _isMuted = false;
  bool _localVideoReady = false;  // Safety: Only show local video when ready
  bool _remoteVideoReady = false; // Safety: Only show remote video when ready
  
  // Reconnection state
  bool _isReconnecting = false;

  @override
  void initState() {
    super.initState();
    _listenToCallStatus();
    _initializeWebRTC();
  }

  /// Initialize WebRTC for video call
  Future<void> _initializeWebRTC() async {
    if (_webrtcInitialized) return;
    
    print('[VideoCallScreen] Initializing WebRTC for video call...');
    
    try {
      // Small delay to ensure Firestore call document is created
      await Future.delayed(const Duration(milliseconds: 500));
      
      _callController = CallController(
        callId: widget.callId,
        isInitiator: !widget.isIncoming,
        isVideoCall: true, // ← VIDEO CALL
        onRemoteStream: (MediaStream stream) {
          print('[VideoCallScreen] 📹 REMOTE_STREAM_CALLBACK: Remote video stream received');
          if (mounted) {
            setState(() {
              _remoteVideoReady = true; // PRODUCTION HARDENING: Explicit ready flag
            });
            print('[VideoCallScreen] ✅ UI_UPDATE: Remote video ready state updated');
          }
        },
        onConnectionStateChange: (String state) {
          print('[VideoCallScreen] 🔗 CONNECTION_STATE_CALLBACK: $state');
          
          // Handle connection failure
          if (state == 'failed' && mounted) {
            _showConnectionFailedDialog();
          }
        },
        onReconnectionStateChange: (bool isReconnecting) {
          print('[VideoCallScreen] 🔄 RECONNECTION_STATE: ${isReconnecting ? "reconnecting" : "connected"}');
          if (mounted) {
            setState(() {
              _isReconnecting = isReconnecting;
            });
          }
        },
      );
      
      await _callController!.initialize();
      _webrtcInitialized = true;
      print('[VideoCallScreen] ✅ WEBRTC_INIT: WebRTC initialized successfully');
      
      // PRODUCTION HARDENING: Check renderer readiness
      if (_callController!.localRendererReady) {
        print('[VideoCallScreen] ✅ RENDERER_CHECK: Local renderer ready');
        if (mounted) {
          setState(() {
            _localVideoReady = true;
          });
        }
      } else {
        print('[VideoCallScreen] ⚠️ RENDERER_WARNING: Local renderer not ready!');
      }
      
      if (mounted) {
        setState(() {
          // Trigger rebuild
        });
      }
    } catch (e) {
      print('[VideoCallScreen] ❌ ERROR initializing WebRTC: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize video call: $e')),
        );
      }
    }
  }

  void _listenToCallStatus() {
    print('[VideoCallScreen] 🎧 Starting Firestore listener for call ${widget.callId}');
    
    final callService = ref.read(callServiceProvider);
    _callSubscription = callService.listenToCall(widget.callId).listen((snapshot) {
      if (!snapshot.exists) {
        print('[VideoCallScreen] ⚠️ Call document no longer exists, closing screen');
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      final data = snapshot.data();
      if (data == null) return;

      final statusStr = data['status'] as String?;
      final newState = CallState.fromString(statusStr);
      
      print('[VideoCallScreen] 📡 Status: $statusStr → ${newState.name}');

      if (newState != _currentState) {
        setState(() {
          _currentState = newState;
        });

        // Start duration timer when call connects
        if (newState == CallState.accepted && _connectedAt == null) {
          _connectedAt = DateTime.now();
          _startDurationTimer();
        }
      }

      // Handle terminal states
      if (newState.isTerminal) {
        _handleTerminalState(newState);
      }
    });
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedAt != null && mounted) {
        setState(() {
          _callDuration = DateTime.now().difference(_connectedAt!);
        });
      }
    });
  }

  void _handleTerminalState(CallState state) {
    print('[VideoCallScreen] 🔴 Terminal state: ${state.name}');
    
    _durationTimer?.cancel();
    
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    print('[CALL_RECOVERY] ========================================');
    print('[CALL_RECOVERY] VideoCallScreen.dispose() called');
    print('[CALL_RECOVERY] Call ID: ${widget.callId}');
    print('[CALL_RECOVERY] Will dispose WebRTC controller: ${_callController != null}');
    
    _durationTimer?.cancel();
    _callSubscription?.cancel();
    _callController?.dispose();
    
    print('[CALL_RECOVERY] VideoCallScreen.dispose() complete');
    print('[CALL_RECOVERY] ========================================');
    
    super.dispose();
  }

  Future<void> _endCall() async {
    final callService = ref.read(callServiceProvider);
    try {
      await callService.endCall(widget.callId);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('[VideoCallScreen] ERROR ending call: $e');
    }
  }

  void _showConnectionFailedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Connection Lost'),
        content: const Text('Unable to reconnect. The call has been ended.'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop(); // Close dialog
              await _endCall();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleCamera() async {
    print('[VideoCallScreen] 🎬 UI_CAMERA_TOGGLE: User toggling camera (current: $_isCameraEnabled)');
    setState(() {
      _isCameraEnabled = !_isCameraEnabled;
    });
    print('[VideoCallScreen] 🎬 UI_STATE_UPDATE: Camera enabled = $_isCameraEnabled');
    await _callController?.toggleCamera(_isCameraEnabled);
  }

  Future<void> _switchCamera() async {
    print('[VideoCallScreen] 🔄 UI_CAMERA_SWITCH: User switching camera (current: ${_isFrontCamera ? "front" : "back"})');
    await _callController?.switchCamera();
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
    print('[VideoCallScreen] 🔄 UI_STATE_UPDATE: Front camera = $_isFrontCamera');
  }

  Future<void> _toggleMute() async {
    print('[VideoCallScreen] 🎤 UI_MUTE_TOGGLE: User toggling mute (current: $_isMuted)');
    setState(() {
      _isMuted = !_isMuted;
    });
    print('[VideoCallScreen] 🎤 UI_STATE_UPDATE: Muted = $_isMuted');
    await _callController?.toggleMute(_isMuted);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _getStatusText() {
    // Show reconnection status first
    if (_isReconnecting) {
      return 'Reconnecting...';
    }
    
    // Normal status display
    if (_currentState == CallState.accepted && _connectedAt != null) {
      return _formatDuration(_callDuration);
    }
    return _currentState.displayText;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // REMOTE VIDEO (full screen background)
          Positioned.fill(
            child: _buildRemoteVideo(),
          ),
          
          // LOCAL VIDEO PREVIEW (floating top-right)
          Positioned(
            top: 56,
            right: 20,
            child: _buildLocalPreview(),
          ),
          
          // TOP INFO BAR (centered)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopInfoBar(),
          ),
          
          // BOTTOM CONTROLS (modern floating pill)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomControls(),
          ),
        ],
      ),
    );
  }

  /// Remote video - full screen with cover fit
  /// PRODUCTION HARDENING: Only render when ready
  Widget _buildRemoteVideo() {
    // Safety check: Only render video if renderer is ready
    if (_callController?.remoteRenderer != null && 
        _callController!.remoteRendererReady && 
        _remoteVideoReady) {
      return RTCVideoView(
        _callController!.remoteRenderer!,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        mirror: false,
      );
    }

    // Waiting for remote video - show placeholder
    return Container(
      color: const Color(0xFF1A1F3A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF5865F2).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                size: 50,
                color: Color(0xFF5865F2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.peerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _remoteVideoReady ? 'Connecting...' : 'Waiting for video...',
              style: const TextStyle(
                color: Color(0xFFBEBEBE),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Local preview - floating mini window with shadow
  /// PRODUCTION HARDENING: Only render when ready, explicit camera-off state
  Widget _buildLocalPreview() {
    // Safety check: Only render if renderer exists and is ready
    if (_callController?.localRenderer == null || !_callController!.localRendererReady) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 110,
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _isCameraEnabled && _localVideoReady
            ? RTCVideoView(
                _callController!.localRenderer!,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                mirror: _isFrontCamera, // Mirror only for front camera
              )
            : Container(
                color: const Color(0xFF2A2A2A),
                child: const Center(
                  child: Icon(
                    Icons.videocam_off,
                    color: Colors.white70,
                    size: 32,
                  ),
                ),
              ),
      ),
    );
  }

  /// Top info bar - centered contact name, status, and duration
  Widget _buildTopInfoBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.peerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    color: Colors.black45,
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _getStatusText(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                shadows: const [
                  Shadow(
                    color: Colors.black45,
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom controls - modern floating pill design
  Widget _buildBottomControls() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40, left: 20, right: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Camera toggle
            _buildControlButton(
              icon: _isCameraEnabled ? Icons.videocam : Icons.videocam_off,
              isActive: !_isCameraEnabled,
              onTap: _toggleCamera,
            ),
            
            // Camera switch
            _buildControlButton(
              icon: Icons.flip_camera_ios,
              isActive: false,
              onTap: _switchCamera,
            ),
            
            // Mute toggle
            _buildControlButton(
              icon: _isMuted ? Icons.mic_off : Icons.mic,
              isActive: _isMuted,
              onTap: _toggleMute,
            ),
            
            // End call (larger, emphasized)
            _buildEndCallButton(),
          ],
        ),
      ),
    );
  }

  /// Control button - circular with dark background
  Widget _buildControlButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF5865F2) // Blue when active
              : const Color(0xFF2A2A2A).withOpacity(0.8), // Dark when inactive
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }

  /// End call button - larger, red, emphasized
  Widget _buildEndCallButton() {
    return GestureDetector(
      onTap: _endCall,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFFFF3B30),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF3B30).withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.call_end,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}
