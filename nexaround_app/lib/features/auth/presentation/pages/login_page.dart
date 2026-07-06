import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:nexaround_app/features/auth/presentation/pages/home_page.dart';
import 'package:nexaround_app/features/auth/presentation/pages/register_page.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_event.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';

import 'package:nexaround_app/core/services/cache_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password')),
      );
      return;
    }

    context.read<AuthBloc>().add(AuthLoginRequested(
          email: email,
          password: password,
        ));
  }

  void _handleSocialLogin(String provider) {
    if (provider == 'google') {
      context.read<AuthBloc>().add(const AuthGoogleLoginRequested());
    } else if (provider == 'apple') {
      context.read<AuthBloc>().add(const AuthAppleLoginRequested());
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
        } else if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: AppColors.error),
          );
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          final isLoading = state is AuthLoading;
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Stack(
              children: [
                // Background glow
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

                // Content
                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildLogo(),
                          const SizedBox(height: 16),

                          // Title
                          const Text(
                            'Welcome Back',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ).animate().fade().slideY(begin: 0.2, end: 0),

                          const SizedBox(height: 4),
                          Text(
                            'Sign in to explore the extraordinary',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ).animate().fade(delay: 200.ms),

                          const SizedBox(height: 22),

                          // Social login buttons
                          _buildSocialButton(
                            icon: Icons.g_mobiledata_rounded,
                            label: 'Continue with Google',
                            onTap: () => _handleSocialLogin('google'),
                            delay: 300,
                          ),
                          const SizedBox(height: 10),
                          _buildSocialButton(
                            icon: Icons.apple_rounded,
                            label: 'Continue with Apple',
                            onTap: () => _handleSocialLogin('apple'),
                            delay: 400,
                          ),

                          const SizedBox(height: 16),

                          // Divider
                          Row(
                            children: [
                              Expanded(child: Container(height: 1, color: AppColors.border)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'OR',
                                  style: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              Expanded(child: Container(height: 1, color: AppColors.border)),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Email field
                          _buildTextField(
                            controller: _emailController,
                            hint: 'Email address',
                            icon: Icons.email_outlined,
                          ).animate().fade(delay: 500.ms).slideX(begin: -0.05, end: 0),

                          const SizedBox(height: 10),

                          // Password field
                          _buildTextField(
                            controller: _passwordController,
                            hint: 'Password',
                            icon: Icons.lock_outline_rounded,
                            obscure: _obscurePassword,
                            suffix: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AppColors.textTertiary,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ).animate().fade(delay: 600.ms).slideX(begin: -0.05, end: 0),

                          const SizedBox(height: 4),

                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {},
                              child: Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Sign In button
                          _buildSignInButton(isLoading),

                          const SizedBox(height: 20),

                          // Create account
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'New to NexAround? ',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const RegisterPage(),
                                  ),
                                ),
                                child: ShaderMask(
                                  shaderCallback: (bounds) =>
                                      AppColors.primaryGradient.createShader(
                                    Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                                  ),
                                  child: const Text(
                                    'Create Account',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Loading overlay
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
                              'AUTHENTICATING...',
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

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required int delay,
  }) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.textPrimary, size: 22),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    ).animate().fade(delay: Duration(milliseconds: delay)).slideY(begin: 0.1, end: 0);
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textTertiary),
        prefixIcon: Icon(icon, color: AppColors.textTertiary, size: 20),
        suffixIcon: suffix,
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
          borderSide:
              BorderSide(color: AppColors.primary.withOpacity(0.6), width: 1.5),
        ),
      ),
    );
  }

  Widget _buildSignInButton(bool isLoading) {
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
          onPressed: isLoading ? null : _handleLogin,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: const Text(
            'SIGN IN',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              fontSize: 15,
            ),
          ),
        ),
      ),
    ).animate().fade(delay: 700.ms).scale(begin: const Offset(0.95, 0.95));
  }
}
