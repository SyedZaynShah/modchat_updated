import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/message_model.dart';
import '../../models/reply_target.dart';
import '../../providers/chat_providers.dart';
import '../../providers/user_providers.dart';
import '../../services/firestore_service.dart';
import '../../widgets/input_field.dart';
import '../../widgets/file_preview_widget.dart';
import '../../widgets/reply_preview_bar.dart';
import '../../widgets/swipe_to_reply.dart';
import '../../widgets/glass_dropdown.dart';
import '../../widgets/message_interaction_overlay.dart';
import '../../services/supabase_service.dart';
import 'chat_contact_info_screen.dart';
import 'forward_select_screen.dart';

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

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<ReplyTarget?> _replyTarget = ValueNotifier(null);
  final ValueNotifier<String?> _highlightId = ValueNotifier(null);
  final ValueNotifier<String?> _selectedMessageId = ValueNotifier(null);
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  final Map<String, ValueNotifier<Map<String, int>?>> _reactionOverrides =
      <String, ValueNotifier<Map<String, int>?>>{};
  final Map<String, String?> _myReactionByMessageId = <String, String?>{};
  bool _nearBottom = true;
  int _lastCount = 0;
  bool _ackSent = false;

  List<Map<String, dynamic>> _normalizePinned(dynamic raw) {
    final list = (raw is List) ? raw : const [];
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is String) {
        out.add({
          'messageId': e,
          'pinnedBy': '',
          'pinnedAt': Timestamp.fromMillisecondsSinceEpoch(0),
        });
      } else if (e is Map) {
        final m = e.cast<String, dynamic>();
        final id = (m['messageId'] as String?) ?? '';
        if (id.isEmpty) continue;
        out.add({
          'messageId': id,
          'pinnedBy': (m['pinnedBy'] as String?) ?? '',
          'pinnedAt': m['pinnedAt'] ?? Timestamp.fromMillisecondsSinceEpoch(0),
        });
      }
    }
    return out;
  }

  void _openPinnedSheet({
    required List<Map<String, dynamic>> pinned,
    required Map<String, MessageModel> messageById,
    required String peerName,
  }) {
    if (pinned.isEmpty) return;
    final me = FirebaseAuth.instance.currentUser!.uid;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.8,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Pinned Messages',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: pinned.length,
                    itemBuilder: (ctx, i) {
                      final p = pinned[i];
                      final mid = (p['messageId'] as String?) ?? '';
                      final m = mid.isEmpty ? null : messageById[mid];
                      final ts = p['pinnedAt'];
                      final dt = ts is Timestamp
                          ? ts.toDate()
                          : DateTime.fromMillisecondsSinceEpoch(0);
                      final hh = dt.hour.toString().padLeft(2, '0');
                      final mm = dt.minute.toString().padLeft(2, '0');
                      final time = '$hh:$mm';

                      final senderName = (m?.senderId == null)
                          ? ''
                          : (m!.senderId == me
                                ? 'You'
                                : (peerName.isNotEmpty ? peerName : 'Contact'));

                      final preview = m == null
                          ? 'Message unavailable'
                          : (m.messageType == MessageType.text
                                ? ((m.text ?? '').trim())
                                : (m.messageType == MessageType.image
                                      ? '📷 Photo'
                                      : (m.messageType == MessageType.video
                                            ? '🎥 Video'
                                            : (m.messageType ==
                                                      MessageType.audio
                                                  ? '🎧 Voice message'
                                                  : '📎 Document'))));

                      return ListTile(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          if (mid.isNotEmpty) _scrollToMessage(mid);
                        },
                        leading: const Icon(
                          Icons.push_pin,
                          color: Color(0xFFC74B6C),
                          size: 18,
                        ),
                        title: Text(
                          senderName.isNotEmpty ? senderName : 'Pinned',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            preview.isNotEmpty ? preview : 'Pinned message',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFBEBEBE),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              time,
                              style: const TextStyle(
                                color: Color(0xFF7A7A7A),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Unpin',
                              onPressed: mid.isEmpty
                                  ? null
                                  : () async {
                                      await ref
                                          .read(chatServiceProvider)
                                          .togglePinMessage(
                                            chatId: widget.chatId,
                                            messageId: mid,
                                          );
                                    },
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFF8A8A8A),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Delay to ensure providers are ready
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(chatServiceProvider).acknowledgeDelivered(widget.chatId);
      if (!mounted) return;
      setState(() => _ackSent = true);
    });
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      // With reverse:true, offset 0 is the bottom (latest message).
      final isNear = pos.pixels <= 30;
      if (isNear != _nearBottom) {
        setState(() => _nearBottom = isNear);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _replyTarget.dispose();
    _highlightId.dispose();
    _selectedMessageId.dispose();
    for (final n in _reactionOverrides.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Keyboard opened/closed. If you are near the bottom, keep the latest
    // message visible (WhatsApp-like behavior).
    if (_nearBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _forceScrollToBottom();
      });
    }
  }

  ValueNotifier<Map<String, int>?> _reactionOverrideNotifier(String messageId) {
    return _reactionOverrides.putIfAbsent(
      messageId,
      () => ValueNotifier<Map<String, int>?>(null),
    );
  }

  Map<String, int> _cloneCounts(Map<String, int>? src) {
    return Map<String, int>.from(src ?? const <String, int>{});
  }

  Future<void> _reactOptimistic(MessageModel m, String emoji) async {
    if (m.isDeletedForAll) return;

    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(chatServiceProvider);
    final id = m.id;

    final notifier = _reactionOverrideNotifier(id);
    final prevCounts = _cloneCounts(notifier.value ?? m.reactions);
    final prevMy = _myReactionByMessageId[id];

    final nextCounts = _cloneCounts(prevCounts);
    if (prevMy == emoji) {
      final cur = (nextCounts[emoji] ?? 0) - 1;
      if (cur <= 0) {
        nextCounts.remove(emoji);
      } else {
        nextCounts[emoji] = cur;
      }
      _myReactionByMessageId[id] = null;
    } else {
      if (prevMy != null) {
        final cur = (nextCounts[prevMy] ?? 0) - 1;
        if (cur <= 0) {
          nextCounts.remove(prevMy);
        } else {
          nextCounts[prevMy] = cur;
        }
      }
      nextCounts[emoji] = (nextCounts[emoji] ?? 0) + 1;
      _myReactionByMessageId[id] = emoji;
    }

    notifier.value = nextCounts;

    try {
      await service.toggleReaction(
        chatId: widget.chatId,
        messageId: id,
        emoji: emoji,
      );
    } catch (e) {
      notifier.value = prevCounts;
      _myReactionByMessageId[id] = prevMy;
      messenger.showSnackBar(SnackBar(content: Text('Reaction failed: $e')));
    }
  }

  ReplyTarget _toReplyTarget(MessageModel m) {
    String preview;
    final t = m.messageType;
    switch (t) {
      case MessageType.text:
        preview = (m.text ?? '').trim();
        break;
      case MessageType.image:
        preview = '📷 Photo';
        break;
      case MessageType.video:
        preview = '🎥 Video';
        break;
      case MessageType.file:
        preview = '📎 Document';
        break;
      case MessageType.audio:
        preview = '🎧 Voice message';
        break;
    }
    if (preview.isEmpty) preview = 'Message';
    return ReplyTarget(
      messageId: m.id,
      senderId: m.senderId,
      previewText: preview,
      messageType: t.name,
    );
  }

  void _scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx == null) return;

    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.2,
    );

    _highlightId.value = messageId;
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      if (_highlightId.value == messageId) _highlightId.value = null;
    });
  }

  Future<void> _sendText(String text) async {
    final reply = _replyTarget.value;
    await ref
        .read(chatServiceProvider)
        .sendText(
          chatId: widget.chatId,
          peerId: widget.peerId,
          text: text,
          replyTo: reply?.toMap(),
        );
    _replyTarget.value = null;
    _forceScrollToBottom();
  }

  Future<void> _sendMedia(
    Uint8List bytes,
    String name,
    String contentType,
    MessageType type, {
    int? durationMs,
  }) async {
    final reply = _replyTarget.value;
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
          replyTo: reply?.toMap(),
        );
    _replyTarget.value = null;
    _forceScrollToBottom();
  }

  void _maybeScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final isNearBottom = pos.pixels <= 80;
      if (!isNearBottom) return;
      _scrollController.jumpTo(0);
    });
  }

  void _forceScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  void _onTypingChanged(bool hasText) {}

  Future<void> _onMessageLongPress(
    BuildContext context,
    MessageModel m,
    bool isMe,
  ) async {
    final key = _messageKeys[m.id];
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final rect = origin & box.size;

    _selectedMessageId.value = m.id;
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(chatServiceProvider);

    bool isPinned = false;
    try {
      final chatSnap = await FirestoreService().dmChats
          .doc(widget.chatId)
          .get();
      final pinned = _normalizePinned(chatSnap.data()?['pinnedMessages']);
      isPinned = pinned.any((p) => p['messageId'] == m.id);
    } catch (_) {}

    final canCopy = m.messageType == MessageType.text && !m.isDeletedForAll;
    final canEdit =
        isMe &&
        m.messageType == MessageType.text &&
        !m.isDeletedForAll &&
        !m.forwarded;
    final canUnsend = isMe && !m.isDeletedForAll;

    final actions = <MessageActionItem>[
      MessageActionItem(
        icon: Icons.reply_rounded,
        label: 'Reply',
        onTap: () {
          _replyTarget.value = _toReplyTarget(m);
        },
      ),
      MessageActionItem(
        icon: Icons.forward_rounded,
        label: 'Forward',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ForwardSelectScreen(source: m)),
          );
        },
      ),
      if (canCopy)
        MessageActionItem(
          icon: Icons.copy_rounded,
          label: 'Copy',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: (m.text ?? '').trim()));
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Message copied'),
                duration: Duration(milliseconds: 1200),
              ),
            );
          },
        ),
      if (canEdit)
        MessageActionItem(
          icon: Icons.edit_rounded,
          label: 'Edit',
          onTap: () async {
            final controller = TextEditingController(text: m.text ?? '');
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
              try {
                await service.editMessage(
                  chatId: widget.chatId,
                  messageId: m.id,
                  newText: newText,
                );
                messenger.showSnackBar(
                  const SnackBar(content: Text('Message edited')),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Edit failed: $e')),
                );
              }
            }
          },
        ),
      if (canUnsend)
        MessageActionItem(
          icon: Icons.delete_forever,
          label: 'Unsend',
          isDestructive: true,
          onTap: () async {
            try {
              await service.deleteForEveryone(
                chatId: widget.chatId,
                messageId: m.id,
              );
              messenger.showSnackBar(
                const SnackBar(content: Text('Message deleted')),
              );
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(content: Text('Unsend failed: $e')),
              );
            }
          },
        ),
      MessageActionItem(
        icon: Icons.delete_outline,
        label: 'Delete for Me',
        isDestructive: true,
        onTap: () async {
          try {
            await service.deleteForMe(chatId: widget.chatId, messageId: m.id);
            messenger.showSnackBar(
              const SnackBar(content: Text('Removed for you')),
            );
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Delete failed: $e')),
            );
          }
        },
      ),
      MessageActionItem(
        icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
        label: isPinned ? 'Unpin Message' : 'Pin Message',
        onTap: () async {
          try {
            await service.togglePinMessage(
              chatId: widget.chatId,
              messageId: m.id,
            );
            messenger.showSnackBar(
              const SnackBar(content: Text('Pin updated')),
            );
          } catch (e) {
            messenger.showSnackBar(SnackBar(content: Text('Pin failed: $e')));
          }
        },
      ),
    ];

    await MessageInteractionOverlay.show(
      context: context,
      messageRect: rect,
      showReactions: !m.isDeletedForAll,
      onReact: (emoji) => _reactOptimistic(m, emoji),
      actions: actions,
      onDismiss: () {
        if (_selectedMessageId.value == m.id) _selectedMessageId.value = null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!.uid;
    final messages = ref.watch(messagesProvider(widget.chatId));
    final hides = ref.watch(hidesProvider(widget.chatId));
    final peerName = ref
        .watch(userDocProvider(widget.peerId))
        .maybeWhen(data: (u) => (u?.name ?? '').trim(), orElse: () => '');

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(0.5),
            child: ColoredBox(
              color: Color(0xFF1A1A1A),
              child: SizedBox(height: 0.5),
            ),
          ),
          title: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _HeaderIcon(
                    icon: Icons.arrow_back_ios_new,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PeerTitle(
                      peerId: widget.peerId,
                      chatId: widget.chatId,
                    ),
                  ),
                  _HeaderIcon(icon: Icons.videocam_outlined, onTap: () {}),
                  const SizedBox(width: 14),
                  _HeaderIcon(icon: Icons.call_outlined, onTap: () {}),
                  const SizedBox(width: 14),
                  GlassDropdown(
                    tooltip: 'More',
                    items: const [
                      GlassDropdownItem(
                        value: 'contact',
                        label: 'Contact info',
                        icon: Icons.contact_page_outlined,
                      ),
                      GlassDropdownItem(
                        value: 'report',
                        label: 'Report',
                        icon: Icons.flag_outlined,
                        isDestructive: true,
                      ),
                      GlassDropdownItem(
                        value: 'block',
                        label: 'Block',
                        icon: Icons.block,
                        isDestructive: true,
                      ),
                    ],
                    onSelected: (v) {
                      if (v == 'contact') {
                        Navigator.pushNamed(
                          context,
                          ChatContactInfoScreen.routeName,
                          arguments: {
                            'peerId': widget.peerId,
                            'chatId': widget.chatId,
                          },
                        );
                      }
                    },
                    child: const Icon(
                      Icons.more_vert,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.02,
              child: Image.asset(
                'lib/assets/background.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          AnimatedPadding(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirestoreService().dmChats
                          .doc(widget.chatId)
                          .snapshots(),
                      builder: (context, chatSnap) {
                        final pinned = _normalizePinned(
                          chatSnap.data?.data()?['pinnedMessages'],
                        );
                        return messages.when(
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
                                _maybeScrollToBottom();
                              }
                              _lastCount = filtered.length;
                            }

                            if (filtered.isEmpty) {
                              return const _EmptyChatState();
                            }

                            final pinnedIds = pinned
                                .map((e) => (e['messageId'] as String?) ?? '')
                                .where((e) => e.isNotEmpty)
                                .toList();
                            final pinnedSet = pinnedIds.toSet();

                            final messageById = <String, MessageModel>{
                              for (final m in filtered) m.id: m,
                            };

                            String pinPreview(String mid) {
                              final m = messageById[mid];
                              if (m == null) return 'Pinned message';
                              if (m.messageType == MessageType.text) {
                                final t = (m.text ?? '').trim();
                                return t.isNotEmpty ? t : 'Pinned message';
                              }
                              switch (m.messageType) {
                                case MessageType.image:
                                  return '📷 Photo';
                                case MessageType.video:
                                  return '🎥 Video';
                                case MessageType.audio:
                                  return '🎧 Voice message';
                                case MessageType.file:
                                  return '📎 Document';
                                case MessageType.text:
                                  return 'Pinned message';
                              }
                            }

                            final bar = pinnedIds.isEmpty
                                ? const SizedBox.shrink()
                                : InkWell(
                                    onTap: () => _openPinnedSheet(
                                      pinned: pinned,
                                      messageById: messageById,
                                      peerName: peerName,
                                    ),
                                    child: Container(
                                      height: 48,
                                      width: double.infinity,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF121212),
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Color(0xFF1A1A1A),
                                            width: 0.5,
                                          ),
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.push_pin,
                                            size: 16,
                                            color: Color(0xFFC74B6C),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              pinnedIds.length == 1
                                                  ? pinPreview(pinnedIds.first)
                                                  : '${pinnedIds.length} pinned messages',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFFEAEAEA),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: Color(0xFF8A8A8A),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );

                            final blocks = _groupIntoBlocks(filtered);

                            // reverse:true => offset 0 is bottom; feed newest block
                            // first so the list opens at the latest message without
                            // any post-layout scrolling.
                            final displayBlocks = blocks.reversed.toList();

                            return Column(
                              children: [
                                bar,
                                Expanded(
                                  child: ListView.builder(
                                    reverse: true,
                                    key: const PageStorageKey(
                                      'dm_chat_messages',
                                    ),
                                    controller: _scrollController,
                                    physics: const BouncingScrollPhysics(),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    itemCount: displayBlocks.length,
                                    itemBuilder: (context, index) {
                                      final b = displayBlocks[index];
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 14,
                                        ),
                                        child: _ConversationBlockView(
                                          block: b,
                                          myUid: me,
                                          isPinned: (id) =>
                                              pinnedSet.contains(id),
                                          onLongPress: (m) =>
                                              _onMessageLongPress(
                                                context,
                                                m,
                                                m.senderId == me,
                                              ),
                                          onReply: (m) => _replyTarget.value =
                                              _toReplyTarget(m),
                                          messageKeys: _messageKeys,
                                          highlightId: _highlightId,
                                          selectedId: _selectedMessageId,
                                          reactionOverrideNotifier:
                                              _reactionOverrideNotifier,
                                          onReplyCardTap: _scrollToMessage,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                          loading: () => const _ChatSkeleton(),
                          error: (e, _) => Center(child: Text('Error: $e')),
                        );
                      },
                    ),
                  ),
                  ValueListenableBuilder<ReplyTarget?>(
                    valueListenable: _replyTarget,
                    builder: (context, rt, _) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (rt != null) ...[
                            const SizedBox(height: 8),
                            ReplyPreviewBar(
                              target: rt,
                              onCancel: () => _replyTarget.value = null,
                              isGroup: false,
                              myUid: me,
                              dmPeerName: peerName.isEmpty ? null : peerName,
                            ),
                            const SizedBox(height: 8),
                          ],
                          InputField(
                            onSend: _sendText,
                            onSendMedia: _sendMedia,
                            onTypingChanged: _onTypingChanged,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationBlock {
  final String senderId;
  final DateTime start;
  final List<MessageModel> messages;
  const _ConversationBlock({
    required this.senderId,
    required this.start,
    required this.messages,
  });
}

List<_ConversationBlock> _groupIntoBlocks(List<MessageModel> list) {
  const window = Duration(minutes: 3);
  final out = <_ConversationBlock>[];
  for (final m in list) {
    final t = m.timestamp.toDate();
    if (out.isEmpty) {
      out.add(
        _ConversationBlock(senderId: m.senderId, start: t, messages: [m]),
      );
      continue;
    }
    final last = out.last;
    final lastMsgTime = last.messages.last.timestamp.toDate();
    final sameSender = last.senderId == m.senderId;
    final closeInTime = t.difference(lastMsgTime).abs() <= window;
    if (sameSender && closeInTime) {
      last.messages.add(m);
    } else {
      out.add(
        _ConversationBlock(senderId: m.senderId, start: t, messages: [m]),
      );
    }
  }
  return out;
}

class _ConversationBlockView extends ConsumerWidget {
  final _ConversationBlock block;
  final String myUid;
  final bool Function(String messageId) isPinned;
  final ValueChanged<MessageModel> onLongPress;
  final ValueChanged<MessageModel> onReply;
  final Map<String, GlobalKey> messageKeys;
  final ValueListenable<String?> highlightId;
  final ValueListenable<String?> selectedId;
  final ValueNotifier<Map<String, int>?> Function(String messageId)
  reactionOverrideNotifier;
  final ValueChanged<String> onReplyCardTap;
  const _ConversationBlockView({
    required this.block,
    required this.myUid,
    required this.isPinned,
    required this.onLongPress,
    required this.onReply,
    required this.messageKeys,
    required this.highlightId,
    required this.selectedId,
    required this.reactionOverrideNotifier,
    required this.onReplyCardTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMe = block.senderId == myUid;
    final timeLabel = _formatBlockTime(block.start);

    final header = isMe
        ? Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'You • $timeLabel',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF9A9A9A),
                ),
              ),
            ],
          )
        : _SenderHeader(senderId: block.senderId, timeLabel: timeLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 8),
        for (int i = 0; i < block.messages.length; i++) ...[
          _BlockMessageView(
            message: block.messages[i],
            isMe: isMe,
            isPinned: isPinned(block.messages[i].id),
            onLongPress: () => onLongPress(block.messages[i]),
            onReply: () => onReply(block.messages[i]),
            messageKey: messageKeys.putIfAbsent(
              block.messages[i].id,
              () => GlobalKey(),
            ),
            highlightId: highlightId,
            selectedId: selectedId,
            reactionsOverride: reactionOverrideNotifier(block.messages[i].id),
            onReplyCardTap: onReplyCardTap,
          ),
          if (i != block.messages.length - 1) const SizedBox(height: 4),
        ],
      ],
    );
  }

  String _formatBlockTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _SenderHeader extends ConsumerWidget {
  final String senderId;
  final String timeLabel;
  const _SenderHeader({required this.senderId, required this.timeLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userDocProvider(senderId));
    return user.when(
      data: (u) {
        final name = (u?.name ?? '').trim().isNotEmpty ? u!.name : senderId;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _OnlineRingAvatar(url: u?.profileImageUrl, isOnline: true),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const TextSpan(
                      text: ' • ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF9A9A9A),
                      ),
                    ),
                    TextSpan(
                      text: timeLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF9A9A9A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
      loading: () => Row(
        children: const [
          CircleAvatar(radius: 19, backgroundColor: Color(0xFF151515)),
          SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFF151515),
                  borderRadius: BorderRadius.all(Radius.circular(99)),
                ),
              ),
            ),
          ),
        ],
      ),
      error: (_, __) => Row(
        children: [
          const CircleAvatar(radius: 19, backgroundColor: Color(0xFF1A1A1A)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$senderId • $timeLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF9A9A9A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlineRingAvatar extends StatelessWidget {
  final String? url;
  final bool isOnline;
  const _OnlineRingAvatar({required this.url, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final ring = isOnline
        ? const BorderSide(color: Color(0xFFC74B6C), width: 2)
        : BorderSide.none;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.fromBorderSide(ring),
      ),
      padding: const EdgeInsets.all(2),
      child: CircleAvatar(
        radius: 17,
        backgroundColor: const Color(0xFF1A1A1A),
        backgroundImage: (url != null && url!.isNotEmpty)
            ? NetworkImage(url!)
            : null,
        child: (url == null || url!.isEmpty)
            ? const Icon(Icons.person, size: 18, color: Colors.white54)
            : null,
      ),
    );
  }
}

class _BlockMessageView extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final bool isPinned;
  final VoidCallback onLongPress;
  final VoidCallback onReply;
  final GlobalKey messageKey;
  final ValueListenable<String?> highlightId;
  final ValueListenable<String?> selectedId;
  final ValueListenable<Map<String, int>?> reactionsOverride;
  final ValueChanged<String> onReplyCardTap;
  const _BlockMessageView({
    required this.message,
    required this.isMe,
    required this.isPinned,
    required this.onLongPress,
    required this.onReply,
    required this.messageKey,
    required this.highlightId,
    required this.selectedId,
    required this.reactionsOverride,
    required this.onReplyCardTap,
  });

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.72;

    final pinTag = isPinned
        ? const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Icon(
              Icons.push_pin_rounded,
              size: 12,
              color: Color(0xFFBEBEBE),
            ),
          )
        : const SizedBox.shrink();

    final forwardedTag = (message.forwarded)
        ? const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'Forwarded',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
                height: 1.1,
              ),
            ),
          )
        : const SizedBox.shrink();

    final isMedia =
        message.messageType == MessageType.image ||
        message.messageType == MessageType.video;

    Widget content;
    if (message.isDeletedForAll) {
      content = const Text(
        'This message was deleted',
        style: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: Color(0xFF9A9A9A),
          fontStyle: FontStyle.italic,
        ),
      );
    } else if (message.messageType == MessageType.text) {
      final txt = (message.text ?? '').trim();
      content = Text(
        txt,
        style: const TextStyle(fontSize: 14, height: 1.35, color: Colors.white),
      );
    } else {
      content = FilePreviewWidget(message: message, isMe: isMe);
    }

    final bubbleAlign = isMe ? Alignment.centerRight : Alignment.centerLeft;

    Widget bubble;
    if (isMedia && !message.isDeletedForAll) {
      bubble = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            forwardedTag,
            ClipRRect(borderRadius: BorderRadius.circular(14), child: content),
          ],
        ),
      );
    } else {
      final bg = isMe ? const Color(0xFF7A1F3D) : const Color(0xFF0F0F0F);
      final border = !isMe
          ? Border.all(color: const Color(0xFF1A1A1A), width: 1)
          : null;
      bubble = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: border,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!message.isDeletedForAll) forwardedTag,
              content,
              if (!message.isDeletedForAll) ...[
                const SizedBox(height: 6),
                _MessageMetaRow(message: message, isMe: isMe),
              ],
            ],
          ),
        ),
      );
    }

    final core = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (!message.isDeletedForAll) pinTag,
        if (message.replyToMessageId != null) ...[
          Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              child: _InlineReplyCard(
                senderId: message.replyToSenderId,
                previewText: message.replyToText,
                onTap: () => onReplyCardTap(message.replyToMessageId!),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        bubble,
      ],
    );

    return ValueListenableBuilder<String?>(
      valueListenable: highlightId,
      builder: (context, hid, _) {
        final highlighted = hid == message.id;
        return ValueListenableBuilder<String?>(
          valueListenable: selectedId,
          builder: (context, sid, __) {
            final selected = sid == message.id;
            final bg = highlighted
                ? const Color(0xFF1A1A1A)
                : (selected
                      ? const Color(0xFF1A1A1A).withOpacity(0.12)
                      : Colors.transparent);
            final pad = highlighted
                ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4)
                : EdgeInsets.zero;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              key: messageKey,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: pad,
              child: Align(
                alignment: bubbleAlign,
                child: SwipeToReply(
                  enabled: !message.isDeletedForAll,
                  onReply: onReply,
                  child: GestureDetector(
                    onLongPress: onLongPress,
                    child: ValueListenableBuilder<Map<String, int>?>(
                      valueListenable: reactionsOverride,
                      builder: (context, override, ____) {
                        final reactions = override ?? message.reactions;
                        final hasReactions = (reactions ?? const {}).isNotEmpty;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            core,
                            if (hasReactions)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: _ReactionsRow(
                                  reactions: reactions ?? const {},
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ReactionsRow extends StatelessWidget {
  final Map<String, int> reactions;
  const _ReactionsRow({required this.reactions});

  @override
  Widget build(BuildContext context) {
    final entries = reactions.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: entries
          .take(4)
          .map(
            (e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '${e.key} ${e.value}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _InlineReplyCard extends ConsumerWidget {
  final String? senderId;
  final String? previewText;
  final VoidCallback onTap;
  const _InlineReplyCard({
    required this.senderId,
    required this.previewText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sid = (senderId ?? '').trim();
    final preview = (previewText ?? '').trim();
    final user = sid.isEmpty ? null : ref.watch(userDocProvider(sid));

    final nameWidget = user == null
        ? const Text(
            'Reply',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFC74B6C),
              height: 1.1,
            ),
          )
        : user.when(
            data: (u) {
              final n = (u?.name ?? '').trim();
              return Text(
                n.isNotEmpty ? n : sid,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFC74B6C),
                  height: 1.1,
                ),
              );
            },
            loading: () => const SizedBox(height: 12),
            error: (_, __) => const SizedBox(height: 12),
          );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF101010),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 2,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFC74B6C),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  nameWidget,
                  const SizedBox(height: 2),
                  Text(
                    preview.isEmpty ? 'Message unavailable' : preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 11,
                      color: preview.isEmpty
                          ? const Color(0xFF888888)
                          : const Color(0xFFB5B5B5),
                      fontStyle: preview.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageMetaRow extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  const _MessageMetaRow({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final t = message.timestamp.toDate();
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    const tc = Color(0xFF9A9A9A);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$h:$m', style: const TextStyle(fontSize: 10, color: tc)),
        if (isMe) ...[
          const SizedBox(width: 6),
          Icon(_tickIcon(message), size: 11, color: _tickColor(message)),
        ],
      ],
    );
  }

  static IconData _tickIcon(MessageModel m) {
    if (m.hasPendingWrites) return Icons.watch_later_outlined;
    switch (m.status) {
      case 1:
        return Icons.done_rounded;
      case 2:
        return Icons.done_all_rounded;
      case 3:
        return Icons.done_all_rounded;
      default:
        return Icons.watch_later_outlined;
    }
  }

  static Color _tickColor(MessageModel m) {
    if (m.hasPendingWrites) return const Color(0xFF9A9A9A);
    if (m.status == 3) return const Color(0xFFC74B6C);
    return const Color(0xFF9A9A9A);
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
            _PeerAvatar(url: u?.profileImageUrl),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    u?.name.isNotEmpty == true ? u!.name : peerId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    'online', // Status placeholder
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      color: const Color(0xFF8A8A8A),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (e, _) =>
          Text(peerId, style: const TextStyle(color: Colors.white)),
    );
  }
}

class _PeerAvatar extends StatelessWidget {
  final String? url;
  const _PeerAvatar({this.url});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ImageProvider?>(
      future: _resolveAvatar(),
      builder: (context, snap) {
        final img = snap.data;
        return CircleAvatar(
          radius: 19,
          backgroundColor: const Color(0xFF1A1A1A),
          backgroundImage: img,
          child: img == null
              ? const Icon(Icons.person, size: 20, color: Colors.white54)
              : null,
        );
      },
    );
  }

  Future<ImageProvider?> _resolveAvatar() async {
    if (url == null || url!.isEmpty) return null;
    try {
      if (url!.startsWith('sb://')) {
        final s = url!.substring(5);
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
      return NetworkImage(url!);
    } catch (_) {
      return null;
    }
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 6,
      itemBuilder: (context, index) {
        final isMe = index % 2 == 0;
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            width: MediaQuery.of(context).size.width * 0.4,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF151515),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: Color(0xFF1A1A1A),
          ),
          const SizedBox(height: 16),
          const Text(
            'Start the conversation',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Send your first message.',
            style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 13),
          ),
        ],
      ),
    );
  }
}
