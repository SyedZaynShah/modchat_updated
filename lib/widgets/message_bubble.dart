import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message_model.dart';
import '../providers/user_providers.dart';
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

    final maxWidth = MediaQuery.of(context).size.width * 0.7;
    final sentColor = const Color(0xFF7A1F3D);
    final receivedColor = const Color(0xFF0F0F0F);

    Widget bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isMe ? sentColor : receivedColor,
        borderRadius: BorderRadius.circular(22),
        border: !widget.isMe
            ? Border.all(color: const Color(0xFF1A1A1A), width: 1)
            : null,
      ),
      child: _content(context),
    );

    if (widget.message.messageType != MessageType.text) {
      bubble = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: _content(context),
      );
    }

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

  Widget _content(BuildContext context) {
    final message = widget.message;
    if (message.isDeletedForAll) {
      return const Text(
        'This message was deleted',
        style: TextStyle(
          fontSize: 14,
          color: Colors.white54,
          fontStyle: FontStyle.italic,
        ),
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
                color: Colors.white70,
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
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9A9A9A),
                  ),
                ),
                if (widget.isMe) ...[
                  const SizedBox(width: 4),
                  _StatusIcon(
                    status: message.status,
                    isPending: message.hasPendingWrites,
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
      case MessageType.file:
      case MessageType.audio:
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
            ? const Icon(Icons.person, size: 14, color: Colors.white54)
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
  const _StatusIcon({required this.status, required this.isPending});

  @override
  Widget build(BuildContext context) {
    if (isPending)
      return const Icon(
        Icons.watch_later_outlined,
        size: 11,
        color: Color(0xFF9A9A9A),
      );

    final color = status == 3
        ? const Color(0xFFC74B6C)
        : const Color(0xFF9A9A9A);
    final icon = status >= 2 ? Icons.done_all_rounded : Icons.done_rounded;

    return Icon(icon, size: 11, color: color);
  }
}
