import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message_model.dart';
import '../providers/user_providers.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../theme/theme.dart';
import 'file_preview_widget.dart';

class GroupMessageBubble extends ConsumerWidget {
  final MessageModel message;
  final bool isMe;
  final bool showIdentity;
  final bool isPinned;
  final double zoom;
  final double bottomSpacing;
  final String groupChatId;
  final Map<String, int>? reactionsOverride;
  final void Function(String messageId)? onOpenThread;
  final ValueChanged<String>? onReplyCardTap;

  const GroupMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.showIdentity,
    required this.groupChatId,
    this.reactionsOverride,
    this.onOpenThread,
    this.onReplyCardTap,
    this.isPinned = false,
    this.zoom = 1.0,
    this.bottomSpacing = 6,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveReactions = reactionsOverride ?? message.reactions;
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    const textColor = Color(0xFFFFFFFF);
    final z = message.messageType == MessageType.text
        ? zoom.clamp(1.0, 1.6)
        : 1.0;

    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.72;
    final bubblePadding = EdgeInsets.symmetric(
      horizontal: 10 * z,
      vertical: 10 * z,
    );

    final pinTag = isPinned
        ? Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.push_pin_rounded,
                  size: 12,
                  color: Color(0xFFBEBEBE),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    Widget bubble() {
      if (message.messageType != MessageType.text) {
        return AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _content(context, textColor, z),
        );
      }

      return AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: Transform.scale(
          scale: 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: Padding(
                padding: bubblePadding,
                child: _content(context, textColor, z),
              ),
            ),
          ),
        ),
      );
    }

    if (isMe) {
      return Column(
        crossAxisAlignment: align,
        children: [
          if (message.replyToMessageId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                  ),
                  child: _ReplyPreview(
                    replyToMessageId: message.replyToMessageId,
                    replyToSenderId: message.replyToSenderId,
                    replyToText: message.replyToText,
                    onTap: onReplyCardTap,
                  ),
                ),
              ),
            ),
          pinTag,
          Align(alignment: Alignment.centerRight, child: bubble()),
          if ((effectiveReactions ?? const {}).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _ReactionsRow(reactions: effectiveReactions ?? const {}),
            ),
          if ((message.threadReplyCount ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _ThreadIndicator(
                count: message.threadReplyCount ?? 0,
                onTap: onOpenThread == null
                    ? null
                    : () => onOpenThread!(message.id),
              ),
            ),
          SizedBox(height: bottomSpacing),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showIdentity)
              _SenderAvatar(senderId: message.senderId, size: 28)
            else
              const SizedBox(width: 28, height: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showIdentity)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _SenderHeader(
                        chatId: groupChatId,
                        senderId: message.senderId,
                        timestamp: message.timestamp,
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  if (message.replyToMessageId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.7,
                          ),
                          child: _ReplyPreview(
                            replyToMessageId: message.replyToMessageId,
                            replyToSenderId: message.replyToSenderId,
                            replyToText: message.replyToText,
                            onTap: onReplyCardTap,
                          ),
                        ),
                      ),
                    ),
                  pinTag,
                  Align(alignment: Alignment.centerLeft, child: bubble()),
                  if ((effectiveReactions ?? const {}).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _ReactionsRow(
                        reactions: effectiveReactions ?? const {},
                      ),
                    ),
                  if ((message.threadReplyCount ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _ThreadIndicator(
                        count: message.threadReplyCount ?? 0,
                        onTap: onOpenThread == null
                            ? null
                            : () => onOpenThread!(message.id),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: bottomSpacing),
      ],
    );
  }

  Widget _content(BuildContext context, Color textColor, double z) {
    if (message.isDeletedForAll) {
      final style = TextStyle(
        fontSize: 12 * (message.messageType == MessageType.text ? z : 1.0),
        color: textColor,
        fontStyle: FontStyle.italic,
      );
      return AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        style: style,
        child: const Text('This message was deleted.'),
      );
    }

    final forwardedTag = (message.forwarded)
        ? const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'Forwarded',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE5E5E5),
                height: 1.1,
              ),
            ),
          )
        : const SizedBox.shrink();

    switch (message.messageType) {
      case MessageType.text:
        final t = (message.text ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            forwardedTag,
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              style: TextStyle(fontSize: 14 * z, height: 1.4, color: textColor),
              child: Text(t),
            ),
            const SizedBox(height: 6),
            _metaRow(textColor),
          ],
        );
      case MessageType.image:
      case MessageType.video:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            forwardedTag,
            FilePreviewWidget(message: message, isMe: isMe),
          ],
        );
      case MessageType.file:
      case MessageType.audio:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            forwardedTag,
            FilePreviewWidget(message: message, isMe: isMe),
            const SizedBox(height: 6),
            _metaRow(textColor),
          ],
        );
    }
  }

  Widget _metaRow(Color baseColor) {
    const timeColor = Color(0xFFFFFFFF);
    final List<Widget> children = [
      Text(
        _formatTime(),
        style: const TextStyle(fontSize: 10, color: timeColor),
      ),
    ];

    if (isMe) {
      children.add(const SizedBox(width: 6));
      final isPending = message.hasPendingWrites;
      final iconData = isPending
          ? Icons.watch_later_outlined
          : (message.status == 3
                ? Icons.done_all_rounded
                : (message.status == 2 ? Icons.done : Icons.done));
      children.add(Icon(iconData, size: 12, color: timeColor));
    }

    if (message.edited) {
      children.add(const SizedBox(width: 6));
      children.add(
        const Text('Edited', style: TextStyle(fontSize: 10, color: timeColor)),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  String _formatTime() {
    final dt = message.timestamp.toDate();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _SenderAvatar extends ConsumerWidget {
  final String senderId;
  final double size;
  const _SenderAvatar({required this.senderId, required this.size});

  Future<ImageProvider?> _resolvePfp(String? url) async {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('sb://')) {
      final s = raw.substring(5);
      final i = s.indexOf('/');
      if (i <= 0) return null;
      final bucket = s.substring(0, i);
      final path = s.substring(i + 1);
      final signed = await SupabaseService.instance.getSignedUrl(
        bucket,
        path,
        expiresInSeconds: 86400,
      );
      return NetworkImage(signed);
    }
    if (!raw.contains('://')) {
      final signed = await SupabaseService.instance.resolveUrl(
        bucket: StorageService().profileBucket,
        path: raw,
      );
      return NetworkImage(signed);
    }
    return NetworkImage(raw);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userDocProvider(senderId));
    return user.when(
      data: (u) {
        return FutureBuilder<ImageProvider?>(
          future: _resolvePfp(u?.profileImageUrl),
          builder: (context, snap) {
            final img = snap.data;
            final hasImage = img != null;
            return CircleAvatar(
              radius: size / 2,
              backgroundColor: AppColors.sinopia.withValues(alpha: 0.25),
              backgroundImage: img,
              onBackgroundImageError: hasImage ? (_, __) {} : null,
              child: hasImage
                  ? null
                  : Icon(
                      Icons.person,
                      size: size * 0.5,
                      color: AppColors.white.withValues(alpha: 0.75),
                    ),
            );
          },
        );
      },
      loading: () => SizedBox(width: size, height: size),
      error: (_, __) => SizedBox(width: size, height: size),
    );
  }
}

class _SenderHeader extends ConsumerWidget {
  final String chatId;
  final String senderId;
  final Timestamp timestamp;
  const _SenderHeader({
    required this.chatId,
    required this.senderId,
    required this.timestamp,
  });

  String _formatTime() {
    final dt = timestamp.toDate();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userDocProvider(senderId));
    final fs = FirestoreService();

    return user.when(
      data: (u) {
        final name = (u?.name ?? '').trim();
        final display = name.isNotEmpty ? name : senderId;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: fs.dmChats
              .doc(chatId)
              .collection('members')
              .doc(senderId)
              .snapshots(),
          builder: (context, snap) {
            final role = (snap.data?.data()?['role'] as String?)?.toLowerCase();
            final badge = role == 'owner'
                ? const _RoleBadge.owner()
                : (role == 'admin' ? const _RoleBadge.admin() : null);

            return Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE5E5E5),
                            height: 1.1,
                          ),
                        ),
                      ),
                      if (badge != null) ...[const SizedBox(width: 6), badge],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTime(),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8A8A8A),
                    height: 1.1,
                  ),
                ),
              ],
            );
          },
        );
      },
      loading: () => const SizedBox(height: 14),
      error: (_, __) => const SizedBox(height: 14),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _RoleBadge._(this.label, this.bg, this.fg);
  const _RoleBadge.admin()
    : this._('ADMIN', const Color(0xFF1E1E1E), Colors.white);
  const _RoleBadge.owner()
    : this._('OWNER', const Color(0xFFC74B6C), Colors.white);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: fg,
          height: 1,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _ReplyPreview extends ConsumerWidget {
  final String? replyToMessageId;
  final String? replyToSenderId;
  final String? replyToText;
  final ValueChanged<String>? onTap;
  const _ReplyPreview({
    required this.replyToMessageId,
    required this.replyToSenderId,
    required this.replyToText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final senderId = (replyToSenderId ?? '').trim();
    final preview = (replyToText ?? '').trim();
    final user = senderId.isEmpty ? null : ref.watch(userDocProvider(senderId));

    Widget nameWidget() {
      if (user == null) {
        return const Text(
          'Reply',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFFE5E5E5),
            height: 1.1,
          ),
        );
      }
      return user.when(
        data: (u) {
          final n = (u?.name ?? '').trim();
          final display = n.isNotEmpty ? n : senderId;
          return Text(
            display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE5E5E5),
              height: 1.1,
            ),
          );
        },
        loading: () => const SizedBox(height: 12),
        error: (_, __) => const SizedBox(height: 12),
      );
    }

    final canTap = onTap != null && (replyToMessageId ?? '').trim().isNotEmpty;
    return GestureDetector(
      onTap: canTap ? () => onTap!(replyToMessageId!.trim()) : null,
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
                  nameWidget(),
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(10),
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

class _ThreadIndicator extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;
  const _ThreadIndicator({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Text(
          '$count replies  ·  View thread',
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFFC74B6C),
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
