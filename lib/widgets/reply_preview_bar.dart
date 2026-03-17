import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/reply_target.dart';
import '../providers/user_providers.dart';

class ReplyPreviewBar extends ConsumerWidget {
  final ReplyTarget target;
  final VoidCallback onCancel;
  final bool isGroup;
  final String myUid;
  final String? dmPeerName;

  const ReplyPreviewBar({
    super.key,
    required this.target,
    required this.onCancel,
    required this.isGroup,
    required this.myUid,
    this.dmPeerName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final senderId = target.senderId;

    String senderLabelFallback() {
      if (!isGroup) {
        if (senderId == myUid) return 'You';
        final n = (dmPeerName ?? '').trim();
        return n.isNotEmpty ? n : senderId;
      }
      if (senderId == myUid) return 'You';
      return senderId;
    }

    final senderLabel = isGroup && senderId.isNotEmpty
        ? ref.watch(userDocProvider(senderId)).maybeWhen(
              data: (u) {
                final n = (u?.name ?? '').trim();
                return n.isNotEmpty ? n : senderLabelFallback();
              },
              orElse: senderLabelFallback,
            )
        : senderLabelFallback();

    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1A1A1A), width: 1),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Container(
              width: 3,
              height: double.infinity,
              color: const Color(0xFFC74B6C),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  senderLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFC74B6C),
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  target.previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFA5A5A5),
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onCancel,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(
              width: 28,
              height: 28,
              child: Center(
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFFA5A5A5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
