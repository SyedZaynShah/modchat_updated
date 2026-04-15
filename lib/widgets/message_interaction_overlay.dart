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
  static const List<String> defaultEmojis = ['❤️', '😂', '😮', '😢', '😡', '👍'];
  static const double messageMaxWidthRatio = 0.75;
  static const double emojiBarOffset = 50;
  static const double menuOffset = 110;

  static OverlayEntry? _activeEntry;
  static VoidCallback? _activeClose;
  static LocalHistoryEntry? _activeHistoryEntry;
  static ModalRoute<dynamic>? _activeRoute;
  static bool _observerAttached = false;

  static final WidgetsBindingObserver _lifecycleObserver =
      _OverlayLifecycleObserver();

  static void dismiss() {
    try {
      _activeClose?.call();
    } catch (_) {}
  }

  static void _ensureObserverAttached() {
    if (_observerAttached) return;
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _observerAttached = true;
  }

  static void _maybeDetachObserver() {
    if (!_observerAttached) return;
    if (_activeEntry != null) return;
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _observerAttached = false;
  }

  static Future<void> show({
    required BuildContext context,
    required Rect messageRect,
    required ValueChanged<String> onReact,
    required List<MessageActionItem> actions,
    required bool alignToRight,
    String? selectedEmoji,
    bool showReactions = true,
    VoidCallback? onDismiss,
  }) async {
    dismiss();

    _ensureObserverAttached();

    final overlay = Overlay.of(context);

    final route = ModalRoute.of(context);

    late OverlayEntry entry;
    void close() {
      try {
        entry.remove();
      } catch (_) {}

      final activeRoute = _activeRoute;
      final activeHistory = _activeHistoryEntry;
      if (activeRoute != null && activeHistory != null) {
        try {
          activeRoute.removeLocalHistoryEntry(activeHistory);
        } catch (_) {}
      }

      if (identical(_activeEntry, entry)) {
        _activeEntry = null;
        _activeClose = null;
        _activeHistoryEntry = null;
        _activeRoute = null;
      }
      onDismiss?.call();

      _maybeDetachObserver();
    }

    _activeClose = close;

    if (route != null) {
      final history = LocalHistoryEntry(onRemove: close);
      try {
        route.addLocalHistoryEntry(history);
        _activeHistoryEntry = history;
        _activeRoute = route;
      } catch (_) {}
    }

    entry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        const screenPad = 12.0;

        final barW =
            (size.width * messageMaxWidthRatio)
                .clamp(180.0, size.width - (screenPad * 2))
                .toDouble();
        const barH = 56.0;
        final approxMenuH = (actions.length * 44.0) + 16.0;

        final barLeftRaw = alignToRight
            ? (messageRect.right - barW)
            : messageRect.left;
        final barLeft = barLeftRaw.clamp(
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
          ? (messageRect.bottom + 8)
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
                  width: barW,
                  child: _ReactionBar(
                    selectedEmoji: selectedEmoji,
                    alignToRight: alignToRight,
                    onEmojiTap: (e) {
                      onReact(e);
                      close();
                    },
                  ),
                ),
              if (actions.isNotEmpty)
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

    _activeEntry = entry;
    overlay.insert(entry);
  }
}

class _OverlayLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      MessageInteractionOverlay.dismiss();
    }
  }
}

class _ReactionBar extends StatelessWidget {
  final String? selectedEmoji;
  final bool alignToRight;
  final ValueChanged<String> onEmojiTap;
  const _ReactionBar({
    required this.onEmojiTap,
    required this.alignToRight,
    this.selectedEmoji,
  });

  @override
  Widget build(BuildContext context) {
    return _AnimatedReactionBar(
      selectedEmoji: selectedEmoji,
      alignToRight: alignToRight,
      onEmojiTap: onEmojiTap,
    );
  }
}

class _AnimatedReactionBar extends StatefulWidget {
  final String? selectedEmoji;
  final bool alignToRight;
  final ValueChanged<String> onEmojiTap;

  const _AnimatedReactionBar({
    required this.selectedEmoji,
    required this.alignToRight,
    required this.onEmojiTap,
  });

  @override
  State<_AnimatedReactionBar> createState() => _AnimatedReactionBarState();
}

class _AnimatedReactionBarState extends State<_AnimatedReactionBar>
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final maxWidth =
        (MediaQuery.of(context).size.width * MessageInteractionOverlay.messageMaxWidthRatio)
            .clamp(180.0, MediaQuery.of(context).size.width * 0.9)
            .toDouble();
    final anim = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset(widget.alignToRight ? 0.08 : -0.08, 0),
        end: Offset.zero,
      ).animate(anim),
      child: FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(anim),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isLight
                      ? const Color(0xFFE5E7EB)
                      : const Color(0xFF2A2A2A),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isLight ? 0.08 : 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Align(
                  alignment: widget.alignToRight
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (
                        int i = 0;
                        i < MessageInteractionOverlay.defaultEmojis.length;
                        i++
                      ) ...[
                        if (i != 0) const SizedBox(width: 8),
                        _ReactionEmojiButton(
                          emoji: MessageInteractionOverlay.defaultEmojis[i],
                          selectedEmoji: widget.selectedEmoji,
                          onTap: widget.onEmojiTap,
                          isLight: isLight,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactionEmojiButton extends StatefulWidget {
  final String emoji;
  final String? selectedEmoji;
  final ValueChanged<String> onTap;
  final bool isLight;

  const _ReactionEmojiButton({
    required this.emoji,
    required this.selectedEmoji,
    required this.onTap,
    required this.isLight,
  });

  @override
  State<_ReactionEmojiButton> createState() => _ReactionEmojiButtonState();
}

class _ReactionEmojiButtonState extends State<_ReactionEmojiButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedEmoji == widget.emoji;
    final highlightBg = widget.isLight
        ? const Color(0xFF5865F2).withOpacity(0.15)
        : const Color(0xFF5865F2).withOpacity(0.25);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: () => widget.onTap(widget.emoji),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        scale: _pressed ? 0.9 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? highlightBg : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: selected
                ? Border.all(
                    color: const Color(0xFF5865F2).withOpacity(0.55),
                    width: 1,
                  )
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF5865F2).withOpacity(0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.emoji,
            style: const TextStyle(fontSize: 24, height: 1),
          ),
        ),
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
