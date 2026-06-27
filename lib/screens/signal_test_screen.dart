import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/signal_test_service.dart';

/// MINIMAL SIGNAL TEST SCREEN
/// 
/// Purpose: Test signal delivery between devices
/// 
/// Device A: Press button to send signal
/// Device B: Should receive dialog
class SignalTestScreen extends StatefulWidget {
  const SignalTestScreen({Key? key}) : super(key: key);

  @override
  State<SignalTestScreen> createState() => _SignalTestScreenState();
}

class _SignalTestScreenState extends State<SignalTestScreen> {
  final SignalTestService _service = SignalTestService();
  final TextEditingController _targetUserController = TextEditingController();
  bool _isSending = false;
  String? _lastSignalId;

  @override
  void initState() {
    super.initState();
    _printDebugInfo();
  }

  void _printDebugInfo() {
    final currentUserId = _service.getCurrentUserId();
    print('[SIGNAL] =================================');
    print('[SIGNAL] SIGNAL TEST SCREEN OPENED');
    print('[SIGNAL] Current User: $currentUserId');
    print('[SIGNAL] =================================');
  }

  Future<void> _sendTestSignal() async {
    final targetUserId = _targetUserController.text.trim();
    
    if (targetUserId.isEmpty) {
      _showError('Please enter target user ID');
      return;
    }

    setState(() {
      _isSending = true;
    });

    print('[SIGNAL] =================================');
    print('[SIGNAL] SENDING TEST SIGNAL');
    print('[SIGNAL] =================================');

    final signalId = await _service.sendTestSignal(targetUserId);

    setState(() {
      _isSending = false;
      _lastSignalId = signalId;
    });

    if (signalId != null) {
      _showSuccess('Signal sent: $signalId');
    } else {
      _showError('Failed to send signal');
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _copyUserId() {
    final userId = _service.getCurrentUserId();
    if (userId != null) {
      Clipboard.setData(ClipboardData(text: userId));
      _showSuccess('User ID copied');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _service.getCurrentUserId() ?? 'Not logged in';

    return Scaffold(
      appBar: AppBar(
        title: Text('Signal Test'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current User Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR USER ID',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            currentUserId,
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.copy),
                          onPressed: _copyUserId,
                          tooltip: 'Copy User ID',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 24),

            // Instructions
            Text(
              'SEND TEST SIGNAL',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Enter the User ID from Device B below, then press Send.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),

            SizedBox(height: 16),

            // Target User Input
            TextField(
              controller: _targetUserController,
              decoration: InputDecoration(
                labelText: 'Target User ID (from Device B)',
                border: OutlineInputBorder(),
                hintText: 'Paste user ID here',
              ),
              maxLines: 3,
            ),

            SizedBox(height: 24),

            // Send Button
            ElevatedButton(
              onPressed: _isSending ? null : _sendTestSignal,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: _isSending
                  ? CircularProgressIndicator(color: Colors.white)
                  : Text(
                      'SEND TEST SIGNAL',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),

            if (_lastSignalId != null) ...[
              SizedBox(height: 16),
              Card(
                color: Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LAST SIGNAL SENT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[900],
                        ),
                      ),
                      SizedBox(height: 8),
                      SelectableText(
                        _lastSignalId!,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            Spacer(),

            // Instructions
            Card(
              color: Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TESTING STEPS:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[900],
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. Open this screen on Device A\n'
                      '2. Open this screen on Device B\n'
                      '3. Copy User ID from Device B\n'
                      '4. Paste into Device A\n'
                      '5. Press SEND on Device A\n'
                      '6. Device B should show dialog',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _targetUserController.dispose();
    super.dispose();
  }
}
