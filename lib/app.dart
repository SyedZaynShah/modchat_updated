import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/verify_email_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/chat/chat_detail_screen.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'ModChat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      builder: (context, child) {
        return DefaultTextStyle(
          style: GoogleFonts.inter().copyWith(color: Colors.white),
          child: child ?? const SizedBox.shrink(),
        );
      },
      onGenerateRoute: (settings) {
        if (settings.name == ChatDetailScreen.routeName) {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              chatId: args['chatId'] as String,
              peerId: args['peerId'] as String,
            ),
          );
        }
        switch (settings.name) {
          case SignUpScreen.routeName:
            return MaterialPageRoute(builder: (_) => const SignUpScreen());
          case VerifyEmailScreen.routeName:
            return MaterialPageRoute(builder: (_) => const VerifyEmailScreen());
          default:
            return MaterialPageRoute(builder: (_) => const AuthGate());
        }
      },
    );
  }
}

/// ✅ AuthGate that always uses fresh user info
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) return const LoginScreen();

        // Reload user to get latest emailVerified status
        return FutureBuilder(
          future: user.reload(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Colors.black,
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (!user.emailVerified) return const VerifyEmailScreen();
            return const HomeScreen();
          },
        );
      },
    );
  }
}
