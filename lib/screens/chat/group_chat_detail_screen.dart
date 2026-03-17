import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/message_model.dart';
import '../../models/reply_target.dart';
import '../../providers/chat_providers.dart';
import '../../providers/user_providers.dart';
import '../../services/firestore_service.dart';
import '../group/group_settings_screen.dart';
import '../../widgets/group_message_bubble.dart';
import '../../widgets/input_field.dart';
import '../../widgets/reply_preview_bar.dart';
import '../../widgets/swipe_to_reply.dart';
import '../../widgets/message_interaction_overlay.dart';
import 'forward_select_screen.dart';

class GroupChatDetailScreen extends ConsumerStatefulWidget {
  static const routeName = '/group-chat-detail';
  final String chatId;

  const GroupChatDetailScreen({super.key, required this.chatId});

  @override
  ConsumerState<GroupChatDetailScreen> createState() =>
      _GroupChatDetailScreenState();
}

class _GroupChatDetailScreenState extends ConsumerState<GroupChatDetailScreen>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final ValueNotifier<ReplyTarget?> _replyTarget = ValueNotifier(null);
  final ValueNotifier<String?> _highlightId = ValueNotifier(null);
  final ValueNotifier<String?> _selectedMessageId = ValueNotifier(null);
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  final Map<String, ValueNotifier<Map<String, int>?>> _reactionOverrides =
      <String, ValueNotifier<Map<String, int>?>>{};
  final Map<String, String?> _myReactionByMessageId = <String, String?>{};
  bool _nearBottom = true;
  int _lastCount = 0;
  double _baseZoom = 1.0;
  static const double _minZoom = 1.0;
  static const double _maxZoom = 1.6;
  static const _groupWindow = Duration(minutes: 5);

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
  }) {
    if (pinned.isEmpty) return;
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

                      final senderId = m?.senderId;
                      final senderName = senderId == null
                          ? ''
                          : ref
                                .watch(userDocProvider(senderId))
                                .maybeWhen(
                                  data: (u) => (u?.name ?? '').trim(),
                                  orElse: () => '',
                                );

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

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF151515),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            onTap: () {
                              Navigator.pop(ctx);
                              if (mid.isNotEmpty) _scrollToMessage(mid);
                            },
                            title: Text(
                              (senderName.isNotEmpty)
                                  ? senderName
                                  : (senderId ?? ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFB5B5B5),
                                fontSize: 12,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  time,
                                  style: const TextStyle(
                                    color: Color(0xFF8A8A8A),
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Color(0xFF9A9A9A),
                                  ),
                                  onPressed: mid.isEmpty
                                      ? null
                                      : () async {
                                          final service = ref.read(
                                            chatServiceProvider,
                                          );
                                          await service.togglePinMessage(
                                            chatId: widget.chatId,
                                            messageId: mid,
                                          );
                                        },
                                ),
                              ],
                            ),
                          ),
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
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
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
    // Keyboard opened/closed. If you are near the bottom (latest), keep the
    // latest message visible.
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

  Future<void> _onMessageLongPress(
    BuildContext context,
    MessageModel m,
    bool isMe,
    bool isAdmin,
    bool isPinned,
  ) async {
    final key = _messageKeys[m.id];
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final rect = origin & box.size;

    _selectedMessageId.value = m.id;
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(chatServiceProvider);

    final canCopy = m.messageType == MessageType.text && !m.isDeletedForAll;
    final canEdit =
        isMe &&
        m.messageType == MessageType.text &&
        !m.isDeletedForAll &&
        !m.forwarded;
    final canUnsend = isMe && !m.isDeletedForAll;
    final canPin = (isAdmin || isMe) && !m.isDeletedForAll;

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
      if (canPin)
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

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!.uid;
    final messages = ref.watch(messagesProvider(widget.chatId));
    final hides = ref.watch(hidesProvider(widget.chatId));
    final fs = FirestoreService();
    final bubbleZoom = bubbleZoomStore[widget.chatId] ?? 1.0;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: fs.dmChats.doc(widget.chatId).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final title = (data?['name'] as String?)?.trim();
        final members = List<String>.from(
          (data?['members'] as List?) ?? const [],
        );

        final settings = Map<String, dynamic>.from(
          (data?['settings'] as Map?) ?? const {},
        );
        final perms = Map<String, dynamic>.from(
          (settings['permissions'] as Map?) ?? const {},
        );
        final membersCanSendMessages =
            (perms['membersCanSendMessages'] as bool?) ?? true;

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: fs.dmChats
              .doc(widget.chatId)
              .collection('members')
              .doc(me)
              .snapshots(),
          builder: (context, roleSnap) {
            final role = roleSnap.data?.data()?['role'] as String?;
            final isAdmin = role == 'owner' || role == 'admin';
            final canSend = membersCanSendMessages || isAdmin;

            Future<void> sendText(String text) async {
              if (!canSend) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Only admins can send messages right now'),
                  ),
                );
                return;
              }
              final reply = _replyTarget.value;
              await ref
                  .read(chatServiceProvider)
                  .sendGroupText(
                    chatId: widget.chatId,
                    memberIds: members,
                    text: text,
                    replyTo: reply?.toMap(),
                  );
              _replyTarget.value = null;
              _forceScrollToBottom();
            }

            Future<void> sendMedia(
              Uint8List bytes,
              String name,
              String contentType,
              MessageType type, {
              int? durationMs,
            }) async {
              if (!canSend) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Only admins can send messages right now'),
                  ),
                );
                return;
              }
              final reply = _replyTarget.value;
              await ref
                  .read(chatServiceProvider)
                  .sendGroupMedia(
                    chatId: widget.chatId,
                    memberIds: members,
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

            return Scaffold(
              backgroundColor: const Color(0xFF000000),
              resizeToAvoidBottomInset: false,
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: AppBar(
                  toolbarHeight: 52,
                  backgroundColor: const Color(0xFF000000),
                  elevation: 0,
                  centerTitle: false,
                  automaticallyImplyLeading: true,
                  iconTheme: const IconThemeData(
                    color: Color(0xFFA0A0A0),
                    size: 20,
                  ),
                  titleSpacing: 0,
                  leadingWidth: 44,
                  title: InkWell(
                    onTap: () => Navigator.pushNamed(
                      context,
                      GroupSettingsScreen.routeName,
                      arguments: {'chatId': widget.chatId},
                    ),
                    child: _GroupTitle(
                      name: (title != null && title.isNotEmpty)
                          ? title
                          : 'Group',
                      memberCount: members.length,
                      photoUrl: (data?['photoUrl'] as String?),
                    ),
                  ),
                  actions: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.search_rounded),
                      tooltip: 'Search',
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.call_outlined),
                      tooltip: 'Call',
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.more_vert_rounded),
                      tooltip: 'More',
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              body: AnimatedPadding(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _PinnedGroupIdentityHeader(
                          name: (title != null && title.isNotEmpty)
                              ? title
                              : 'Group',
                          description: (data?['description'] as String?),
                          chatId: widget.chatId,
                        ),
                      ),
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
                                final display = filtered.reversed.toList();
                                final messageById = <String, MessageModel>{
                                  for (final m in filtered) m.id: m,
                                };

                                final pinnedIds = pinned
                                    .map(
                                      (e) => (e['messageId'] as String?) ?? '',
                                    )
                                    .where((e) => e.isNotEmpty)
                                    .toList();
                                final pinnedSet = pinnedIds.toSet();

                                if (display.length > _lastCount &&
                                    _nearBottom) {
                                  WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => _maybeScrollToBottom(),
                                  );
                                }
                                _lastCount = display.length;

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
                                                      ? pinPreview(
                                                          pinnedIds.first,
                                                        )
                                                      : '${pinnedIds.length} pinned messages',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
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

                                return Column(
                                  children: [
                                    bar,
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onScaleStart: (details) {
                                          _baseZoom =
                                              bubbleZoomStore[widget.chatId] ??
                                              1.0;
                                        },
                                        onScaleUpdate: (details) {
                                          final s = details.scale;
                                          if (details.pointerCount >= 2 ||
                                              s != 1.0) {
                                            final scaled = (_baseZoom * s)
                                                .clamp(_minZoom, _maxZoom)
                                                .toDouble();
                                            final cur =
                                                bubbleZoomStore[widget
                                                    .chatId] ??
                                                1.0;
                                            if (scaled != cur) {
                                              bubbleZoomStore[widget.chatId] =
                                                  scaled;
                                              setState(() {});
                                            }
                                          }
                                        },
                                        child: ListView.builder(
                                          reverse: true,
                                          key: const PageStorageKey(
                                            'group_chat_messages',
                                          ),
                                          controller: _scrollController,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                          itemCount: display.length,
                                          itemBuilder: (context, index) {
                                            final m = display[index];
                                            final isMe = m.senderId == me;

                                            final older =
                                                index + 1 < display.length
                                                ? display[index + 1]
                                                : null;
                                            final isSameSenderAsOlder =
                                                older != null &&
                                                older.senderId == m.senderId;
                                            final isWithinWindow = older != null
                                                ? (m.timestamp
                                                          .toDate()
                                                          .difference(
                                                            older.timestamp
                                                                .toDate(),
                                                          )
                                                          .abs() <=
                                                      _groupWindow)
                                                : false;
                                            final showIdentity =
                                                !isMe &&
                                                (!isSameSenderAsOlder ||
                                                    !isWithinWindow);

                                            final newer = index > 0
                                                ? display[index - 1]
                                                : null;
                                            final isSameSenderAsNewer =
                                                newer != null &&
                                                newer.senderId == m.senderId;
                                            final bottomSpacing =
                                                !isSameSenderAsNewer
                                                ? 10.0
                                                : 6.0;

                                            return Align(
                                              alignment: isMe
                                                  ? Alignment.centerRight
                                                  : Alignment.centerLeft,
                                              child: ValueListenableBuilder<String?>(
                                                valueListenable: _highlightId,
                                                builder: (context, hid, _) {
                                                  final highlighted =
                                                      hid == m.id;
                                                  final key = _messageKeys
                                                      .putIfAbsent(
                                                        m.id,
                                                        () => GlobalKey(),
                                                      );
                                                  return ValueListenableBuilder<
                                                    String?
                                                  >(
                                                    valueListenable:
                                                        _selectedMessageId,
                                                    builder: (context, sid, __) {
                                                      final selected =
                                                          sid == m.id;
                                                      final bg = highlighted
                                                          ? const Color(
                                                              0xFF1A1A1A,
                                                            )
                                                          : (selected
                                                                ? const Color(
                                                                    0xFF1A1A1A,
                                                                  ).withOpacity(
                                                                    0.12,
                                                                  )
                                                                : Colors
                                                                      .transparent);
                                                      final pad = highlighted
                                                          ? const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 4,
                                                            )
                                                          : EdgeInsets.zero;
                                                      return AnimatedContainer(
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 120,
                                                            ),
                                                        curve: Curves.easeOut,
                                                        key: key,
                                                        decoration: BoxDecoration(
                                                          color: bg,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                14,
                                                              ),
                                                        ),
                                                        padding: pad,
                                                        child: SwipeToReply(
                                                          enabled: !m
                                                              .isDeletedForAll,
                                                          onReply: () =>
                                                              _replyTarget
                                                                      .value =
                                                                  _toReplyTarget(
                                                                    m,
                                                                  ),
                                                          child: GestureDetector(
                                                            onLongPress: () =>
                                                                _onMessageLongPress(
                                                                  context,
                                                                  m,
                                                                  isMe,
                                                                  isAdmin,
                                                                  pinnedSet
                                                                      .contains(
                                                                        m.id,
                                                                      ),
                                                                ),
                                                            child: ValueListenableBuilder<Map<String, int>?>(
                                                              valueListenable:
                                                                  _reactionOverrideNotifier(
                                                                    m.id,
                                                                  ),
                                                              builder:
                                                                  (
                                                                    context,
                                                                    override,
                                                                    ___,
                                                                  ) {
                                                                    return GroupMessageBubble(
                                                                      key: ValueKey(
                                                                        m.id,
                                                                      ),
                                                                      message:
                                                                          m,
                                                                      isMe:
                                                                          isMe,
                                                                      showIdentity:
                                                                          showIdentity,
                                                                      zoom:
                                                                          bubbleZoom,
                                                                      bottomSpacing:
                                                                          bottomSpacing,
                                                                      groupChatId:
                                                                          widget
                                                                              .chatId,
                                                                      reactionsOverride:
                                                                          override,
                                                                      isPinned: pinnedSet
                                                                          .contains(
                                                                            m.id,
                                                                          ),
                                                                      onOpenThread:
                                                                          (
                                                                            messageId,
                                                                          ) {
                                                                            Navigator.of(
                                                                              context,
                                                                            ).push(
                                                                              MaterialPageRoute(
                                                                                builder:
                                                                                    (
                                                                                      _,
                                                                                    ) => _ThreadScreen(
                                                                                      chatId: widget.chatId,
                                                                                      messageId: messageId,
                                                                                    ),
                                                                              ),
                                                                            );
                                                                          },
                                                                      onReplyCardTap:
                                                                          _scrollToMessage,
                                                                    );
                                                                  },
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                              loading: () => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              error: (e, _) => Center(
                                child: Text(
                                  'Error: $e',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
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
                                  isGroup: true,
                                  myUid: me,
                                ),
                                const SizedBox(height: 8),
                              ],
                              Container(
                                height: 56,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF0F0F0F),
                                  border: Border(
                                    top: BorderSide(
                                      color: Color(0xFF1A1A1A),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: InputField(
                                  onSend: sendText,
                                  onSendMedia: sendMedia,
                                  onTypingChanged: (_) {},
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
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

class _GroupTitle extends StatelessWidget {
  final String name;
  final int memberCount;
  final String? photoUrl;
  const _GroupTitle({
    required this.name,
    required this.memberCount,
    required this.photoUrl,
  });

  String _initials(String t) {
    final parts = t.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final list = parts.toList();
    if (list.isEmpty) return 'G';
    final a = list.first.characters.isNotEmpty
        ? list.first.characters.first
        : 'G';
    final b = list.length > 1 && list[1].characters.isNotEmpty
        ? list[1].characters.first
        : '';
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = name.trim().isEmpty ? 'Group' : name.trim();
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF141414),
          ),
          alignment: Alignment.center,
          child: Text(
            _initials(displayName),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$memberCount members',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8A8A8A),
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PinnedGroupIdentityHeader extends StatelessWidget {
  final String name;
  final String? description;
  final String chatId;
  const _PinnedGroupIdentityHeader({
    required this.name,
    required this.description,
    required this.chatId,
  });

  @override
  Widget build(BuildContext context) {
    final title = (description ?? '').trim().isNotEmpty
        ? (description ?? '').trim()
        : '${name.trim()} Group';
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          SizedBox(height: 6),
          const Text(
            'Admins: —',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF8A8A8A),
              height: 1.2,
            ),
          ),
          SizedBox(height: 2),
          const Text(
            '0 pinned messages',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF8A8A8A),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadScreen extends StatelessWidget {
  final String chatId;
  final String messageId;
  const _ThreadScreen({required this.chatId, required this.messageId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        title: const Text(
          'Thread',
          style: TextStyle(color: Colors.white, fontSize: 15),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFA0A0A0), size: 20),
      ),
      body: const Center(
        child: Text(
          'Thread view (scaffold)',
          style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 12),
        ),
      ),
    );
  }
}
