import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/group_call_service.dart';
import '../../services/firestore_service.dart';
import '../../models/group_call.dart';
import '../../models/user_model.dart';

/// PHASE 1.1: Group Room Verification Test Screen
/// 
/// NO WebRTC. NO CallController. NO CallService. NO RTCPeerConnection.
/// NO MediaStream. NO offer/answer. NO ICE candidates.
/// 
/// ONLY room management:
/// - Create room
/// - Join room
/// - Leave room
/// - Real-time participant updates

class GroupCallTestScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;

  const GroupCallTestScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  ConsumerState<GroupCallTestScreen> createState() => _GroupCallTestScreenState();
}

class _GroupCallTestScreenState extends ConsumerState<GroupCallTestScreen> {
  final GroupCallService _groupCallService = GroupCallService();
  final FirestoreService _firestoreService = FirestoreService();
  
  String? _activeCallId;
  GroupCall? _currentCall;
  Map<String, ModUser> _userCache = {};
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Group Call Test')),
        body: Center(child: Text('Not authenticated')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text('Group Call Test'),
        centerTitle: true,
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<GroupCall?>(
        stream: _listenToActiveCall(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _currentCall == null) {
            return Center(child: CircularProgressIndicator());
          }

          _currentCall = snapshot.data;
          _activeCallId = _currentCall?.callId;

          // Load user data for participants
          if (_currentCall != null) {
            _loadParticipantData(_currentCall!);
          }

          final isInCall = _currentCall != null && 
                          _currentCall!.joinedParticipants.contains(currentUserId);
          final isInvited = _currentCall != null && 
                           _currentCall!.invitedParticipants.contains(currentUserId);
          final hasDeclined = _currentCall != null &&
                             _currentCall!.declinedParticipants.contains(currentUserId);
          final hasLeft = _currentCall != null &&
                         _currentCall!.leftParticipants.contains(currentUserId);
          final canRejoin = (hasDeclined || hasLeft) && 
                           _currentCall != null &&
                           _currentCall!.status != GroupCallStatus.ended;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(),
                SizedBox(height: 16),
                
                if (_currentCall == null)
                  _buildCreateButton(currentUserId)
                else if (isInvited)
                  _buildInvitationButtons(currentUserId)
                else if (isInCall)
                  _buildLeaveButton(currentUserId)
                else if (canRejoin)
                  _buildRejoinButton(currentUserId, hasDeclined)
                else
                  _buildAlreadyRespondedCard(),
                
                SizedBox(height: 16),
                
                if (_currentCall != null) ...[
                  _buildCallInfoCard(),
                  SizedBox(height: 16),
                  _buildParticipantsCard(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.group, color: Colors.blue.shade700, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.groupName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade900,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Divider(),
          SizedBox(height: 12),
          _buildInfoRow('Status', _getStatusText(), _getStatusColor()),
          if (_activeCallId != null) ...[
            SizedBox(height: 8),
            _buildInfoRow('Call ID', _activeCallId!, Colors.grey.shade700),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: valueColor,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildCreateButton(String currentUserId) {
    return ElevatedButton(
      onPressed: _isLoading ? null : () => _createCall(currentUserId),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: _isLoading
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.phone, size: 24),
                SizedBox(width: 12),
                Text(
                  'Start Group Call',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInvitationButtons(String currentUserId) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.call, color: Colors.blue.shade700, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'You have been invited to this call',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : () => _declineCall(currentUserId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.call_end, size: 20),
                    SizedBox(width: 8),
                    Text('Decline', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : () => _joinCall(currentUserId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.call, size: 20),
                    SizedBox(width: 8),
                    Text('Join', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLeaveButton(String currentUserId) {
    final isInitiator = _currentCall?.initiatorId == currentUserId;
    
    return ElevatedButton(
      onPressed: _isLoading ? null : () => _leaveCall(currentUserId),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red.shade600,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.call_end, size: 24),
          SizedBox(width: 12),
          Text(
            isInitiator ? 'End Call for Everyone' : 'Leave Call',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRejoinButton(String currentUserId, bool wasDeclined) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              Icon(
                wasDeclined ? Icons.phone_disabled : Icons.exit_to_app,
                color: Colors.blue.shade700,
                size: 28,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  wasDeclined 
                      ? 'You declined this call. Changed your mind?'
                      : 'You left this call. Want to rejoin?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        ElevatedButton(
          onPressed: _isLoading ? null : () => _rejoinCall(currentUserId),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade600,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isLoading
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.call, size: 24),
                    SizedBox(width: 12),
                    Text(
                      wasDeclined ? 'Join Call' : 'Rejoin Call',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildAlreadyRespondedCard() {
    // Only shown for ended calls or edge cases
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility, color: Colors.grey.shade700, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Watching as observer',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallInfoCard() {
    if (_currentCall == null) return SizedBox.shrink();
    
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Call Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade900,
            ),
          ),
          SizedBox(height: 12),
          Divider(),
          SizedBox(height: 12),
          _buildInfoRow('Participants', '${_currentCall!.joinedParticipants.length}', Colors.blue.shade700),
          SizedBox(height: 8),
          _buildInfoRow('Invited', '${_currentCall!.invitedParticipants.length}', Colors.orange.shade700),
          SizedBox(height: 8),
          _buildInfoRow('Declined', '${_currentCall!.declinedParticipants.length}', Colors.red.shade700),
          SizedBox(height: 8),
          _buildInfoRow('Left', '${_currentCall!.leftParticipants.length}', Colors.grey.shade700),
        ],
      ),
    );
  }

  Widget _buildParticipantsCard() {
    if (_currentCall == null) return SizedBox.shrink();
    
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Participants',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade900,
            ),
          ),
          SizedBox(height: 16),
          
          if (_currentCall!.joinedParticipants.isNotEmpty) ...[
            _buildParticipantSection(
              'In Call',
              _currentCall!.joinedParticipants,
              Colors.green.shade700,
              Icons.check_circle,
            ),
            SizedBox(height: 16),
          ],
          
          if (_currentCall!.invitedParticipants.isNotEmpty) ...[
            _buildParticipantSection(
              'Invited',
              _currentCall!.invitedParticipants,
              Colors.orange.shade700,
              Icons.phone_in_talk,
            ),
            SizedBox(height: 16),
          ],
          
          if (_currentCall!.declinedParticipants.isNotEmpty) ...[
            _buildParticipantSection(
              'Declined',
              _currentCall!.declinedParticipants,
              Colors.red.shade700,
              Icons.phone_disabled,
            ),
            SizedBox(height: 16),
          ],
          
          if (_currentCall!.leftParticipants.isNotEmpty) ...[
            _buildParticipantSection(
              'Left',
              _currentCall!.leftParticipants,
              Colors.grey.shade700,
              Icons.exit_to_app,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildParticipantSection(String title, List<String> userIds, Color color, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            SizedBox(width: 8),
            Text(
              '$title (${userIds.length})',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        ...userIds.map((userId) => _buildParticipantTile(userId, color)),
      ],
    );
  }

  Widget _buildParticipantTile(String userId, Color color) {
    final user = _userCache[userId];
    final name = user?.name ?? 'Loading...';
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isMe = userId == currentUserId;
    final isInitiator = _currentCall?.initiatorId == userId;
    
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withOpacity(0.2),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? 'You' : name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade900,
                  ),
                ),
                if (isInitiator)
                  Text(
                    'Initiator',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.circle, size: 10, color: color),
        ],
      ),
    );
  }

  String _getStatusText() {
    if (_currentCall == null) {
      return 'No Active Call';
    }
    
    switch (_currentCall!.status) {
      case GroupCallStatus.ringing:
        return 'Ringing';
      case GroupCallStatus.active:
        return 'Active';
      case GroupCallStatus.ended:
        return 'Ended';
    }
  }

  Color _getStatusColor() {
    if (_currentCall == null) {
      return Colors.grey.shade600;
    }
    
    switch (_currentCall!.status) {
      case GroupCallStatus.ringing:
        return Colors.orange.shade700;
      case GroupCallStatus.active:
        return Colors.green.shade700;
      case GroupCallStatus.ended:
        return Colors.red.shade700;
    }
  }

  Stream<GroupCall?> _listenToActiveCall() {
    print('[ROOM_TEST] 🎧 Listener attached for group: ${widget.groupId}');
    
    // FIXED: Listen to Firestore directly instead of one-time read
    // This ensures we get updates when new rooms are created
    return FirebaseFirestore.instance
        .collection('groupCalls')
        .where('groupId', isEqualTo: widget.groupId)
        .where('status', whereIn: ['ringing', 'active'])
        .limit(1)
        .snapshots()
        .map((querySnapshot) {
      print('[ROOM_TEST] 📡 Snapshot received: ${querySnapshot.docs.length} active calls');
      
      if (querySnapshot.docs.isEmpty) {
        print('[ROOM_TEST] ℹ️ No active room');
        return null;
      }
      
      final doc = querySnapshot.docs.first;
      final call = GroupCall.fromFirestore(doc);
      print('[ROOM_TEST] ✅ Active room detected: ${call.callId}');
      print('[ROOM_TEST] 👥 Participants: ${call.joinedParticipants.length} joined, ${call.invitedParticipants.length} invited');
      print('[ROOM_TEST] 🔄 UI rebuilt');
      
      return call;
    });
  }

  Future<void> _loadParticipantData(GroupCall call) async {
    final allUserIds = <String>{
      ...call.joinedParticipants,
      ...call.invitedParticipants,
      ...call.declinedParticipants,
      ...call.leftParticipants,
    };

    for (var userId in allUserIds) {
      if (!_userCache.containsKey(userId)) {
        _loadUserData(userId);
      }
    }
  }

  Future<void> _loadUserData(String userId) async {
    try {
      final doc = await _firestoreService.users.doc(userId).get();
      if (doc.exists && mounted) {
        final user = ModUser.fromMap(doc.data()!);
        if (mounted) {
          setState(() {
            _userCache[userId] = user;
          });
        }
      }
    } catch (e) {
      print('[GroupCallTest] Error loading user: $e');
    }
  }

  Future<void> _createCall(String currentUserId) async {
    setState(() => _isLoading = true);
    
    try {
      print('[GroupCallTest] 🎬 Creating call...');
      final callId = await _groupCallService.createGroupCall(
        groupId: widget.groupId,
        initiatorId: currentUserId,
      );
      print('[GroupCallTest] ✅ Call created: $callId');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Call started successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('[GroupCallTest] ❌ Error creating call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start call: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _joinCall(String currentUserId) async {
    if (_activeCallId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      print('[GroupCallTest] ➕ Joining call...');
      await _groupCallService.joinGroupCall(_activeCallId!, currentUserId);
      print('[GroupCallTest] ✅ Joined call');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Joined call successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('[GroupCallTest] ❌ Error joining call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join call: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _declineCall(String currentUserId) async {
    if (_activeCallId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      print('[GroupCallTest] ❌ Declining call...');
      await _groupCallService.declineGroupCall(_activeCallId!, currentUserId);
      print('[GroupCallTest] ✅ Declined call');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Call declined'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('[GroupCallTest] ❌ Error declining call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to decline call: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _leaveCall(String currentUserId) async {
    if (_activeCallId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      print('[GroupCallTest] ➖ Leaving call...');
      await _groupCallService.leaveGroupCall(_activeCallId!, currentUserId);
      print('[GroupCallTest] ✅ Left call');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Left call successfully'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('[GroupCallTest] ❌ Error leaving call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to leave call: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _rejoinCall(String currentUserId) async {
    if (_activeCallId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      print('[GroupCallTest] 🔄 Rejoining call...');
      await _groupCallService.rejoinGroupCall(_activeCallId!, currentUserId);
      print('[GroupCallTest] ✅ Rejoined call');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rejoined call successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('[GroupCallTest] ❌ Error rejoining call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to rejoin call: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
