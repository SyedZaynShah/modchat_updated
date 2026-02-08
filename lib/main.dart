import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'firebase_options.dart';
import 'app.dart';
import 'services/firestore_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  // Initialize Firebase properly using FlutterFire
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Optional: use Firebase Auth emulator for local development if configured
  final emuHost = dotenv.env['FIREBASE_AUTH_EMULATOR_HOST'];
  final emuPort = int.tryParse(dotenv.env['FIREBASE_AUTH_EMULATOR_PORT'] ?? '');
  if (emuHost != null && emuHost.isNotEmpty && emuPort != null) {
    try {
      await fb_auth.FirebaseAuth.instance.useAuthEmulator(emuHost, emuPort);
    } catch (_) {
      // ignore if not supported on platform
    }
  }

  // On web, ensure LOCAL persistence to reduce network/cookie related failures
  if (kIsWeb) {
    try {
      await fb_auth.FirebaseAuth.instance.setPersistence(
        fb_auth.Persistence.LOCAL,
      );
    } catch (_) {}
  }

  // Initialize Supabase for storage usage
  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
  if (supabaseUrl != null &&
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey != null &&
      supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }

  runApp(const _AuthDrivenProviderScope(child: App()));
}

class _AuthDrivenProviderScope extends StatefulWidget {
  final Widget child;
  const _AuthDrivenProviderScope({required this.child});

  @override
  State<_AuthDrivenProviderScope> createState() =>
      _AuthDrivenProviderScopeState();
}

class _AuthDrivenProviderScopeState extends State<_AuthDrivenProviderScope> {
  fb_auth.User? _lastUser;
  bool _resetInFlight = false;

  @override
  void initState() {
    super.initState();
    _lastUser = fb_auth.FirebaseAuth.instance.currentUser;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<fb_auth.User?>(
      stream: fb_auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;

        // If identity changed, hard-reset Firestore to avoid cross-account cache.
        final lastUid = _lastUser?.uid;
        final nextUid = user?.uid;
        if (lastUid != nextUid) {
          _lastUser = user;
          if (!_resetInFlight) {
            _resetInFlight = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              try {
                await FirestoreService.resetPersistenceAndNetwork();
              } finally {
                if (mounted) _resetInFlight = false;
              }
            });
          }
        }

        // Recreate the ProviderContainer whenever auth identity changes.
        return ProviderScope(
          key: ValueKey(nextUid ?? 'signed_out'),
          child: widget.child,
        );
      },
    );
  }
}
