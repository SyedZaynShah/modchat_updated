# Phase 1 UI Integration Example

This document shows simple examples of how to integrate Phase 1 group call room management into your UI.

---

## 📱 1. Start Call Button (Group Chat Screen)

```dart
// In your group chat screen
FloatingActionButton(
  onPressed: () async {
    final service = GroupCallService();
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    
    try {
      // Create call room
      final callId = await service.createGroupCall(
        groupId: widget.groupId,
        initiatorId: currentUserId,
      );
      
      // Navigate to call screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupCallScreen(
            callId: callId,
            groupId: widget.groupId,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start call: $e')),
      );
    }
  },
  child: Icon(Icons.call),
)
```

---

## 📞 2. Incoming Call Listener (Background Service)

```dart
// Listen for incoming calls in your app's main state
class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _service = GroupCallService();
  StreamSubscription? _callListener;
  
  @override
  void initState() {
    super.initState();
    _listenForIncomingCalls();
  }
  
  void _listenForIncomingCalls() {
    _callListener = _service.listenToIncomingGroupCalls().listen((snapshot) {
      for (var doc in snapshot.docs) {
        final call = GroupCall.fromFirestore(doc);
        _showIncomingCallDialog(call);
      }
    });
  }
  
  void _showIncomingCallDialog(GroupCall call) {
    // Show incoming call UI
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => IncomingGroupCallDialog(call: call),
    );
  }
  
  @override
  void dispose() {
    _callListener?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomeScreen(),
    );
  }
}
```

---

## 🔔 3. Incoming Call Dialog

```dart
class IncomingGroupCallDialog extends StatelessWidget {
  final GroupCall call;
  
  const IncomingGroupCallDialog({required this.call});
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Incoming Group Call'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Group: ${call.groupId}'),
          SizedBox(height: 8),
          Text('${call.joinedParticipants.length} participant(s)'),
        ],
      ),
      actions: [
        // Decline button
        TextButton(
          onPressed: () async {
            final service = GroupCallService();
            final userId = FirebaseAuth.instance.currentUser!.uid;
            
            await service.declineGroupCall(call.callId, userId);
            Navigator.pop(context);
          },
          child: Text('Decline'),
        ),
        
        // Accept button
        ElevatedButton(
          onPressed: () async {
            final service = GroupCallService();
            final userId = FirebaseAuth.instance.currentUser!.uid;
            
            try {
              await service.joinGroupCall(call.callId, userId);
              
              // Close dialog
              Navigator.pop(context);
              
              // Navigate to call screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupCallScreen(
                    callId: call.callId,
                    groupId: call.groupId,
                  ),
                ),
              );
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to join: $e')),
              );
            }
          },
          child: Text('Accept'),
        ),
      ],
    );
  }
}
```

---

## 📺 4. Group Call Screen (Phase 1 UI)

```dart
class GroupCallScreen extends StatefulWidget {
  final String callId;
  final String groupId;
  
  const GroupCallScreen({
    required this.callId,
    required this.groupId,
  });
  
  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final _service = GroupCallService();
  StreamSubscription? _callListener;
  GroupCall? _currentCall;
  
  @override
  void initState() {
    super.initState();
    _listenToCall();
  }
  
  void _listenToCall() {
    _callListener = _service.listenToGroupCall(widget.callId).listen((snapshot) {
      if (snapshot.exists) {
        setState(() {
          _currentCall = GroupCall.fromFirestore(snapshot);
        });
        
        // Check if call ended
        if (_currentCall!.status == GroupCallStatus.ended) {
          _exitCall();
        }
      } else {
        _exitCall();
      }
    });
  }
  
  void _exitCall() {
    Navigator.pop(context);
  }
  
  Future<void> _leaveCall() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    await _service.leaveGroupCall(widget.callId, userId);
    _exitCall();
  }
  
  @override
  void dispose() {
    _callListener?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (_currentCall == null) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final isInitiator = _currentCall!.initiatorId == currentUserId;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Group Call - ${_currentCall!.status.name}'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Status indicator
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Status: ${_currentCall!.status.name.toUpperCase()}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          
          Divider(),
          
          // Joined participants
          Expanded(
            child: ListView(
              children: [
                _buildSection(
                  'Joined',
                  _currentCall!.joinedParticipants,
                  Colors.green,
                ),
                
                _buildSection(
                  'Invited',
                  _currentCall!.invitedParticipants,
                  Colors.orange,
                ),
                
                _buildSection(
                  'Declined',
                  _currentCall!.declinedParticipants,
                  Colors.red,
                ),
                
                _buildSection(
                  'Left',
                  _currentCall!.leftParticipants,
                  Colors.grey,
                ),
              ],
            ),
          ),
          
          // Leave/End button
          Padding(
            padding: EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _leaveCall,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                minimumSize: Size(double.infinity, 50),
              ),
              child: Text(
                isInitiator ? 'End Call' : 'Leave Call',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSection(String title, List<String> userIds, Color color) {
    if (userIds.isEmpty) return SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '$title (${userIds.length})',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        ...userIds.map((userId) => ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.2),
            child: Icon(Icons.person, color: color),
          ),
          title: Text(userId), // Replace with user name lookup
          trailing: Icon(Icons.circle, color: color, size: 12),
        )),
        Divider(),
      ],
    );
  }
}
```

---

## 🎨 Phase 1 UI Guidelines

### ✅ What to Show

1. **Participant Lists**
   - Joined (green)
   - Invited (orange)
   - Declined (red)
   - Left (grey)

2. **Call Status**
   - Ringing
   - Active
   - Ended

3. **Action Buttons**
   - Accept (for invited users)
   - Decline (for invited users)
   - Leave (for joined users)
   - End Call (for initiator only)

### ❌ What NOT to Show

- Mute/unmute button
- Speaker toggle
- Call timer
- Audio waveforms
- Connection quality
- Video controls

---

## 🔄 State Flow Example

```
User A starts call
    ↓
GroupCallScreen opens for User A
Status: ringing
Joined: [A]
Invited: [B, C, D]
    ↓
User B sees IncomingCallDialog
User B presses Accept
    ↓
User B's GroupCallScreen opens
Status: active
Joined: [A, B]
Invited: [C, D]
    ↓
User A sees real-time update
Status: active
Joined: [A, B]
Invited: [C, D]
    ↓
User C presses Decline
    ↓
All users see real-time update
Status: active
Joined: [A, B]
Invited: [D]
Declined: [C]
```

---

## 🔒 Duplicate Invitation Protection

```dart
// Before showing incoming call dialog
void _showIncomingCallDialog(GroupCall call) {
  final userId = FirebaseAuth.instance.currentUser!.uid;
  
  // DON'T show if user already responded
  if (call.joinedParticipants.contains(userId)) return;
  if (call.declinedParticipants.contains(userId)) return;
  if (call.leftParticipants.contains(userId)) return;
  
  // DON'T show if user is not invited
  if (!call.invitedParticipants.contains(userId)) return;
  
  // OK to show
  showDialog(...);
}
```

---

## 📝 Notes

- This is a **minimal UI for Phase 1**
- No audio controls needed
- Real-time updates via Firestore listeners
- Status changes trigger UI updates automatically
- Call screen is just a participant tracker
- Think of it like WhatsApp's call room before audio starts

---

## 🎯 Testing Your Integration

1. Start call from User A's device
2. User B should see incoming call dialog
3. User B accepts → both see each other in "Joined" list
4. User C declines → all see User C in "Declined" list
5. User B leaves → all see User B in "Left" list
6. User A ends call → all users exit call screen

**All updates should be instant (real-time).**

---

## ✅ Ready for Phase 2

Once this UI works and all tests pass, Phase 2 will add:
- WebRTC audio transport
- Mute/unmute controls
- Speaker controls
- Actual audio streaming

But Phase 1 UI proves the room management works correctly.
