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
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
    this.radius = 22,
    this.glow = true,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(radius),
        splashColor: Colors.black.withValues(alpha: 0.08),
        highlightColor: Colors.black.withValues(alpha: 0.04),
        child: Ink(
          height: 44,
          padding: padding,
          decoration: BoxDecoration(
            color: enabled ? AppColors.highlight : AppColors.outlineStrong,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: enabled ? Colors.transparent : AppColors.outline,
              width: 1,
            ),
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
