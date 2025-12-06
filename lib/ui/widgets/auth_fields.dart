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
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focus.hasFocus
                ? AppColors.navy
                : AppColors.navy.withOpacity(0.6),
            width: 1.5,
          ),
          boxShadow: _focus.hasFocus
              ? [
                  BoxShadow(
                    color: AppColors.navy.withOpacity(0.12),
                    blurRadius: 18,
                    spreadRadius: 1,
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
            color: Colors.black,
          ),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            labelText: widget.label,
            labelStyle: TextStyle(
              fontSize: 13,
              color: _focus.hasFocus
                  ? AppColors.navy
                  : AppColors.navy.withOpacity(0.7),
            ),
            hintText: widget.hint,
            hintStyle: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.85),
            ),
            prefixIcon: widget.prefixIcon != null
                ? Icon(widget.prefixIcon, size: 18, color: AppColors.navy)
                : null,
            suffixIcon: widget.enableToggle
                ? IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: _focus.hasFocus
                          ? AppColors.navy
                          : AppColors.navy.withOpacity(0.55),
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
