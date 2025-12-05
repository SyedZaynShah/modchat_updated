import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'firebase_options.dart';
import 'app.dart';

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
      await FirebaseAuth.instance.useAuthEmulator(emuHost, emuPort);
    } catch (_) {
      // ignore if not supported on platform
    }
  }

  // On web, ensure LOCAL persistence to reduce network/cookie related failures
  if (kIsWeb) {
    try {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
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

  runApp(const ProviderScope(child: App()));
}
