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
import '../../widgets/audio_recorder_widget.dart';

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
  bool _inputHasText = false;
  int _lastCount = 0;

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
      final isNear = (pos.maxScrollExtent - pos.pixels) <= 200;
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

  void _onTypingChanged(bool hasText) {
    if (_inputHasText != hasText) {
      setState(() => _inputHasText = hasText);
    }
  }

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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: _PeerTitle(peerId: widget.peerId)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: messages.when(
                data: (list) {
                  if (_ackSent) {
                    if (list.length > _lastCount && _nearBottom) {
                      ref.read(chatServiceProvider).markAllSeen(widget.chatId);
                    }
                    _lastCount = list.length;
                  }
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _maybeScrollToBottom(),
                  );
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final m = list[index];
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
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: InputField(
                    onSend: _sendText,
                    onSendMedia: _sendMedia,
                    onTypingChanged: _onTypingChanged,
                  ),
                ),
                if (!_inputHasText)
                  AudioRecorderWidget(onSendAudio: _sendMedia),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerTitle extends ConsumerWidget {
  final String peerId;
  const _PeerTitle({required this.peerId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userDocProvider(peerId));
    return user.when(
      data: (u) => Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundImage: (u?.profileImageUrl?.isNotEmpty == true)
                ? NetworkImage(u!.profileImageUrl!)
                : null,
            child: (u?.profileImageUrl?.isNotEmpty == true)
                ? null
                : const Icon(Icons.person, size: 18),
          ),
          const SizedBox(width: 8),
          Text(
            u?.name.isNotEmpty == true ? u!.name : peerId,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      loading: () => const Text('...'),
      error: (e, _) => Text(peerId),
    );
  }
}
