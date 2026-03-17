import 'package:flutter/material.dart';

class MessageActionItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;
  const MessageActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
}

class MessageInteractionOverlay {
  static const List<String> defaultEmojis = ['👍', '❤️', '😂', '😮', '😢'];
  static const double emojiBarOffset = 50;
  static const double menuOffset = 110;

  static Future<void> show({
    required BuildContext context,
    required Rect messageRect,
    required ValueChanged<String> onReact,
    required List<MessageActionItem> actions,
    bool showReactions = true,
    VoidCallback? onDismiss,
  }) async {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    late OverlayEntry entry;
    void close() {
      try {
        entry.remove();
      } catch (_) {}
      onDismiss?.call();
    }

    entry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        const screenPad = 12.0;

        final barW =
            6 +
            (defaultEmojis.length * 24) +
            ((defaultEmojis.length - 1) * 12) +
            6;
        const barH = 44.0;
        final approxMenuH = (actions.length * 44.0) + 16.0;

        final barLeft = (messageRect.center.dx - (barW / 2)).clamp(
          screenPad,
          size.width - barW - screenPad,
        );

        final fitsBelow =
            messageRect.bottom + menuOffset + approxMenuH <=
            (size.height - screenPad);
        final fitsAbove =
            messageRect.top - menuOffset - approxMenuH >=
            (screenPad + MediaQuery.of(ctx).padding.top);
        final placeBelow = fitsBelow || !fitsAbove;

        final barTopUnclamped = placeBelow
            ? (messageRect.bottom + emojiBarOffset)
            : (messageRect.top - emojiBarOffset);
        final menuTopUnclamped = placeBelow
            ? (messageRect.bottom + menuOffset)
            : (messageRect.top - menuOffset - approxMenuH);

        final minTop = screenPad + MediaQuery.of(ctx).padding.top;
        final maxTop = size.height - screenPad;

        final barTop = barTopUnclamped.clamp(minTop, maxTop - barH);

        double menuTop = menuTopUnclamped.clamp(minTop, maxTop - approxMenuH);
        if (showReactions) {
          if (placeBelow) {
            final minMenuTop = barTop + barH + 6;
            if (menuTop < minMenuTop) menuTop = minMenuTop;
          } else {
            final maxMenuBottom = barTop - 6;
            final desiredTop = maxMenuBottom - approxMenuH;
            if (menuTop > desiredTop) menuTop = desiredTop;
          }
        }
        menuTop = menuTop.clamp(minTop, maxTop - approxMenuH);

        const menuMaxW = 220.0;
        final menuLeft = (messageRect.center.dx - (menuMaxW / 2)).clamp(
          screenPad,
          size.width - menuMaxW - screenPad,
        );

        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: close,
                  child: Container(color: Colors.black.withOpacity(0.35)),
                ),
              ),
              if (showReactions)
                Positioned(
                  left: barLeft,
                  top: barTop,
                  child: _ReactionBar(
                    onEmojiTap: (e) {
                      onReact(e);
                      close();
                    },
                  ),
                ),
              Positioned(
                left: menuLeft,
                top: menuTop,
                width: menuMaxW,
                child: _FloatingActionMenu(actions: actions, onClose: close),
              ),
            ],
          ),
        );
      },
    );

    overlay.insert(entry);
  }
}

class _ReactionBar extends StatelessWidget {
  final ValueChanged<String> onEmojiTap;
  const _ReactionBar({required this.onEmojiTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (
            int i = 0;
            i < MessageInteractionOverlay.defaultEmojis.length;
            i++
          ) ...[
            if (i != 0) const SizedBox(width: 12),
            InkWell(
              onTap: () =>
                  onEmojiTap(MessageInteractionOverlay.defaultEmojis[i]),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Text(
                  MessageInteractionOverlay.defaultEmojis[i],
                  style: const TextStyle(fontSize: 24, height: 1),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FloatingActionMenu extends StatefulWidget {
  final List<MessageActionItem> actions;
  final VoidCallback onClose;
  const _FloatingActionMenu({required this.actions, required this.onClose});

  @override
  State<_FloatingActionMenu> createState() => _FloatingActionMenuState();
}

class _FloatingActionMenuState extends State<_FloatingActionMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1.0).animate(anim),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 18,
                spreadRadius: 1,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in widget.actions)
                _ActionRow(
                  icon: a.icon,
                  label: a.label,
                  isDestructive: a.isDestructive,
                  onTap: () {
                    widget.onClose();
                    a.onTap();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDestructive;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDestructive,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.redAccent : Colors.white;
    return SizedBox(
      height: 44,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color.withOpacity(0.9)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
