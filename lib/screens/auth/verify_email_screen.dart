import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/glass_button.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  static const routeName = '/verify';
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _sending = false;
  bool _checking = false;
  String? _msg;

  Future<void> _resend() async {
    setState(() { _sending = true; _msg = null; });
    try {
      await ref.read(firebaseAuthServiceProvider).sendEmailVerification();
      setState(() { _msg = 'Verification email sent.'; });
    } catch (e) {
      setState(() { _msg = e.toString(); });
    } finally {
      if (mounted) setState(() { _sending = false; });
    }
  }

  Future<void> _check() async {
    setState(() { _checking = true; _msg = null; });
    try {
      await ref.read(firebaseAuthServiceProvider).reloadUser();
      final u = FirebaseAuth.instance.currentUser;
      if (u != null && u.emailVerified && mounted) {
        Navigator.pop(context);
      } else {
        setState(() { _msg = 'Email not verified yet.'; });
      }
    } finally {
      if (mounted) setState(() { _checking = false; });
    }
  }

  Future<void> _logout() => ref.read(firebaseAuthServiceProvider).signOut();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mark_email_read, color: Colors.white, size: 56),
              const SizedBox(height: 12),
              const Text('Verify your email to continue', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              if (_msg != null) ...[
                Text(_msg!, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
              ],
              Row(children: [
                Expanded(child: GlassButton(onPressed: _sending ? null : _resend, child: _sending ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Resend'))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: GlassButton(onPressed: _checking ? null : _check, child: _checking ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("I've verified"))),
              ]),
              const SizedBox(height: 12),
              TextButton(onPressed: _logout, child: const Text('Logout', style: TextStyle(color: Colors.white70))),
            ],
          ),
        ),
      ),
    );
  }
}
