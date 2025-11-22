import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_providers.dart';
import '../../theme/theme.dart';
import '../../widgets/glass_button.dart';
import '../auth/signup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(firebaseAuthServiceProvider).signIn(_email.text.trim(), _password.text);
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('ModChat', style: Theme.of(context).textTheme.displaySmall?.copyWith(color: AppColors.sinopia, fontWeight: FontWeight.w700)),
                const SizedBox(height: 24),
                AppTheme.glass(
                  child: Container(
                    decoration: AppTheme.glassDecoration(glow: true),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email', hintText: 'name@example.com')),
                        const SizedBox(height: 12),
                        TextField(controller: _password, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: GlassButton(
                                onPressed: _loading ? null : _login,
                                child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Login'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, SignUpScreen.routeName),
                  child: const Text('Create account', style: TextStyle(color: Colors.white70)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
