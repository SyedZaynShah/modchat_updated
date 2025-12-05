import 'package:flutter/material.dart';
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(firebaseAuthServiceProvider)
          .signIn(_email.text.trim(), _password.text);
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
                          width: 340,
                          height: 340,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                kAccentBlue.withOpacity(0.22),
                                kAccentBlue.withOpacity(0.0),
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
                                'Modchat',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.navy,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Welcome back',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.sinopia,
                                ),
                              ),
                              const SizedBox(height: 18),
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
                                onPressed: _loading ? null : _login,
                                label: 'Login',
                                loading: _loading,
                                filled: true,
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
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.sinopia, width: 1.5),
            foregroundColor: AppColors.sinopia,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () => Navigator.pushNamed(context, SignUpScreen.routeName),
          child: const Text('Create account'),
        ),
      ),
    );
  }
}
