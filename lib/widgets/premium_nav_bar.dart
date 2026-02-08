import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/theme.dart';

class PremiumNavItem {
  final IconData icon;
  final String label;
  const PremiumNavItem({required this.icon, required this.label});
}

class PremiumNavBar extends StatefulWidget {
  final List<PremiumNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double height;
  final Duration duration;

  const PremiumNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.height = 60,
    this.duration = const Duration(milliseconds: 275),
  });

  @override
  State<PremiumNavBar> createState() => _PremiumNavBarState();
}

class _PremiumNavBarState extends State<PremiumNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _indicatorAnimation;
  late int _previousIndex;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.currentIndex;
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _indicatorAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant PremiumNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _previousIndex = oldWidget.currentIndex;
      _controller
        ..stop()
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _getIndicatorPosition(int index, double width) {
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
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A), // Near-black charcoal
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            return AnimatedBuilder(
              animation: _indicatorAnimation,
              builder: (context, child) {
                final fromX = _getIndicatorPosition(_previousIndex, width);
                final toX = _getIndicatorPosition(widget.currentIndex, width);
                final currentX = lerpDouble(
                  fromX,
                  toX,
                  _indicatorAnimation.value,
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
                              isSelected: i == widget.currentIndex,
                              onTap: () => widget.onTap(i),
                            ),
                        ],
                      ),
                    ),

                    // Minimal indicator bar - solid burgundy, no effects
                    Positioned(
                      left: currentX - 20,
                      top: 0,
                      child: Container(
                        width: 40,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppColors.burgundy,
                          borderRadius: BorderRadius.circular(1.5),
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
    );
  }
}

class _NavButton extends StatelessWidget {
  final PremiumNavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon with gradient for active state
              SizedBox(
                width: 24,
                height: 24,
                child: isSelected
                    ? ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [AppColors.burgundy, AppColors.white],
                        ).createShader(bounds),
                        child: Icon(item.icon, size: 24, color: Colors.white),
                      )
                    : Icon(item.icon, size: 24, color: AppColors.white),
              ),
              const SizedBox(height: 6),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.white
                      : AppColors.white.withValues(alpha: 0.70),
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
