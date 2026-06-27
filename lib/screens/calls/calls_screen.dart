import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';
import '../../models/call_log.dart';
import '../../models/user_model.dart';
import '../../theme/theme.dart';
import '../../providers/call_providers.dart';
import 'package:intl/intl.dart';

enum CallFilter { all, missed, voice, video, incoming, outgoing }

class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});

  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  CallFilter _selectedFilter = CallFilter.all;

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in')),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1115) : Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: isDark ? const Color(0xFF0F1115) : Colors.white,
            elevation: 0,
            title: Text(
              'Calls',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildStatisticsSection(currentUser.uid, isDark),
          ),
          SliverToBoxAdapter(
            child: _buildFilterChips(isDark),
          ),
          SliverToBoxAdapter(
            child: _buildCallsList(currentUser.uid, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsSection(String userId, bool isDark) {
    print('[CallsScreen] 📊 Building statistics for user: $userId');
    
    // Use a simple query without OR - we'll filter in Dart instead
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.callLogs
          .orderBy('startedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        print('[CallsScreen] 📊 Stats stream - State: ${snapshot.connectionState}, HasData: ${snapshot.hasData}, HasError: ${snapshot.hasError}');
        if (snapshot.hasError) {
          print('[CallsScreen] ❌ Stats error: ${snapshot.error}');
        }
        if (snapshot.hasData) {
          print('[CallsScreen] 📊 Stats total docs: ${snapshot.data!.docs.length}');
        }
        
        if (!snapshot.hasData) {
          return const SizedBox(height: 120);
        }

        // Filter in Dart to get only this user's calls
        final allLogs = snapshot.data!.docs
            .map((doc) => CallLog.fromFirestore(doc))
            .where((log) => log.callerId == userId || log.receiverId == userId)
            .toList();
        
        print('[CallsScreen] 📊 Filtered logs for user: ${allLogs.length}');

        final totalCalls = allLogs.length;
        final missedCalls = allLogs.where((log) => log.isMissed()).length;
        final voiceCalls = allLogs.where((log) => log.type == 'voice').length;
        final videoCalls = allLogs.where((log) => log.type == 'video').length;

        return Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _buildStatCard('Total', totalCalls, Icons.phone, AppColors.highlight, isDark),
              const SizedBox(width: 12),
              _buildStatCard('Missed', missedCalls, Icons.phone_missed, Colors.red, isDark),
              const SizedBox(width: 12),
              _buildStatCard('Voice', voiceCalls, Icons.phone_in_talk, Colors.green, isDark),
              const SizedBox(width: 12),
              _buildStatCard('Video', videoCalls, Icons.videocam, Colors.purple, isDark),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String label, int count, IconData icon, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF171A21) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? const Color(0xFFA0A4AE) : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('All', CallFilter.all, isDark),
            const SizedBox(width: 8),
            _buildFilterChip('Missed', CallFilter.missed, isDark),
            const SizedBox(width: 8),
            _buildFilterChip('Voice', CallFilter.voice, isDark),
            const SizedBox(width: 8),
            _buildFilterChip('Video', CallFilter.video, isDark),
            const SizedBox(width: 8),
            _buildFilterChip('Incoming', CallFilter.incoming, isDark),
            const SizedBox(width: 8),
            _buildFilterChip('Outgoing', CallFilter.outgoing, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, CallFilter filter, bool isDark) {
    final isSelected = _selectedFilter == filter;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedFilter = filter;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected 
                ? AppColors.highlight 
                : (isDark ? const Color(0xFF171A21) : Colors.grey.shade200),
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.highlight.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected 
                  ? Colors.white 
                  : (isDark ? const Color(0xFFA0A4AE) : AppColors.textSecondary),
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCallsList(String userId, bool isDark) {
    print('[CallsScreen] 🔍 Building calls list for user: $userId');
    
    // Use a simple query without OR - we'll filter in Dart instead
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.callLogs
          .orderBy('startedAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        print('[CallsScreen] 📊 Stream state: ${snapshot.connectionState}');
        print('[CallsScreen] 📊 Has data: ${snapshot.hasData}');
        print('[CallsScreen] 📊 Has error: ${snapshot.hasError}');
        if (snapshot.hasError) {
          print('[CallsScreen] ❌ Stream error: ${snapshot.error}');
          print('[CallsScreen] ❌ Stack trace: ${snapshot.stackTrace}');
        }
        if (snapshot.hasData) {
          print('[CallsScreen] 📊 Total document count: ${snapshot.data!.docs.length}');
          for (var doc in snapshot.data!.docs) {
            print('[CallsScreen] 📄 Doc ID: ${doc.id}, Data: ${doc.data()}');
          }
        }
        
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 300,
            child: Center(
              child: CircularProgressIndicator(color: AppColors.highlight),
            ),
          );
        }

        if (!snapshot.hasData) {
          return SizedBox(
            height: 300,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.phone_disabled,
                    size: 64,
                    color: isDark ? const Color(0xFF171A21) : Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No call history',
                    style: TextStyle(
                      fontSize: 18,
                      color: isDark ? const Color(0xFFA0A4AE) : Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your call history will appear here',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? const Color(0xFF6B7280) : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        
        // Filter in Dart to get only this user's calls
        final allLogs = snapshot.data!.docs
            .map((doc) => CallLog.fromFirestore(doc))
            .where((log) => log.callerId == userId || log.receiverId == userId)
            .toList();
        
        print('[CallsScreen] 📊 Filtered logs for user: ${allLogs.length}');

        if (allLogs.isEmpty) {
          return SizedBox(
            height: 200,
            child: Center(
              child: Text(
                'No ${_selectedFilter.name} calls',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? const Color(0xFFA0A4AE) : Colors.grey.shade600,
                ),
              ),
            ),
          );
        }

        final filteredLogs = _applyFilter(allLogs, userId);

        if (filteredLogs.isEmpty) {
          return SizedBox(
            height: 200,
            child: Center(
              child: Text(
                'No ${_selectedFilter.name} calls',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? const Color(0xFFA0A4AE) : Colors.grey.shade600,
                ),
              ),
            ),
          );
        }

        final groupedLogs = _groupByDate(filteredLogs);

        return Column(
          children: groupedLogs.entries.map((entry) {
            return _buildDateGroup(entry.key, entry.value, userId, isDark);
          }).toList(),
        );
      },
    );
  }

  List<CallLog> _applyFilter(List<CallLog> logs, String userId) {
    switch (_selectedFilter) {
      case CallFilter.all:
        return logs;
      case CallFilter.missed:
        return logs.where((log) => log.isMissed()).toList();
      case CallFilter.voice:
        return logs.where((log) => log.type == 'voice').toList();
      case CallFilter.video:
        return logs.where((log) => log.type == 'video').toList();
      case CallFilter.incoming:
        return logs.where((log) => log.isIncoming(userId)).toList();
      case CallFilter.outgoing:
        return logs.where((log) => log.isOutgoing(userId)).toList();
    }
  }

  Map<String, List<CallLog>> _groupByDate(List<CallLog> logs) {
    final grouped = <String, List<CallLog>>{};
    final now = DateTime.now();

    for (final log in logs) {
      final logDate = log.startedAt.toDate();
      String key;

      if (_isSameDay(logDate, now)) {
        key = 'Today';
      } else if (_isSameDay(logDate, now.subtract(const Duration(days: 1)))) {
        key = 'Yesterday';
      } else {
        key = 'Earlier';
      }

      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(log);
    }

    return grouped;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateGroup(String date, List<CallLog> logs, String userId, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            date,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFA0A4AE) : AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...logs.map((log) => _buildCallLogItem(log, userId, isDark)),
      ],
    );
  }

  Widget _buildCallLogItem(CallLog log, String userId, bool isDark) {
    final isIncoming = log.isIncoming(userId);
    final isMissed = log.isMissed();
    final peerId = log.callerId == userId ? log.receiverId : log.callerId;

    return FutureBuilder<ModUser?>(
      future: _getUserData(peerId),
      builder: (context, snapshot) {
        final peerName = snapshot.data?.name ?? 'Unknown';
        final photoUrl = snapshot.data?.profileImageUrl;

        return Dismissible(
          key: Key(log.id),
          background: Container(
            color: AppColors.highlight,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.phone, color: Colors.white, size: 24),
                SizedBox(height: 4),
                Text('Call', style: TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
          secondaryBackground: Container(
            color: Colors.red.shade600,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.delete_outline, color: Colors.white, size: 24),
                SizedBox(height: 4),
                Text('Delete', style: TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              _callAgain(log, userId);
              return false;
            } else {
              return await _confirmDelete(context);
            }
          },
          onDismissed: (direction) {
            if (direction == DismissDirection.endToStart) {
              _deleteCallLog(log.id);
            }
          },
          child: InkWell(
            onTap: () => _showCallOptions(context, log, userId, peerName, isDark),
            onLongPress: () => _showCallOptions(context, log, userId, peerName, isDark),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F1115) : Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? const Color(0xFF171A21) : Colors.grey.shade100,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                          ? NetworkImage(photoUrl)
                          : null,
                      backgroundColor: isDark 
                          ? const Color(0xFF171A21) 
                          : AppColors.primary.withOpacity(0.1),
                      child: photoUrl == null || photoUrl.isEmpty
                          ? Text(
                              peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.highlight : AppColors.primary,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                peerName,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: isMissed 
                                      ? Colors.red 
                                      : (isDark ? Colors.white : AppColors.textPrimary),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              isIncoming ? Icons.call_received : Icons.call_made,
                              size: 15,
                              color: isMissed ? Colors.red : AppColors.highlight,
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              log.type == 'video' ? Icons.videocam : Icons.phone,
                              size: 15,
                              color: isMissed 
                                  ? Colors.red 
                                  : (isDark ? const Color(0xFFA0A4AE) : AppColors.textSecondary),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _getCallStatusText(log),
                              style: TextStyle(
                                fontSize: 14,
                                color: isMissed 
                                    ? Colors.red 
                                    : (isDark ? const Color(0xFFA0A4AE) : AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(log.startedAt.toDate()),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? const Color(0xFFA0A4AE) : AppColors.textSecondary,
                        ),
                      ),
                      if (log.status == CallLogStatus.completed && log.durationSeconds > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatDuration(log.durationSeconds),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF6B7280) : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: isDark ? const Color(0xFF6B7280) : Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<ModUser?> _getUserData(String userId) async {
    try {
      final doc = await _firestoreService.users.doc(userId).get();
      if (doc.exists) {
        return ModUser.fromMap(doc.data()!);
      }
    } catch (e) {
      print('Error fetching user data: $e');
    }
    return null;
  }

  String _getCallStatusText(CallLog log) {
    if (log.status == CallLogStatus.missed) {
      return 'Missed';
    } else if (log.status == CallLogStatus.declined) {
      return 'Declined';
    } else if (log.status == CallLogStatus.cancelled) {
      return 'Cancelled';
    } else if (log.status == CallLogStatus.failed) {
      return 'Failed';
    } else {
      return log.type == 'video' ? 'Video call' : 'Voice call';
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    if (_isSameDay(time, now)) {
      final hour = time.hour.toString().padLeft(2, '0');
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    
    final yesterday = now.subtract(const Duration(days: 1));
    if (_isSameDay(time, yesterday)) {
      return 'Yesterday';
    }
    
    return DateFormat('MMM d').format(time);
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    }
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}m ${secs}s';
  }

  void _callAgain(CallLog log, String userId) {
    final peerId = log.callerId == userId ? log.receiverId : log.callerId;
    
    if (log.type == 'video') {
      _startVideoCall(peerId);
    } else {
      _startVoiceCall(peerId);
    }
  }

  Future<void> _startVoiceCall(String peerId) async {
    final callService = ref.read(callServiceProvider);
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      await callService.startVoiceCall(
        callerId: currentUser.uid,
        callerName: currentUser.displayName ?? 'Unknown',
        receiverId: peerId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start call: $e')),
        );
      }
    }
  }

  Future<void> _startVideoCall(String peerId) async {
    final callService = ref.read(callServiceProvider);
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      await callService.startVideoCall(
        callerId: currentUser.uid,
        callerName: currentUser.displayName ?? 'Unknown',
        receiverId: peerId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start call: $e')),
        );
      }
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete call log?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteCallLog(String logId) async {
    try {
      await _firestoreService.callLogs.doc(logId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Call log deleted')),
        );
      }
    } catch (e) {
      print('Error deleting call log: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  void _showCallOptions(BuildContext context, CallLog log, String userId, String peerName, bool isDark) {
    final peerId = log.callerId == userId ? log.receiverId : log.callerId;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF171A21) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone, color: AppColors.highlight),
              title: Text('Voice Call', style: TextStyle(color: isDark ? Colors.white : AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _startVoiceCall(peerId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: AppColors.highlight),
              title: Text('Video Call', style: TextStyle(color: isDark ? Colors.white : AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _startVideoCall(peerId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Entry', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await _confirmDelete(context);
                if (confirm) {
                  _deleteCallLog(log.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
