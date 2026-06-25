import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../providers/call_providers.dart';
import '../../models/call_state.dart';
import '../../models/network_quality.dart';
import '../../widgets/call_status_overlay.dart';
import '../../services/call_controller.dart';
import '../../widgets/network_quality_indicator.dart';

class CallScreen extends ConsumerStatefulWidget {
  static const routeName = '/call';

  final String callId;
  final String peerId;
  final String peerName;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.callId,
    required this.peerId,
    required this.peerName,
    this.isIncoming = false,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with SingleTickerProviderStateMixin {
  CallState _currentState = CallState.calling;
  StreamSubscription? _callSubscription;
  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _showingTerminalState = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _callDurationTimer;
  int _callDurationSeconds = 0;
  String _animatedStatus = 'Ringing';
  int _dotCount = 0;
  Timer? _dotTimer;
  
  // Reconnection state
  bool _isReconnecting = false;
  
  // Network quality state
  NetworkQuality _networkQuality = NetworkQuality.good;
  
  // WebRTC controller
  CallController? _callController;
  bool _webrtcInitialized = false;

  @override
  void initState() {
    super.initState();
    _setupPulseAnimation();
    _listenToCallStatus();
    _initializeWebRTC();
  }

  /// Initialize WebRTC when screen opens
  Future<void> _initializeWebRTC() async {
    if (_webrtcInitialized) return;
    
    print('[CallScreen] Initializing WebRTC...');
    
    try {
      // Small delay to ensure Firestore call document is created
      await Future.delayed(const Duration(milliseconds: 500));
      
      _callController = CallController(
        callId: widget.callId,
        isInitiator: !widget.isIncoming,
        onRemoteStream: (MediaStream stream) {
          print('[CallScreen] Remote stream received');
          // Remote audio will play automatically through device speaker/earpiece
        },
        onConnectionStateChange: (String state) {
          print('[CallScreen] WebRTC connection state: $state');
          
          // Handle connection failure
          if (state == 'failed' && mounted) {
            _showConnectionFailedDialog();
          }
        },
        onReconnectionStateChange: (bool isReconnecting) {
          print('[CallScreen] 🔄 RECONNECTION_STATE: ${isReconnecting ? "reconnecting" : "connected"}');
          if (mounted) {
            setState(() {
              _isReconnecting = isReconnecting;
            });
          }
        },
        onNetworkQualityChange: (NetworkQuality quality) {
          print('[CallScreen] 📶 NETWORK_QUALITY: ${quality.displayText}');
          if (mounted) {
            setState(() {
              _networkQuality = quality;
            });
          }
        },
      );
      
      await _callController!.initialize();
      _webrtcInitialized = true;
      print('[CallScreen] WebRTC initialized successfully');
    } catch (e) {
      print('[CallScreen] ERROR initializing WebRTC: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize call: $e')),
        );
      }
    }
  }

  void _setupPulseAnimation() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (_currentState == CallState.calling) {
      _pulseController.repeat(reverse: true);
    }
  }

  void _startRingingAnimation() {
    _dotTimer?.cancel();
    _dotTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _dotCount = (_dotCount + 1) % 4;
        _animatedStatus = 'Ringing${'.' * _dotCount}';
      });
    });
  }

  void _stopRingingAnimation() {
    _dotTimer?.cancel();
    _dotTimer = null;
  }

  void _startCallDurationTimer() {
    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _callDurationSeconds++;
      });
    });
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _listenToCallStatus() {
    print('[CallScreen] 🎧 Starting Firestore listener for call ${widget.callId}');
    
    final callService = ref.read(callServiceProvider);
    _callSubscription = callService.listenToCall(widget.callId).listen((snapshot) {
      if (!snapshot.exists) {
        print('[CallScreen] ⚠️ Call document no longer exists, closing screen');
        if (mounted && !_showingTerminalState) {
          Navigator.of(context).pop();
        }
        return;
      }

      final data = snapshot.data();
      if (data == null) {
        print('[CallScreen] ⚠️ Call document data is null');
        return;
      }

      final statusStr = data['status'] as String?;
      final newState = CallState.fromString(statusStr);
      
      print('[CallScreen] 📡 Firestore update: status = "$statusStr" → ${newState.name} (current: ${_currentState.name})');

      if (newState == _currentState) {
        print('[CallScreen] ℹ️ State unchanged, skipping UI update');
        return;
      }

      final oldState = _currentState;
      setState(() {
        _currentState = newState;
      });
      
      print('[CallScreen] ✅ UI STATE UPDATED: ${oldState.name} → ${newState.name}');

      // Handle animations based on state
      if (newState == CallState.ringing && oldState == CallState.calling) {
        print('[CallScreen] 🔔 Transition: calling → ringing (starting ring animation)');
        _pulseController.stop();
        _pulseController.reset();
        _startRingingAnimation();
      }

      if (newState == CallState.accepted) {
        print('[CallScreen] ✅ CALL ACCEPTED: Starting duration timer');
        _stopRingingAnimation();
        _pulseController.stop();
        _startCallDurationTimer();
        
        // Ensure audio is routed to earpiece (unless speaker button was already pressed)
        if (!_isSpeaker) {
          _ensureEarpieceAudio();
        }
      }

      // Handle terminal states
      if (newState.isTerminal) {
        print('[CallScreen] 🔴 Terminal state reached: ${newState.name}');
        _handleTerminalState(newState);
      }
    }, onError: (e) {
      print('[CallScreen] ❌ Error listening to call: $e');
    });
  }

  void _handleTerminalState(CallState state) {
    if (_showingTerminalState) return;

    _showingTerminalState = true;
    _pulseController.stop();
    _stopRingingAnimation();
    _callDurationTimer?.cancel();

    // Show the terminal state overlay for 2 seconds
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      showCallStatusOverlay(context, state);
    });

    // Close screen after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    _pulseController.dispose();
    _callDurationTimer?.cancel();
    _dotTimer?.cancel();
    
    // Dispose WebRTC controller
    _callController?.dispose();
    
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to end call: $e')),
        );
      }
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

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    // Toggle actual microphone mute via WebRTC
    _callController?.toggleMute(_isMuted);
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeaker = !_isSpeaker;
    });
    // Toggle actual speaker via WebRTC
    _callController?.toggleSpeaker(_isSpeaker);
  }
  
  /// Ensure audio is routed to earpiece (called when call connects)
  void _ensureEarpieceAudio() {
    print('[CallScreen] 🎧 Ensuring audio routed to earpiece on connection');
    _callController?.setEarpieceAudio();
  }

  String _getStatusText() {
    // Show reconnection status first
    if (_isReconnecting) {
      return 'Reconnecting...';
    }
    
    switch (_currentState) {
      case CallState.calling:
        return 'Calling...';
      case CallState.ringing:
        return _animatedStatus;
      case CallState.accepted:
        return 'Connected';
      default:
        return _currentState.displayText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_showingTerminalState,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B141A),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.5),
              radius: 1.2,
              colors: [
                const Color(0xFF1A2633).withOpacity(0.3),
                const Color(0xFF0B141A),
              ],
            ),
          ),
          child: SafeArea(
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // TOP SECTION
                  _buildTopSection(),

                  // CENTER SECTION (breathing room)
                  const Spacer(),

                  // BOTTOM SECTION
                  _buildBottomSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar with pulse animation
            Center(
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _currentState == CallState.calling
                        ? _pulseAnimation.value
                        : 1.0,
                    child: child,
                  );
                },
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF1E3A5F),
                        Color(0xFF0F2744),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E3A5F).withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      widget.peerName.isNotEmpty
                          ? widget.peerName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                widget.peerName,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: Colors.white,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(height: 8),

            // Network quality indicator
            NetworkQualityIndicator(quality: _networkQuality),

            const SizedBox(height: 8),

            // Status
            Text(
              _getStatusText(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.8),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            // Call duration (only when connected)
            if (_currentState == CallState.accepted) ...[
              const SizedBox(height: 4),
              Text(
                _formatDuration(_callDurationSeconds),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSection() {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 50),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Control buttons (only when accepted)
            if (_currentState == CallState.accepted)
              Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildControlButton(
                      icon: _isMuted ? Icons.mic_off : Icons.mic,
                      isActive: _isMuted,
                      onTap: _toggleMute,
                    ),
                    const SizedBox(width: 32),
                    _buildControlButton(
                      icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
                      isActive: _isSpeaker,
                      onTap: _toggleSpeaker,
                    ),
                  ],
                ),
              ),

            // End call button (hide on terminal states)
            if (!_currentState.isTerminal)
              Center(
                child: GestureDetector(
                  onTap: _endCall,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF3B30).withOpacity(0.4),
                          blurRadius: 16,
                          spreadRadius: 0,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF34C759)
              : const Color(0xFF1C2630),
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive
                ? const Color(0xFF34C759)
                : const Color(0xFF2A3744),
            width: 1.5,
          ),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}
