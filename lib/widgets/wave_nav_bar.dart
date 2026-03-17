import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/theme.dart';

class WaveNavItem {
  final IconData icon;
  final String label;
  const WaveNavItem({required this.icon, required this.label});
}

class WaveNavBar extends StatefulWidget {
  final List<WaveNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double height;
  final Color barColor;
  final Color iconColor;
  final Color activeIconColor;
  final double cornerRadius;
  final Duration duration;

  const WaveNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.height = 70,
    this.barColor = AppColors.surface,
    this.iconColor = AppColors.iconMuted,
    this.activeIconColor = AppColors.navy,
    this.cornerRadius = 24,
    this.duration = const Duration(milliseconds: 280),
  });

  @override
  State<WaveNavBar> createState() => _WaveNavBarState();
}

class _WaveNavBarState extends State<WaveNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late int _fromIndex;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.currentIndex;
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant WaveNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _fromIndex = oldWidget.currentIndex;
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

  double _indexCenterX(int index, double width) {
    final count = widget.items.length;
    final tabWidth = width / count;
    return tabWidth * (index + 0.5);
  }

  double _delayedT(double t) {
    final d = ((t - 0.16) / 0.84).clamp(0.0, 1.0);
    return Curves.easeInOut.transform(d);
  }

  Widget _gradientIcon(IconData icon, double size, double opacity) {
    return Opacity(
      opacity: opacity,
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.burgundy, Colors.white],
          ).createShader(rect);
        },
        child: Icon(icon, size: size, color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final barHeight = widget.height + bottomInset;

    return SizedBox(
      height: barHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = Curves.easeInOut.transform(_controller.value);
              final iconT = _delayedT(_controller.value);

              final count = widget.items.length;
              final tabWidth = width / count;

              final fromX = _indexCenterX(_fromIndex, width);
              final toX = _indexCenterX(widget.currentIndex, width);
              final centerX = lerpDouble(fromX, toX, t)!;

              final indicatorWidth = (tabWidth * 0.58).clamp(30.0, 62.0);
              final indicatorLeft = (centerX - indicatorWidth / 2).clamp(
                0.0,
                width - indicatorWidth,
              );

              final radius = widget.cornerRadius.clamp(28.0, 32.0);

              return SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    height: widget.height,
                    decoration: BoxDecoration(
                      color: widget.barColor,
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.45),
                          blurRadius: 38,
                          spreadRadius: -18,
                          offset: const Offset(0, 18),
                        ),
                        BoxShadow(
                          color: Colors.black.withOpacity(0.20),
                          blurRadius: 18,
                          spreadRadius: -18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      border: Border.all(
                        color: AppColors.outline.withOpacity(0.65),
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: Stack(
                        children: [
                          Positioned(
                            top: 10,
                            left: indicatorLeft,
                            child: Container(
                              width: indicatorWidth,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.burgundy,
                                borderRadius: BorderRadius.circular(99),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.burgundy.withValues(
                                      alpha: 0.18,
                                    ),
                                    blurRadius: 18,
                                    spreadRadius: -14,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              for (int i = 0; i < widget.items.length; i++)
                                _LampNavButton(
                                  item: widget.items[i],
                                  index: i,
                                  fromIndex: _fromIndex,
                                  toIndex: widget.currentIndex,
                                  iconT: iconT,
                                  onTap: () => widget.onTap(i),
                                  iconColor: widget.iconColor,
                                  activeGradientBuilder: _gradientIcon,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _LampNavButton extends StatelessWidget {
  final WaveNavItem item;
  final int index;
  final int fromIndex;
  final int toIndex;
  final double iconT;
  final VoidCallback onTap;
  final Color iconColor;
  final Widget Function(IconData icon, double size, double opacity)
  activeGradientBuilder;

  const _LampNavButton({
    required this.item,
    required this.index,
    required this.fromIndex,
    required this.toIndex,
    required this.iconT,
    required this.onTap,
    required this.iconColor,
    required this.activeGradientBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final isFrom = index == fromIndex;
    final isTo = index == toIndex;

    double activeOpacity = 0.0;
    if (isTo) {
      activeOpacity = iconT;
    } else if (isFrom) {
      activeOpacity = 1.0 - iconT;
    } else {
      activeOpacity = 0.0;
    }

    final inactiveOpacity = (isTo || isFrom) ? (1.0 - activeOpacity) : 0.93;

    final labelOpacity = (isTo)
        ? (0.70 + 0.30 * iconT)
        : (isFrom)
        ? (0.70 + 0.30 * (1.0 - iconT))
        : 0.70;

    return Expanded(
      child: InkResponse(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        radius: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 26,
                width: 26,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: inactiveOpacity,
                      child: Icon(
                        item.icon,
                        size: 24,
                        color: iconColor.withOpacity(0.98),
                      ),
                    ),
                    activeGradientBuilder(item.icon, 24, activeOpacity),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Opacity(
                opacity: labelOpacity,
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.highlight.withOpacity(0.92),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
