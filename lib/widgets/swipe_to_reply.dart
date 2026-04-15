import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;
  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  static const double _maxDx = 80;
  static const double _threshold = 40;

  double _dx = 0;
  late final AnimationController _reset;

  @override
  void initState() {
    super.initState();
    _reset = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    )..addListener(() {
        setState(() {
          _dx = _dx * (1 - _reset.value);
        });
      });
  }

  @override
  void dispose() {
    _reset.dispose();
    super.dispose();
  }

  void _animateReset() {
    _reset.stop();
    _reset.reset();
    _reset.forward();
  }

  @override
  Widget build(BuildContext context) {
    final t = (_dx / _threshold).clamp(0.0, 1.0);
    final opacity = Curves.easeOut.transform(t);
    final scale = 0.8 + 0.2 * opacity;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: widget.enabled
          ? (d) {
              final next = (_dx + d.delta.dx).clamp(0.0, _maxDx);
              if (next != _dx) setState(() => _dx = next);
            }
          : null,
      onHorizontalDragEnd: widget.enabled
          ? (_) {
              final shouldReply = _dx >= _threshold;
              _animateReset();
              if (shouldReply) {
                HapticFeedback.lightImpact();
                widget.onReply();
              }
            }
          : null,
      onHorizontalDragCancel: widget.enabled
          ? () {
              _animateReset();
            }
          : null,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: opacity,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  child: AnimatedScale(
                    scale: scale,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: const Icon(
                      Icons.reply_rounded,
                      size: 20,
                      color: Color(0xFF5865F2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

