import 'dart:ui';
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(opacity),
            borderRadius: BorderRadius.circular(radius),
            border: const Border(
              top: BorderSide(color: AppColors.sinopia, width: 3),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(0.10),
                offset: const Offset(0, 6),
                blurRadius: 20,
              ),
              if (glow)
                BoxShadow(
                  color: AppColors.sinopia.withOpacity(0.18),
                  blurRadius: 24,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: child,
        ),
      ),
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
    final bg = widget.filled ? AppColors.navy : Colors.transparent;
    final fg = widget.filled ? Colors.white : AppColors.navy;
    final border = AppColors.navy;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.loading ? null : widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.loading ? bg.withOpacity(0.7) : bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.sinopia.withOpacity(
                  widget.filled ? 0.22 : 0.10,
                ),
                blurRadius: 22,
                spreadRadius: 1,
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
