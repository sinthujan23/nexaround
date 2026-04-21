import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:flutter_animate/flutter_animate.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> with TickerProviderStateMixin {
  int _selectedTab = 0;
  late AnimationController _radarController;

  final List<String> _tabs = ['Food', 'Experiences', 'Shopping', 'Budget', 'Emergency'];

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback: (b) => AppColors.primaryGradient.createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
                    child: const Text(
                      'Discover',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppColors.surfaceVariant,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
                  ),
                ],
              ),
            ),

            // Tab selector
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: SizedBox(
                height: 40,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  scrollDirection: Axis.horizontal,
                  itemCount: _tabs.length,
                  itemBuilder: (context, index) {
                    final isActive = _selectedTab == index;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedTab = index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: isActive ? AppColors.primaryGradient : null,
                          color: isActive ? null : AppColors.surfaceVariant,
                          border: Border.all(color: isActive ? Colors.transparent : AppColors.border),
                        ),
                        child: Center(
                          child: Text(
                            _tabs[index],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                              color: isActive ? Colors.white : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildTabContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0: return _buildFoodTab();
      case 1: return _buildExperiencesTab();
      case 2: return _buildShoppingTab();
      case 3: return _buildBudgetTab();
      case 4: return _buildEmergencyTab();
      default: return _buildFoodTab();
    }
  }

  // ═══════════════════════════════════════
  // FOOD TAB
  // ═══════════════════════════════════════
  Widget _buildFoodTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Radar
        _buildFoodRadar(),
        const SizedBox(height: 28),

        // Categories
        const Text('Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        Row(
          children: [
            _buildFoodCategory('🍜', 'Street Food', const Color(0xFFFFEAEA)),
            const SizedBox(width: 10),
            _buildFoodCategory('🍽', 'Fine Dining', const Color(0xFFEAF2FF)),
            const SizedBox(width: 10),
            _buildFoodCategory('☕', 'Cafés', const Color(0xFFFFF8EA)),
          ],
        ),
        const SizedBox(height: 28),

        // Restaurant list
        const Text('Top Picks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        _buildRestaurantCard('Ministry of Crab', '🦀', 4.8, 'Seafood · Fine Dining', 'LKR 3,500', '800 m', 0),
        _buildRestaurantCard('Hoppers Corner', '🥘', 4.6, 'Local · Street Food', 'LKR 850', '200 m', 1),
        _buildRestaurantCard('Tea House Garden', '🍵', 4.7, 'Café · Tea Experience', 'LKR 1,200', '600 m', 2),
        _buildRestaurantCard('Colombo Café Lounge', '☕', 4.5, 'Café · Fusion', 'LKR 2,200', '350 m', 3),
      ],
    );
  }

  Widget _buildFoodRadar() {
    return Center(
      child: SizedBox(
        width: 220,
        height: 220,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Rings
            ...List.generate(3, (i) => Container(
              width: 80.0 + i * 70,
              height: 80.0 + i * 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withOpacity(0.1 + i * 0.05)),
              ),
            )),

            // Sweep
            AnimatedBuilder(
              animation: _radarController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _radarController.value * 2 * pi,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.08),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.25, 0.5],
                      ),
                    ),
                  ),
                );
              },
            ),

            // Food dots
            _buildRadarDot(0.15, -0.2, '🍜', const Color(0xFFFF5252)),
            _buildRadarDot(-0.25, 0.15, '🦀', const Color(0xFFFFAB40)),
            _buildRadarDot(0.3, 0.28, '☕', const Color(0xFF8D6E63)),
            _buildRadarDot(-0.1, -0.35, '🥘', const Color(0xFF66BB6A)),
            _buildRadarDot(0.35, -0.05, '🍵', const Color(0xFF26C6DA)),

            // Center dot
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.6), blurRadius: 12)],
              ),
            ),

            // Pulse
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary),
              ),
            )
                .animate(onPlay: (c) => c.repeat())
                .scale(begin: const Offset(1, 1), end: const Offset(5, 5), duration: 2.seconds)
                .fade(begin: 0.6, end: 0),
          ],
        ),
      ),
    ).animate().fade().scale(begin: const Offset(0.8, 0.8));
  }

  Widget _buildRadarDot(double dx, double dy, String emoji, Color color) {
    return Positioned(
      left: 110 + dx * 200 - 14,
      top: 110 + dy * 200 - 14,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.2),
          border: Border.all(color: color.withOpacity(0.5)),
          boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8)],
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 12))),
      )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 1500.ms),
    );
  }

  Widget _buildFoodCategory(String emoji, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestaurantCard(String name, String emoji, double rating, String type, String price, String dist, int index) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppColors.primary.withOpacity(0.1),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(type, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.star_rounded, size: 13, color: AppColors.warning),
                    const SizedBox(width: 3),
                    Text('$rating', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(width: 10),
                    Text(dist, style: TextStyle(fontSize: 11, color: AppColors.primary)),
                    const SizedBox(width: 10),
                    Text(price, style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: AppColors.primaryGradient,
            ),
            child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 16),
          ),
        ],
      ),
    ).animate().fade(delay: Duration(milliseconds: 100 * index)).slideX(begin: 0.05, end: 0);
  }

  // ═══════════════════════════════════════
  // EXPERIENCES TAB
  // ═══════════════════════════════════════
  Widget _buildExperiencesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildExperienceCard('Village Cycling Tour', '🚲', 'Explore traditional Sri Lankan villages on a guided cycling adventure through paddy fields.', '3 hours', 'LKR 4,500', 4.8, 0),
        _buildExperienceCard('Batik Workshop', '🎨', 'Learn the ancient art of batik from master craftsmen in a traditional workshop.', '2 hours', 'LKR 3,000', 4.6, 1),
        _buildExperienceCard('Tea Plantation Walk', '🍃', 'Guided tour through lush tea estates with tasting sessions of premium Ceylon tea.', '4 hours', 'LKR 5,200', 4.9, 2),
        _buildExperienceCard('Cooking Class', '👨‍🍳', 'Master Sri Lankan cuisine — hoppers, curries, and sambols — with a local chef.', '3 hours', 'LKR 3,800', 4.7, 3),
        _buildExperienceCard('Sunset Boat Ride', '🚣', 'Scenic boat ride through mangroves and lagoons as the sun sets.', '2 hours', 'LKR 2,800', 4.5, 4),
      ],
    );
  }

  Widget _buildExperienceCard(String title, String emoji, String desc, String duration, String price, double rating, int index) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      glowColor: index % 2 == 0 ? AppColors.secondary : AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Row(
                      children: [
                        Icon(Icons.star_rounded, size: 13, color: AppColors.warning),
                        Text(' $rating', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        const SizedBox(width: 10),
                        Icon(Icons.schedule_rounded, size: 12, color: AppColors.textTertiary),
                        Text(' $duration', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                      ],
                    ),
                  ],
                ),
              ),
              Text(price, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 10),
          Text(desc, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
        ],
      ),
    ).animate().fade(delay: Duration(milliseconds: 100 * index)).slideY(begin: 0.05, end: 0);
  }

  // ═══════════════════════════════════════
  // SHOPPING TAB
  // ═══════════════════════════════════════
  Widget _buildShoppingTab() {
    final markets = [
      {'name': 'Pettah Market', 'emoji': '🏪', 'type': 'Traditional bazaar', 'dist': '1.2 km'},
      {'name': 'Odel Department Store', 'emoji': '🛍', 'type': 'Designer fashion', 'dist': '800 m'},
      {'name': 'Laksala Craft Centre', 'emoji': '🎭', 'type': 'Handicrafts & souvenirs', 'dist': '500 m'},
      {'name': 'Floating Market', 'emoji': '🌊', 'type': 'Night market on water', 'dist': '1.8 km'},
      {'name': 'Barefoot Gallery', 'emoji': '🧶', 'type': 'Textiles & art', 'dist': '600 m'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Map preview placeholder
        GlassCard(
          padding: EdgeInsets.zero,
          child: Container(
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.surfaceElevated, AppColors.primary.withOpacity(0.08)],
              ),
            ),
            child: Stack(
              children: [
                Center(child: Icon(Icons.map_rounded, size: 48, color: AppColors.textMuted)),
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: AppColors.primaryGradient,
                    ),
                    child: const Text('View Full Map', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ).animate().fade(),
        const SizedBox(height: 24),
        const Text('Markets & Shops', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        ...markets.asMap().entries.map((e) => _buildShopItem(e.value, e.key)),
      ],
    );
  }

  Widget _buildShopItem(Map<String, String> shop, int index) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Text(shop['emoji']!, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shop['name']!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(shop['type']!, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
              ],
            ),
          ),
          Text(shop['dist']!, style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
        ],
      ),
    ).animate().fade(delay: Duration(milliseconds: 80 * index)).slideX(begin: 0.05, end: 0);
  }

  // ═══════════════════════════════════════
  // BUDGET TAB
  // ═══════════════════════════════════════
  Widget _buildBudgetTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Today's budget overview
        GlassCard(
          padding: const EdgeInsets.all(20),
          glowColor: AppColors.primary,
          child: Column(
            children: [
              const Text('TODAY\'S SPENDING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textTertiary, letterSpacing: 2)),
              const SizedBox(height: 12),
              ShaderMask(
                shaderCallback: (b) => AppColors.primaryGradient.createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
                child: const Text('LKR 8,450', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(height: 6),
              Text('of LKR 15,000 daily budget', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
              const SizedBox(height: 16),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  children: [
                    Container(height: 8, color: AppColors.surfaceVariant),
                    FractionallySizedBox(
                      widthFactor: 0.56,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: AppColors.primaryGradient,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('56% used', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
            ],
          ),
        ).animate().fade(),
        const SizedBox(height: 24),

        const Text('By Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        _buildBudgetCategory('🍽', 'Food & Drinks', 'LKR 3,200', 0.38, AppColors.accent, 0),
        _buildBudgetCategory('🚕', 'Transport', 'LKR 2,800', 0.33, AppColors.secondary, 1),
        _buildBudgetCategory('🛍', 'Shopping', 'LKR 1,500', 0.18, AppColors.warning, 2),
        _buildBudgetCategory('🎫', 'Activities', 'LKR 950', 0.11, AppColors.neonGreen, 3),

        const SizedBox(height: 24),
        const Text('Recent Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        _buildTransaction('Hoppers Corner', '🥘', '-LKR 850', '12:30 PM'),
        _buildTransaction('Tuk-tuk ride', '🛺', '-LKR 400', '11:15 AM'),
        _buildTransaction('Colombo Museum', '🏛', '-LKR 1,500', '09:45 AM'),
        _buildTransaction('Morning tea', '☕', '-LKR 350', '08:00 AM'),
      ],
    );
  }

  Widget _buildBudgetCategory(String emoji, String name, String amount, double pct, Color color, int index) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      Container(height: 4, color: AppColors.surfaceVariant),
                      FractionallySizedBox(
                        widthFactor: pct,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text(amount, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    ).animate().fade(delay: Duration(milliseconds: 100 * index));
  }

  Widget _buildTransaction(String name, String emoji, String amount, String time) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(time, style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ),
          Text(amount, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.error)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // EMERGENCY TAB
  // ═══════════════════════════════════════
  Widget _buildEmergencyTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // SOS button
        Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error.withOpacity(0.15),
                border: Border.all(color: AppColors.error.withOpacity(0.4), width: 3),
                boxShadow: [BoxShadow(color: AppColors.error.withOpacity(0.2), blurRadius: 30)],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.emergency_rounded, size: 40, color: AppColors.error),
                  const SizedBox(height: 6),
                  Text('SOS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.error, letterSpacing: 3)),
                ],
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05), duration: 1.seconds),
          ),
        ).animate().fade(),
        const SizedBox(height: 28),

        const Text('Nearby Hospitals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        _buildEmergencyCard('National Hospital', '🏥', '1.2 km', '+94 11 269 1111', 0),
        _buildEmergencyCard('Lanka Hospital', '🏥', '2.5 km', '+94 11 553 0000', 1),
        _buildEmergencyCard('Nawaloka Hospital', '🏥', '1.8 km', '+94 11 254 4444', 2),

        const SizedBox(height: 24),
        const Text('Emergency Numbers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        _buildEmergencyNumber('Police', '119', Icons.local_police_rounded),
        _buildEmergencyNumber('Ambulance', '1990', Icons.medical_services_rounded),
        _buildEmergencyNumber('Fire', '110', Icons.local_fire_department_rounded),
        _buildEmergencyNumber('Tourist Police', '+94 11 242 1052', Icons.support_agent_rounded),

        const SizedBox(height: 24),
        const Text('Emergency Phrases', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        _buildPhrase('Help!', 'උදව් කරන්න! (Udaw karanna!)'),
        _buildPhrase('I need a doctor', 'මට වෛද්‍යවරයෙක් ඕනැ (Mata vaidyawarayek one)'),
        _buildPhrase('Where is the hospital?', 'රෝහල කොහෙද? (Rohala koheda?)'),
        _buildPhrase('Call the police', 'පොලීසියට කතා කරන්න (Polisiyata katha karanna)'),
      ],
    );
  }

  Widget _buildEmergencyCard(String name, String emoji, String dist, String phone, int index) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      glowColor: AppColors.error,
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(dist, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.error.withOpacity(0.15),
              border: Border.all(color: AppColors.error.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.phone_rounded, color: AppColors.error, size: 14),
                const SizedBox(width: 4),
                Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.error)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fade(delay: Duration(milliseconds: 100 * index));
  }

  Widget _buildEmergencyNumber(String label, String number, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.error),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
          Text(number, style: TextStyle(fontSize: 14, color: AppColors.primary, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildPhrase(String english, String sinhala) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(english, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(sinhala, style: TextStyle(fontSize: 13, color: AppColors.primary)),
        ],
      ),
    );
  }
}
