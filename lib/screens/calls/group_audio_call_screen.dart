import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../../services/group_call_service.dart';
import '../../services/firestore_service.dart';
import '../../models/group_call.dart';
import '../../models/user_model.dart';

/// PHASE 1: Group Audio Call Screen - Room Management Only
/// 
/// Simple group call UI with:
/// ✓ Room participant tracking
/// ✓ Participant status display (Joined, Invited, Declined, Left)
/// ✓ Join/Leave functionality
/// ✓ Real-time updates
/// 
/// NOTE: This is Phase 1 - NO WebRTC audio transport yet
class GroupAudioCallScreen extends ConsumerStatefulWidget {
  final String callId;
  final String groupId;
  final String groupName;
  final bool isInitiator;

  const GroupAudioCallScreen({
    super.key,
    required this.callId,
    required this.groupId,
    required this.groupName,
    this.isInitiator = false,
  });

  @override
  ConsumerState<GroupAudioCallScreen> createState() => _GroupAudioCallScreenState();
}

class _GroupAudioCallScreenState extends ConsumerState<GroupAudioCallScreen> {
  final GroupCallService _callService = GroupCallService();
  final FirestoreService _firestoreService = FirestoreService();
  
  StreamSubscription? _callSubscription;
  GroupCall? _currentCall;
  Map<String, ModUser> _userCache = {};

  @override
  void initState() {
    super.initState();
    _initializeCall();
  }

  Future<void> _initializeCall() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      print('[GroupCallScreen] Phase 1: Initializing room management only');

      // Join the call if not initiator
      if (!widget.isInitiator) {
        await _callService.joinGroupCall(widget.callId, currentUserId);
      }

      // Listen to call updates
      _listenToCallUpdates();

    } catch (e) {
      print('[GroupCallScreen] Error initializing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join call: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  void _listenToCallUpdates() {
    _callSubscription = _callService.listenToGroupCall(widget.callId).listen((snapshot) {
      if (!mounted) return;

      if (!snapshot.exists) {
        _exitCall();
        return;
      }

      final call = GroupCall.fromFirestore(snapshot);
      setState(() {
        _currentCall = call;
      });

      // Check if call ended
      if (call.status == GroupCallStatus.ended) {
        _exitCall();
        return;
      }

      // Load user data for all participants
      _loadParticipantData(call);
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
        setState(() {
          _userCache[userId] = user;
        });
      }
    } catch (e) {
      print('[GroupCallScreen] Error loading user: $e');
    }
  }

  Future<void> _leaveCall() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      await _callService.leaveGroupCall(widget.callId, currentUserId);
    } catch (e) {
      print('[GroupCallScreen] Error leaving: $e');
    }

    _exitCall();
  }

  void _exitCall() {
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _callSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (_currentCall == null || currentUserId == null) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F1115) : Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isInitiator = _currentCall!.initiatorId == currentUserId;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1115) : Colors.white,
      appBar: AppBar(
        title: Text(widget.groupName),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF171A21) : Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          _buildStatusHeader(isDark),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    'Joined',
                    _currentCall!.joinedParticipants,
                    Colors.green,
                    Icons.check_circle,
                    isDark,
                  ),
                  _buildSection(
                    'Invited (Ringing)',
                    _currentCall!.invitedParticipants,
                    Colors.orange,
                    Icons.phone_in_talk,
                    isDark,
                  ),
                  _buildSection(
                    'Declined',
                    _currentCall!.declinedParticipants,
                    Colors.red,
                    Icons.call_end,
                    isDark,
                  ),
                  _buildSection(
                    'Left',
                    _currentCall!.leftParticipants,
                    Colors.grey,
                    Icons.exit_to_app,
                    isDark,
                  ),
                ],
              ),
            ),
          ),
          _buildLeaveButton(isInitiator, isDark),
        ],
      ),
    );
  }

  Widget _buildStatusHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171A21) : Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade300,
          ),
        ),
      ),
      child: Column(
        children: [
          Text(
            'Status: ${_currentCall!.status.name.toUpperCase()}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _getStatusColor(_currentCall!.status),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_currentCall!.joinedParticipants.length} Joined • ${_currentCall!.invitedParticipants.length} Invited',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? const Color(0xFFA0A4AE) : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Text(
              'PHASE 1: Room Management Only - No Audio',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(GroupCallStatus status) {
    switch (status) {
      case GroupCallStatus.ringing:
        return Colors.orange;
      case GroupCallStatus.active:
        return Colors.green;
      case GroupCallStatus.ended:
        return Colors.red;
    }
  }

  Widget _buildSection(
    String title,
    List<String> userIds,
    Color color,
    IconData icon,
    bool isDark,
  ) {
    if (userIds.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 16, bottom: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                '$title (${userIds.length})',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        ...userIds.map((userId) => _buildParticipantTile(userId, color, isDark)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildParticipantTile(String userId, Color statusColor, bool isDark) {
    final user = _userCache[userId];
    final name = user?.name ?? 'Loading...';
    final profileImageUrl = user?.profileImageUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171A21) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.2),
          backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
              ? NetworkImage(profileImageUrl)
              : null,
          child: profileImageUrl == null || profileImageUrl.isEmpty
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        title: Text(
          name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        trailing: Icon(
          Icons.circle,
          size: 12,
          color: statusColor,
        ),
      ),
    );
  }

  Widget _buildLeaveButton(bool isInitiator, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171A21) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ElevatedButton(
          onPressed: _leaveCall,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.call_end, size: 24),
              const SizedBox(width: 12),
              Text(
                isInitiator ? 'End Call for Everyone' : 'Leave Call',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
