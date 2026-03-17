import 'package:flutter/material.dart';
import '../../theme/theme.dart';

const Color kAccentBlue = Color(0xFF00AFFF);

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final double opacity;
  final bool glow;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = 20,
    this.blur = 22,
    this.opacity = 0.20,
    this.glow = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: AppColors.card,
        border: Border.all(color: AppColors.outline, width: 1),
      ),
      child: child,
    );
  }
}

class BlueButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String label;
  final bool loading;
  final bool filled;
  final IconData? icon;
  final double height;

  const BlueButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.loading = false,
    this.filled = true,
    this.icon,
    this.height = 44,
  });

  @override
  State<BlueButton> createState() => _BlueButtonState();
}

class _BlueButtonState extends State<BlueButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.filled ? Colors.black : AppColors.highlight;
    final border = widget.filled ? Colors.transparent : AppColors.outlineStrong;
    final bg = widget.filled ? AppColors.highlight : Colors.transparent;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.loading ? null : widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: border, width: 1),
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 18, color: fg),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: fg,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
