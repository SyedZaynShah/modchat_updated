import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message_model.dart';
import '../providers/user_providers.dart';
import '../theme/theme.dart';
import 'file_preview_widget.dart';

class MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final bool showAvatar;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.showAvatar = false,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryText = isDark
        ? AppColors.textDarkPrimary
        : AppColors.textLightPrimary;
    final secondaryText = isDark
        ? AppColors.textDarkSecondary
        : AppColors.textLightSecondary;
    final timeText = isDark ? AppColors.textDarkSecondary : AppColors.timeTextLight;
    final maxWidth = MediaQuery.of(context).size.width * 0.7;
    final sentColor = isDark
        ? AppColors.primary.withOpacity(0.2)
        : AppColors.outgoingBubbleLight;
    final receivedColor = isDark
        ? AppColors.darkCard
        : AppColors.incomingBubbleLight;
    final incomingBorder = isDark ? AppColors.darkBorder : AppColors.bubbleBorderLight;

    final bubble = widget.message.messageType == MessageType.text
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isMe ? sentColor : receivedColor,
              borderRadius: BorderRadius.circular(16),
              border: !widget.isMe
                  ? Border.all(color: incomingBorder, width: 1)
                  : null,
            ),
            child: _content(
              context,
              primaryText: primaryText,
              secondaryText: secondaryText,
              timeText: timeText,
            ),
          )
        : _content(
            context,
            primaryText: primaryText,
            secondaryText: secondaryText,
            timeText: timeText,
          );

    return Row(
      mainAxisAlignment: widget.isMe
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!widget.isMe) ...[
          SizedBox(
            width: 32,
            child: widget.showAvatar
                ? _BubbleAvatar(senderId: widget.message.senderId)
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
        ],
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: bubble,
        ),
      ],
    );
  }

  Widget _content(
    BuildContext context, {
    required Color primaryText,
    required Color secondaryText,
    required Color timeText,
  }) {
    final message = widget.message;
    if (message.isDeletedForAll) {
      return Text(
        'This message was deleted',
        style: TextStyle(
          fontSize: 14,
          color: secondaryText,
          fontStyle: FontStyle.italic,
        ),
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            forwardedTag,
            Text(
              message.text ?? '',
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: primaryText,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(),
                  style: TextStyle(
                    fontSize: 10,
                    color: timeText,
                  ),
                ),
                if (widget.isMe) ...[
                  const SizedBox(width: 4),
                  _StatusIcon(
                    status: message.status,
                    isPending: message.hasPendingWrites,
                    timeText: timeText,
                  ),
                ],
              ],
            ),
          ],
        );
      case MessageType.image:
      case MessageType.video:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            forwardedTag,
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.65,
              ),
              child: FilePreviewWidget(message: message, isMe: widget.isMe),
            ),
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
              child: FilePreviewWidget(message: message, isMe: widget.isMe),
            ),
          ],
        );
      case MessageType.file:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            forwardedTag,
            FilePreviewWidget(message: message, isMe: widget.isMe),
          ],
        );
    }
  }

  String _formatTime() {
    final dt = widget.message.timestamp.toDate();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _BubbleAvatar extends ConsumerWidget {
  final String senderId;
  const _BubbleAvatar({required this.senderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userDocProvider(senderId));
    return user.when(
      data: (u) => CircleAvatar(
        radius: 14,
        backgroundColor: const Color(0xFF1A1A1A),
        backgroundImage: u?.profileImageUrl != null
            ? NetworkImage(u!.profileImageUrl!)
            : null,
        child: u?.profileImageUrl == null
            ? Icon(
                Icons.person,
                size: 14,
                color: Theme.of(
                  context,
                ).iconTheme.color?.withOpacity(0.6),
              )
            : null,
      ),
      loading: () =>
          const CircleAvatar(radius: 14, backgroundColor: Color(0xFF151515)),
      error: (_, __) =>
          const CircleAvatar(radius: 14, backgroundColor: Color(0xFF1A1A1A)),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final int status;
  final bool isPending;
  final Color timeText;
  const _StatusIcon({
    required this.status,
    required this.isPending,
    required this.timeText,
  });

  @override
  Widget build(BuildContext context) {
    if (isPending) {
      return const Icon(
        Icons.watch_later_outlined,
        size: 11,
        color: Color(0xFF94A3B8),
      );
    }

    final color = status == 3 ? AppColors.primary : timeText;
    final icon = status >= 2 ? Icons.done_all_rounded : Icons.done_rounded;

    return Icon(icon, size: 11, color: color);
  }
}

