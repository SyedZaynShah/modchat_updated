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
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focus.hasFocus ? AppColors.highlight : AppColors.outline,
            width: 1,
          ),
        ),
        child: SizedBox(
          height: 46,
          child: Align(
            alignment: Alignment.center,
            child: TextField(
              controller: widget.controller,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              onSubmitted: widget.onSubmitted,
              textAlignVertical: TextAlignVertical.center,
              obscureText: _obscure,
              strutStyle: const StrutStyle(height: 1.0, forceStrutHeight: true),
              style: const TextStyle(
                fontSize: 14.0,
                height: 1.0,
                color: AppColors.highlight,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                hintText: widget.hint ?? widget.label,
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                prefixIcon: widget.prefixIcon != null
                    ? Icon(
                        widget.prefixIcon,
                        size: 18,
                        color: _focus.hasFocus
                            ? AppColors.highlight
                            : AppColors.iconMuted,
                      )
                    : null,
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                suffixIcon: widget.enableToggle
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                          color: _focus.hasFocus
                              ? AppColors.highlight
                              : AppColors.iconMuted,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
