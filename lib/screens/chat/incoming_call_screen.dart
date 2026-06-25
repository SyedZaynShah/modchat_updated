import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/call_providers.dart';
import '../../models/call_state.dart';
import '../../widgets/call_status_overlay.dart';
import 'call_screen.dart';
import 'video_call_screen.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  static const routeName = '/incoming-call';
  
  final String callId;
  final String callerId;
  final String callerName;
  final String callType; // 'voice' or 'video'

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerId,
    required this.callerName,
    this.callType = 'voice', // Default to voice for backward compatibility
  });

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  StreamSubscription? _callSubscription;
  bool _showingTerminalState = false;

  @override
  void initState() {
    super.initState();
    _listenToCallStatus();
  }

  void _listenToCallStatus() {
    final callService = ref.read(callServiceProvider);
    _callSubscription = callService.listenToCall(widget.callId).listen((snapshot) {
      if (!snapshot.exists) {
        if (mounted && !_showingTerminalState) {
          Navigator.of(context).pop();
        }
        return;
      }

      final data = snapshot.data();
      if (data == null) return;

      final statusStr = data['status'] as String?;
      final state = CallState.fromString(statusStr);

      // Handle terminal states
      if (state.isTerminal && !_showingTerminalState) {
        // For declined, we're the receiver, so just close
        // (caller will see "Call Declined" message)
        if (state == CallState.declined) {
          if (mounted) {
            Navigator.of(context).pop();
          }
        } else {
          // For other terminal states, show overlay
          _handleTerminalState(state);
        }
      }
    });
  }

  void _handleTerminalState(CallState state) {
    if (_showingTerminalState) return;
    
    _showingTerminalState = true;
    
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callService = ref.read(callServiceProvider);

    return WillPopScope(
      onWillPop: () async => !_showingTerminalState,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top section
                Column(
                  children: [
                    const SizedBox(height: 60),
                    // Avatar
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5865F2),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF5865F2).withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Caller name
                    Text(
                      widget.callerName,
                      style: const TextStyle(
                        color: Color(0xFF1A1F3A),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    // Call type
                    Text(
                      widget.callType == 'video' 
                          ? 'Incoming Video Call' 
                          : 'Incoming Voice Call',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                // Bottom buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Decline button
                    Column(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            try {
                              await callService.declineCall(widget.callId);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to decline call: $e')),
                                );
                              }
                            }
                          },
                          child: Container(
                            width: 70,
                            height: 70,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.call_end_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Decline',
                          style: TextStyle(
                            color: Color(0xFF1A1F3A),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    // Accept button
                    Column(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            try {
                              await callService.acceptCall(widget.callId);
                              if (context.mounted) {
                                // Route to appropriate screen based on call type
                                if (widget.callType == 'video') {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => VideoCallScreen(
                                        callId: widget.callId,
                                        peerId: widget.callerId,
                                        peerName: widget.callerName,
                                        isIncoming: true,
                                      ),
                                    ),
                                  );
                                } else {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => CallScreen(
                                        callId: widget.callId,
                                        peerId: widget.callerId,
                                        peerName: widget.callerName,
                                        isIncoming: true,
                                      ),
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to accept call: $e')),
                                );
                              }
                            }
                          },
                          child: Container(
                            width: 70,
                            height: 70,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.call_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Accept',
                          style: TextStyle(
                            color: Color(0xFF1A1F3A),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
