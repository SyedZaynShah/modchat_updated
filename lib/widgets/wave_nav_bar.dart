import 'dart:math' as math;
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
    this.barColor = AppColors.navy,
    this.iconColor = AppColors.white,
    this.activeIconColor = AppColors.navy,
    this.cornerRadius = 24,
    this.duration = const Duration(milliseconds: 420),
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
              final t = Curves.easeInOutCubicEmphasized.transform(
                _controller.value,
              );

              final fromX = _indexCenterX(_fromIndex, width);
              final toX = _indexCenterX(widget.currentIndex, width);
              final centerX = lerpDouble(fromX, toX, t)!;

              final count = widget.items.length;
              final tabWidth = width / count;

              // 🔥 WIDER & SMOOTHER WAVE
              final baseWaveWidth = tabWidth * 1.45;
              final intendedWidth = baseWaveWidth + 8 * math.sin(t * math.pi);
              final waveWidth = intendedWidth.clamp(
                tabWidth * 1.35,
                tabWidth * 1.55,
              );

              // 🔥 DEEPER DIP
              final maxDepth = widget.height - 2.0;
              final baseDepth = widget.height - 4.0;
              final intendedDepth = baseDepth + 6 * math.sin(t * math.pi);
              final depth = intendedDepth.clamp(0.0, maxDepth);

              return ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(widget.cornerRadius),
                  topRight: Radius.circular(widget.cornerRadius),
                ),
                child: CustomPaint(
                  painter: _WaveBarPainter(
                    color: widget.barColor,
                    centerX: centerX,
                    waveWidth: waveWidth,
                    depth: depth,
                    cornerRadius: widget.cornerRadius,
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: widget.height,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (int i = 0; i < widget.items.length; i++)
                            _NavButton(
                              item: widget.items[i],
                              selected: i == widget.currentIndex,
                              onTap: () => widget.onTap(i),
                              iconColor: widget.iconColor,
                              activeIconColor: widget.activeIconColor,
                              lift:
                                  -6 *
                                  math.sin(t * math.pi) *
                                  (i == widget.currentIndex ? 1 : 0),
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

class _NavButton extends StatelessWidget {
  final WaveNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final Color iconColor;
  final Color activeIconColor;
  final double lift;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.iconColor,
    required this.activeIconColor,
    required this.lift,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeIconColor : iconColor.withOpacity(0.92);
    return Expanded(
      child: InkResponse(
        onTap: onTap,
        splashColor: AppColors.white.withOpacity(0.08),
        highlightColor: Colors.transparent,
        radius: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: Offset(0, lift),
                child: Icon(item.icon, color: color, size: 26),
              ),
              const SizedBox(height: 6),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaveBarPainter extends CustomPainter {
  final Color color;
  final double centerX;
  final double waveWidth;
  final double depth;
  final double cornerRadius;

  _WaveBarPainter({
    required this.color,
    required this.centerX,
    required this.waveWidth,
    required this.depth,
    required this.cornerRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    final double start = (centerX - waveWidth / 2).clamp(0.0, w);
    final double end = (centerX + waveWidth / 2).clamp(0.0, w);

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(start, 0);

    // 🔥 WIDER CONTROL POINTS
    final double c1x = start + waveWidth * 0.40;
    final double c2x = centerX - waveWidth * 0.35;
    path.cubicTo(c1x, 0, c2x, depth, centerX, depth);

    final double c3x = centerX + waveWidth * 0.35;
    final double c4x = end - waveWidth * 0.40;
    path.cubicTo(c3x, depth, c4x, 0, end, 0);

    path.lineTo(w, 0);
    path.lineTo(w, h);
    path.lineTo(0, h);
    path.close();

    canvas.drawShadow(path, Colors.black.withOpacity(0.16), 12, false);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WaveBarPainter oldDelegate) {
    return oldDelegate.centerX != centerX ||
        oldDelegate.waveWidth != waveWidth ||
        oldDelegate.depth != depth ||
        oldDelegate.color != color;
  }
}
