import 'package:flutter/material.dart';
import '../theme/theme.dart';

class GlassButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool glow;

  const GlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.radius = 16,
    this.glow = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(radius),
      child: AppTheme.glass(
        radius: radius,
        child: Container(
          decoration: AppTheme.glassDecoration(radius: radius, glow: glow),
          padding: padding,
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Color(0xFF1E1E1E)),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
