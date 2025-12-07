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

final hidesProvider = StreamProvider.family<Set<String>, String>((ref, chatId) {
  ref.keepAlive();
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  final fs = ref.watch(firestoreServiceProvider);
  return fs.users.doc(uid).snapshots().map((snap) {
    if (!snap.exists) return <String>{};
    final data = snap.data();
    final hidesMap = (data?['hides'] as Map?) ?? const {};
    final list = List<String>.from((hidesMap[chatId] as List?) ?? const []);
    return list.toSet();
  });
});

// Hidden chats for the current user (soft delete of conversations)
final hiddenChatsProvider = StreamProvider<Set<String>>((ref) {
  ref.keepAlive();
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  final fs = ref.watch(firestoreServiceProvider);
  return fs.users.doc(uid).snapshots().map((snap) {
    if (!snap.exists) return <String>{};
    final data = snap.data();
    final list = List<String>.from((data?['hiddenChats'] as List?) ?? const []);
    return list.toSet();
  });
});
