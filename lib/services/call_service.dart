import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import '../models/call_state.dart';
import '../models/call_log.dart';

class CallService {
  final FirestoreService _firestoreService = FirestoreService();
  
  // Timeout duration for unanswered calls
  static const Duration callTimeout = Duration(seconds: 30);
  
  // Map to track active call timeouts
  final Map<String, Timer> _callTimeouts = {};
  
  // Map to track timeout listeners
  final Map<String, StreamSubscription> _callTimeoutListeners = {};

  /// Check if user has an active call
  Future<Map<String, dynamic>> checkActiveCall(String userId) async {
    try {
      // Check if user is caller in an active call
      final asCallerQuery = await _firestoreService.calls
          .where('callerId', isEqualTo: userId)
          .where('status', whereIn: ['calling', 'ringing', 'accepted'])
          .limit(1)
          .get();

      if (asCallerQuery.docs.isNotEmpty) {
        return {
          'hasActiveCall': true,
          'callId': asCallerQuery.docs.first.id,
          'role': 'caller',
        };
      }

      // Check if user is receiver in an active call
      final asReceiverQuery = await _firestoreService.calls
          .where('receiverId', isEqualTo: userId)
          .where('status', whereIn: ['calling', 'ringing', 'accepted'])
          .limit(1)
          .get();

      if (asReceiverQuery.docs.isNotEmpty) {
        return {
          'hasActiveCall': true,
          'callId': asReceiverQuery.docs.first.id,
          'role': 'receiver',
        };
      }

      return {'hasActiveCall': false};
    } catch (e) {
      print('Error checking active call: $e');
      return {'hasActiveCall': false, 'error': e};
    }
  }

  /// Check if a user is online before making a call
  Future<Map<String, dynamic>> checkUserOnlineStatus(String userId) async {
    try {
      final userDoc = await _firestoreService.users.doc(userId).get();
      
      if (!userDoc.exists) {
        return {'isOnline': false, 'lastSeen': null, 'exists': false};
      }
      
      final data = userDoc.data();
      final isOnline = data?['isOnline'] as bool? ?? false;
      final lastSeen = data?['lastSeen'] as Timestamp?;
      
      return {
        'isOnline': isOnline,
        'lastSeen': lastSeen,
        'exists': true,
      };
    } catch (e) {
      print('Error checking online status: $e');
      return {'isOnline': false, 'lastSeen': null, 'exists': false, 'error': e};
    }
  }

  /// Start a voice call
  /// Returns the document ID of the created call
  Future<String> startVoiceCall({
    required String callerId,
    required String callerName,
    required String receiverId,
  }) async {
    return _startCall(
      callerId: callerId,
      callerName: callerName,
      receiverId: receiverId,
      type: 'voice',
    );
  }

  /// Start a video call
  /// Returns the document ID of the created call
  Future<String> startVideoCall({
    required String callerId,
    required String callerName,
    required String receiverId,
  }) async {
    return _startCall(
      callerId: callerId,
      callerName: callerName,
      receiverId: receiverId,
      type: 'video',
    );
  }

  /// Internal method to start a call (voice or video)
  Future<String> _startCall({
    required String callerId,
    required String callerName,
    required String receiverId,
    required String type,
  }) async {
    // Check if caller already has an active call
    final callerActiveCall = await checkActiveCall(callerId);
    if (callerActiveCall['hasActiveCall'] == true) {
      throw Exception('You are already on a call');
    }

    // Check if receiver already has an active call
    final receiverActiveCall = await checkActiveCall(receiverId);
    if (receiverActiveCall['hasActiveCall'] == true) {
      throw Exception('User is already on another call');
    }

    // DIAGNOSTIC LOGGING
    final currentAuthUid = FirebaseAuth.instance.currentUser?.uid;
    print('=== CALL CREATION DEBUG ===');
    print('AUTH UID: $currentAuthUid');
    print('CALLER ID: $callerId');
    print('RECEIVER ID: $receiverId');
    print('CALL TYPE: $type');
    print('UID MATCHES CALLER: ${currentAuthUid == callerId}');
    
    final callData = {
      'callerId': callerId,
      'callerName': callerName,
      'receiverId': receiverId,
      'type': type, // 'voice' or 'video'
      'status': CallState.calling.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
      'answeredAt': null,
      'endedAt': null,
    };
    
    print('CALL DOC: $callData');
    print('STATUS VALUE: ${CallState.calling.toFirestore()}');
    print('===========================');
    
    final docRef = await _firestoreService.calls.add(callData);

    final callId = docRef.id;
    
    _logStateTransition(callId, null, CallState.calling);
    
    // Start timeout timer
    _startCallTimeout(callId);
    
    // Update status to ringing after document is created
    // This simulates the call starting to ring
    Future.delayed(const Duration(milliseconds: 500), () {
      _updateCallState(callId, CallState.ringing);
    });

    return callId;
  }

  /// Update call state with logging
  Future<void> _updateCallState(String callId, CallState newState) async {
    try {
      // Get current state first
      final doc = await _firestoreService.calls.doc(callId).get();
      if (!doc.exists) return;
      
      final currentStateStr = doc.data()?['status'] as String?;
      final currentState = CallState.fromString(currentStateStr);
      
      if (currentState == newState) return; // No change needed
      
      _logStateTransition(callId, currentState, newState);
      
      await _firestoreService.calls.doc(callId).update({
        'status': newState.toFirestore(),
        if (newState.isTerminal) 'endedAt': FieldValue.serverTimestamp(),
      });
      
      // Cancel timeout if call reaches terminal state
      if (newState.isTerminal) {
        _cancelCallTimeout(callId);
      }
    } catch (e) {
      print('Error updating call state: $e');
    }
  }

  /// Accept an incoming call
  Future<void> acceptCall(String callId) async {
    print('[CallService] ✅ ACCEPTING CALL: $callId');
    print('[CallService] 📝 Updating Firestore: status → accepted');
    
    await _firestoreService.calls.doc(callId).update({
      'status': CallState.accepted.toFirestore(),
      'answeredAt': FieldValue.serverTimestamp(),
    });
    
    print('[CallService] ✅ Firestore updated successfully');
    _logStateTransition(callId, CallState.ringing, CallState.accepted);
    
    // Note: We don't cancel timeout here because this is called on RECEIVER device
    // The timeout timer exists on CALLER device
    // The monitoring listener will cancel it when it detects status = accepted
    print('[CallService] 📡 Timeout will be cancelled by monitoring listener on caller side');
  }

  /// Decline an incoming call
  Future<void> declineCall(String callId) async {
    print('[CallService] ❌ DECLINING CALL: $callId');
    
    await _firestoreService.calls.doc(callId).update({
      'status': CallState.declined.toFirestore(),
      'endedAt': FieldValue.serverTimestamp(),
    });
    
    _logStateTransition(callId, CallState.ringing, CallState.declined);
    
    // CRITICAL: Wait a moment for Firestore to write the timestamp
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Save call log
    await saveCallLog(callId);
    
    // Timeout monitoring listener will cancel it automatically
    print('[CallService] 📡 Timeout will be cancelled by monitoring listener');
  }

  /// End an ongoing call
  Future<void> endCall(String callId) async {
    print('[CallService] 🔚 ENDING CALL: $callId');
    
    // Get current call state
    final doc = await _firestoreService.calls.doc(callId).get();
    if (!doc.exists) {
      print('[CallService] ⚠️ Call document does not exist');
      return;
    }
    
    final currentStateStr = doc.data()?['status'] as String?;
    final currentState = CallState.fromString(currentStateStr);
    
    print('[CallService] Current state: ${currentState.name}');
    
    // If ending before answer, mark as cancelled
    final newState = (currentState == CallState.calling || currentState == CallState.ringing)
        ? CallState.cancelled
        : CallState.ended;
    
    print('[CallService] New state will be: ${newState.name}');
    
    await _firestoreService.calls.doc(callId).update({
      'status': newState.toFirestore(),
      'endedAt': FieldValue.serverTimestamp(),
    });
    
    _logStateTransition(callId, currentState, newState);
    
    // CRITICAL: Wait a moment for Firestore to write the timestamp
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Save call log
    await saveCallLog(callId);
    
    // Timeout monitoring listener will cancel it automatically
    print('[CallService] 📡 Timeout will be cancelled by monitoring listener');
  }

  /// Mark call as failed
  Future<void> failCall(String callId, String reason) async {
    await _firestoreService.calls.doc(callId).update({
      'status': CallState.failed.toFirestore(),
      'endedAt': FieldValue.serverTimestamp(),
      'failureReason': reason,
    });
    
    _logStateTransition(callId, null, CallState.failed);
    _cancelCallTimeout(callId);
  }

  /// Start timeout timer for a call
  void _startCallTimeout(String callId) {
    _cancelCallTimeout(callId); // Cancel any existing timer
    
    print('[CallService] Starting timeout timer for call: $callId (${callTimeout.inSeconds}s)');
    
    // CRITICAL: Start monitoring immediately to cancel timeout if status changes
    _monitorCallForTimeoutCancellation(callId);
    
    _callTimeouts[callId] = Timer(callTimeout, () async {
      try {
        print('[CallService] Timeout fired for call: $callId, checking current status...');
        
        final doc = await _firestoreService.calls.doc(callId).get();
        if (!doc.exists) {
          print('[CallService] Call document no longer exists, ignoring timeout');
          return;
        }
        
        final status = CallState.fromString(doc.data()?['status'] as String?);
        print('[CallService] Current status: ${status.name}');
        
        // Only timeout if still in calling or ringing state
        // If status is already accepted, declined, ended, etc., do nothing
        if (status == CallState.calling || status == CallState.ringing) {
          print('[CallService] Call not answered, setting status to missed');
          await _firestoreService.calls.doc(callId).update({
            'status': CallState.missed.toFirestore(),
            'endedAt': FieldValue.serverTimestamp(),
          });
          
          _logStateTransition(callId, status, CallState.missed);
          
          // CRITICAL: Wait a moment for Firestore to write the timestamp
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Save call log
          await saveCallLog(callId);
        } else {
          print('[CallService] Call already in state ${status.name}, not timing out');
        }
      } catch (e) {
        print('[CallService] Error handling call timeout: $e');
      } finally {
        _callTimeouts.remove(callId);
        _callTimeoutListeners[callId]?.cancel();
        _callTimeoutListeners.remove(callId);
      }
    });
  }

  /// Cancel timeout timer for a call
  void _cancelCallTimeout(String callId) {
    final timer = _callTimeouts[callId];
    if (timer != null) {
      print('[CallService] Cancelling timeout for call: $callId');
      timer.cancel();
      _callTimeouts.remove(callId);
    }
    
    // Also cancel the monitoring listener
    final listener = _callTimeoutListeners[callId];
    if (listener != null) {
      listener.cancel();
      _callTimeoutListeners.remove(callId);
    }
  }

  /// Log state transitions
  void _logStateTransition(String callId, CallState? from, CallState to) {
    if (from == null) {
      print('CALL STATE [$callId]: -> ${to.name}');
    } else {
      print('CALL STATE [$callId]: ${from.name} -> ${to.name}');
    }
  }

  /// Listen to incoming calls for the current user
  Stream<QuerySnapshot<Map<String, dynamic>>> listenToIncomingCalls() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return const Stream.empty();
    }

    return _firestoreService.calls
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', isEqualTo: CallState.ringing.toFirestore())
        .snapshots();
  }

  /// Get a specific call document
  Future<DocumentSnapshot<Map<String, dynamic>>> getCall(String callId) {
    return _firestoreService.calls.doc(callId).get();
  }

  /// Listen to a specific call for status updates
  Stream<DocumentSnapshot<Map<String, dynamic>>> listenToCall(String callId) {
    return _firestoreService.calls.doc(callId).snapshots();
  }
  
  /// Monitor call status and cancel timeout if accepted/declined/ended
  /// CRITICAL: This must be called immediately when timeout starts, not when UI subscribes
  void _monitorCallForTimeoutCancellation(String callId) {
    // Cancel any existing listener for this call
    _callTimeoutListeners[callId]?.cancel();
    
    print('[CallService] 🔔 Starting real-time monitoring for call $callId (will cancel timeout if status changes)');
    
    final listener = _firestoreService.calls.doc(callId).snapshots().listen((snapshot) {
      if (!snapshot.exists) {
        print('[CallService] Call $callId document deleted, cancelling timeout');
        _cancelCallTimeout(callId);
        return;
      }
      
      final status = CallState.fromString(snapshot.data()?['status'] as String?);
      print('[CallService] 📡 Call $callId status update: ${status.name}');
      
      // Cancel timeout if call moves beyond ringing state (accepted, declined, ended, etc.)
      if (status != CallState.calling && status != CallState.ringing) {
        print('[CallService] ✅ Call $callId status changed to ${status.name}, CANCELLING TIMEOUT');
        _cancelCallTimeout(callId);
      }
    }, onError: (e) {
      print('[CallService] ❌ Error monitoring call $callId: $e');
    });
    
    // Store listener so we can cancel it later
    _callTimeoutListeners[callId] = listener;
  }
  
  /// Save call log to Firestore with UNIQUE ID (separate from active call)
  Future<void> saveCallLog(String callId) async {
    try {
      print('[CallService] 💾 ========== SAVE CALL LOG START ==========');
      print('[CallService] 💾 Call ID: $callId');
      
      final callDoc = await _firestoreService.calls.doc(callId).get();
      if (!callDoc.exists) {
        print('[CallService] ❌ Call document not found, cannot save log');
        return;
      }
      
      final data = callDoc.data()!;
      print('[CallService] 📄 Call data: $data');
      
      final status = CallState.fromString(data['status'] as String?);
      print('[CallService] 📊 Call status: ${status.name}');
      
      // Determine call log status
      CallLogStatus logStatus;
      if (status == CallState.missed) {
        logStatus = CallLogStatus.missed;
      } else if (status == CallState.declined) {
        logStatus = CallLogStatus.declined;
      } else if (status == CallState.cancelled) {
        logStatus = CallLogStatus.cancelled;
      } else if (status == CallState.failed) {
        logStatus = CallLogStatus.failed;
      } else if (status == CallState.ended) {
        logStatus = CallLogStatus.completed;
      } else {
        print('[CallService] ⚠️ Call status is ${status.name}, not saving yet');
        return;
      }
      
      print('[CallService] ✅ Log status determined: ${logStatus.value}');
      
      // Calculate duration
      final answeredAt = data['answeredAt'] as Timestamp?;
      final endedAt = data['endedAt'] as Timestamp?;
      int durationSeconds = 0;
      if (answeredAt != null && endedAt != null) {
        durationSeconds = endedAt.seconds - answeredAt.seconds;
        print('[CallService] ⏱️ Duration: ${durationSeconds}s');
      } else {
        print('[CallService] ⚠️ No duration (answeredAt: $answeredAt, endedAt: $endedAt)');
      }
      
      // CRITICAL FIX: Check if log already exists to prevent duplicates
      print('[CallService] 🔍 Checking for existing log...');
      final existingLog = await _firestoreService.callLogs
          .where('callId', isEqualTo: callId)
          .limit(1)
          .get();
      
      if (existingLog.docs.isNotEmpty) {
        print('[CallService] ⚠️ Call log already exists for $callId, skipping');
        return;
      }
      
      print('[CallService] ✅ No existing log found, creating new one');
      
      // CRITICAL FIX: Use auto-generated ID instead of callId for permanent history
      final logRef = _firestoreService.callLogs.doc();
      final logId = logRef.id;
      
      print('[CallService] 🆔 Generated log ID: $logId');
      
      final callLog = CallLog(
        id: logId, // Use unique log ID
        callId: callId, // Keep reference to original call
        type: data['type'] as String? ?? 'voice',
        callerId: data['callerId'] as String,
        receiverId: data['receiverId'] as String,
        startedAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
        answeredAt: answeredAt,
        endedAt: endedAt,
        durationSeconds: durationSeconds,
        status: logStatus,
        initiatorId: data['callerId'] as String,
      );
      
      print('[CallService] 📦 Call log object created: ${callLog.toFirestore()}');
      
      // Save with merge to prevent overwriting
      print('[CallService] 💾 Writing to Firestore...');
      await logRef.set(callLog.toFirestore(), SetOptions(merge: true));
      print('[CallService] ✅ ✅ ✅ Call log saved successfully with ID: $logId');
      
      // Also save as chat message
      print('[CallService] 💬 Saving chat message...');
      await _saveCallMessage(callLog);
      print('[CallService] 💾 ========== SAVE CALL LOG END ==========');
    } catch (e, stackTrace) {
      print('[CallService] ❌ ❌ ❌ Error saving call log: $e');
      print('[CallService] 📚 Stack trace: $stackTrace');
    }
  }
  
  /// Save call as chat message (CRITICAL: Check for duplicates)
  Future<void> _saveCallMessage(CallLog callLog) async {
    try {
      print('[CallService] 💬 ========== SAVE CHAT MESSAGE START ==========');
      
      final callerId = callLog.callerId;
      final receiverId = callLog.receiverId;
      
      print('[CallService] 👤 Caller: $callerId');
      print('[CallService] 👤 Receiver: $receiverId');
      
      // Generate chat ID (same logic as DM chats)
      final chatId = _generateChatId(callerId, receiverId);
      print('[CallService] 💬 Chat ID: $chatId');
      
      // CRITICAL FIX: Check if message already exists to prevent duplicates
      print('[CallService] 🔍 Checking for existing message...');
      final existingMessage = await _firestoreService.messages(chatId)
          .where('meta.callId', isEqualTo: callLog.callId)
          .limit(1)
          .get();
      
      if (existingMessage.docs.isNotEmpty) {
        print('[CallService] ⚠️ Call message already exists for ${callLog.callId}, skipping');
        return;
      }
      
      print('[CallService] ✅ No existing message, creating new one');
      
      // Create call message for BOTH participants
      final messageData = {
        'chatId': chatId,
        'senderId': callLog.initiatorId,
        'receiverId': callLog.initiatorId == callerId ? receiverId : callerId,
        'type': 'system',
        'messageType': 'call',
        'text': _getCallMessageText(callLog),
        'meta': {
          'callType': callLog.type,
          'callStatus': callLog.status.value,
          'callDuration': callLog.durationSeconds,
          'callId': callLog.callId,
          'callLogId': callLog.id,
        },
        'timestamp': callLog.endedAt ?? callLog.startedAt,
        'isSeen': false,
        'status': 1,
      };
      
      print('[CallService] 📦 Message data: $messageData');
      print('[CallService] 💾 Writing to Firestore messages...');
      
      await _firestoreService.messages(chatId).add(messageData);
      print('[CallService] ✅ ✅ ✅ Call message saved to chat $chatId');
      print('[CallService] 💬 ========== SAVE CHAT MESSAGE END ==========');
    } catch (e, stackTrace) {
      print('[CallService] ❌ ❌ ❌ Error saving call message: $e');
      print('[CallService] 📚 Stack trace: $stackTrace');
    }
  }
  
  String _generateChatId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }
  
  String _getCallMessageText(CallLog log) {
    final isVideo = log.type == 'video';
    final icon = isVideo ? '📹' : '📞';
    
    if (log.status == CallLogStatus.missed) {
      return '$icon Missed ${isVideo ? 'video' : 'voice'} call';
    } else if (log.status == CallLogStatus.declined) {
      return '$icon ${isVideo ? 'Video' : 'Voice'} call declined';
    } else if (log.status == CallLogStatus.cancelled) {
      return '$icon ${isVideo ? 'Video' : 'Voice'} call cancelled';
    } else if (log.status == CallLogStatus.completed) {
      final duration = _formatDuration(log.durationSeconds);
      return '$icon ${isVideo ? 'Video' : 'Voice'} call • $duration';
    } else {
      return '$icon ${isVideo ? 'Video' : 'Voice'} call failed';
    }
  }
  
  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else {
      final minutes = seconds ~/ 60;
      final secs = seconds % 60;
      if (secs == 0) {
        return '${minutes}m';
      }
      return '${minutes}m ${secs}s';
    }
  }
  
  /// Clean up all timers (call on logout or app dispose)
  void dispose() {
    print('[CallService] Disposing CallService, cleaning up ${_callTimeouts.length} timers and ${_callTimeoutListeners.length} listeners');
    
    for (final timer in _callTimeouts.values) {
      timer.cancel();
    }
    _callTimeouts.clear();
    
    for (final listener in _callTimeoutListeners.values) {
      listener.cancel();
    }
    _callTimeoutListeners.clear();
  }
}
