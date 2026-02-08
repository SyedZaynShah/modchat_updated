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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.cardTop, AppColors.cardBottom],
        ),
        border: Border.all(color: AppColors.outline.withOpacity(0.9), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 28,
            spreadRadius: -10,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 10,
            spreadRadius: -8,
            offset: const Offset(0, 6),
          ),
        ],
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
    this.height = 50,
  });

  @override
  State<BlueButton> createState() => _BlueButtonState();
}

class _BlueButtonState extends State<BlueButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.filled ? AppColors.highlight : AppColors.highlight;
    final border = widget.filled ? Colors.transparent : AppColors.outline;

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
            gradient: widget.filled
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.navy.withOpacity(widget.loading ? 0.82 : 0.95),
                      AppColors.navy.withOpacity(widget.loading ? 0.70 : 0.88),
                    ],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.cardTop, AppColors.cardBottom],
                  ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(widget.filled ? 0.45 : 0.30),
                blurRadius: 26,
                spreadRadius: -14,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
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
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
