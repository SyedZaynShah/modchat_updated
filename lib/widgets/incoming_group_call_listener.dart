import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/group_call_providers.dart';
import '../screens/calls/incoming_group_call_screen.dart';

/// Global listener for incoming group calls
/// Wraps the entire app to detect incoming group calls from any screen
/// Similar to IncomingCallListener but for group calls
class IncomingGroupCallListener extends ConsumerStatefulWidget {
  final Widget child;

  const IncomingGroupCallListener({super.key, required this.child});

  @override
  ConsumerState<IncomingGroupCallListener> createState() =>
      _IncomingGroupCallListenerState();
}

class _IncomingGroupCallListenerState
    extends ConsumerState<IncomingGroupCallListener> {
  
  // Track which calls we've already shown to avoid duplicate screens
  final Set<String> _shownCallIds = {};
  
  @override
  Widget build(BuildContext context) {
    // Listen to incoming group calls stream
    ref.listen<AsyncValue<QuerySnapshot<Map<String, dynamic>>>>(
      incomingGroupCallsStreamProvider,
      (previous, next) {
        next.whenData((snapshot) {
          if (snapshot.docs.isEmpty) {
            print('[IncomingGroupCallListener] No incoming group calls');
            return;
          }

          for (var doc in snapshot.docs) {
            final callId = doc.id;
            final data = doc.data();

            // Skip if already shown
            if (_shownCallIds.contains(callId)) {
              continue;
            }

            final currentUserId = FirebaseAuth.instance.currentUser?.uid;
            if (currentUserId == null) continue;

            final groupId = data['groupId'] as String?;
            final initiatorId = data['initiatorId'] as String?;
            final participants = List<String>.from(data['participants'] as List? ?? []);
            final status = data['status'] as String?;

            // Validate
            if (groupId == null || initiatorId == null || status != 'ringing') {
              continue;
            }

            // Don't show to initiator (they started the call)
            if (initiatorId == currentUserId) {
              continue;
            }

            // Verify current user is a participant
            if (!participants.contains(currentUserId)) {
              continue;
            }

            print('[IncomingGroupCallListener] 🔔 Incoming group call: $callId from group $groupId');

            // Mark as shown
            _shownCallIds.add(callId);

            // Don't show if already on an incoming group call screen
            if (ModalRoute.of(context)?.settings.name == IncomingGroupCallScreen.routeName) {
              print('[IncomingGroupCallListener] Already on incoming call screen, skipping');
              continue;
            }

            // Navigate to incoming group call screen
            Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: IncomingGroupCallScreen.routeName),
                builder: (_) => IncomingGroupCallScreen(
                  callId: callId,
                  groupId: groupId,
                  initiatorId: initiatorId,
                ),
              ),
            ).then((_) {
              // Remove from shown list when screen is dismissed
              // This allows re-showing if the call is somehow re-triggered
              _shownCallIds.remove(callId);
            });
          }
        });
      },
    );

    return widget.child;
  }
}
