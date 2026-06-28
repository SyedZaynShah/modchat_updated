import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/call_recovery_service.dart';

/// FIX 3: Debug screen to view and force-end active calls
/// This is GOLD during development for diagnosing stale call issues
class CallDebugScreen extends StatefulWidget {
  static const routeName = '/debug/calls';

  const CallDebugScreen({super.key});

  @override
  State<CallDebugScreen> createState() => _CallDebugScreenState();
}

class _CallDebugScreenState extends State<CallDebugScreen> {
  final CallRecoveryService _recoveryService = CallRecoveryService();
  List<Map<String, dynamic>> _activeCalls = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadActiveCalls();
  }

  Future<void> _loadActiveCalls() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final calls = await _recoveryService.getActiveCallsForDebug();
      setState(() {
        _activeCalls = calls;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _forceEndCall(String callId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Force End Call?'),
        content: Text('This will mark call $callId as ended.\n\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Force End', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _recoveryService.forceEndCall(callId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Call $callId force-ended'),
            backgroundColor: Colors.green,
          ),
        );
        _loadActiveCalls(); // Reload
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _runCleanup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Run Stale Call Cleanup?'),
        content: const Text(
          'This will:\n'
          '• End accepted calls > 5 minutes old\n'
          '• Mark calling/ringing calls > 60s as missed\n\n'
          'Check console for detailed logs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Run Cleanup', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);

    try {
      await _recoveryService.cleanupStaleCalls();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cleanup complete! Check console for details.'),
            backgroundColor: Colors.green,
          ),
        );
        _loadActiveCalls(); // Reload
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _loading = false);
      }
    }
  }

  String _formatAge(Duration? age) {
    if (age == null) return 'Unknown';
    
    if (age.inDays > 0) {
      return '${age.inDays}d ${age.inHours % 24}h';
    } else if (age.inHours > 0) {
      return '${age.inHours}h ${age.inMinutes % 60}m';
    } else if (age.inMinutes > 0) {
      return '${age.inMinutes}m ${age.inSeconds % 60}s';
    } else {
      return '${age.inSeconds}s';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'calling':
        return Colors.blue;
      case 'ringing':
        return Colors.orange;
      case 'accepted':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'calling':
        return Icons.phone_in_talk;
      case 'ringing':
        return Icons.phone_callback;
      case 'accepted':
        return Icons.call;
      default:
        return Icons.phone;
    }
  }

  bool _isStale(Map<String, dynamic> call) {
    final status = call['status'] as String;
    final age = call['age'] as Duration?;
    
    if (age == null) return false;
    
    if (status == 'accepted' && age.inMinutes > 5) {
      return true; // Stale accepted call
    }
    
    if ((status == 'calling' || status == 'ringing') && age.inSeconds > 60) {
      return true; // Stale ringing call
    }
    
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadActiveCalls,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            onPressed: _loading ? null : _runCleanup,
            tooltip: 'Run Cleanup',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadActiveCalls,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_activeCalls.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              'No active calls found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'All clear! 🎉',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSummaryCard(),
        const SizedBox(height: 16),
        ..._activeCalls.map((call) => _buildCallCard(call)),
      ],
    );
  }

  Widget _buildSummaryCard() {
    final staleCount = _activeCalls.where(_isStale).length;
    final hasStale = staleCount > 0;

    return Card(
      color: hasStale ? Colors.red.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasStale ? Icons.warning : Icons.info,
                  color: hasStale ? Colors.red : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  'Active Calls Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: hasStale ? Colors.red.shade900 : Colors.green.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Total active calls: ${_activeCalls.length}',
              style: const TextStyle(fontSize: 16),
            ),
            if (hasStale) ...[
              const SizedBox(height: 4),
              Text(
                '🚨 Stale calls detected: $staleCount',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'These calls are likely blocking new calls.\nRun cleanup to fix.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCallCard(Map<String, dynamic> call) {
    final status = call['status'] as String;
    final type = call['type'] as String;
    final role = call['role'] as String;
    final age = call['age'] as Duration?;
    final isStale = _isStale(call);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isStale ? Colors.red.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getStatusIcon(status),
                  color: isStale ? Colors.red : _getStatusColor(status),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isStale ? Colors.red : _getStatusColor(status),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              type,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              role,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Age: ${_formatAge(age)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: isStale ? Colors.red.shade700 : Colors.grey.shade700,
                          fontWeight: isStale ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Call ID: ${call['id']}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 4),
            Text(
              'Caller: ${call['callerId']}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Receiver: ${call['receiverId']}',
              style: const TextStyle(fontSize: 12),
            ),
            if (isStale) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status == 'accepted'
                            ? 'STALE: Accepted call older than 5 minutes'
                            : 'STALE: Ringing call older than 60 seconds',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _forceEndCall(call['id']),
                icon: const Icon(Icons.stop),
                label: const Text('Force End'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

