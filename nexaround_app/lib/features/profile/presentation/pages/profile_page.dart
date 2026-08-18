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
import 'package:nexaround_app/core/services/notification_service.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
import 'package:nexaround_app/core/services/currency_service.dart';
import 'package:nexaround_app/features/profile/presentation/pages/help_support_page.dart';
import 'package:nexaround_app/features/attractions/presentation/pages/attraction_detail_page.dart';
import 'package:go_router/go_router.dart';
import 'package:nexaround_app/features/travel_stories/presentation/pages/travel_journal_page.dart';
import 'package:nexaround_app/core/services/avatar_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
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

                    // Travel Journal Card
                    _buildJournalCard(context),
                    const SizedBox(height: 28),

                    // Favourite Places
                    ValueListenableBuilder<int>(
                      valueListenable: CacheService.favoritePlacesNotifier,
                      builder: (context, _, __) {
                        return _buildSection('Favourite Places', Icons.favorite_rounded, [
                          if (CacheService.getFavoritePlaceJsons().isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: Text('No favourite places yet', style: TextStyle(color: AppColors.textTertiary))),
                            )
                          else
                            ...CacheService.getFavoritePlaceJsons().map((jsonStr) {
                              final attraction = AttractionModel.fromJson(json.decode(jsonStr));
                              return _buildFavoritePlace(
                                attraction.name, 
                                attraction.categoryName?.contains('Food') == true ? '🍜' : '🏛', 
                                attraction.rating, 
                                attraction.categoryName ?? 'Attraction',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AttractionDetailPage(
                                        id: attraction.id,
                                        name: attraction.name,
                                        category: attraction.categoryName ?? 'Attraction',
                                        rating: attraction.rating,
                                        distance: attraction.distanceM != null 
                                            ? '${(attraction.distanceM! / 1000).toStringAsFixed(1)} km' 
                                            : '0.0 km',
                                        emoji: attraction.categoryName?.contains('Food') == true ? '🍜' : '🏛',
                                        imageUrl: attraction.photoUrls.isNotEmpty 
                                            ? attraction.photoUrls.first 
                                            : null,
                                        latitude: attraction.latitude,
                                        longitude: attraction.longitude,
                                      ),
                                    ),
                                  );
                                },
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
    return Column(
      children: [
        // Avatar + edit studio
        UserAvatarView(
          user: user,
          size: 104,
          showEditBadge: true,
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
        final visited = CacheService.getPlacesVisited();
        return Row(
          children: [
            _buildStat('$visited', 'Places\nVisited', AppColors.primary),
            const SizedBox(width: 10),
            _buildStat('0', 'Trips\nCompleted', AppColors.secondary),
            const SizedBox(width: 10),
            ValueListenableBuilder<int>(
              valueListenable: CacheService.favoritePlacesNotifier,
              builder: (context, _, __) {
                final favCount = CacheService.getFavoritePlaceJsons().length;
                return _buildStat('$favCount', 'Favourite\nPlaces', const Color(0xFFFF2D55));
              },
            ),
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
            Icon(icon, size: 18, color: icon == Icons.favorite_rounded ? const Color(0xFFFF2D55) : AppColors.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    );
  }

  Widget _buildFavoritePlace(String name, String emoji, double rating, String type, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
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
            const Icon(Icons.favorite_rounded, size: 18, color: Color(0xFFFF2D55)),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferencesSection(Map<String, dynamic> preferences) {
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
        // Preference customization isn't available yet — show a placeholder
        // instead of the editable pills.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: AppColors.surfaceVariant,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_top_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const Text(
                'Coming Soon',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsMenu(BuildContext context, dynamic user) {
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
        _buildMenuItem(
          Icons.auto_awesome_rounded,
          'Travel Avatar',
          'Persona',
          onTap: () => AvatarService.showAvatarStudio(context, user),
        ),
        _buildMenuItem(
          Icons.language_rounded,
          'Language',
          'Coming Soon',
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Language settings coming soon!'),
                backgroundColor: AppColors.primary,
              ),
            );
          },
        ),
        _buildMenuItem(
          Icons.attach_money_rounded,
          'Currency',
          user.preferences['currency']?.toString().toUpperCase() ?? 'USD',
          onTap: () => _showCurrencyPicker(context, user),
        ),
        _buildMenuItem(
          Icons.notifications_rounded, 
          'Notifications', 
          CacheService.areNotificationsEnabled() ? 'On' : 'Off',
          onTap: () async {
            final current = CacheService.areNotificationsEnabled();
            await CacheService.setNotificationsEnabled(!current);
            setState(() {});
          },
        ),
        _buildMenuItem(
          Icons.bug_report_rounded, 
          'FCM Debug Status', 
          NotificationService.instance.debugStatus,
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: AppColors.surface,
                title: const Text('FCM Diagnostics', style: TextStyle(color: AppColors.textPrimary)),
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Status:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      Text(NotificationService.instance.debugStatus, style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                      const SizedBox(height: 12),
                      const Text('FCM Token:', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      SelectableText(
                        NotificationService.instance.token ?? 'None',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      const Text('APNs Token (iOS Only):', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      SelectableText(
                        NotificationService.instance.apnsToken ?? 'None / Not iOS',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
        ),
        _buildMenuItem(
          Icons.help_outline_rounded, 
          'Help & Support', 
          '',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HelpSupportPage()),
            );
          },
        ),
        _buildMenuItem(
          Icons.book_rounded, 
          'My Travel Journal', 
          'Private',
          onTap: () {
            context.push('/journal');
          },
        ),
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
    String searchQuery = '';
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final filtered = CurrencyService.supportedCurrencies.where((c) {
            final query = searchQuery.toLowerCase();
            return c['code']!.toLowerCase().contains(query) ||
                c['name']!.toLowerCase().contains(query);
          }).toList();
          
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Select Currency',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  style: const TextStyle(color: Colors.black),
                  onChanged: (val) {
                    setState(() {
                      searchQuery = val;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search currency code or name...',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No currencies found',
                            style: TextStyle(color: AppColors.textTertiary, fontSize: 15),
                          ),
                        )
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final c = filtered[index];
                            final isSelected = (user.preferences['currency'] ?? 'USD') == c['code'];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 4),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.primary.withOpacity(0.1) : AppColors.surfaceVariant,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    c['flag']!,
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    c['code']!,
                                    style: TextStyle(
                                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '(${c['symbol']})',
                                    style: const TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                c['name']!,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
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
          );
        },
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

  Widget _buildJournalCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const TravelJournalPage()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text('📖', style: TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MY TRAVEL JOURNAL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: Colors.white70,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Document Your Odyssey',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Save memories & upload photos to your drive',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    ).animate().fade().slideY(begin: 0.1, end: 0);
  }
}
