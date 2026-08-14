import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_event.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/auth/presentation/pages/home_page.dart';
import 'package:nexaround_app/features/auth/presentation/pages/reset_password_page.dart';

class OTPVerificationPage extends StatefulWidget {
  final String email;
  final String? initialMessage;
  final bool isPasswordReset;

  const OTPVerificationPage({
    super.key,
    required this.email,
    this.initialMessage,
    this.isPasswordReset = false,
  });

  @override
  State<OTPVerificationPage> createState() => _OTPVerificationPageState();
}

class _OTPVerificationPageState extends State<OTPVerificationPage> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  Timer? _timer;
  int _start = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    if (widget.initialMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.initialMessage!),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      });
    }
  }

  void _startTimer() {
    setState(() {
      _start = 60;
      _canResend = false;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_start == 0) {
        setState(() {
          _timer?.cancel();
          _canResend = true;
        });
      } else {
        setState(() {
          _start--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otpCode => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        _submitOtp();
      }
    } else {
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
    }
  }

  void _submitOtp() {
    final code = _otpCode;
    if (code.length == 6) {
      if (widget.isPasswordReset) {
        context.read<AuthBloc>().add(
              AuthVerifyResetOTPRequested(
                email: widget.email,
                otp: code,
              ),
            );
      } else {
        context.read<AuthBloc>().add(
              AuthVerifyOTPRequested(
                email: widget.email,
                otp: code,
              ),
            );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter all 6 digits of the verification code'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _resendOtp() {
    if (_canResend) {
      _startTimer();
      if (widget.isPasswordReset) {
        context.read<AuthBloc>().add(
              AuthForgotPasswordRequested(email: widget.email),
            );
      } else {
        context.read<AuthBloc>().add(
              AuthResendOTPRequested(email: widget.email),
            );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) async {
        if (state is AuthAuthenticated) {
          await CacheService.setLoggedIn(true);
          if (!mounted) return;

          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, animation, __) => HomePage(),
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
              transitionDuration: const Duration(milliseconds: 800),
            ),
          );
        } else if (state is AuthResetOTPVerified) {
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ResetPasswordPage(
                email: state.email,
                resetToken: state.resetToken,
              ),
            ),
          );
        } else if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          final isLoading = state is AuthLoading;
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AppColors.textPrimary,
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            body: Stack(
              children: [
                // Background glow (Matching Login & Register pages)
                Positioned(
                  top: -100,
                  right: -80,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.primary.withOpacity(0.08),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -80,
                  left: -60,
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.secondary.withOpacity(0.06),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Main Content
                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // App Logo
                          _buildLogo(),
                          const SizedBox(height: 16),

                          // Title
                          const Text(
                            'Verification Code',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ).animate().fade().slideY(begin: 0.2, end: 0),

                          const SizedBox(height: 4),

                          // Subtitle with Email display
                          Column(
                            children: [
                              Text(
                                'We sent a 6-digit OTP verification code to',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.email,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ).animate().fade(delay: 200.ms),

                          const SizedBox(height: 32),

                          // 6-Digit PIN Fields
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(6, (index) {
                              return SizedBox(
                                width: 44,
                                height: 56,
                                child: TextField(
                                  controller: _controllers[index],
                                  focusNode: _focusNodes[index],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  textAlignVertical: TextAlignVertical.center,
                                  maxLength: 1,
                                  cursorColor: Colors.black,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black,
                                  ),
                                  decoration: InputDecoration(
                                    counterText: '',
                                    filled: true,
                                    fillColor: AppColors.surfaceVariant,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(color: AppColors.border),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(color: AppColors.border),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: AppColors.primary.withOpacity(0.6),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  onChanged: (val) => _onDigitChanged(index, val),
                                ),
                              );
                            }),
                          ).animate().fade(delay: 350.ms).slideY(begin: 0.05, end: 0),

                          const SizedBox(height: 28),

                          // Verify Button
                          _buildVerifyButton(isLoading),

                          const SizedBox(height: 20),

                          // Resend Code Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Didn't receive code? ",
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                              GestureDetector(
                                onTap: _canResend ? _resendOtp : null,
                                child: _canResend
                                    ? ShaderMask(
                                        shaderCallback: (bounds) =>
                                            AppColors.primaryGradient.createShader(
                                          Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                                        ),
                                        child: const Text(
                                          'Resend Code',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      )
                                    : Text(
                                        'Resend in ${_start}s',
                                        style: TextStyle(
                                          color: AppColors.textTertiary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                              ),
                            ],
                          ).animate().fade(delay: 600.ms),
                        ],
                      ),
                    ),
                  ),
                ),

                // Fullscreen Loading Overlay (Matching Login & Register)
                if (isLoading)
                  Positioned.fill(
                    child: Container(
                      color: AppColors.background.withOpacity(0.8),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'VERIFYING CODE...',
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 11,
                                letterSpacing: 3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLogo() {
    return Image.asset(
      'assets/images/logo_2.png',
      width: 90,
      fit: BoxFit.contain,
    ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack);
  }

  Widget _buildVerifyButton(bool isLoading) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: AppColors.primaryGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : _submitOtp,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: const Text(
            'VERIFY & PROCEED',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              fontSize: 15,
            ),
          ),
        ),
      ),
    ).animate().fade(delay: 500.ms).scale(begin: const Offset(0.95, 0.95));
  }
}


