import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_providers.dart';
import '../../theme/theme.dart';
import '../auth/signup_screen.dart';
import '../../ui/widgets/auth_ui.dart';
import '../../ui/widgets/auth_fields.dart';

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
  bool _anim = false;

  Widget _whitePrimaryButton({
    required String label,
    required VoidCallback? onPressed,
    required bool loading,
  }) {
    return _WhitePillButton(
      label: label,
      loading: loading,
      onPressed: onPressed,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _anim = true);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _loading = true);
    setState(() => _error = null);

    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );

      await cred.user?.reload();
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message ?? 'Login failed');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Stack(
        children: [
          AnimatedOpacity(
            opacity: _anim ? 1 : 0,
            duration: const Duration(milliseconds: 280),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedSlide(
                        offset: _anim ? Offset.zero : const Offset(0, 0.05),
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        child: GlassCard(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Hey, Welcome Back',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onBackground,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Sign in to continue.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onBackground
                                      .withOpacity(0.6),
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 20),
                              CustomField(
                                controller: _email,
                                label: 'Email',
                                hint: 'name@example.com',
                                prefixIcon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),
                              CustomField(
                                controller: _password,
                                label: 'Password',
                                enableToggle: true,
                                obscure: true,
                                prefixIcon: Icons.lock_outline,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _loading ? null : _login(),
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'Forgot password?',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              _whitePrimaryButton(
                                label: 'Login',
                                onPressed: _loading ? null : _login,
                                loading: _loading,
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      height: 1,
                                      color: isLight
                                          ? Colors.black.withOpacity(0.05)
                                          : AppColors.outline,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: Text(
                                      'or continue with',
                                      style: TextStyle(
                                        color: theme.colorScheme.onBackground
                                            .withOpacity(0.5),
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      height: 1,
                                      color: isLight
                                          ? Colors.black.withOpacity(0.05)
                                          : AppColors.outline,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              _GoogleButton(onPressed: null),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Don’t have an account? ",
              style: TextStyle(
                color: theme.colorScheme.onBackground.withOpacity(0.6),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
              onPressed: () =>
                  Navigator.pushNamed(context, SignUpScreen.routeName),
              child: const Text('Sign up'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleButton extends StatefulWidget {
  final VoidCallback? onPressed;
  const _GoogleButton({required this.onPressed});

  @override
  State<_GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<_GoogleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.99 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isLight
                  ? Colors.black.withOpacity(0.05)
                  : AppColors.outlineStrong,
              width: 1,
            ),
            color: isLight ? theme.colorScheme.surface : Colors.transparent,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 18,
                width: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surface,
                ),
                alignment: Alignment.center,
                child: Text(
                  'G',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Continue with Google',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhitePillButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const _WhitePillButton({
    required this.label,
    required this.onPressed,
    required this.loading,
  });

  @override
  State<_WhitePillButton> createState() => _WhitePillButtonState();
}

class _WhitePillButtonState extends State<_WhitePillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = widget.onPressed == null;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.loading ? null : widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: isDisabled
                ? theme.colorScheme.onSurface.withOpacity(0.2)
                : theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(22),
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? SizedBox(
                  height: 18,
                  width: 18,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}
