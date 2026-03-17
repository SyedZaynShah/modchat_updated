import 'package:flutter/material.dart';
import '../theme/theme.dart';

class GlassDropdownItem {
  final String value;
  final String label;
  final IconData icon;
  final Color? iconColor;
  final bool isDestructive;

  const GlassDropdownItem({
    required this.value,
    required this.label,
    required this.icon,
    this.iconColor,
    this.isDestructive = false,
  });
}

class GlassDropdown extends StatefulWidget {
  final List<GlassDropdownItem> items;
  final Function(String) onSelected;
  final Widget child;
  final String? tooltip;
  final Offset offset;
  final PopupMenuPosition position;
  final double width;

  const GlassDropdown({
    super.key,
    required this.items,
    required this.onSelected,
    required this.child,
    this.tooltip,
    this.offset = const Offset(0, 8),
    this.position = PopupMenuPosition.under,
    this.width = 220,
  });

  @override
  State<GlassDropdown> createState() => _GlassDropdownState();
}

class _GlassDropdownState extends State<GlassDropdown> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  void _toggleDropdown() {
    if (_isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _closeDropdown() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _isOpen = false);
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: _closeDropdown,
            behavior: HitTestBehavior.translucent,
            child: Container(
              color: Colors.transparent,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: widget.offset,
            targetAnchor: widget.position == PopupMenuPosition.under
                ? Alignment.bottomRight
                : Alignment.topRight,
            followerAnchor: Alignment.topRight,
            child: Material(
              color: Colors.transparent,
              child: _DropdownMenu(
                items: widget.items,
                width: widget.width,
                onSelected: (val) {
                  _closeDropdown();
                  widget.onSelected(val);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: _toggleDropdown,
        borderRadius: BorderRadius.circular(12),
        child: widget.child,
      ),
    );
  }
}

class _DropdownMenu extends StatefulWidget {
  final List<GlassDropdownItem> items;
  final double width;
  final ValueChanged<String> onSelected;

  const _DropdownMenu({
    required this.items,
    required this.width,
    required this.onSelected,
  });

  @override
  State<_DropdownMenu> createState() => _DropdownMenuState();
}

class _DropdownMenuState extends State<_DropdownMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            alignment: Alignment.topRight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: widget.width,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.outline, width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final isLast = index == widget.items.length - 1;

                    return _DropdownTile(
                      item: item,
                      isLast: isLast,
                      onTap: () => widget.onSelected(item.value),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DropdownTile extends StatefulWidget {
  final GlassDropdownItem item;
  final bool isLast;
  final VoidCallback onTap;

  const _DropdownTile({
    required this.item,
    required this.isLast,
    required this.onTap,
  });

  @override
  State<_DropdownTile> createState() => _DropdownTileState();
}

class _DropdownTileState extends State<_DropdownTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.item.isDestructive
        ? Colors.redAccent
        : (widget.item.iconColor ?? AppColors.highlight);

    return InkWell(
      onTap: widget.onTap,
      onHover: (hovering) => setState(() => _isHovered = hovering),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _isHovered ? AppColors.surface : Colors.transparent,
          border: widget.isLast
              ? null
              : Border(bottom: BorderSide(color: AppColors.outline, width: 1)),
        ),
        child: Row(
          children: [
            Icon(widget.item.icon, size: 18, color: baseColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.item.label,
                style: TextStyle(
                  color: baseColor.withValues(alpha: 0.95),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
