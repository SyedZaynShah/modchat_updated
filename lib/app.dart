import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/landing_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/verify_email_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/chat/chat_detail_screen.dart';
import 'screens/chat/chat_contact_info_screen.dart';
import 'screens/group/create_group_screen.dart';
import 'screens/chat/group_chat_detail_screen.dart';
import 'screens/group/group_settings_screen.dart';
import 'screens/group/group_permissions_screen.dart';
import 'ui/splash/splash_screen.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'ModChat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const ModChatSplashScreen(),
      routes: {
        "/home": (context) => const AuthGate(),
        LandingScreen.routeName: (context) => const LandingScreen(),
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
        if (settings.name == CreateGroupScreen.routeName) {
          return MaterialPageRoute(builder: (_) => const CreateGroupScreen());
        }
        if (settings.name == GroupChatDetailScreen.routeName) {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) =>
                GroupChatDetailScreen(chatId: args['chatId'] as String),
          );
        }
        if (settings.name == GroupSettingsScreen.routeName) {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) =>
                GroupSettingsScreen(chatId: args['chatId'] as String),
          );
        }
        if (settings.name == GroupPermissionsScreen.routeName) {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) =>
                GroupPermissionsScreen(chatId: args['chatId'] as String),
          );
        }
        if (settings.name == ChatContactInfoScreen.routeName) {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) => ChatContactInfoScreen(
              peerId: args['peerId'] as String,
              chatId: args['chatId'] as String,
            ),
          );
        }
        switch (settings.name) {
          case LandingScreen.routeName:
            return MaterialPageRoute(builder: (_) => const LandingScreen());
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
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.highlight,
                ),
              ),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) return const LoginScreen();

        if (!user.emailVerified) return const VerifyEmailScreen();
        return const HomeScreen();
      },
    );
  }
}
