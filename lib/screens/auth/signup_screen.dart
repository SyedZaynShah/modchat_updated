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
      if (mounted)
        setState(() {
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('lib/assets/background.png', fit: BoxFit.cover),
          ),
          AnimatedOpacity(
            opacity: _anim ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedScale(
                        scale: _anim ? 1 : 0.95,
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOut,
                        child: Container(
                          width: 360,
                          height: 360,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppColors.sinopia.withOpacity(0.18),
                                AppColors.sinopia.withOpacity(0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                      AnimatedSlide(
                        offset: _anim ? Offset.zero : const Offset(0, 0.05),
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOut,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: const Border(
                              top: BorderSide(
                                color: AppColors.sinopia,
                                width: 3,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.navy.withOpacity(0.10),
                                offset: const Offset(0, 6),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Create Account',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.navy,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Join ModChat',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.sinopia,
                                ),
                              ),
                              const SizedBox(height: 18),
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
                              BlueButton(
                                onPressed: _loading ? null : _signup,
                                label: 'Create my account',
                                loading: _loading,
                                filled: true,
                                icon: Icons.person_add_alt_1_outlined,
                              ),
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
              style: TextStyle(color: AppColors.navy),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.navy,
                backgroundColor: Colors.transparent,
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Log in'),
            ),
          ],
        ),
      ),
    );
  }
}
