import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message_model.dart';
import '../services/chat_service.dart';
import 'auth_providers.dart';

final chatServiceProvider = Provider<ChatService>((ref) {
  final fs = ref.watch(firestoreServiceProvider);
  return ChatService(fs);
});

final chatListProvider =
    StreamProvider<List<QueryDocumentSnapshot<Map<String, dynamic>>>>((ref) {
      ref.keepAlive();
      final user = ref.watch(currentUserProvider);
      final service = ref.watch(chatServiceProvider);
      final uid = user?.uid;
      if (uid == null) return const Stream.empty();
      return service.streamChats(uid);
    });

final messagesProvider = StreamProvider.family<List<MessageModel>, String>((
  ref,
  chatId,
) {
  ref.keepAlive();
  final service = ref.watch(chatServiceProvider);
  return service.streamMessages(chatId);
});
