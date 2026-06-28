import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/group_call_providers.dart';
import '../../providers/user_providers.dart';
import '../../services/firestore_service.dart';
import 'group_audio_call_screen.dart';

/// Incoming group call screen - shows ringing UI for invited participants
/// Similar to IncomingCallScreen but for group calls
class IncomingGroupCallScreen extends ConsumerStatefulWidget {
  static const routeName = '/incoming-group-call';

  final String callId;
  final String groupId;
  final String initiatorId;

  const IncomingGroupCallScreen({
    super.key,
    required this.callId,
    required this.groupId,
    required this.initiatorId,
  });

  @override
  ConsumerState<IncomingGroupCallScreen> createState() =>
      _IncomingGroupCallScreenState();
}

class _IncomingGroupCallScreenState
    extends ConsumerState<IncomingGroupCallScreen> {
  
  StreamSubscription? _callSubscription;
  bool _isAnswering = false;
  bool _isDeclining = false;
  String? _groupName;

  @override
  void initState() {
    super.initState();
    _listenToCallStatus();
    _loadGroupName();
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    super.dispose();
  }

  /// Load group name from Firestore
  Future<void> _loadGroupName() async {
    try {
      final groupDoc = await FirestoreService().dmChats.doc(widget.groupId).get();
      if (groupDoc.exists) {
        final data = groupDoc.data();
        setState(() {
          _groupName = data?['name'] as String? ?? 'Group';
        });
      }
    } catch (e) {
      print('[IncomingGroupCallScreen] Error loading group name: $e');
    }
  }

  /// Listen to call status changes
  void _listenToCallStatus() {
    _callSubscription = FirestoreService()
        .groupCalls
        .doc(widget.callId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) {
        print('[IncomingGroupCallScreen] Call document deleted');
        _endCall();
        return;
      }

      final data = snapshot.data();
      if (data == null) return;

      final status = data['status'] as String?;

      // If call is no longer ringing, close this screen
      if (status != 'ringing') {
        print('[IncomingGroupCallScreen] Call status changed to $status');
        if (status == 'ended' && mounted) {
          _endCall();
        }
      }
    });
  }

  /// Accept the call
  Future<void> _acceptCall() async {
    if (_isAnswering || _isDeclining) return;

    setState(() {
      _isAnswering = true;
    });

    try {
      print('[IncomingGroupCallScreen] 📞 Accepting group call: ${widget.callId}');

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        throw Exception('Not authenticated');
      }

      final groupCallService = ref.read(groupCallServiceProvider);

      // Join the call
      await groupCallService.joinGroupCall(widget.callId, currentUserId);

      if (!mounted) return;

      print('[IncomingGroupCallScreen] ✅ Joined call, navigating to call screen');

      // Navigate to call screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GroupAudioCallScreen(
            callId: widget.callId,
            groupId: widget.groupId,
            groupName: _groupName ?? 'Group',
            isInitiator: false,
          ),
        ),
      );
    } catch (e) {
      print('[IncomingGroupCallScreen] ❌ Error accepting call: $e');

      if (!mounted) return;

      setState(() {
        _isAnswering = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to join call: $e')),
      );
    }
  }

  /// Decline the call
  Future<void> _declineCall() async {
    if (_isAnswering || _isDeclining) return;

    setState(() {
      _isDeclining = true;
    });

    try {
      print('[IncomingGroupCallScreen] ❌ Declining group call: ${widget.callId}');

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        throw Exception('Not authenticated');
      }

      final groupCallService = ref.read(groupCallServiceProvider);

      // Decline the call (just don't join - could optionally remove from participants)
      await groupCallService.declineGroupCall(widget.callId, currentUserId);

      if (!mounted) return;

      _endCall();
    } catch (e) {
      print('[IncomingGroupCallScreen] ❌ Error declining call: $e');

      if (!mounted) return;

      setState(() {
        _isDeclining = false;
      });
    }
  }

  /// End call and close screen
  void _endCall() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Get initiator info
    final initiatorAsync = ref.watch(userDocProvider(widget.initiatorId));

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Incoming Group Call',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),

            const Spacer(),

            // Group icon
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people,
                size: 60,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),

            const SizedBox(height: 32),

            // Group name
            Text(
              _groupName ?? 'Group Call',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Initiator name
            initiatorAsync.when(
              data: (initiator) {
                final name = initiator?.name ?? 'Unknown';
                return Text(
                  '$name is calling...',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                );
              },
              loading: () => Text(
                'Incoming call...',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              error: (_, __) => Text(
                'Incoming call...',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ),

            const Spacer(),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(40.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline button
                  Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: _isDeclining
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.call_end, size: 32),
                                color: Colors.white,
                                onPressed: _declineCall,
                              ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Decline',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),

                  // Accept button
                  Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: _isAnswering
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.call, size: 32),
                                color: Colors.white,
                                onPressed: _acceptCall,
                              ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Accept',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
