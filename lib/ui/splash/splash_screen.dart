import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/theme.dart';
import '../../screens/auth/landing_screen.dart';

class ModChatSplashScreen extends StatefulWidget {
  const ModChatSplashScreen({super.key});

  @override
  State<ModChatSplashScreen> createState() => _ModChatSplashScreenState();
}

class _ModChatSplashScreenState extends State<ModChatSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _logoScale = Tween<double>(
      begin: 0.9,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();

    Future.delayed(const Duration(seconds: 3), () {
      final u = FirebaseAuth.instance.currentUser;
      if (!mounted) return;
      if (u == null) {
        Navigator.pushReplacementNamed(context, LandingScreen.routeName);
      } else {
        Navigator.pushReplacementNamed(context, "/home");
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _logoScale,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.outline, width: 1),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.chat_bubble_rounded,
                  size: 34,
                  color: AppColors.highlight,
                ),
              ),
            ),

            const SizedBox(height: 20),

            Text('ModChat', style: textTheme.titleLarge),

            const SizedBox(height: 6),

            Text('Modern Messaging Experience', style: textTheme.bodySmall),

            const SizedBox(height: 34),

            Text(
              'From\nProject ModChat',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}
