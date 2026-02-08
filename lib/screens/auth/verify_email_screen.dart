import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_providers.dart';
import '../../theme/theme.dart';
import '../../ui/widgets/auth_ui.dart';

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

  Widget _whitePrimaryButton({
    required String label,
    required VoidCallback? onPressed,
    required bool loading,
  }) {
    return _WhitePillButton(
      label: label,
      onPressed: onPressed,
      loading: loading,
    );
  }

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _msg = null;
    });
    try {
      await ref.read(firebaseAuthServiceProvider).sendEmailVerification();
      if (!mounted) return;
      setState(() {
        _msg = 'Verification email sent.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _msg = null;
    });
    try {
      await ref.read(firebaseAuthServiceProvider).reloadUser();
      if (!mounted) return;
      final u = FirebaseAuth.instance.currentUser;
      if (u != null && u.emailVerified && mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        return;
      } else {
        if (!mounted) return;
        setState(() {
          _msg = 'Email not verified yet.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.bgTop, AppColors.bgBottom],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.cardTop, AppColors.cardBottom],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.outline.withOpacity(0.9),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 18,
                        spreadRadius: -10,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: AppColors.iconMuted,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.mark_email_read,
                        color: AppColors.iconMuted.withOpacity(0.95),
                        size: 56,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Account Verification',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          color: AppColors.highlight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'We sent a verification link to your email. This helps protect your account and confirms it belongs to you. Open the email, verify, then return here to continue.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_msg != null) ...[
                        Text(
                          _msg!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _whitePrimaryButton(
                        label: 'Verify your account',
                        onPressed: _checking ? null : _check,
                        loading: _checking,
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _sending ? null : _resend,
                        child: _sending
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.highlight,
                                ),
                              )
                            : Text(
                                'Resend email',
                                style: TextStyle(
                                  color: AppColors.textSecondary.withOpacity(
                                    0.92,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Already have an account? ',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Login'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 26,
                spreadRadius: -16,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.06),
                blurRadius: 1,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF121417),
                  ),
                )
              : Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF121417),
                    letterSpacing: 0.2,
                  ),
                ),
        ),
      ),
    );
  }
}
