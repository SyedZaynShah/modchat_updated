import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'group_call_service.dart';
import '../models/group_call_invitation.dart';
import '../screens/calls/incoming_group_call_dialog.dart';

/// PHASE 1.1: Incoming Group Call Listener
/// 
/// This service listens for group call invitations in the background.
/// When a new invitation arrives, it shows the incoming call dialog.
/// 
/// Duplicate protection: Only shows invitation once per invitationId.
class IncomingGroupCallListener {
  static final IncomingGroupCallListener _instance = IncomingGroupCallListener._internal();
  factory IncomingGroupCallListener() => _instance;
  IncomingGroupCallListener._internal();

  final GroupCallService _callService = GroupCallService();
  StreamSubscription? _invitationListener;
  
  // Duplicate protection: track active invitation
  String? _activeInvitationId;
  
  // Context for showing dialog
  BuildContext? _context;

  /// Start listening for incoming group call invitations
  void startListening(BuildContext context) {
    _context = context;
    
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      print('[GROUP_SIGNAL] ❌ Cannot start listener - no user');
      return;
    }

    print('[GROUP_SIGNAL] 🎧 Starting invitation listener for $currentUserId');

    _invitationListener?.cancel();
    _invitationListener = _callService
        .listenToIncomingGroupCallInvitations()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        _handleInvitation(doc);
      }
    });
  }

  /// Handle incoming invitation
  void _handleInvitation(doc) {
    try {
      final invitation = GroupCallInvitation.fromFirestore(doc);
      
      print('[GROUP_SIGNAL] INVITATION_RECEIVED -> ${invitation.targetUserId}');
      print('[GROUP_SIGNAL] Invitation ID: ${invitation.invitationId}');
      print('[GROUP_SIGNAL] Call ID: ${invitation.callId}');
      print('[GROUP_SIGNAL] From: ${invitation.inviterId}');
      
      // Duplicate protection
      if (_activeInvitationId == invitation.invitationId) {
        print('[GROUP_SIGNAL] ⚠️ Duplicate invitation - ignoring');
        return;
      }
      
      // Check if already expired
      if (invitation.expiresAt.toDate().isBefore(DateTime.now())) {
        print('[GROUP_SIGNAL] ⚠️ Invitation expired - ignoring');
        return;
      }
      
      // Show incoming call dialog
      _showIncomingCallDialog(invitation);
      
    } catch (e) {
      print('[GROUP_SIGNAL] ❌ Error handling invitation: $e');
    }
  }

  /// Show incoming call dialog
  void _showIncomingCallDialog(GroupCallInvitation invitation) {
    if (_context == null || !_context!.mounted) {
      print('[GROUP_SIGNAL] ❌ Cannot show dialog - no context');
      return;
    }

    // Set as active to prevent duplicates
    _activeInvitationId = invitation.invitationId;
    
    print('[GROUP_SIGNAL] INCOMING_SCREEN_SHOWN');

    showDialog(
      context: _context!,
      barrierDismissible: false,
      builder: (context) => IncomingGroupCallDialog(
        invitation: invitation,
        onDismiss: () {
          // Clear active invitation when dialog dismissed
          _activeInvitationId = null;
        },
      ),
    );
  }

  /// Stop listening
  void stopListening() {
    print('[GROUP_SIGNAL] 🔇 Stopping invitation listener');
    _invitationListener?.cancel();
    _invitationListener = null;
    _activeInvitationId = null;
    _context = null;
  }

  /// Dispose
  void dispose() {
    stopListening();
  }
}
