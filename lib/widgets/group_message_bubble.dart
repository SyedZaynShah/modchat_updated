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
  final String? myReaction;
  final VoidCallback? onReactionsTap;
  final void Function(String messageId)? onOpenThread;
  final ValueChanged<String>? onReplyCardTap;

  const GroupMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.showIdentity,
    required this.groupChatId,
    this.reactionsOverride,
    this.myReaction,
    this.onReactionsTap,
    this.onOpenThread,
    this.onReplyCardTap,
    this.isPinned = false,
    this.zoom = 1.0,
    this.bottomSpacing = 6,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryText = isDark
        ? AppColors.textDarkPrimary
        : AppColors.textLightPrimary;
    final secondaryText = isDark
        ? AppColors.textDarkSecondary
        : AppColors.textLightSecondary;
    final timeText = isDark ? AppColors.textDarkSecondary : AppColors.timeTextLight;

    if (message.kind == 'system') {
      final t = (message.text ?? '').trim();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Align(
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            switchInCurve: Curves.easeOut,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Text(
              t,
              key: ValueKey(message.id),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF888888),
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    final effectiveReactions = reactionsOverride ?? message.reactions;
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final textColor = primaryText;
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
          child: _content(
            context,
            textColor,
            z,
            secondaryText: secondaryText,
            timeText: timeText,
          ),
        );
      }

      final incomingBubble = isDark
          ? AppColors.darkCard
          : AppColors.incomingBubbleLight;
      final outgoingBubble = isDark
          ? AppColors.primary.withOpacity(0.2)
          : AppColors.outgoingBubbleLight;
      final incomingBorder = isDark
          ? AppColors.darkBorder
          : AppColors.bubbleBorderLight;

      return AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: Transform.scale(
          scale: 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: isMe ? outgoingBubble : incomingBubble,
              borderRadius: BorderRadius.circular(14),
              border: !isMe
                  ? Border.all(color: incomingBorder, width: 1)
                  : null,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: Padding(
                padding: bubblePadding,
                child: _content(
                  context,
                  textColor,
                  z,
                  secondaryText: secondaryText,
                  timeText: timeText,
                ),
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
              child: _ReactionsRow(
                reactions: effectiveReactions ?? const {},
                myReaction: myReaction,
                onTap: onReactionsTap,
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
                        myReaction: myReaction,
                        onTap: onReactionsTap,
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

  Widget _content(
    BuildContext context,
    Color textColor,
    double z, {
    required Color secondaryText,
    required Color timeText,
  }) {
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
        ? Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Forwarded',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: secondaryText,
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
            _metaRow(textColor, timeText: timeText),
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
      case MessageType.audio:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            forwardedTag,
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: FilePreviewWidget(message: message, isMe: isMe),
            ),
            const SizedBox(height: 6),
            _metaRow(textColor, timeText: timeText),
          ],
        );
      case MessageType.file:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            forwardedTag,
            FilePreviewWidget(message: message, isMe: isMe),
            const SizedBox(height: 6),
            _metaRow(textColor, timeText: timeText),
          ],
        );
    }
  }

  Widget _metaRow(Color baseColor, {required Color timeText}) {
    final List<Widget> children = [
      Text(
        _formatTime(),
        style: TextStyle(fontSize: 10, color: timeText),
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
      children.add(
        Icon(
          iconData,
          size: 12,
          color: message.status == 3 ? AppColors.primary : timeText,
        ),
      );
    }

    if (message.edited) {
      children.add(const SizedBox(width: 6));
      children.add(
        Text('Edited', style: TextStyle(fontSize: 10, color: timeText)),
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
                      color: Theme.of(
                        context,
                      ).iconTheme.color?.withValues(alpha: 0.75),
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
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
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
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withOpacity(0.7),
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
    : this._('ADMIN', const Color(0xFF1E1E1E), AppColors.textDarkPrimary);
  const _RoleBadge.owner()
    : this._('OWNER', const Color(0xFF5865F2), AppColors.textDarkPrimary);

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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final senderId = (replyToSenderId ?? '').trim();
    final preview = (replyToText ?? '').trim();
    final user = senderId.isEmpty ? null : ref.watch(userDocProvider(senderId));

    Widget nameWidget() {
      if (user == null) {
        return Text(
          'Reply',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isLight ? const Color(0xFF111827) : const Color(0xFFE5E5E5),
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
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isLight
                  ? const Color(0xFF111827)
                  : const Color(0xFFE5E5E5),
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
          color: isLight ? const Color(0xFFF3F4F6) : const Color(0xFF101010),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isLight ? const Color(0xFFD1D5DB) : const Color(0xFF1A1A1A),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 2,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF5865F2),
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
                        ? (isLight
                          ? const Color(0xFF6B7280)
                          : const Color(0xFF888888))
                        : (isLight
                          ? const Color(0xFF4B5563)
                          : const Color(0xFFB5B5B5)),
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
  final String? myReaction;
  final VoidCallback? onTap;
  const _ReactionsRow({
    required this.reactions,
    this.myReaction,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final entries = reactions.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    final isLight = Theme.of(context).brightness == Brightness.light;
    final chips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: entries.take(4).map((e) {
        final selected = myReaction == e.key;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? (isLight
                      ? const Color(0xFF5865F2).withOpacity(0.15)
                      : const Color(0xFF5865F2).withOpacity(0.25))
                : (isLight ? const Color(0xFFF3F4F6) : const Color(0xFF1A1A1A)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF5865F2)
                  : (isLight
                        ? const Color(0xFFE5E7EB)
                        : const Color(0xFF2A2A2A)),
              width: 1,
            ),
          ),
          child: Text(
            '${e.key} ${e.value}',
            style: TextStyle(
              fontSize: 11,
              color: isLight ? const Color(0xFF111827) : Colors.white,
              height: 1.0,
            ),
          ),
        );
      }).toList(),
    );
    final animated = AnimatedSwitcher(
      duration: const Duration(milliseconds: 170),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: anim, child: child),
      ),
      child: KeyedSubtree(
        key: ValueKey(entries.map((e) => '${e.key}:${e.value}').join('|')),
        child: chips,
      ),
    );
    if (onTap == null) return animated;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: animated,
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
          '$count replies  -  View thread',
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF5865F2),
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}


