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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
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
        ? ref
              .watch(userDocProvider(senderId))
              .maybeWhen(
                data: (u) {
                  final n = (u?.name ?? '').trim();
                  return n.isNotEmpty ? n : senderLabelFallback();
                },
                orElse: senderLabelFallback,
              )
        : senderLabelFallback();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 72),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isLight ? const Color(0xFFF3F4F6) : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLight ? const Color(0xFFD1D5DB) : const Color(0xFF1A1A1A),
            width: 1,
          ),
        ),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Container(
                  width: 3,
                  height: 40,
                  color: const Color(0xFF5865F2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      senderLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isLight
                            ? const Color(0xFF111827)
                            : const Color(0xFF5865F2),
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      target.previewText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isLight
                            ? const Color(0xFF4B5563)
                            : const Color(0xFFA5A5A5),
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onCancel,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(child: Icon(Icons.close_rounded, size: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
