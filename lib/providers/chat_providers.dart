import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message_model.dart';
import '../services/chat_service.dart';
import '../services/block_service.dart';
import '../services/group_moderation_service.dart';
import '../services/optimistic_message_service.dart';
import 'auth_providers.dart';

final chatServiceProvider = Provider<ChatService>((ref) {
  final fs = ref.watch(firestoreServiceProvider);
  return ChatService(fs);
});

final optimisticMessageServiceProvider = Provider<OptimisticMessageService>((ref) {
  return OptimisticMessageService();
});

final groupModerationServiceProvider = Provider<GroupModerationService>((ref) {
  final fs = ref.watch(firestoreServiceProvider);
  return GroupModerationService(fs);
});

final blockServiceProvider = Provider<BlockService>((ref) {
  final fs = ref.watch(firestoreServiceProvider);
  return BlockService(fs);
});

final myBlockedUsersProvider = StreamProvider<Set<String>>((ref) {
  ref.keepAlive();
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  final fs = ref.watch(firestoreServiceProvider);
  return fs.users.doc(uid).snapshots().map((snap) {
    if (!snap.exists) return <String>{};
    final data = snap.data();
    final list =
        (data?['blockedUsers'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    return list.toSet();
  });
});

final peerBlockedUsersProvider = StreamProvider.family<Set<String>, String>((
  ref,
  peerId,
) {
  ref.keepAlive();
  if (peerId.isEmpty) return const Stream.empty();
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  final fs = ref.watch(firestoreServiceProvider);
  return fs.users.doc(peerId).snapshots().map((snap) {
    if (!snap.exists) return <String>{};
    final data = snap.data();
    final list =
        (data?['blockedUsers'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    return list.toSet();
  });
});

typedef BlockStatus = ({bool iBlocked, bool iAmBlocked, bool blockedEither});

final dmBlockStatusProvider = Provider.family<BlockStatus, String>((
  ref,
  peerId,
) {
  final blocked = ref
      .watch(myBlockedUsersProvider)
      .maybeWhen(data: (s) => s, orElse: () => <String>{});
  final peerBlocked = ref
      .watch(peerBlockedUsersProvider(peerId))
      .maybeWhen(data: (s) => s, orElse: () => <String>{});

  final iBlocked = blocked.contains(peerId);
  final iAmBlocked = peerBlocked.contains(ref.watch(currentUserProvider)?.uid);
  return (
    iBlocked: iBlocked,
    iAmBlocked: iAmBlocked,
    blockedEither: iBlocked || iAmBlocked,
  );
});

final groupChatDocProvider =
    StreamProvider.family<DocumentSnapshot<Map<String, dynamic>>, String>((
      ref,
      chatId,
    ) {
      ref.keepAlive();
      final service = ref.watch(groupModerationServiceProvider);
      return service.streamChat(chatId);
    });

final groupMemberDocProvider =
    StreamProvider.family<
      DocumentSnapshot<Map<String, dynamic>>,
      ({String chatId, String uid})
    >((ref, args) {
      ref.keepAlive();
      final service = ref.watch(groupModerationServiceProvider);
      return service.streamMember(args.chatId, args.uid);
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
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) return const Stream.empty();
  final service = ref.watch(chatServiceProvider);
  return service.streamMessages(chatId);
});

/// Combined messages provider that includes both Firestore messages
/// and optimistic (pending) messages for instant UI updates
final combinedMessagesProvider = StreamProvider.family<List<MessageModel>, String>((
  ref,
  chatId,
) async* {
  ref.keepAlive();
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) {
    yield [];
    return;
  }

  final service = ref.watch(chatServiceProvider);
  final optimisticService = ref.watch(optimisticMessageServiceProvider);

  // Stream Firestore messages
  final firestoreStream = service.streamMessages(chatId);

  // Combine both streams
  await for (final firestoreMessages in firestoreStream) {
    final pendingMessages = optimisticService.getPendingMessages(chatId);
    
    // Remove any pending messages that have been confirmed by Firestore
    // (This happens automatically when the message appears in Firestore)
    final firestoreIds = firestoreMessages.map((m) => m.id).toSet();
    final validPending = pendingMessages.where((pending) {
      // Keep pending messages that haven't appeared in Firestore yet
      return !firestoreIds.contains(pending.id) && pending.id.startsWith('pending_');
    }).toList();

    // Combine: pending messages first (newest), then Firestore messages
    final combined = [...validPending, ...firestoreMessages];
    
    yield combined;
  }
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

// Per-chat message bubble zoom factors map: {chatId: zoom}. Default 1.0 when absent.
final Map<String, double> bubbleZoomStore = <String, double>{};
