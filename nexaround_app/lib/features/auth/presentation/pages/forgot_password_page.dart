import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_event.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/auth/presentation/pages/otp_verification_page.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _handleSendCode() {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your email address'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    context.read<AuthBloc>().add(AuthForgotPasswordRequested(email: email));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthForgotPasswordOTPRequired) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OTPVerificationPage(
                email: state.email,
                initialMessage: state.message,
                isPasswordReset: true,
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
                // Background ambient glows
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
                            'Forgot Password?',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ).animate().fade().slideY(begin: 0.2, end: 0),

                          const SizedBox(height: 8),

                          // Subtitle
                          Text(
                            "Enter your registered email address below. We'll send you a 6-digit verification code to reset your password.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                          ).animate().fade(delay: 200.ms),

                          const SizedBox(height: 28),

                          // Email Field
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Enter your email address',
                              hintStyle: TextStyle(color: AppColors.textTertiary),
                              prefixIcon: const Icon(Icons.email_outlined, color: AppColors.textTertiary, size: 20),
                              filled: true,
                              fillColor: AppColors.surfaceVariant,
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
                          ).animate().fade(delay: 350.ms).slideY(begin: 0.05, end: 0),

                          const SizedBox(height: 24),

                          // Action Button
                          _buildSubmitButton(isLoading),
                        ],
                      ),
                    ),
                  ),
                ),

                // Fullscreen Loading Overlay
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
                              'VERIFYING EMAIL...',
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

  Widget _buildSubmitButton(bool isLoading) {
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
          onPressed: isLoading ? null : _handleSendCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: const Text(
            'SEND RESET CODE',
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
