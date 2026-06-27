import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/group_call_service.dart';
import '../models/group_call_invitation.dart';
import '../screens/calls/incoming_group_call_dialog.dart';

/// PHASE 1.1: Global Incoming Group Call Listener Widget
/// 
/// Wraps the entire app to listen for group call invitations.
/// Uses dedicated invitation documents for reliable delivery.
/// 
/// Each user receives invitations where targetUserId == currentUserId.
/// Shows incoming call dialog exactly once per invitation.
class IncomingGroupCallListener extends ConsumerStatefulWidget {
  final Widget child;

  const IncomingGroupCallListener({super.key, required this.child});

  @override
  ConsumerState<IncomingGroupCallListener> createState() =>
      _IncomingGroupCallListenerState();
}

class _IncomingGroupCallListenerState
    extends ConsumerState<IncomingGroupCallListener> {
  
  final GroupCallService _callService = GroupCallService();
  
  // Duplicate protection: track active invitation
  String? _activeInvitationId;
  
  // Track shown invitations to prevent duplicates
  final Set<String> _shownInvitationIds = {};

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    if (currentUserId == null) {
      return widget.child;
    }

    return StreamBuilder(
      stream: _callService.listenToIncomingGroupCallInvitations(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          final docs = snapshot.data!.docs;
          
          for (var doc in docs) {
            _handleInvitation(context, doc);
          }
        }
        
        return widget.child;
      },
    );
  }

  /// Handle incoming invitation
  void _handleInvitation(BuildContext context, doc) {
    try {
      final invitation = GroupCallInvitation.fromFirestore(doc);
      
      print('[GROUP_SIGNAL] INVITATION_RECEIVED -> ${invitation.targetUserId}');
      print('[GROUP_SIGNAL] Invitation ID: ${invitation.invitationId}');
      print('[GROUP_SIGNAL] Call ID: ${invitation.callId}');
      print('[GROUP_SIGNAL] From: ${invitation.inviterId}');
      
      // Duplicate protection - check if already shown
      if (_shownInvitationIds.contains(invitation.invitationId)) {
        print('[GROUP_SIGNAL] ⚠️ Already shown - ignoring');
        return;
      }
      
      // Duplicate protection - check if currently active
      if (_activeInvitationId == invitation.invitationId) {
        print('[GROUP_SIGNAL] ⚠️ Currently active - ignoring');
        return;
      }
      
      // Check if already expired
      if (invitation.expiresAt.toDate().isBefore(DateTime.now())) {
        print('[GROUP_SIGNAL] ⚠️ Invitation expired - ignoring');
        return;
      }
      
      // Mark as shown and active
      _shownInvitationIds.add(invitation.invitationId);
      _activeInvitationId = invitation.invitationId;
      
      // Show incoming call dialog
      print('[GROUP_SIGNAL] INCOMING_SCREEN_SHOWN');
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => IncomingGroupCallDialog(
          invitation: invitation,
          onDismiss: () {
            // Clear active invitation when dialog dismissed
            _activeInvitationId = null;
            print('[GROUP_SIGNAL] Dialog dismissed for ${invitation.invitationId}');
          },
        ),
      );
      
    } catch (e) {
      print('[GROUP_SIGNAL] ❌ Error handling invitation: $e');
    }
  }

  @override
  void dispose() {
    _shownInvitationIds.clear();
    _activeInvitationId = null;
    super.dispose();
  }
}
