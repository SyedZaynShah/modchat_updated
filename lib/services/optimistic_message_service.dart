import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/message_model.dart';

/// Service for managing optimistic (pending) messages that appear instantly
/// in the UI before being confirmed by Firestore
class OptimisticMessageService {
  final _uuid = const Uuid();
  
  /// Map of chatId to list of pending messages
  final Map<String, List<MessageModel>> _pendingMessages = {};
  
  /// StreamController to notify listeners of pending message changes
  final Map<String, StreamController<List<MessageModel>>> _controllers = {};

  /// Get stream of pending messages for a specific chat
  Stream<List<MessageModel>> pendingMessagesStream(String chatId) {
    if (!_controllers.containsKey(chatId)) {
      _controllers[chatId] = StreamController<List<MessageModel>>.broadcast();
    }
    return _controllers[chatId]!.stream;
  }

  /// Get current pending messages for a chat
  List<MessageModel> getPendingMessages(String chatId) {
    return List.from(_pendingMessages[chatId] ?? []);
  }

  /// Add a pending text message that will appear instantly in the UI
  String addPendingTextMessage({
    required String chatId,
    required String senderId,
    required String receiverId,
    required String text,
    Map<String, dynamic>? replyTo,
  }) {
    // Generate a temporary ID for the optimistic message
    final tempId = 'pending_${_uuid.v4()}';
    
    final now = DateTime.now();
    
    // Create the optimistic message
    final message = MessageModel(
      id: tempId,
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      text: text,
      messageType: MessageType.text,
      timestamp: Timestamp.fromDate(now),
      isSeen: false,
      status: 0, // 0 = sending/pending
      edited: false,
      isDeletedForAll: false,
      replyToMessageId: replyTo?['messageId'] as String?,
      replyToSenderId: replyTo?['senderId'] as String?,
      replyToText: replyTo?['text'] as String?,
      replyToMessageType: replyTo?['messageType'] as String?,
      reactions: const {},
      userReactions: const {},
      forwarded: false,
      uploadStatus: 'uploading', // Indicate it's being sent
    );

    // Add to pending list
    _pendingMessages.putIfAbsent(chatId, () => []);
    _pendingMessages[chatId]!.add(message);

    // Notify listeners
    _notifyListeners(chatId);

    return tempId;
  }

  /// Add a pending media message
  String addPendingMediaMessage({
    required String chatId,
    required String senderId,
    required String receiverId,
    required MessageType type,
    String? caption,
    String? localPath,
    Map<String, dynamic>? replyTo,
    Map<String, dynamic>? meta,
  }) {
    final tempId = 'pending_${_uuid.v4()}';
    final now = DateTime.now();

    final message = MessageModel(
      id: tempId,
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      text: caption,
      messageType: type,
      timestamp: Timestamp.fromDate(now),
      isSeen: false,
      status: 0, // Sending
      edited: false,
      isDeletedForAll: false,
      mediaUrl: localPath, // Show local file while uploading
      localPath: localPath,
      replyToMessageId: replyTo?['messageId'] as String?,
      replyToSenderId: replyTo?['senderId'] as String?,
      replyToText: replyTo?['text'] as String?,
      replyToMessageType: replyTo?['messageType'] as String?,
      reactions: const {},
      userReactions: const {},
      forwarded: false,
      meta: meta,
      uploadStatus: 'uploading',
    );

    _pendingMessages.putIfAbsent(chatId, () => []);
    _pendingMessages[chatId]!.add(message);
    _notifyListeners(chatId);

    return tempId;
  }

  /// Remove a pending message (called when Firestore confirms the message)
  void removePendingMessage(String chatId, String tempId) {
    if (_pendingMessages.containsKey(chatId)) {
      _pendingMessages[chatId]!.removeWhere((msg) => msg.id == tempId);
      if (_pendingMessages[chatId]!.isEmpty) {
        _pendingMessages.remove(chatId);
      }
      _notifyListeners(chatId);
    }
  }

  /// Update pending message status (e.g., upload progress)
  void updatePendingMessage(
    String chatId,
    String tempId, {
    int? status,
    String? mediaUrl,
    Map<String, dynamic>? meta,
  }) {
    if (_pendingMessages.containsKey(chatId)) {
      final index = _pendingMessages[chatId]!.indexWhere((m) => m.id == tempId);
      if (index != -1) {
        final oldMsg = _pendingMessages[chatId]![index];
        _pendingMessages[chatId]![index] = MessageModel(
          id: oldMsg.id,
          chatId: oldMsg.chatId,
          senderId: oldMsg.senderId,
          receiverId: oldMsg.receiverId,
          text: oldMsg.text,
          messageType: oldMsg.messageType,
          timestamp: oldMsg.timestamp,
          isSeen: oldMsg.isSeen,
          status: status ?? oldMsg.status,
          edited: oldMsg.edited,
          isDeletedForAll: oldMsg.isDeletedForAll,
          mediaUrl: mediaUrl ?? oldMsg.mediaUrl,
          localPath: oldMsg.localPath,
          replyToMessageId: oldMsg.replyToMessageId,
          replyToSenderId: oldMsg.replyToSenderId,
          replyToText: oldMsg.replyToText,
          replyToMessageType: oldMsg.replyToMessageType,
          reactions: oldMsg.reactions,
          userReactions: oldMsg.userReactions,
          forwarded: oldMsg.forwarded,
          meta: meta ?? oldMsg.meta,
          uploadStatus: status == -1 ? 'failed' : oldMsg.uploadStatus,
        );
        _notifyListeners(chatId);
      }
    }
  }

  /// Mark a pending message as failed
  void markAsFailed(String chatId, String tempId) {
    updatePendingMessage(chatId, tempId, status: -1); // -1 = failed
  }

  /// Retry sending a failed message
  void retryMessage(String chatId, String tempId) {
    updatePendingMessage(chatId, tempId, status: 0); // 0 = sending
  }

  /// Clear all pending messages for a chat
  void clearPendingMessages(String chatId) {
    _pendingMessages.remove(chatId);
    _notifyListeners(chatId);
  }

  /// Clear all pending messages (e.g., on logout)
  void clearAll() {
    _pendingMessages.clear();
    for (final controller in _controllers.values) {
      if (!controller.isClosed) {
        controller.add([]);
      }
    }
  }

  void _notifyListeners(String chatId) {
    if (_controllers.containsKey(chatId) && !_controllers[chatId]!.isClosed) {
      _controllers[chatId]!.add(getPendingMessages(chatId));
    }
  }

  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
    _pendingMessages.clear();
  }
}
