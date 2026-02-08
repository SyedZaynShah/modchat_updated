import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class CustomField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final bool enableToggle;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final void Function(String)? onSubmitted;
  final IconData? prefixIcon;

  const CustomField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.enableToggle = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.prefixIcon,
  });

  @override
  State<CustomField> createState() => _CustomFieldState();
}

class _CustomFieldState extends State<CustomField> {
  late bool _obscure;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscure;
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.cardTop, AppColors.cardBottom],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focus.hasFocus
                ? AppColors.outline.withOpacity(1.0)
                : AppColors.outline.withOpacity(0.8),
            width: 1,
          ),
          boxShadow: _focus.hasFocus
              ? [
                  BoxShadow(
                    color: AppColors.navy.withOpacity(0.10),
                    blurRadius: 28,
                    spreadRadius: -10,
                    offset: const Offset(0, 16),
                  ),
                ]
              : [],
        ),
        child: TextField(
          controller: widget.controller,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
          obscureText: _obscure,
          style: const TextStyle(
            fontSize: 14.0,
            height: 1.25,
            color: AppColors.highlight,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            labelText: widget.label,
            labelStyle: TextStyle(
              fontSize: 13,
              color: _focus.hasFocus
                  ? AppColors.highlight.withOpacity(0.92)
                  : AppColors.textSecondary,
            ),
            hintText: widget.hint,
            hintStyle: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary.withOpacity(0.85),
            ),
            prefixIcon: widget.prefixIcon != null
                ? Icon(
                    widget.prefixIcon,
                    size: 18,
                    color: _focus.hasFocus
                        ? AppColors.highlight.withOpacity(0.92)
                        : AppColors.iconMuted,
                  )
                : null,
            suffixIcon: widget.enableToggle
                ? IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: _focus.hasFocus
                          ? AppColors.highlight.withOpacity(0.92)
                          : AppColors.iconMuted.withOpacity(0.85),
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
