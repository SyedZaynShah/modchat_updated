import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
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
import '../../widgets/chat_typing_indicator.dart';
import '../../services/typing_controller.dart';
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
  final ValueNotifier<int> _slowRemainingSec = ValueNotifier<int>(0);
  DateTime? _slowLastSentAtOverride;
  bool? _lastSlowEnabled;
  int? _lastSlowDuration;
  int? _lastSlowLastSentAtMs;
  Timer? _slowTick;
  final TypingController _typingController = TypingController();
  final ValueNotifier<List<Map<String, dynamic>>?> _pinnedOverride =
      ValueNotifier<List<Map<String, dynamic>>?>(null);
  List<Map<String, dynamic>> _lastPinnedFromStream = const [];
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  final Map<String, ValueNotifier<Map<String, int>?>> _reactionOverrides =
      <String, ValueNotifier<Map<String, int>?>>{};
  final Map<String, Timer> _reactionSyncTimers = <String, Timer>{};
  final Map<String, String?> _myReactionByMessageId = <String, String?>{};
  String? _cachedUnreadMessageId;
  DateTime? _lastReadWriteAt;
  bool _nearBottom = true;
  int _lastCount = 0;
  bool _lastMemberExists = true;
  double _baseZoom = 1.0;
  static const double _minZoom = 1.0;
  static const double _maxZoom = 1.6;
  static const _groupWindow = Duration(minutes: 5);

  void _onTypingChanged(bool hasText) {
    if (!hasText) {
      _typingController.onTextChanged('', widget.chatId);
    }
  }

  void _onTypingTextChanged(String text) {
    _typingController.onTextChanged(text, widget.chatId);
  }

  void _onVoiceRecordingChanged(bool recording) {
    if (recording) {
      _typingController.startVoice(widget.chatId);
      return;
    }
    _typingController.onSend(widget.chatId);
  }

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

  bool _samePinnedIds(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    final aIds = a
        .map((e) => (e['messageId'] as String?) ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    final bIds = b
        .map((e) => (e['messageId'] as String?) ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    if (aIds.length != bIds.length) return false;
    for (int i = 0; i < aIds.length; i++) {
      if (aIds[i] != bIds[i]) return false;
    }
    return true;
  }

  void _openPinnedSheet({
    required List<Map<String, dynamic>> pinned,
    required Map<String, MessageModel> messageById,
  }) {
    if (pinned.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Pinned Messages',
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.onSurface,
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
                                      ? 'Photo'
                                      : (m.messageType == MessageType.video
                                            ? 'Video'
                                            : (m.messageType ==
                                                      MessageType.audio
                                                  ? 'Voice message'
                                                  : 'Document'))));

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(ctx).colorScheme.surfaceVariant,
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
                              style: TextStyle(
                                color: Theme.of(ctx).colorScheme.onSurface,
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
                                          await _togglePinOptimistic(mid);
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
      if (isNear) {
        _touchLastRead();
        if (_cachedUnreadMessageId != null && mounted) {
          setState(() => _cachedUnreadMessageId = null);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _touchLastRead(force: true);
    });
  }

  @override
  void dispose() {
    MessageInteractionOverlay.dismiss();
    _typingController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _replyTarget.dispose();
    _highlightId.dispose();
    _selectedMessageId.dispose();
    _slowTick?.cancel();
    _slowRemainingSec.dispose();
    _pinnedOverride.dispose();
    for (final t in _reactionSyncTimers.values) {
      t.cancel();
    }
    _reactionSyncTimers.clear();
    for (final n in _reactionOverrides.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GroupChatDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) {
      _replyTarget.value = null;
      _highlightId.value = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _replyTarget.value = null;
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _typingController.onLeaveChat(widget.chatId);
    }
  }

  void _updateSlowRemaining({
    required bool enabled,
    required int durationSec,
    required Timestamp? lastSentAt,
  }) {
    if (_slowLastSentAtOverride != null && lastSentAt != null) {
      final overrideMs = _slowLastSentAtOverride!.millisecondsSinceEpoch;
      final remoteMs = lastSentAt.toDate().millisecondsSinceEpoch;
      if ((remoteMs - overrideMs).abs() <= 2000) {
        _slowLastSentAtOverride = null;
      }
    }

    final effectiveLast = _slowLastSentAtOverride ?? lastSentAt?.toDate();

    final lastMs = effectiveLast?.millisecondsSinceEpoch;
    final inputsChanged =
        _lastSlowEnabled != enabled ||
        _lastSlowDuration != durationSec ||
        _lastSlowLastSentAtMs != lastMs;

    if (!inputsChanged) return;

    _lastSlowEnabled = enabled;
    _lastSlowDuration = durationSec;
    _lastSlowLastSentAtMs = lastMs;

    _slowTick?.cancel();
    _slowTick = null;

    if (!enabled || durationSec <= 0 || effectiveLast == null) {
      if (_slowRemainingSec.value != 0) _slowRemainingSec.value = 0;
      return;
    }

    int calcRemainingSec() {
      final nextAllowed = effectiveLast.add(Duration(seconds: durationSec));
      final remainingMs =
          nextAllowed.millisecondsSinceEpoch -
          DateTime.now().millisecondsSinceEpoch;
      if (remainingMs <= 0) return 0;
      return (remainingMs / 1000).ceil();
    }

    _slowRemainingSec.value = calcRemainingSec();
    if (_slowRemainingSec.value == 0) return;

    _slowTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = calcRemainingSec();
      if (next != _slowRemainingSec.value) _slowRemainingSec.value = next;
      if (next == 0) {
        _slowTick?.cancel();
        _slowTick = null;
      }
    });
  }

  Future<void> _togglePinOptimistic(String messageId) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(chatServiceProvider);
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final prev = _pinnedOverride.value;
    final base = prev ?? _lastPinnedFromStream;
    final current = List<Map<String, dynamic>>.from(base);
    final alreadyPinned = current.any((p) => p['messageId'] == messageId);

    if (alreadyPinned) {
      current.removeWhere((p) => p['messageId'] == messageId);
    } else {
      current.insert(0, {
        'messageId': messageId,
        'pinnedBy': uid,
        'pinnedAt': Timestamp.now(),
      });
      if (current.length > 5) {
        current.removeRange(5, current.length);
      }
    }

    _pinnedOverride.value = current;

    try {
      await service.togglePinMessage(
        chatId: widget.chatId,
        messageId: messageId,
      );
    } catch (e) {
      _pinnedOverride.value = prev;
      messenger.showSnackBar(SnackBar(content: Text('Pin failed: $e')));
    }
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

  String? _myReactionFor(MessageModel m) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return _myReactionByMessageId[m.id];
    return _myReactionByMessageId[m.id] ?? m.userReactions?[me];
  }

  Future<void> _openReactionTray(MessageModel m) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final key = _messageKeys[m.id];
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final rect = origin & box.size;

    await MessageInteractionOverlay.show(
      context: context,
      messageRect: rect,
      showReactions: !m.isDeletedForAll,
      alignToRight: m.senderId == me,
      selectedEmoji: _myReactionFor(m),
      onReact: (emoji) => _reactOptimistic(m, emoji),
      actions: const <MessageActionItem>[],
    );
  }

  Future<void> _reactOptimistic(MessageModel m, String emoji) async {
    if (m.isDeletedForAll) return;

    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(chatServiceProvider);
    final id = m.id;
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;

    final notifier = _reactionOverrideNotifier(id);
    final prevCounts = _cloneCounts(notifier.value ?? m.reactions);
    final prevMy = _myReactionByMessageId[id] ?? m.userReactions?[me];

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
      _scheduleReactionSyncUnlock(id);
    } catch (e) {
      notifier.value = prevCounts;
      _myReactionByMessageId[id] = prevMy;
      _scheduleReactionSyncUnlock(id);
      messenger.showSnackBar(SnackBar(content: Text('Reaction failed: $e')));
    }
  }

  void _scheduleReactionSyncUnlock(String messageId) {
    _reactionSyncTimers[messageId]?.cancel();
    _reactionSyncTimers[messageId] = Timer(
      const Duration(milliseconds: 420),
      () {
        if (!mounted) return;
        final notifier = _reactionOverrides[messageId];
        if (notifier != null) {
          notifier.value = null;
        }
        _myReactionByMessageId.remove(messageId);
        _reactionSyncTimers.remove(messageId);
      },
    );
  }

  ReplyTarget _toReplyTarget(MessageModel m) {
    String preview;
    final t = m.messageType;
    switch (t) {
      case MessageType.text:
        preview = (m.text ?? '').trim();
        break;
      case MessageType.image:
        preview = 'Photo';
        break;
      case MessageType.video:
        preview = 'Video';
        break;
      case MessageType.file:
        preview = 'Document';
        break;
      case MessageType.audio:
        preview = 'Voice message';
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
    Future.delayed(const Duration(milliseconds: 950), () {
      if (!mounted) return;
      if (_highlightId.value == messageId) _highlightId.value = null;
    });
  }

  void _syncReplyTargetWithMessages(List<MessageModel> messages) {
    final active = _replyTarget.value;
    if (active == null) return;
    final targetId = active.messageId.trim();
    if (targetId.isEmpty) {
      _replyTarget.value = null;
      return;
    }
    final match = messages.cast<MessageModel?>().firstWhere(
      (m) => m?.id == targetId,
      orElse: () => null,
    );
    if (match == null || match.isDeletedForAll) {
      _replyTarget.value = null;
    }
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
              if (_replyTarget.value?.messageId == m.id) {
                _replyTarget.value = null;
              }
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
            if (_replyTarget.value?.messageId == m.id) {
              _replyTarget.value = null;
            }
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
            await _togglePinOptimistic(m.id);
            messenger.showSnackBar(
              const SnackBar(content: Text('Pin updated')),
            );
          },
        ),
    ];

    await MessageInteractionOverlay.show(
      context: context,
      messageRect: rect,
      showReactions: !m.isDeletedForAll,
      alignToRight: isMe,
      selectedEmoji: _myReactionFor(m),
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

  Future<void> _touchLastRead({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastReadWriteAt != null &&
        now.difference(_lastReadWriteAt!) < const Duration(seconds: 1)) {
      return;
    }
    _lastReadWriteAt = now;
    await ref.read(chatServiceProvider).updateLastRead(widget.chatId);
  }

  String? _firstUnreadIncomingMessageId({
    required List<MessageModel> messages,
    required Map<String, dynamic>? chatData,
    required String currentUid,
  }) {
    final lastReadMap = Map<String, dynamic>.from(
      (chatData?['lastRead'] as Map?) ?? const <String, dynamic>{},
    );
    final rawLastRead = lastReadMap[currentUid];

    DateTime? lastReadAt;
    if (rawLastRead is Timestamp) lastReadAt = rawLastRead.toDate();
    if (rawLastRead is DateTime) lastReadAt = rawLastRead;

    for (final m in messages) {
      if (m.senderId == currentUid) continue;
      if (m.isDeletedForAll) continue;
      final t = m.timestamp.toDate();
      if (lastReadAt == null || t.isAfter(lastReadAt)) {
        return m.id;
      }
    }
    return null;
  }

  String? _resolveUnreadBoundaryId({
    required List<MessageModel> messages,
    required Map<String, dynamic>? chatData,
    required String currentUid,
  }) {
    final computed = _firstUnreadIncomingMessageId(
      messages: messages,
      chatData: chatData,
      currentUid: currentUid,
    );
    final ids = messages.map((m) => m.id).toSet();

    if (_cachedUnreadMessageId != null && !ids.contains(_cachedUnreadMessageId)) {
      _cachedUnreadMessageId = null;
    }
    if (computed == null) {
      _cachedUnreadMessageId = null;
      return null;
    }
    _cachedUnreadMessageId ??= computed;
    return _cachedUnreadMessageId;
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!.uid;
    final messages = ref.watch(messagesProvider(widget.chatId));
    final hides = ref.watch(hidesProvider(widget.chatId));
    final fs = FirestoreService();
    final bubbleZoom = bubbleZoomStore[widget.chatId] ?? 1.0;

    return PopScope(
      onPopInvokedWithResult: (_, __) {
        MessageInteractionOverlay.dismiss();
        _replyTarget.value = null;
      },
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
              final memberExists = roleSnap.data?.exists ?? _lastMemberExists;
              if (roleSnap.hasData) {
                _lastMemberExists = roleSnap.data!.exists;
              }
              final role = roleSnap.data?.data()?['role'] as String?;
              final isAdmin = role == 'owner' || role == 'admin';
              final canSend = membersCanSendMessages || isAdmin;

              final memberData =
                  roleSnap.data?.data() ?? const <String, dynamic>{};
              final muteUntilTs = memberData['muteUntil'];
              final muteUntil = muteUntilTs is Timestamp ? muteUntilTs : null;
              final isMuted =
                  muteUntil != null &&
                  DateTime.now().isBefore(muteUntil.toDate());

              final moderation = Map<String, dynamic>.from(
                (data?['moderation'] as Map?) ?? const {},
              );
              final slowModeEnabled =
                  (moderation['slowModeEnabled'] as bool?) ?? false;
              final slowModeDurationSec =
                  (moderation['slowModeDurationSec'] as int?) ?? 0;

              final lastSentTs = memberData['lastSentAt'];
              final lastSentAt = lastSentTs is Timestamp ? lastSentTs : null;
              _updateSlowRemaining(
                enabled: slowModeEnabled,
                durationSec: slowModeDurationSec,
                lastSentAt: lastSentAt,
              );

              Future<void> sendText(String text) async {
                if (!memberExists) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('You were removed from this group'),
                    ),
                  );
                  return;
                }
                if (!canSend) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Only admins can send messages right now'),
                    ),
                  );
                  return;
                }
                if (isMuted) {
                  final until = muteUntil.toDate();
                  final hh = until.hour.toString().padLeft(2, '0');
                  final mm = until.minute.toString().padLeft(2, '0');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('You are muted until $hh:$mm')),
                  );
                  return;
                }
                if (slowModeEnabled && slowModeDurationSec > 0) {
                  final remaining = _slowRemainingSec.value;
                  if (remaining > 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Slow mode: wait ${remaining}s')),
                    );
                    return;
                  }
                }
                final reply = _replyTarget.value;
                _replyTarget.value = null;
                _typingController.onSend(widget.chatId);

                final prevOverride = _slowLastSentAtOverride;
                if (slowModeEnabled && slowModeDurationSec > 0) {
                  _slowLastSentAtOverride = DateTime.now();
                  _updateSlowRemaining(
                    enabled: slowModeEnabled,
                    durationSec: slowModeDurationSec,
                    lastSentAt: lastSentAt,
                  );
                }

                try {
                  await ref
                      .read(chatServiceProvider)
                      .sendGroupText(
                        chatId: widget.chatId,
                        memberIds: members,
                        text: text,
                        replyTo: reply?.toMap(),
                      );
                      await _touchLastRead(force: true);
                      _cachedUnreadMessageId = null;
                } catch (_) {
                  _slowLastSentAtOverride = prevOverride;
                  _updateSlowRemaining(
                    enabled: slowModeEnabled,
                    durationSec: slowModeDurationSec,
                    lastSentAt: lastSentAt,
                  );
                  rethrow;
                }

                // Fire-and-forget: only after message send succeeds.
                ref
                    .read(groupModerationServiceProvider)
                    .recordMyLastSentAt(chatId: widget.chatId);
                _forceScrollToBottom();
              }

              Future<void> sendMedia(
                Uint8List bytes,
                String name,
                String contentType,
                MessageType type, {
                String? localPath,
                String? thumbnailPath,
                int? durationMs,
              }) async {
                if (!memberExists) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('You were removed from this group'),
                    ),
                  );
                  return;
                }
                if (!canSend) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Only admins can send messages right now'),
                    ),
                  );
                  return;
                }
                if (isMuted) {
                  final until = muteUntil.toDate();
                  final hh = until.hour.toString().padLeft(2, '0');
                  final mm = until.minute.toString().padLeft(2, '0');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('You are muted until $hh:$mm')),
                  );
                  return;
                }
                if (slowModeEnabled && slowModeDurationSec > 0) {
                  final remaining = _slowRemainingSec.value;
                  if (remaining > 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Slow mode: wait ${remaining}s')),
                    );
                    return;
                  }
                }
                final reply = _replyTarget.value;
                _replyTarget.value = null;
                _typingController.onSend(widget.chatId);

                final prevOverride = _slowLastSentAtOverride;
                if (slowModeEnabled && slowModeDurationSec > 0) {
                  _slowLastSentAtOverride = DateTime.now();
                  _updateSlowRemaining(
                    enabled: slowModeEnabled,
                    durationSec: slowModeDurationSec,
                    lastSentAt: lastSentAt,
                  );
                }

                try {
                  await ref
                      .read(chatServiceProvider)
                      .sendGroupMedia(
                        chatId: widget.chatId,
                        memberIds: members,
                        bytes: bytes,
                        fileName: name,
                        contentType: contentType,
                        type: type,
                        localPath: localPath,
                        thumbnailPath: thumbnailPath,
                        audioDurationMs: durationMs,
                        replyTo: reply?.toMap(),
                      );
                      await _touchLastRead(force: true);
                      _cachedUnreadMessageId = null;
                } catch (_) {
                  _slowLastSentAtOverride = prevOverride;
                  _updateSlowRemaining(
                    enabled: slowModeEnabled,
                    durationSec: slowModeDurationSec,
                    lastSentAt: lastSentAt,
                  );
                  rethrow;
                }

                // Fire-and-forget: only after message send succeeds.
                ref
                    .read(groupModerationServiceProvider)
                    .recordMyLastSentAt(chatId: widget.chatId);
                _forceScrollToBottom();
              }

              return Scaffold(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                resizeToAvoidBottomInset: false,
                appBar: PreferredSize(
                  preferredSize: const Size.fromHeight(52),
                  child: AppBar(
                    toolbarHeight: 52,
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                            stream: FirestoreService().groups
                                .doc(widget.chatId)
                                .snapshots(),
                            builder: (context, chatSnap) {
                              final pinned = _normalizePinned(
                                chatSnap.data?.data()?['pinnedMessages'],
                              );
                              _lastPinnedFromStream = pinned;
                              return ValueListenableBuilder<
                                List<Map<String, dynamic>>?
                              >(
                                valueListenable: _pinnedOverride,
                                builder: (context, override, __) {
                                  if (override != null &&
                                      _samePinnedIds(override, pinned)) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (!mounted) return;
                                          if (_pinnedOverride.value != null) {
                                            _pinnedOverride.value = null;
                                          }
                                        });
                                  }
                                  final effectivePinned = override ?? pinned;
                                  return messages.when(
                                    data: (list) {
                                      final blockedUsers = ref
                                          .watch(myBlockedUsersProvider)
                                          .maybeWhen(
                                            data: (s) => s,
                                            orElse: () => <String>{},
                                          );
                                      final hidden = hides.maybeWhen(
                                        data: (s) => s,
                                        orElse: () => <String>{},
                                      );
                                      final filtered = list
                                          .where(
                                            (m) =>
                                                !hidden.contains(m.id) &&
                                                !blockedUsers.contains(
                                                  m.senderId,
                                                ),
                                          )
                                          .toList();
                                      final unreadBoundaryId = _resolveUnreadBoundaryId(
                                        messages: filtered,
                                        chatData: data,
                                        currentUid: me,
                                      );
                                      _syncReplyTargetWithMessages(filtered);
                                      final display = filtered.reversed
                                          .toList();
                                      final messageById =
                                          <String, MessageModel>{
                                            for (final m in filtered) m.id: m,
                                          };

                                      final pinnedIds = effectivePinned
                                          .map(
                                            (e) =>
                                                (e['messageId'] as String?) ??
                                                '',
                                          )
                                          .where((e) => e.isNotEmpty)
                                          .toList();
                                      final pinnedSet = pinnedIds.toSet();

                                      if (display.length > _lastCount &&
                                          _nearBottom) {
                                        _touchLastRead();
                                        WidgetsBinding.instance
                                            .addPostFrameCallback(
                                              (_) => _maybeScrollToBottom(),
                                            );
                                      }
                                      _lastCount = display.length;

                                      String pinPreview(String mid) {
                                        final m = messageById[mid];
                                        if (m == null) return 'Pinned message';
                                        if (m.messageType == MessageType.text) {
                                          final t = (m.text ?? '').trim();
                                          return t.isNotEmpty
                                              ? t
                                              : 'Pinned message';
                                        }
                                        switch (m.messageType) {
                                          case MessageType.image:
                                            return 'Photo';
                                          case MessageType.video:
                                            return 'Video';
                                          case MessageType.audio:
                                            return 'Voice message';
                                          case MessageType.file:
                                            return 'Document';
                                          case MessageType.text:
                                            return 'Pinned message';
                                        }
                                      }

                                      final bar = pinnedIds.isEmpty
                                          ? const SizedBox.shrink()
                                          : InkWell(
                                              onTap: () => _openPinnedSheet(
                                                pinned: effectivePinned,
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
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.push_pin,
                                                      size: 16,
                                                      color: Color(0xFF5865F2),
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
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xFFEAEAEA,
                                                          ),
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    const Icon(
                                                      Icons
                                                          .chevron_right_rounded,
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
                                                    bubbleZoomStore[widget
                                                        .chatId] ??
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
                                                    bubbleZoomStore[widget
                                                            .chatId] =
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
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12,
                                                    ),
                                                itemCount: display.length,
                                                itemBuilder: (context, index) {
                                                  final m = display[index];
                                                  final isMe = m.senderId == me;
                                                  final showUnreadDivider =
                                                      m.id == unreadBoundaryId;

                                                  final older =
                                                      index + 1 < display.length
                                                      ? display[index + 1]
                                                      : null;
                                                  final isSameSenderAsOlder =
                                                      older != null &&
                                                      older.senderId ==
                                                          m.senderId;
                                                  final isWithinWindow =
                                                      older != null
                                                      ? (m.timestamp
                                                                .toDate()
                                                                .difference(
                                                                  older
                                                                      .timestamp
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
                                                      newer.senderId ==
                                                          m.senderId;
                                                  final bottomSpacing =
                                                      m.kind == 'system'
                                                      ? 6.0
                                                      : (!isSameSenderAsNewer
                                                            ? 10.0
                                                            : 6.0);

                                                  return RepaintBoundary(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        AnimatedSwitcher(
                                                          duration:
                                                              const Duration(
                                                                milliseconds:
                                                                    200,
                                                              ),
                                                          child: showUnreadDivider
                                                              ? const _UnreadDivider(
                                                                  key: ValueKey(
                                                                    'group_unread_divider',
                                                                  ),
                                                                )
                                                              : const SizedBox.shrink(
                                                                  key: ValueKey(
                                                                    'group_no_unread_divider',
                                                                  ),
                                                                ),
                                                        ),
                                                        KeyedSubtree(
                                                          key: ValueKey(m.id),
                                                          child: Align(
                                                        alignment: isMe
                                                            ? Alignment
                                                                  .centerRight
                                                            : Alignment
                                                                  .centerLeft,
                                                        child: ValueListenableBuilder<String?>(
                                                          valueListenable:
                                                              _highlightId,
                                                          builder: (context, hid, _) {
                                                            final highlighted =
                                                                hid == m.id;
                                                            final key = _messageKeys
                                                                .putIfAbsent(
                                                                  m.id,
                                                                  () =>
                                                                      GlobalKey(),
                                                                );
                                                            return ValueListenableBuilder<
                                                              String?
                                                            >(
                                                              valueListenable:
                                                                  _selectedMessageId,
                                                              builder: (context, sid, __) {
                                                                final selected =
                                                                    sid == m.id;
                                                                final theme = Theme.of(
                                                                  context,
                                                                );
                                                                final isLight =
                                                                    theme.brightness ==
                                                                    Brightness.light;
                                                                final bg =
                                                                    highlighted
                                                                    ? (isLight
                                                                          ? const Color(0xFF5865F2)
                                                                                .withOpacity(0.15)
                                                                          : const Color(0xFF5865F2)
                                                                                .withOpacity(0.25))
                                                                    : (selected
                                                                          ? const Color(
                                                                              0xFF1A1A1A,
                                                                            ).withOpacity(
                                                                              0.12,
                                                                            )
                                                                          : Colors.transparent);
                                                                final pad =
                                                                    highlighted
                                                                    ? const EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            6,
                                                                        vertical:
                                                                            4,
                                                                      )
                                                                    : EdgeInsets
                                                                          .zero;
                                                                return AnimatedContainer(
                                                                  duration: const Duration(
                                                                    milliseconds: 180,
                                                                  ),
                                                                  curve: Curves
                                                                      .easeOut,
                                                                  key: key,
                                                                  decoration: BoxDecoration(
                                                                    color: bg,
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          14,
                                                                        ),
                                                                    border: highlighted
                                                                        ? Border.all(
                                                                            color: const Color(0xFF5865F2),
                                                                            width: 1,
                                                                          )
                                                                        : null,
                                                                  ),
                                                                  padding: pad,
                                                                  child: SwipeToReply(
                                                                    enabled: !m
                                                                        .isDeletedForAll,
                                                                    onReply: () =>
                                                                        _replyTarget.value =
                                                                            _toReplyTarget(
                                                                              m,
                                                                            ),
                                                                    child: GestureDetector(
                                                                      onLongPress: () => _onMessageLongPress(
                                                                        context,
                                                                        m,
                                                                        isMe,
                                                                        isAdmin,
                                                                        pinnedSet
                                                                            .contains(
                                                                              m.id,
                                                                            ),
                                                                      ),
                                                                      child:
                                                                          ValueListenableBuilder<
                                                                            Map<
                                                                              String,
                                                                              int
                                                                            >?
                                                                          >(
                                                                            valueListenable: _reactionOverrideNotifier(
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
                                                                                    message: m,
                                                                                    isMe: isMe,
                                                                                    showIdentity: showIdentity,
                                                                                    zoom: bubbleZoom,
                                                                                    bottomSpacing: bottomSpacing,
                                                                                    groupChatId: widget.chatId,
                                                                                    reactionsOverride: override,
                                                                                    myReaction:
                                                                                        _myReactionByMessageId[m.id] ??
                                                                                        m.userReactions?[me],
                                                                                    onReactionsTap: () =>
                                                                                        _openReactionTray(m),
                                                                                    isPinned: pinnedSet.contains(
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
                                                                                    onReplyCardTap: _scrollToMessage,
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
                                                      ),
                                                        ),
                                                      ],
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
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface.withOpacity(
                                            0.7,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
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
                                if (slowModeEnabled && slowModeDurationSec > 0)
                                  ValueListenableBuilder<int>(
                                    valueListenable: _slowRemainingSec,
                                    builder: (context, remaining, __) {
                                      final label = remaining > 0
                                          ? 'Slow mode: ${remaining}s'
                                          : 'Slow mode: ${slowModeDurationSec}s';
                                      return Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          0,
                                          12,
                                          8,
                                        ),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.surfaceVariant,
                                              borderRadius:
                                                  BorderRadius.circular(100),
                                              border: Border.all(
                                                color: Theme.of(
                                                  context,
                                                ).dividerColor,
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.schedule_rounded,
                                                  size: 14,
                                                  color: Theme.of(
                                                    context,
                                                  ).iconTheme.color,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  label,
                                                  style: TextStyle(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
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
                                ValueListenableBuilder<int>(
                                  valueListenable: _slowRemainingSec,
                                  builder: (context, remaining, _) {
                                    final slowBlocked =
                                        slowModeEnabled &&
                                        slowModeDurationSec > 0 &&
                                        remaining > 0;
                                    final sendBlocked =
                                        isMuted || slowBlocked || !canSend;

                                    if (!memberExists) {
                                      return const Center(
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 14,
                                          ),
                                          child: Text(
                                            'You were removed from this group',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Color(0xFF888888),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      );
                                    }

                                    final blockedUsers = ref
                                        .watch(myBlockedUsersProvider)
                                        .maybeWhen(
                                          data: (s) => s,
                                          orElse: () => <String>{},
                                        );

                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        RepaintBoundary(
                                          child: ChatTypingIndicator(
                                            chatId: widget.chatId,
                                            currentUid: me,
                                            isGroup: true,
                                            blockedUserIds: blockedUsers,
                                            hideIndicator: isMuted,
                                          ),
                                        ),
                                        InputField(
                                          onSend: sendText,
                                          onSendMedia: sendMedia,
                                          onTypingChanged: _onTypingChanged,
                                          onTextChanged: _onTypingTextChanged,
                                          onVoiceRecordingChanged:
                                              _onVoiceRecordingChanged,
                                          sendDisabled: sendBlocked,
                                        ),
                                      ],
                                    );
                                  },
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
      ),
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
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
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
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
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

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              thickness: 1,
              color: Theme.of(context).dividerColor.withOpacity(0.35),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Unread messages',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
          ),
          Expanded(
            child: Divider(
              thickness: 1,
              color: Theme.of(context).dividerColor.withOpacity(0.35),
            ),
          ),
        ],
      ),
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
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.2,
            ),
          ),
          SizedBox(height: 6),
          const Text(
            'Admins: -',
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
          'Thread',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 15,
          ),
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


