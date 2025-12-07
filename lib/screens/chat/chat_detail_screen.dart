import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/message_model.dart';
import '../../providers/chat_providers.dart';
import '../../providers/user_providers.dart';
import '../../theme/theme.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/input_field.dart';
import '../../services/supabase_service.dart';
import '../../services/storage_service.dart';
import 'chat_contact_info_screen.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  static const routeName = '/chat-detail';
  final String chatId;
  final String peerId;
  const ChatDetailScreen({
    super.key,
    required this.chatId,
    required this.peerId,
  });

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  final _scrollController = ScrollController();
  bool _ackSent = false;
  bool _nearBottom = true;
  // typing state no longer used for VN visibility (handled inside InputField)
  int _lastCount = 0;
  bool _didInitialScroll = false;

  @override
  void initState() {
    super.initState();
    // Delay to ensure providers are ready
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(chatServiceProvider).acknowledgeDelivered(widget.chatId);
      setState(() => _ackSent = true);
    });
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final isNear = (pos.maxScrollExtent - pos.pixels) <= 30;
      if (isNear != _nearBottom) {
        setState(() => _nearBottom = isNear);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendText(String text) async {
    await ref
        .read(chatServiceProvider)
        .sendText(chatId: widget.chatId, peerId: widget.peerId, text: text);
    _maybeScrollToBottom();
  }

  Future<void> _sendMedia(
    Uint8List bytes,
    String name,
    String contentType,
    MessageType type, {
    int? durationMs,
  }) async {
    await ref
        .read(chatServiceProvider)
        .sendMedia(
          chatId: widget.chatId,
          peerId: widget.peerId,
          bytes: bytes,
          fileName: name,
          contentType: contentType,
          type: type,
          audioDurationMs: durationMs,
        );
    _maybeScrollToBottom();
  }

  void _maybeScrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!_scrollController.hasClients) return;
      if (_nearBottom) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTypingChanged(bool hasText) {}

  Future<void> _onMessageLongPress(
    BuildContext context,
    MessageModel m,
    bool isMe,
  ) async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMe && m.messageType == MessageType.text)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final controller = TextEditingController(
                      text: m.text ?? '',
                    );
                    final newText = await showDialog<String>(
                      context: context,
                      builder: (dCtx) => AlertDialog(
                        title: const Text('Edit message'),
                        content: TextField(
                          controller: controller,
                          maxLines: 5,
                          minLines: 1,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dCtx, controller.text.trim()),
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    );
                    if (newText != null && newText.isNotEmpty) {
                      await ref
                          .read(chatServiceProvider)
                          .editMessage(
                            chatId: widget.chatId,
                            messageId: m.id,
                            newText: newText,
                          );
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete for me'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref
                      .read(chatServiceProvider)
                      .deleteForMe(chatId: widget.chatId, messageId: m.id);
                },
              ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('Delete for everyone'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ref
                        .read(chatServiceProvider)
                        .deleteForEveryone(
                          chatId: widget.chatId,
                          messageId: m.id,
                        );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!.uid;
    final messages = ref.watch(messagesProvider(widget.chatId));
    final hides = ref.watch(hidesProvider(widget.chatId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: _PeerTitle(peerId: widget.peerId, chatId: widget.chatId),
        centerTitle: false,
        automaticallyImplyLeading: true,
        iconTheme: const IconThemeData(color: AppColors.navy, size: 18),
        titleSpacing: 0,
        leadingWidth: 40,
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.videocam_outlined,
              color: AppColors.navy,
              size: 18,
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.call_outlined,
              color: AppColors.navy,
              size: 18,
            ),
          ),
          PopupMenuButton<String>(
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'contact', child: Text('Contact info')),
              PopupMenuItem(value: 'report', child: Text('Report')),
              PopupMenuItem(value: 'block', child: Text('Block')),
            ],
            onSelected: (v) {
              if (v == 'contact') {
                Navigator.pushNamed(
                  context,
                  ChatContactInfoScreen.routeName,
                  arguments: {'peerId': widget.peerId, 'chatId': widget.chatId},
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(v == 'report' ? 'Reported' : 'Blocked'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.more_vert, color: AppColors.navy, size: 18),
          ),
        ],
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(3),
          child: SizedBox(
            height: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(color: AppColors.sinopia),
            ),
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('lib/assets/background.png', fit: BoxFit.cover),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: messages.when(
                    data: (list) {
                      final hidden = hides.maybeWhen(
                        data: (s) => s,
                        orElse: () => <String>{},
                      );
                      final filtered = list
                          .where((m) => !hidden.contains(m.id))
                          .toList();
                      if (_ackSent) {
                        if (filtered.length > _lastCount && _nearBottom) {
                          ref
                              .read(chatServiceProvider)
                              .markAllSeen(widget.chatId);
                          // Only auto-scroll when we received new messages and are at bottom
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _maybeScrollToBottom(),
                          );
                        }
                        _lastCount = filtered.length;
                      }
                      if (!_didInitialScroll) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scrollController.hasClients) {
                            _scrollController.jumpTo(
                              _scrollController.position.maxScrollExtent + 80,
                            );
                          }
                        });
                        setState(() => _didInitialScroll = true);
                      }
                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final m = filtered[index];
                          final isMe = m.senderId == me;
                          return GestureDetector(
                            key: ValueKey(m.id),
                            onLongPress: () =>
                                _onMessageLongPress(context, m, isMe),
                            child: Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: MessageBubble(message: m, isMe: isMe),
                            ),
                          );
                        },
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                  ),
                ),
                InputField(
                  onSend: _sendText,
                  onSendMedia: _sendMedia,
                  onTypingChanged: _onTypingChanged,
                ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: 84,
            child: AnimatedOpacity(
              opacity: _nearBottom ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Visibility(
                visible: !_nearBottom,
                child: Material(
                  color: AppColors.navy,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(
                          _scrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.arrow_downward,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeerTitle extends ConsumerWidget {
  final String peerId;
  final String chatId;
  const _PeerTitle({required this.peerId, required this.chatId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userDocProvider(peerId));
    return user.when(
      data: (u) => InkWell(
        onTap: () => Navigator.pushNamed(
          context,
          ChatContactInfoScreen.routeName,
          arguments: {'peerId': peerId, 'chatId': chatId},
        ),
        child: Row(
          children: [
            FutureBuilder<ImageProvider?>(
              future: () async {
                final url = u?.profileImageUrl;
                if (url == null || url.isEmpty) return null;
                if (url.startsWith('sb://')) {
                  final s = url.substring(5);
                  final i = s.indexOf('/');
                  final bucket = s.substring(0, i);
                  final path = s.substring(i + 1);
                  final signed = await SupabaseService.instance.getSignedUrl(
                    bucket,
                    path,
                    expiresInSeconds: 86400,
                  );
                  return NetworkImage(signed);
                }
                if (!url.contains('://')) {
                  final signed = await SupabaseService.instance.resolveUrl(
                    bucket: StorageService().profileBucket,
                    path: url,
                  );
                  return NetworkImage(signed);
                }
                return NetworkImage(url);
              }(),
              builder: (context, snap) => CircleAvatar(
                radius: 16,
                backgroundImage: snap.data,
                child: snap.data == null
                    ? const Icon(Icons.person, size: 18)
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              u?.name.isNotEmpty == true ? u!.name : peerId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
      loading: () => const Text('...'),
      error: (e, _) => Text(peerId),
    );
  }
}
