import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:nexaround_app/features/auth/presentation/pages/login_page.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_event.dart';
import 'dart:convert';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthAuthenticated) {
          final user = state.user;
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
                child: Column(
                  children: [
                    // Header
                    _buildProfileHeader(context, user),
                    const SizedBox(height: 28),

                    // Stats row
                    _buildStatsRow(),
                    const SizedBox(height: 28),

                    // Saved Places
                    ValueListenableBuilder<int>(
                      valueListenable: CacheService.savedPlacesNotifier,
                      builder: (context, _, __) {
                        return _buildSection('Saved Places', Icons.bookmark_rounded, [
                          if (CacheService.getSavedPlaceJsons().isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: Text('No saved places yet', style: TextStyle(color: AppColors.textTertiary))),
                            )
                          else
                            ...CacheService.getSavedPlaceJsons().map((jsonStr) {
                              final attraction = AttractionModel.fromJson(json.decode(jsonStr));
                              return _buildSavedPlace(
                                attraction.name, 
                                attraction.categoryName?.contains('Food') == true ? '🍜' : '🏛', 
                                attraction.rating, 
                                attraction.categoryName ?? 'Attraction'
                              );
                            }),
                        ]);
                      },
                    ),
                    const SizedBox(height: 24),

                    // Preferences 
                    _buildPreferencesSection(user.preferences),
                    const SizedBox(height: 24),

                    // Settings menu
                    _buildSettingsMenu(context, user),
                  ],
                ),
              ),
            ),
          );
        }
        return const Scaffold(
          backgroundColor: AppColors.background,
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Widget _buildProfileHeader(BuildContext context, dynamic user) {
    final String name = user.displayName?.toString() ?? '';
    final initials = name.isNotEmpty 
        ? name.split(' ').where((String e) => e.isNotEmpty).map((String e) => e[0]).take(2).join('').toUpperCase()
        : '??';

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
              child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(50),
                    child: CachedNetworkImage(
                      imageUrl: user.avatarUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(color: AppColors.surfaceVariant),
                      errorWidget: (context, url, error) => Center(
                        child: Text(
                          initials,
                          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
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

        Text(
          user.displayName?.toString() ?? 'Guest User',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ).animate().fade(delay: 200.ms),

        const SizedBox(height: 4),
        Text(
          user.email?.toString() ?? '',
          style: const TextStyle(fontSize: 14, color: AppColors.textTertiary),
        ).animate().fade(delay: 300.ms),

        const SizedBox(height: 12),
        // Level badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: AppColors.achievementGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.warning.withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ValueListenableBuilder<int>(
            valueListenable: CacheService.statsNotifier,
            builder: (context, _, __) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.diamond_rounded, color: Colors.black, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Explorer Level ${CacheService.getExplorerLevel()}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ).animate().fade(delay: 400.ms).scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack),
      ],
    );
  }

  Widget _buildStatsRow() {
    return ValueListenableBuilder<int>(
      valueListenable: CacheService.statsNotifier,
      builder: (context, _, __) {
        final savedCount = CacheService.getSavedPlaceJsons().length;
        final visited = CacheService.getPlacesVisited();
        return Row(
          children: [
            _buildStat('$visited', 'Places\nVisited', AppColors.primary),
            const SizedBox(width: 10),
            _buildStat('0', 'Trips\nCompleted', AppColors.secondary),
            const SizedBox(width: 10),
            _buildStat('$savedCount', 'Places\nSaved', AppColors.neonGreen),
            const SizedBox(width: 10),
            _buildStat('--', 'Avg\nRating', AppColors.warning),
          ],
        );
      },
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
              style: const TextStyle(fontSize: 10, color: AppColors.textTertiary, height: 1.3),
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
                    const Icon(Icons.star_rounded, size: 12, color: AppColors.warning),
                    const SizedBox(width: 3),
                    Text('$rating', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                    const SizedBox(width: 8),
                    Text(type, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.bookmark_rounded, size: 18, color: AppColors.primary),
        ],
      ),
    );
  }

  Widget _buildPreferencesSection(Map<String, dynamic> preferences) {
    final List<String> prefs = preferences.isNotEmpty 
      ? preferences.keys.take(4).toList() 
      : ['🍜 Food', '🏛 Culture', '🌿 Nature', '🏔 Adventure'];

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
          icon: const Icon(Icons.edit_rounded, size: 14, color: AppColors.primary),
          label: const Text('Edit Preferences', style: TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildSettingsMenu(BuildContext context, dynamic user) {
    final language = user.language;
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
        _buildMenuItem(Icons.language_rounded, 'Language', language.toUpperCase()),
        _buildMenuItem(
          Icons.attach_money_rounded,
          'Currency',
          user.preferences['currency']?.toString().toUpperCase() ?? 'USD',
          onTap: () => _showCurrencyPicker(context, user),
        ),
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
                context.read<AuthBloc>().add(const AuthLogoutRequested());
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              },
              icon: const Icon(Icons.logout_rounded, color: AppColors.error, size: 18),
              label: const Text('Sign Out', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ],
    );
  }

  void _showCurrencyPicker(BuildContext context, dynamic user) {
    final currencies = [
      {'code': 'USD', 'name': 'US Dollar', 'symbol': r'$'},
      {'code': 'EUR', 'name': 'Euro', 'symbol': '€'},
      {'code': 'GBP', 'name': 'British Pound', 'symbol': '£'},
      {'code': 'LKR', 'name': 'Sri Lankan Rupee', 'symbol': 'රු'},
      {'code': 'INR', 'name': 'Indian Rupee', 'symbol': '₹'},
      {'code': 'JPY', 'name': 'Japanese Yen', 'symbol': '¥'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Currency', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: currencies.length,
                itemBuilder: (context, index) {
                  final c = currencies[index];
                  final isSelected = (user.preferences['currency'] ?? 'USD') == c['code'];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary.withOpacity(0.1) : AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: Center(child: Text(c['symbol']!, style: TextStyle(color: isSelected ? AppColors.primary : AppColors.textSecondary, fontWeight: FontWeight.bold))),
                    ),
                    title: Text(c['name']!, style: TextStyle(color: isSelected ? AppColors.primary : AppColors.textPrimary, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
                    trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
                    onTap: () {
                      final newPrefs = Map<String, dynamic>.from(user.preferences);
                      newPrefs['currency'] = c['code'];
                      context.read<AuthBloc>().add(UpdateUserPreferences(newPrefs));
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String label, String value, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
              Text(value, style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
