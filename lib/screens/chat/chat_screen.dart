import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/supabase_service.dart';
import '../../services/storage_service.dart';
import '../../providers/chat_providers.dart';
import '../../providers/user_providers.dart';
import '../../theme/theme.dart';
import 'chat_detail_screen.dart';
import 'group_chat_detail_screen.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatList = ref.watch(chatListProvider);
    final hiddenChats = ref.watch(hiddenChatsProvider);
    final me = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Chats')),
      body: chatList.when(
        data: (docs) {
          final hidden = hiddenChats.maybeWhen(
            data: (s) => s,
            orElse: () => <String>{},
          );
          final filteredDocs = docs
              .where((d) => !hidden.contains(d.id))
              .toList();
          if (filteredDocs.isEmpty) {
            return const Center(
              child: Text(
                'No chats yet',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          return ListView.builder(
            itemCount: filteredDocs.length,
            itemBuilder: (context, index) {
              final d = filteredDocs[index];
              final data = d.data();
              final type = (data['type'] as String?) ?? 'dm';
              final groupName = data['name'] as String?;
              final members = List<String>.from(data['members'] as List);
              final peerId = members.firstWhere(
                (m) => m != me,
                orElse: () => me ?? '',
              );
              final last = data['lastMessage'] as String?;
              final ts = (data['lastTimestamp'] as Timestamp?)?.toDate();
              return _Tile(
                key: ValueKey(d.id),
                chatId: d.id,
                peerId: peerId,
                last: last,
                time: ts,
                chatType: type,
                groupName: groupName,
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  const _Avatar({this.url});

  Future<ImageProvider?> _resolve(String? u) async {
    if (u == null || u.isEmpty) return null;
    if (u.startsWith('sb://')) {
      final s = u.substring(5);
      final i = s.indexOf('/');
      final bucket = s.substring(0, i);
      final path = s.substring(i + 1);
      final signed = await SupabaseService.instance.getSignedUrl(
        bucket,
        path,
        expiresInSeconds: 600,
      );
      return NetworkImage(signed);
    }
    if (!u.contains('://')) {
      final signed = await SupabaseService.instance.resolveUrl(
        bucket: StorageService().profileBucket,
        path: u,
      );
      return NetworkImage(signed);
    }
    return NetworkImage(u);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ImageProvider?>(
      future: _resolve(url),
      builder: (context, snap) {
        final img = snap.data;
        final hasImage = img != null;
        return CircleAvatar(
          backgroundColor: AppColors.sinopia.withValues(alpha: 0.25),
          backgroundImage: img,
          onBackgroundImageError: hasImage ? (_, __) {} : null,
          child: (snap.data != null)
              ? null
              : const Icon(Icons.person, color: Colors.white70),
        );
      },
    );
  }
}

class _Tile extends ConsumerWidget {
  final String chatId;
  final String peerId;
  final String? last;
  final DateTime? time;
  final String chatType;
  final String? groupName;
  const _Tile({
    super.key,
    required this.chatId,
    required this.peerId,
    this.last,
    this.time,
    this.chatType = 'dm',
    this.groupName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (chatType == 'group') {
      final title = (groupName ?? '').trim().isNotEmpty ? groupName! : 'Group';
      return ListTile(
        onTap: () => Navigator.pushNamed(
          context,
          GroupChatDetailScreen.routeName,
          arguments: {'chatId': chatId},
        ),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          last ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70),
        ),
        trailing: time != null
            ? Text(
                '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              )
            : null,
        leading: const CircleAvatar(
          backgroundColor: AppColors.sinopia,
          child: Icon(Icons.group, color: Colors.white),
        ),
      );
    }

    final user2 = ref.watch(userDocProvider(peerId));
    return user2.when(
      data: (u) => ListTile(
        onTap: () => Navigator.pushNamed(
          context,
          ChatDetailScreen.routeName,
          arguments: {'chatId': chatId, 'peerId': peerId},
        ),
        title: Text(u?.name.isNotEmpty == true ? u!.name : peerId),
        subtitle: Text(
          last ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: time != null
            ? Text(
                '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              )
            : null,
        leading: _Avatar(url: u?.profileImageUrl),
      ),
      loading: () => const ListTile(title: Text('...'), subtitle: Text('...')),
      error: (e, _) =>
          ListTile(title: Text(peerId), subtitle: Text(last ?? '')),
    );
  }
}
