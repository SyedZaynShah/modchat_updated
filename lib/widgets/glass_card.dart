import 'package:flutter/material.dart';
import '../theme/theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool glow;

  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 16, this.glow = true});

  @override
  Widget build(BuildContext context) {
    return AppTheme.glass(
      radius: radius,
      child: Container(
        decoration: AppTheme.glassDecoration(radius: radius, glow: glow),
        padding: padding,
        child: child,
      ),
    );
  }
}
