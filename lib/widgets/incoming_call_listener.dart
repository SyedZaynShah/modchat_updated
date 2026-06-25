import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/call_providers.dart';
import '../models/call_state.dart';
import '../screens/chat/incoming_call_screen.dart';

class IncomingCallListener extends ConsumerStatefulWidget {
  final Widget child;

  const IncomingCallListener({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<IncomingCallListener> createState() => _IncomingCallListenerState();
}

class _IncomingCallListenerState extends ConsumerState<IncomingCallListener> {
  String? _currentCallId;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<QuerySnapshot<Map<String, dynamic>>>>(
      incomingCallsStreamProvider,
      (previous, next) {
        next.whenData((snapshot) {
          if (snapshot.docs.isEmpty) {
            return;
          }

          // Get the most recent incoming call
          final call = snapshot.docs.first;
          final callId = call.id;
          final data = call.data();

          // Parse call state
          final statusStr = data['status'] as String?;
          final state = CallState.fromString(statusStr);

          // CRITICAL: Never show popup for missed calls
          // Only caller sees "No Answer" terminal state
          if (state == CallState.missed) {
            return;
          }

          // Only show for ringing calls
          if (state != CallState.ringing) {
            return;
          }

          // Prevent duplicate pop-ups for the same call
          if (_currentCallId == callId) {
            return;
          }

          _currentCallId = callId;

          final callerId = data['callerId'] as String? ?? '';
          final callerName = data['callerName'] as String? ?? 'Unknown';
          final callType = data['type'] as String? ?? 'voice'; // Get call type

          // Only show incoming call screen if not already on a call screen
          if (ModalRoute.of(context)?.settings.name != IncomingCallScreen.routeName) {
            Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: IncomingCallScreen.routeName),
                builder: (_) => IncomingCallScreen(
                  callId: callId,
                  callerId: callerId,
                  callerName: callerName,
                  callType: callType, // Pass call type
                ),
              ),
            ).then((_) {
              // Reset current call ID when screen is dismissed
              _currentCallId = null;
            });
          }
        });
      },
    );

    return widget.child;
  }
}
