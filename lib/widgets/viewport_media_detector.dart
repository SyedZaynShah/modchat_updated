import 'package:flutter/material.dart';

class ViewportMediaDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback? onViewportEnter;

  const ViewportMediaDetector({
    super.key,
    required this.child,
    this.onViewportEnter,
  });

  @override
  State<ViewportMediaDetector> createState() => _ViewportMediaDetectorState();
}

class _ViewportMediaDetectorState extends State<ViewportMediaDetector> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onViewportEnter?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
