import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/group_call_invitation.dart';
import '../../services/group_call_service.dart';
import '../../services/firestore_service.dart';
import '../../models/user_model.dart';
import 'group_audio_call_screen.dart';

/// PHASE 1.1: Incoming Group Call Dialog
/// 
/// Shows when a group call invitation is received.
/// User can accept or decline.
/// 
/// This dialog appears exactly once per invitation.
class IncomingGroupCallDialog extends StatefulWidget {
  final GroupCallInvitation invitation;
  final VoidCallback onDismiss;

  const IncomingGroupCallDialog({
    Key? key,
    required this.invitation,
    required this.onDismiss,
  }) : super(key: key);

  @override
  State<IncomingGroupCallDialog> createState() => _IncomingGroupCallDialogState();
}

class _IncomingGroupCallDialogState extends State<IncomingGroupCallDialog> {
  final GroupCallService _callService = GroupCallService();
  final FirestoreService _firestoreService = FirestoreService();
  
  bool _isProcessing = false;
  ModUser? _inviterUser;
  String _groupName = 'Group';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Load inviter user data
    try {
      final userDoc = await _firestoreService.users.doc(widget.invitation.inviterId).get();
      if (userDoc.exists && mounted) {
        setState(() {
          _inviterUser = ModUser.fromMap(userDoc.data()!);
        });
      }
    } catch (e) {
      print('[GROUP_SIGNAL] Error loading inviter: $e');
    }

    // Load group name
    try {
      final groupDoc = await _firestoreService.dmChats.doc(widget.invitation.groupId).get();
      if (groupDoc.exists && mounted) {
        final data = groupDoc.data();
        setState(() {
          _groupName = data?['name'] ?? 'Group';
        });
      }
    } catch (e) {
      print('[GROUP_SIGNAL] Error loading group: $e');
    }
  }

  Future<void> _acceptCall() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      print('[GROUP_SIGNAL] User accepting invitation ${widget.invitation.invitationId}');
      
      // Accept invitation
      await _callService.acceptInvitation(
        widget.invitation.invitationId,
        widget.invitation.callId,
      );

      if (!mounted) return;

      // Close dialog
      widget.onDismiss();
      Navigator.of(context).pop();

      // Navigate to call screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => GroupAudioCallScreen(
            callId: widget.invitation.callId,
            groupId: widget.invitation.groupId,
            groupName: _groupName,
            isInitiator: false,
          ),
        ),
      );

      print('[GROUP_SIGNAL] ✅ User joined call ${widget.invitation.callId}');
    } catch (e) {
      print('[GROUP_SIGNAL] ❌ Error accepting call: $e');
      
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join call: $e')),
        );
      }
    }
  }

  Future<void> _declineCall() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      print('[GROUP_SIGNAL] User declining invitation ${widget.invitation.invitationId}');
      
      // Decline invitation
      await _callService.declineInvitation(
        widget.invitation.invitationId,
        widget.invitation.callId,
      );

      if (!mounted) return;

      // Close dialog
      widget.onDismiss();
      Navigator.of(context).pop();

      print('[GROUP_SIGNAL] ✅ User declined call ${widget.invitation.callId}');
    } catch (e) {
      print('[GROUP_SIGNAL] ❌ Error declining call: $e');
      
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to decline call: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inviterName = _inviterUser?.name ?? 'Someone';

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      backgroundColor: isDark ? const Color(0xFF171A21) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.green.withOpacity(0.2),
              backgroundImage: _inviterUser?.profileImageUrl != null
                  ? NetworkImage(_inviterUser!.profileImageUrl!)
                  : null,
              child: _inviterUser?.profileImageUrl == null
                  ? Icon(Icons.group, size: 50, color: Colors.green)
                  : null,
            ),
            
            const SizedBox(height: 20),
            
            // Title
            Text(
              'Incoming Group Call',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Group name
            Text(
              _groupName,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            
            const SizedBox(height: 4),
            
            // Inviter
            Text(
              'From: $inviterName',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Buttons
            if (_isProcessing)
              CircularProgressIndicator()
            else
              Row(
                children: [
                  // Decline button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _declineCall,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.call_end),
                          const SizedBox(width: 8),
                          Text('Decline'),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Accept button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _acceptCall,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.call),
                          const SizedBox(width: 8),
                          Text('Accept'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
