import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/theme.dart';

class SpotlightNavItem {
  final IconData icon;
  const SpotlightNavItem({required this.icon});
}

class SpotlightNavBar extends StatefulWidget {
  final List<SpotlightNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double height;

  const SpotlightNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.height = 62,
  });

  @override
  State<SpotlightNavBar> createState() => _SpotlightNavBarState();
}

class _SpotlightNavBarState extends State<SpotlightNavBar>
    with TickerProviderStateMixin {
  late AnimationController _markerController;
  late AnimationController _glowController;
  late AnimationController _iconController;

  late Animation<double> _markerAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _iconAnimation;

  late int _previousIndex;
  late int _targetIndex;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.currentIndex;
    _targetIndex = widget.currentIndex;

    _markerController = AnimationController(vsync: this);
    _glowController = AnimationController(vsync: this);
    _iconController = AnimationController(vsync: this);

    _initializeAnimations();
  }

  void _initializeAnimations() {
    _markerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _markerController, curve: Curves.easeInOut),
    );

    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _iconAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _iconController, curve: Curves.easeOut));

    _markerController.value = 1.0;
    _glowController.value = 1.0;
    _iconController.value = 1.0;
  }

  Duration _calculateDuration(int distance) {
    switch (distance) {
      case 1:
        return const Duration(milliseconds: 220);
      case 2:
        return const Duration(milliseconds: 320);
      case 3:
        return const Duration(milliseconds: 420);
      default:
        return const Duration(milliseconds: 220);
    }
  }

  Curve _createCustomCurve() {
    return const Cubic(0.25, 0.1, 0.25, 1.0); // Gentle ease-in-out
  }

  void _startSpotlightTransition(int newIndex) {
    if (_isAnimating || newIndex == _targetIndex) return;

    _isAnimating = true;
    _previousIndex = _targetIndex;
    _targetIndex = newIndex;

    final distance = (newIndex - _previousIndex).abs();
    final duration = _calculateDuration(distance);
    final curve = _createCustomCurve();

    // Reset all animations
    _markerController.reset();
    _glowController.reset();
    _iconController.reset();

    // Set duration for marker controller
    _markerController.duration = duration;
    _glowController.duration = duration;
    _iconController.duration = duration;

    // Layer 1: Marker starts immediately
    _markerAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _markerController, curve: curve));

    // Layer 2: Glow follows with 50ms delay
    _glowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _glowController, curve: curve));

    // Layer 3: Icon changes at 85% completion
    _iconAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _iconController,
        curve: Interval(0.85, 1.0, curve: Curves.easeOut),
      ),
    );

    // Start animations with staggered timing
    _markerController.forward(from: 0.0);

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _glowController.forward(from: 0.0);
      }
    });

    Future.delayed(
      Duration(milliseconds: (duration.inMilliseconds * 0.85).round()),
      () {
        if (mounted) {
          _iconController.forward(from: 0.0);
        }
      },
    );

    // Complete animation sequence
    Future.delayed(duration, () {
      if (mounted) {
        _isAnimating = false;
      }
    });
  }

  Future<void> _handleTap(int index) async {
    // Haptic feedback
    HapticFeedback.lightImpact();

    // Start spotlight transition
    _startSpotlightTransition(index);
    widget.onTap(index);
  }

  @override
  void didUpdateWidget(covariant SpotlightNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _startSpotlightTransition(widget.currentIndex);
    }
  }

  @override
  void dispose() {
    _markerController.dispose();
    _glowController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  double _getMarkerPosition(int index, double width) {
    final count = widget.items.length;
    final tabWidth = width / count;
    return tabWidth * (index + 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final totalHeight = widget.height + bottomInset;

    return Container(
      height: totalHeight,
      padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomInset + 4),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F), // Matte charcoal
          borderRadius: BorderRadius.circular(30),
          border: Border(
            left: BorderSide(color: AppColors.burgundy, width: 2),
            right: BorderSide(color: AppColors.burgundy, width: 2),
            top: BorderSide.none,
            bottom: BorderSide.none,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 24,
              spreadRadius: 0,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 40,
              spreadRadius: 0,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              return AnimatedBuilder(
                animation: Listenable.merge([
                  _markerAnimation,
                  _glowAnimation,
                  _iconAnimation,
                ]),
                builder: (context, child) {
                  final fromX = _getMarkerPosition(_previousIndex, width);
                  final toX = _getMarkerPosition(_targetIndex, width);
                  final currentX = lerpDouble(
                    fromX,
                    toX,
                    _markerAnimation.value,
                  )!;

                  return Stack(
                    children: [
                      // Navigation buttons
                      Positioned.fill(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (int i = 0; i < widget.items.length; i++)
                              _NavButton(
                                item: widget.items[i],
                                isSelected: i == _targetIndex,
                                isTransitioning: _isAnimating,
                                iconProgress: _iconAnimation.value,
                                onTap: () => _handleTap(i),
                              ),
                          ],
                        ),
                      ),

                      // Top marker (locator) - much brighter
                      Positioned(
                        left: currentX - 18,
                        top: 0,
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.burgundy,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.burgundy.withValues(
                                  alpha: 0.8,
                                ),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.3),
                                blurRadius: 6,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Light beam / glow cone - fades when reaching icons
                      Positioned(
                        left: currentX - 22,
                        top: 2,
                        child: Container(
                          width: 44,
                          height: 30,
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0, -0.5),
                              radius: 0.5,
                              colors: [
                                AppColors.burgundy.withValues(
                                  alpha:
                                      (0.8 * (1.0 - _markerAnimation.value)) *
                                      _glowAnimation.value,
                                ),
                                AppColors.burgundy.withValues(
                                  alpha:
                                      (0.5 * (1.0 - _markerAnimation.value)) *
                                      _glowAnimation.value,
                                ),
                                AppColors.burgundy.withValues(
                                  alpha:
                                      (0.2 * (1.0 - _markerAnimation.value)) *
                                      _glowAnimation.value,
                                ),
                                Colors.transparent,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.burgundy.withValues(
                                  alpha:
                                      (0.4 * (1.0 - _markerAnimation.value)) *
                                      _glowAnimation.value,
                                ),
                                blurRadius: 20,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final SpotlightNavItem item;
  final bool isSelected;
  final bool isTransitioning;
  final double iconProgress;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.isTransitioning,
    required this.iconProgress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Icon(
            item.icon,
            size: 22, // Slightly larger since no text
            color: isSelected
                ? Color.lerp(
                    AppColors.white.withValues(alpha: 0.5),
                    AppColors.burgundy,
                    iconProgress,
                  )
                : AppColors.white.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}
