# Voice Call Phase 1 - Quick Reference

## 🚀 Quick Start

### Start a Voice Call
```dart
final callService = ref.read(callServiceProvider);
final callId = await callService.startVoiceCall(
  callerId: currentUserId,
  callerName: currentUserName,
  receiverId: peerUserId,
);
```

### Listen for Incoming Calls
```dart
// Automatically handled by IncomingCallListener widget
// Already integrated in app.dart - no action needed
```

### Accept a Call
```dart
await callService.acceptCall(callId);
```

### Decline a Call
```dart
await callService.declineCall(callId);
```

### End a Call
```dart
await callService.endCall(callId);
```

---

## 📁 File Structure

```
lib/
├── services/
│   └── call_service.dart                 # Core call logic
├── providers/
│   └── call_providers.dart               # Riverpod providers
├── screens/
│   └── chat/
│       ├── incoming_call_screen.dart     # Incoming call UI
│       ├── call_screen.dart              # Active call UI
│       └── chat_detail_screen.dart       # Modified: added call button
├── widgets/
│   └── incoming_call_listener.dart       # Global call listener
└── app.dart                               # Modified: wrapped with listener
```

---

## 🎨 UI Components

### Call Button (in ChatDetailScreen AppBar)
```dart
_HeaderIcon(
  icon: Icons.call_rounded,
  onTap: () => _startVoiceCall(),
)
```

### IncomingCallScreen
- **Background**: White
- **Text**: Dark Navy (#1A1F3A)
- **Accent**: Electric Blue (#5865F2)
- **Buttons**: Red decline, Green accept

### CallScreen
- **Background**: Dark Navy (#1A1F3A)
- **Text**: White
- **Status**: Dynamic (Ringing/Connected)
- **Controls**: Mute (disabled), Speaker (disabled), End Call (active)

---

## 🔄 Call Status Flow

```
ringing → accepted → ended
   ↓
declined
```

### Status Meanings
- **ringing**: Call initiated, waiting for receiver
- **accepted**: Receiver answered, call in progress
- **declined**: Receiver rejected the call
- **ended**: Either party terminated the call

---

## 🗄️ Firestore Schema

### Collection: `calls`

```javascript
{
  callerId: string,        // UID of caller
  callerName: string,      // Display name of caller
  receiverId: string,      // UID of receiver
  type: "voice",           // Call type (voice only in Phase 1)
  status: string,          // "ringing" | "accepted" | "declined" | "ended"
  createdAt: timestamp,    // When call was initiated
  answeredAt: timestamp?,  // When call was accepted (null if not answered)
  endedAt: timestamp?      // When call was ended (null if ongoing)
}
```

---

## 🔍 Debugging

### Enable Logs
```dart
// In call_service.dart
print('Call created: $callId');
print('Call status: ${data['status']}');

// In incoming_call_listener.dart
print('Incoming calls: ${snapshot.docs.length}');

// In call_screen.dart
print('Call status changed to: $_callStatus');
```

### Check Firestore
```bash
# Firebase Console
Firestore Database → calls → [document ID]
```

### Flutter Analyze
```bash
cd modchat_updated
flutter analyze
```

### Run Tests
```bash
flutter test
```

---

## ⚠️ Known Limitations

1. **No Audio**: Phase 1 is signaling only
2. **No Push Notifications**: Receiver must have app open
3. **No Call History**: Calls not logged in UI yet
4. **No Timeout**: Calls ring indefinitely
5. **No Busy State**: Can receive multiple calls
6. **No Ringing Sound**: Silent notification only

---

## 🛠️ Troubleshooting

### Call Button Does Nothing
- Check: Is user authenticated?
- Check: Does peer user exist in Firestore?
- Check: Are Firestore rules allowing writes?

### Incoming Call Doesn't Appear
- Check: Is IncomingCallListener wrapped correctly in app.dart?
- Check: Are Firestore rules allowing reads?
- Check: Is receiver's app in foreground?
- Check: Network connectivity

### Call Screen Doesn't Close When Ended
- Check: Is stream subscription active?
- Check: Is callId correct?
- Check: Firestore rules allow updates?

### Multiple Incoming Call Screens
- Check: `_currentCallId` state in IncomingCallListener
- Check: Route settings name comparison

---

## 📊 Performance Metrics

### Expected Performance
- **Call Initiation**: < 500ms
- **Incoming Call Notification**: 1-2 seconds
- **Status Updates**: < 1 second
- **Screen Navigation**: Instant

### Firestore Operations
- **Per Call**: 1 write (create) + 1 write (status update) + continuous reads
- **Optimize**: Add indexes for `receiverId` + `status`

---

## 🔐 Security Checklist

- [ ] Firestore rules deployed
- [ ] User can only create calls as themselves
- [ ] User cannot call themselves
- [ ] Only caller/receiver can read call
- [ ] Only caller/receiver can update call
- [ ] Caller/receiver IDs cannot be changed
- [ ] Calls cannot be deleted

---

## 🎯 Testing Checklist

- [ ] Outgoing call works
- [ ] Incoming call appears
- [ ] Accept works
- [ ] Decline works
- [ ] End call (caller) works
- [ ] End call (receiver) works
- [ ] No duplicate notifications
- [ ] UI matches design
- [ ] No crashes
- [ ] Firestore updates correctly

---

## 📞 Common Code Patterns

### Get Call Service in Widget
```dart
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callService = ref.read(callServiceProvider);
    // Use callService...
  }
}
```

### Listen to Specific Call
```dart
final callStream = callService.listenToCall(callId);
callStream.listen((snapshot) {
  final data = snapshot.data();
  final status = data?['status'];
  // Handle status change...
});
```

### Navigate to Call Screen
```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => CallScreen(
      callId: callId,
      peerId: peerId,
      peerName: peerName,
      isIncoming: false,
    ),
  ),
);
```

---

## 🚦 Next Steps

### Before Phase 2
1. Complete all Phase 1 tests
2. Fix any bugs found
3. Get stakeholder approval
4. Review performance metrics
5. Update documentation

### Phase 2 Preview
- Integrate Agora SDK
- Add real audio streaming
- Enable mute/unmute
- Enable speaker toggle
- Add call quality indicators

---

## 📚 Additional Resources

- [Implementation Guide](VOICE_CALL_PHASE1_IMPLEMENTATION.md)
- [Testing Guide](VOICE_CALL_TESTING_GUIDE.md)
- [Firestore Rules](firestore_calls_rules.txt)
- [Flutter Riverpod Docs](https://riverpod.dev/)
- [Cloud Firestore Docs](https://firebase.google.com/docs/firestore)

---

## 🆘 Need Help?

1. Check existing documentation
2. Review test scenarios
3. Enable debug logging
4. Check Firebase Console
5. Review code comments
6. Test on different devices

---

**Last Updated**: Phase 1 Implementation Complete
**Version**: 1.0.0
**Status**: ✅ Ready for Testing
