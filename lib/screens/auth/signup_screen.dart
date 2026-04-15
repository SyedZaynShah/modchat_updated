import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_providers.dart';
import '../../theme/theme.dart';
import 'verify_email_screen.dart';
import '../../ui/widgets/auth_ui.dart';
import '../../ui/widgets/auth_fields.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  static const routeName = '/signup';
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _anim = false;

  Widget _whitePrimaryButton({
    required String label,
    required VoidCallback? onPressed,
    required bool loading,
    IconData? icon,
  }) {
    return _WhitePillButton(
      label: label,
      icon: icon,
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
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(firebaseAuthServiceProvider)
          .signUp(
            name: _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
          );
      if (mounted) {
        Navigator.pushReplacementNamed(context, VerifyEmailScreen.routeName);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Scaffold(
      extendBody: true,
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
                                "Let’s get started",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onBackground,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Create your account to continue.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onBackground
                                      .withOpacity(0.6),
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 20),
                              CustomField(
                                controller: _name,
                                label: 'Full name',
                                prefixIcon: Icons.person_outline,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),
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
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),
                              CustomField(
                                controller: _confirm,
                                label: 'Confirm Password',
                                enableToggle: true,
                                obscure: true,
                                prefixIcon: Icons.lock_outline,
                                textInputAction: TextInputAction.done,
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
                                onPressed: _loading ? null : _signup,
                                label: 'Sign up',
                                loading: _loading,
                                icon: Icons.person_add_alt_1_outlined,
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
      bottomNavigationBar: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Already have an account? ',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                backgroundColor: Colors.transparent,
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Login'),
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
  final IconData? icon;

  const _WhitePillButton({
    required this.label,
    required this.onPressed,
    required this.loading,
    this.icon,
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
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
