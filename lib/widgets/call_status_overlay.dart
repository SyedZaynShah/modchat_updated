import 'package:flutter/material.dart';
import '../models/call_state.dart';

/// Overlay widget that shows call status and auto-dismisses terminal states
class CallStatusOverlay extends StatefulWidget {
  final CallState status;
  final VoidCallback onDismiss;
  final Duration displayDuration;

  const CallStatusOverlay({
    super.key,
    required this.status,
    required this.onDismiss,
    this.displayDuration = const Duration(seconds: 2),
  });

  @override
  State<CallStatusOverlay> createState() => _CallStatusOverlayState();
}

class _CallStatusOverlayState extends State<CallStatusOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    // Auto-dismiss terminal states after delay
    if (widget.status.isTerminal) {
      Future.delayed(widget.displayDuration, () {
        if (mounted) {
          _controller.reverse().then((_) {
            if (mounted) {
              widget.onDismiss();
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        decoration: BoxDecoration(
          color: _getBackgroundColor(),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _getIcon(),
            const SizedBox(width: 12),
            Text(
              widget.status.displayText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getBackgroundColor() {
    switch (widget.status) {
      case CallState.calling:
      case CallState.ringing:
        return const Color(0xFF5865F2); // Blue
      case CallState.accepted:
        return const Color(0xFF10B981); // Green
      case CallState.declined:
      case CallState.failed:
        return const Color(0xFFEF4444); // Red
      case CallState.missed:
      case CallState.cancelled:
        return const Color(0xFFF59E0B); // Orange
      case CallState.ended:
        return const Color(0xFF6B7280); // Gray
    }
  }

  Widget _getIcon() {
    IconData iconData;
    
    switch (widget.status) {
      case CallState.calling:
      case CallState.ringing:
        iconData = Icons.phone_in_talk;
        break;
      case CallState.accepted:
        iconData = Icons.check_circle;
        break;
      case CallState.declined:
        iconData = Icons.call_end;
        break;
      case CallState.missed:
        iconData = Icons.phone_missed;
        break;
      case CallState.cancelled:
        iconData = Icons.cancel;
        break;
      case CallState.ended:
        iconData = Icons.call_end;
        break;
      case CallState.failed:
        iconData = Icons.error;
        break;
    }

    return Icon(
      iconData,
      color: Colors.white,
      size: 24,
    );
  }
}

/// Show a call status overlay at the top of the screen
void showCallStatusOverlay(BuildContext context, CallState status) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: CallStatusOverlay(
          status: status,
          onDismiss: () {
            entry.remove();
          },
        ),
      ),
    ),
  );

  overlay.insert(entry);
}
