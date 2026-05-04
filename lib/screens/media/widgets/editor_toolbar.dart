import 'package:flutter/material.dart';

class EditorToolbar extends StatelessWidget {
  final VoidCallback onDraw;
  final VoidCallback onText;
  final VoidCallback onEmoji;
  final VoidCallback onCrop;

  const EditorToolbar({
    super.key,
    required this.onDraw,
    required this.onText,
    required this.onEmoji,
    required this.onCrop,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _ToolBtn(icon: Icons.brush_outlined, onTap: onDraw),
            _ToolBtn(icon: Icons.text_fields_rounded, onTap: onText),
            _ToolBtn(icon: Icons.emoji_emotions_outlined, onTap: onEmoji),
            _ToolBtn(icon: Icons.crop_rounded, onTap: onCrop),
          ],
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ToolBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white70, size: 22),
    );
  }
}
