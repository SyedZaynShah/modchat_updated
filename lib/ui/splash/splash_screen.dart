import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
      duration: const Duration(seconds: 2),
    );

    _logoScale = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo));

    _controller.forward();

    Future.delayed(const Duration(seconds: 3), () {
      Navigator.pushReplacementNamed(context, "/home");
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _logoScale,
              child: Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: const Color(0xff0096ff), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.15),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                  ],
                  backgroundBlendMode: BlendMode.overlay,
                ),
                child: Icon(
                  Icons.chat_bubble_rounded,
                  size: 110,
                  color: Colors.black.withOpacity(0.85),
                ),
              ),
            ),

            const SizedBox(height: 40),

            Text(
              "ModChat",
              style: GoogleFonts.poppins(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              "Modern Messaging Experience",
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: Colors.black54,
              ),
            ),

            const SizedBox(height: 50),

            Text(
              "From\nProject ModChat",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                height: 1.3,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
