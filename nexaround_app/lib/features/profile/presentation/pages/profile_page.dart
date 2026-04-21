import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:nexaround_app/features/onboarding/presentation/pages/splash_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
          child: Column(
            children: [
              // Header
              _buildProfileHeader(context),
              const SizedBox(height: 28),

              // Stats row
              _buildStatsRow(),
              const SizedBox(height: 28),

              // Saved Places
              _buildSection('Saved Places', Icons.bookmark_rounded, [
                _buildSavedPlace('Sigiriya Rock Fortress', '🏛', 4.8, 'Culture'),
                _buildSavedPlace('Ministry of Crab', '🦀', 4.8, 'Restaurant'),
                _buildSavedPlace('Lotus Temple', '🪷', 4.9, 'Temple'),
              ]),
              const SizedBox(height: 24),

              // Completed Trips
              _buildSection('Completed Trips', Icons.flight_takeoff_rounded, [
                _buildTripCard('Sri Lanka Explorer', '🇱🇰', 'Dec 2025', '12 places visited'),
                _buildTripCard('Bali Adventure', '🇮🇩', 'Aug 2025', '8 places visited'),
              ]),
              const SizedBox(height: 24),

              // Preferences 
              _buildPreferencesSection(),
              const SizedBox(height: 24),

              // Settings menu
              _buildSettingsMenu(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context) {
    return Column(
      children: [
        // Avatar + edit
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'AK',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceElevated,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 14),
            ),
          ],
        ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
        const SizedBox(height: 16),

        const Text(
          'Alex Karunarathne',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ).animate().fade(delay: 200.ms),

        const SizedBox(height: 4),
        Text(
          'alex.k@email.com',
          style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
        ).animate().fade(delay: 300.ms),

        const SizedBox(height: 12),
        // Level badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: AppColors.secondaryGradient,
            boxShadow: [
              BoxShadow(color: AppColors.secondary.withOpacity(0.3), blurRadius: 12),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.diamond_rounded, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              const Text(
                'Explorer Level 5',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.5),
              ),
            ],
          ),
        ).animate().fade(delay: 400.ms).scale(begin: const Offset(0.9, 0.9)),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStat('23', 'Places\nVisited', AppColors.primary),
        const SizedBox(width: 10),
        _buildStat('3', 'Trips\nCompleted', AppColors.secondary),
        const SizedBox(width: 10),
        _buildStat('15', 'Places\nSaved', AppColors.neonGreen),
        const SizedBox(width: 10),
        _buildStat('4.8', 'Avg\nRating', AppColors.warning),
      ],
    ).animate().fade(delay: 300.ms);
  }

  Widget _buildStat(String value, String label, Color color) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        glowColor: color,
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: AppColors.textTertiary, height: 1.3),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    );
  }

  Widget _buildSavedPlace(String name, String emoji, double rating, String type) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Row(
                  children: [
                    Icon(Icons.star_rounded, size: 12, color: AppColors.warning),
                    const SizedBox(width: 3),
                    Text('$rating', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                    const SizedBox(width: 8),
                    Text(type, style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.bookmark_rounded, size: 18, color: AppColors.primary),
        ],
      ),
    );
  }

  Widget _buildTripCard(String name, String flag, String date, String summary) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: AppColors.secondaryGradient.scale(0.5),
            ),
            child: Center(child: Text(flag, style: const TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 11, color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(date, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                    const SizedBox(width: 10),
                    Text(summary, style: TextStyle(fontSize: 12, color: AppColors.primary)),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textTertiary),
        ],
      ),
    );
  }

  Widget _buildPreferencesSection() {
    final prefs = ['🍜 Food', '🏛 Culture', '🌿 Nature', '🏔 Adventure'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tune_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('Preferences', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: prefs.map((pref) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: AppColors.primaryGradient,
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 8)],
            ),
            child: Text(pref, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          )).toList(),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () {},
          icon: Icon(Icons.edit_rounded, size: 14, color: AppColors.primary),
          label: Text('Edit Preferences', style: TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildSettingsMenu(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.settings_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 14),
        _buildMenuItem(Icons.language_rounded, 'Language', 'English'),
        _buildMenuItem(Icons.attach_money_rounded, 'Currency', 'LKR (රු)'),
        _buildMenuItem(Icons.notifications_rounded, 'Notifications', 'On'),
        _buildMenuItem(Icons.dark_mode_rounded, 'Dark Mode', 'Always'),
        _buildMenuItem(Icons.privacy_tip_rounded, 'Privacy', ''),
        _buildMenuItem(Icons.help_outline_rounded, 'Help & Support', ''),
        const SizedBox(height: 20),
        // Logout
        SizedBox(
          width: double.infinity,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.error.withOpacity(0.3)),
            ),
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AnimatedSplashScreen()),
                  (route) => false,
                );
              },
              icon: Icon(Icons.logout_rounded, color: AppColors.error, size: 18),
              label: Text('Sign Out', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surfaceVariant,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
          if (value.isNotEmpty)
            Text(value, style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
