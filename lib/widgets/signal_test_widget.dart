import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/signal_test_service.dart';

/// MINIMAL SIGNAL TEST WIDGET
/// 
/// Shows listener status and provides test button
class SignalTestWidget extends StatefulWidget {
  final Widget child;
  
  const SignalTestWidget({Key? key, required this.child}) : super(key: key);

  @override
  State<SignalTestWidget> createState() => _SignalTestWidgetState();
}

class _SignalTestWidgetState extends State<SignalTestWidget> {
  final SignalTestService _service = SignalTestService();
  final Set<String> _processedSignals = {};

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    print('[SIGNAL] Widget: Starting listener');
    
    _service.listenForSignals().listen((snapshot) {
      print('[SIGNAL] SNAPSHOT_TRIGGERED');
      print('[SIGNAL] Document count: ${snapshot.docs.length}');
      
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final signalId = doc.id;
        final targetUserId = data['targetUserId'];
        final received = data['received'] ?? false;
        
        print('[SIGNAL] DOC_FOUND');
        print('[SIGNAL] signalId=$signalId');
        print('[SIGNAL] targetUserId=$targetUserId');
        print('[SIGNAL] received=$received');

        // Skip if already processed
        if (_processedSignals.contains(signalId)) {
          print('[SIGNAL] Already processed - skipping');
          continue;
        }

        // Skip if already acknowledged
        if (received == true) {
          print('[SIGNAL] Already acknowledged - skipping');
          continue;
        }

        // Mark as processed
        _processedSignals.add(signalId);

        // Show dialog
        _showSignalDialog(signalId, data);
      }
    }, onError: (error) {
      print('[SIGNAL] ❌ LISTENER_ERROR: $error');
    });
  }

  void _showSignalDialog(String signalId, Map<String, dynamic> data) {
    print('[SIGNAL] SHOWING_DIALOG for $signalId');

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('TEST SIGNAL RECEIVED'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signal ID: $signalId'),
            SizedBox(height: 8),
            Text('From: ${data['senderId']}'),
            SizedBox(height: 8),
            Text('To: ${data['targetUserId']}'),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              await _service.acknowledgeSignal(signalId);
              Navigator.pop(context);
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
