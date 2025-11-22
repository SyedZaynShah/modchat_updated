import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/chat_providers.dart';
import '../../providers/user_providers.dart';
import '../../theme/theme.dart';
import 'chat_detail_screen.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatList = ref.watch(chatListProvider);
    final me = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Chats')),
      body: chatList.when(
        data: (docs) {
          if (docs.isEmpty) {
            return const Center(child: Text('No chats yet', style: TextStyle(color: Colors.white70)));
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final d = docs[index];
              final data = d.data();
              final members = List<String>.from(data['members'] as List);
              final peerId = members.firstWhere((m) => m != me, orElse: () => me ?? '');
              final last = data['lastMessage'] as String?;
              final ts = (data['lastTimestamp'] as Timestamp?)?.toDate();
              return _Tile(chatId: d.id, peerId: peerId, last: last, time: ts);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')), 
      ),
    );
  }
}

class _Tile extends ConsumerWidget {
  final String chatId;
  final String peerId;
  final String? last;
  final DateTime? time;
  const _Tile({required this.chatId, required this.peerId, this.last, this.time});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user2 = ref.watch(userDocProvider(peerId));
    return user2.when(
      data: (u) => ListTile(
        onTap: () => Navigator.pushNamed(context, ChatDetailScreen.routeName, arguments: {'chatId': chatId, 'peerId': peerId}),
        title: Text(u?.name.isNotEmpty == true ? u!.name : peerId),
        subtitle: Text(last ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: time != null ? Text('${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.white54, fontSize: 12)) : null,
        leading: CircleAvatar(
          backgroundColor: AppColors.sinopia.withValues(alpha: 0.25),
          backgroundImage: (u?.profilePicUrl?.isNotEmpty == true) ? NetworkImage(u!.profilePicUrl!) : null,
          child: (u?.profilePicUrl?.isNotEmpty == true) ? null : const Icon(Icons.person, color: Colors.white70),
        ),
      ),
      loading: () => const ListTile(title: Text('...'), subtitle: Text('...')),
      error: (e, _) => ListTile(title: Text(peerId), subtitle: Text(last ?? '')),
    );
  }
}
