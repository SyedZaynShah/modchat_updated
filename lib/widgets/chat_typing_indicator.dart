import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ChatTypingIndicator extends StatefulWidget {
  const ChatTypingIndicator({
    super.key,
    required this.chatId,
    required this.currentUid,
    required this.isGroup,
    this.peerId,
    this.blockedUserIds = const <String>{},
    this.hideIndicator = false,
  });

  final String chatId;
  final String currentUid;
  final bool isGroup;
  final String? peerId;
  final Set<String> blockedUserIds;
  final bool hideIndicator;

  @override
  State<ChatTypingIndicator> createState() => _ChatTypingIndicatorState();
}

class _ChatTypingIndicatorState extends State<ChatTypingIndicator> {
  final Map<String, String> _nameCache = <String, String>{};
  final Set<String> _resolving = <String>{};
  static const Duration _staleAfter = Duration(seconds: 5);

  @override
  Widget build(BuildContext context) {
    if (widget.hideIndicator) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('dmChats')
          .doc(widget.chatId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final rawTyping = Map<String, dynamic>.from(
          (data['typing'] as Map?) ?? const <String, dynamic>{},
        );

        final typingUsers = rawTyping.entries
            .where((entry) {
              final typed = _entryToTypingState(entry.value);
              if (!typed.active) return false;
              if (typed.timestamp != null) {
                final age = DateTime.now().difference(typed.timestamp!);
                if (age > _staleAfter) return false;
              }
              return true;
            })
            .map((entry) => entry.key)
            .where((uid) => uid != widget.currentUid)
            .where((uid) => !widget.blockedUserIds.contains(uid))
            .where((uid) {
              if (widget.isGroup) return true;
              if (widget.peerId == null || widget.peerId!.isEmpty) {
                return true;
              }
              return uid == widget.peerId;
            })
            .toList()
          ..sort();

        final voiceUsers = typingUsers.where((uid) {
          final state = _entryToTypingState(rawTyping[uid]);
          return state.type == 'voice';
        }).toList();

        final textUsers = typingUsers.where((uid) {
          final state = _entryToTypingState(rawTyping[uid]);
          return state.type != 'voice';
        }).toList();

        final hasRemoteTyping = typingUsers.isNotEmpty;
        if (!hasRemoteTyping) return const SizedBox.shrink();

        for (final uid in typingUsers) {
          _resolveName(uid);
        }

        final label = _labelFor(textUsers);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final textColor = isDark ? Colors.white70 : const Color(0xFF1C1C1C);
        final background = isDark
            ? const Color(0xFF1A1A1A)
            : const Color(0xFFF2F3F5);
        final bubbleShadow = isDark
            ? const <BoxShadow>[]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ];

        final showVoiceUI = voiceUsers.isNotEmpty;
        final bubbleContent = showVoiceUI
            ? _VoiceRecordingRow(
                textColor: textColor,
                leading: widget.isGroup
                    ? _avatarStrip(
                        users: voiceUsers,
                      )
                    : null,
              )
            : _TextTypingRow(
                textColor: textColor,
                label: label,
                leading: widget.isGroup
                    ? _avatarStrip(
                        users: textUsers,
                      )
                    : null,
              );

        return RepaintBoundary(
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.2),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Container(
                key: ValueKey<String>(
                  '${typingUsers.join('_')}_${widget.isGroup}_${showVoiceUI}',
                ),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: bubbleShadow,
                ),
                child: bubbleContent,
              ),
            ),
          ),
        );
      },
    );
  }

  _ParsedTypingState _entryToTypingState(dynamic raw) {
    if (raw is bool) {
      return _ParsedTypingState(active: raw, type: raw ? 'text' : null);
    }
    final map = Map<String, dynamic>.from((raw as Map?) ?? const {});
    final active = (map['active'] as bool?) ?? false;
    final type = (map['type'] as String?)?.trim();
    final tsRaw = map['timestamp'];
    final ts = tsRaw is Timestamp ? tsRaw.toDate() : null;
    return _ParsedTypingState(active: active, type: type, timestamp: ts);
  }

  Widget _avatarStrip({
    required List<String> users,
  }) {
    final top = users.take(3).toList();
    final extra = users.length - top.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...top.map((uid) => _TypingAvatar(label: _nameCache[uid] ?? uid)),
        if (extra > 0)
          _TypingAvatar(label: '+$extra', forceText: true),
        const SizedBox(width: 6),
      ],
    );
  }

  String _labelFor(List<String> typingUsers) {
    String nameFor(String uid) => _nameCache[uid] ?? uid;

    if (typingUsers.isEmpty) {
      return 'Typing...';
    }
    if (!widget.isGroup) {
      return '${nameFor(typingUsers.first)} is typing...';
    }
    if (typingUsers.length == 1) {
      return '${nameFor(typingUsers.first)} is typing...';
    }
    if (typingUsers.length == 2) {
      return '${nameFor(typingUsers[0])} & ${nameFor(typingUsers[1])}';
    }
    return '${typingUsers.length} people typing';
  }

  Future<void> _resolveName(String uid) async {
    if (_nameCache.containsKey(uid) || _resolving.contains(uid)) return;
    _resolving.add(uid);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data() ?? const <String, dynamic>{};
      final resolved =
          ((data['name'] as String?) ?? (data['displayName'] as String?) ?? '')
              .trim();

      if (!mounted) return;
      setState(() {
        _nameCache[uid] = resolved.isEmpty ? uid : resolved;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nameCache[uid] = uid;
      });
    } finally {
      _resolving.remove(uid);
    }
  }
}

class _TextTypingRow extends StatelessWidget {
  const _TextTypingRow({
    required this.textColor,
    required this.label,
    this.leading,
  });

  final Color textColor;
  final String label;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) leading!,
        const _TypingDots(),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: textColor,
          ),
        ),
      ],
    );
  }
}

class _VoiceRecordingRow extends StatelessWidget {
  const _VoiceRecordingRow({required this.textColor, this.leading});

  final Color textColor;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) leading!,
        const _PulseMic(),
        const SizedBox(width: 8),
        Text(
          'Recording...',
          style: TextStyle(fontSize: 13, color: textColor),
        ),
      ],
    );
  }
}

class _TypingAvatar extends StatelessWidget {
  const _TypingAvatar({required this.label, this.forceText = false});

  final String label;
  final bool forceText;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white70 : Colors.black87;
    final bg = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF2F3F5);
    final trimmed = label.trim();
    final initial = forceText
      ? trimmed
      : (trimmed.isEmpty ? '?' : trimmed[0].toUpperCase());

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: CircleAvatar(
        radius: 16,
        backgroundColor: bg,
        child: Text(
          initial,
          style: TextStyle(
            fontSize: forceText ? 10 : 11,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dotColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          children: List.generate(3, (index) {
            return _DotPulse(
              progress: _controller.value,
              delayMs: index * 200,
              color: dotColor,
              width: 4,
              height: 4,
            );
          }),
        );
      },
    );
  }
}

class _DotPulse extends StatelessWidget {
  const _DotPulse({
    required this.progress,
    required this.delayMs,
    required this.color,
    this.width = 6,
    this.height = 6,
  });

  final double progress;
  final int delayMs;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final shifted = (progress + (delayMs / 900)) % 1.0;
    final wave = 0.5 + 0.5 * math.sin(2 * math.pi * shifted);
    final scale = 0.6 + (wave * 0.4);
    final opacity = 0.3 + (wave * 0.7);

    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          width: width,
          height: height,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _PulseMic extends StatefulWidget {
  const _PulseMic();

  @override
  State<_PulseMic> createState() => _PulseMicState();
}

class _PulseMicState extends State<_PulseMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 1.0, end: 1.3).animate(_controller),
      child: const Icon(Icons.mic, color: Color(0xFFE57373), size: 16),
    );
  }
}

class _ParsedTypingState {
  const _ParsedTypingState({
    required this.active,
    this.type,
    this.timestamp,
  });

  final bool active;
  final String? type;
  final DateTime? timestamp;
}
