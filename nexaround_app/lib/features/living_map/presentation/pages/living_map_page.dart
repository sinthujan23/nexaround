import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:nexaround_app/features/attractions/presentation/pages/attraction_detail_page.dart';
import 'package:nexaround_app/features/planning/presentation/pages/odyssey_planner_page.dart';
import 'package:flutter_animate/flutter_animate.dart';

class LivingMapPage extends StatefulWidget {
  const LivingMapPage({super.key});

  @override
  State<LivingMapPage> createState() => _LivingMapPageState();
}

class _LivingMapPageState extends State<LivingMapPage>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _showProximityAlert = false;
  String _selectedCategory = 'All';

  final List<String> _categories = [
    'All', 'Attractions', 'Restaurants', 'Hotels', 'Cafés', 'Shopping'
  ];

  final List<_MockAttraction> _trendingPlaces = [
    _MockAttraction('Lotus Tower', 'Temple', 4.9, '800 m', 'assets/images/lotus_temple.png', '🪷'),
    _MockAttraction('Sigiriya Fortress', 'Ancient', 4.8, '1.2 km', 'assets/images/sigiriya.png', '🏛'),
    _MockAttraction('Colombo Café', 'Café', 4.5, '350 m', 'assets/images/food_corner.png', '☕'),
    _MockAttraction('Galle Fort', 'Heritage', 4.7, '2 km', 'assets/images/craft_market.png', '🏰'),
  ];

  final List<_MockAttraction> _hiddenGems = [
    _MockAttraction('Secret Beach Cove', 'Nature', 4.6, '1.8 km', 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?q=80&w=1000&auto=format&fit=crop', '🏖'),
    _MockAttraction('Dambulla Cave Art', 'Culture', 4.7, '1.5 km', 'https://images.unsplash.com/photo-1544644181-1484b3fdfc62?q=80&w=1000&auto=format&fit=crop', '🎨'),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Show proximity alert after a delay (simulated)
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showProximityAlert = true);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 3D Map Background
        _buildMapBackground(),

        // Content overlay
        CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header
            SliverAppBar(
              floating: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 80,
              flexibleSpace: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(color: AppColors.background.withOpacity(0.5)),
                ),
              ),
              title: _buildHeader(),
            ),

            // Greeting + AI prompt
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGreeting(),
                    const SizedBox(height: 24),
                    _buildAIPromptBar(),
                    const SizedBox(height: 16),
                    _buildOdysseyCTA(),
                  ],
                ),
              ),
            ),

            // Categories
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 28, bottom: 8),
                child: _buildCategoryScroller(),
              ),
            ),

            // Trending Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: _buildSectionHeader('🔥  Trending Near You', 'See all'),
              ),
            ),
            SliverToBoxAdapter(child: _buildTrendingCards()),

            // Hidden Gems
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: _buildSectionHeader('✨  Hidden Gems', 'Explore'),
              ),
            ),
            SliverToBoxAdapter(child: _buildHiddenGemCards()),

            // Cluster suggestion
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _buildClusterSuggestion(),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),

        // Proximity alert bottom sheet
        if (_showProximityAlert) _buildProximityAlert(),
      ],
    );
  }

  Widget _buildMapBackground() {
    return Positioned.fill(
      child: Container(color: AppColors.background),
    );
  }



  Widget _buildHeader() {
    return Row(
      children: [
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          borderRadius: BorderRadius.circular(100),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryGradient,
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)],
                ),
                child: const Icon(Icons.near_me_rounded, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CURRENT NEIGHBORHOOD',
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 1),
                  ),
                  const Text(
                    'Colombo, Sri Lanka',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Spacer(),
        _buildGlassCircle(Icons.notifications_none_rounded),
      ],
    );
  }

  Widget _buildGlassCircle(IconData icon) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.glassWhite,
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: 20),
        ),
      ),
    );
  }

  Widget _buildGreeting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Good Afternoon, Alex',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w500,
          ),
        ).animate().fade(),
        const SizedBox(height: 8),
        const Text(
          'Where shall we\ndiscover today?',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            height: 1.15,
            color: AppColors.textPrimary,
            letterSpacing: -1,
          ),
        ).animate().fade(delay: 100.ms).slideY(begin: 0.15, end: 0),
      ],
    );
  }

  Widget _buildAIPromptBar() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      glowColor: AppColors.primary,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 12),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: Image.asset(
                'assets/images/neva_avatar.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MEET NEVA',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '"Neva, what\'s the secret vibe here?"',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Icon(Icons.mic_rounded, color: AppColors.primary, size: 18),
          ),
        ],
      ),
    ).animate().fade(delay: 300.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildOdysseyCTA() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OdysseyPlannerPage()),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.ratingGold.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: const Icon(Icons.auto_mode_rounded, color: AppColors.ratingGold, size: 24),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: AppColors.ratingGold, shape: BoxShape.circle),
                    child: const Icon(Icons.star, size: 8, color: Colors.black),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BUILD AN ODYSSEY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ratingGold,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Personalized Trip Mining',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 16),
          ],
        ),
      ),
    ).animate().fade(delay: 400.ms).slideX(begin: 0.1, end: 0);
  }

  Widget _buildCategoryScroller() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isActive = _selectedCategory == cat;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: isActive ? AppColors.primaryGradient : null,
                color: isActive ? null : AppColors.surfaceVariant,
                border: Border.all(
                  color: isActive ? Colors.transparent : AppColors.border,
                ),
                boxShadow: isActive
                    ? [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 10)]
                    : null,
              ),
              child: Center(
                child: Text(
                  cat,
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
    );
  }

  Widget _buildSectionHeader(String title, String action) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        GestureDetector(
          onTap: () {},
          child: ShaderMask(
            shaderCallback: (b) => AppColors.primaryGradient.createShader(
              Rect.fromLTWH(0, 0, b.width, b.height),
            ),
            child: Text(
              action,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrendingCards() {
    return SizedBox(
      height: 240,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 16, 0, 0),
        scrollDirection: Axis.horizontal,
        itemCount: _trendingPlaces.length,
        itemBuilder: (context, index) {
          final p = _trendingPlaces[index];
          return _buildPlaceCard(p, index);
        },
      ),
    );
  }

  Widget _buildPlaceCard(_MockAttraction place, int index) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AttractionDetailPage(name: place.name, category: place.category, rating: place.rating, distance: place.distance, emoji: place.emoji, imageUrl: place.imageUrl)),
      ),
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 16),
        child: Stack(
          children: [
            // Card background image + overlay
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                image: DecorationImage(
                  image: place.imageUrl.startsWith('assets/') 
                      ? AssetImage(place.imageUrl) as ImageProvider
                      : NetworkImage(place.imageUrl),
                  fit: BoxFit.cover,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.9),
                      Colors.black.withOpacity(0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Emoji + category
                  Row(
                    children: [
                      Text(place.emoji, style: const TextStyle(fontSize: 28)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white.withOpacity(0.2),
                        ),
                        child: Text(
                          place.category,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Name
                  Text(
                    place.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),

                  // Rating & distance
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 14, color: AppColors.ratingGold),
                      const SizedBox(width: 4),
                      Text(
                        place.rating.toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.location_on_rounded, size: 12, color: Colors.white.withOpacity(0.7)),
                      const SizedBox(width: 3),
                      Text(
                        place.distance,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Action
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: AppColors.primaryGradient,
                    ),
                    child: const Text(
                      'Explore →',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ).animate().fade(delay: Duration(milliseconds: 100 * index)).slideX(begin: 0.1, end: 0),
    );
  }

  Widget _buildHiddenGemCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: _hiddenGems.asMap().entries.map((entry) {
          final p = entry.value;
          final i = entry.key;
          return _buildGemRow(p, i);
        }).toList(),
      ),
    );
  }

  Widget _buildGemRow(_MockAttraction place, int index) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AttractionDetailPage(name: place.name, category: place.category, rating: place.rating, distance: place.distance, emoji: place.emoji, imageUrl: place.imageUrl)),
      ),
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: AppColors.secondaryGradient.scale(0.3),
              ),
              child: Center(
                child: Text(place.emoji, style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.star_rounded, size: 13, color: AppColors.warning),
                      const SizedBox(width: 3),
                      Text('${place.rating}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Text(place.distance, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textTertiary),
          ],
        ),
      ).animate().fade(delay: Duration(milliseconds: 100 * index)).slideX(begin: 0.05, end: 0),
    );
  }

  Widget _buildClusterSuggestion() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      glowColor: AppColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.secondaryGradient,
                ),
                child: const Icon(Icons.route_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Mini Tour Nearby',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Route items
          _buildRouteItem('1', 'Lotus Tower', '10 min walk', AppColors.primary),
          _buildRouteConnector(),
          _buildRouteItem('2', 'Colombo Museum', '5 min walk', AppColors.secondary),
          _buildRouteConnector(),
          _buildRouteItem('3', 'Independence Square', '8 min walk', AppColors.neonGreen),
          _buildRouteConnector(),
          _buildRouteItem('4', 'Colombo Café Lounge', 'Destination', AppColors.accent),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
              ),
              child: TextButton(
                onPressed: () {},
                child: Text(
                  'START TOUR',
                  style: TextStyle(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fade(delay: 400.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildRouteItem(String num, String name, String info, Color color) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.05),
            border: Border.all(color: Colors.black.withOpacity(0.1)),
          ),
          child: Center(
            child: Text(num, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ),
        Text(info, style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
      ],
    );
  }

  Widget _buildRouteConnector() {
    return Padding(
      padding: const EdgeInsets.only(left: 13),
      child: Container(width: 2, height: 20, color: AppColors.border),
    );
  }

  Widget _buildProximityAlert() {
    return Positioned(
      bottom: 110,
      left: 20,
      right: 20,
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        glowColor: AppColors.primary,
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.15),
                  ),
                  child: Icon(Icons.location_on_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PROXIMITY ALERT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'You are near Lotus Temple',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showProximityAlert = false),
                  child: Icon(Icons.close_rounded, color: AppColors.textTertiary, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: AppColors.primaryGradient,
                    ),
                    child: TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AttractionDetailPage(name: 'Lotus Tower', category: 'Temple', rating: 4.9, distance: '200 m', emoji: '🪷', imageUrl: 'assets/images/lotus_temple.png'))),
                      child: const Text('View Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.secondary.withOpacity(0.4)),
                    ),
                    child: TextButton(
                      onPressed: () {},
                      child: Text('Start AR', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ).animate().slideY(begin: 1, end: 0, duration: 500.ms, curve: Curves.easeOutBack).fade(),
    );
  }
}

class _MockAttraction {
  final String name;
  final String category;
  final double rating;
  final String distance;
  final String imageUrl;
  final String emoji;

  const _MockAttraction(this.name, this.category, this.rating, this.distance, this.imageUrl, this.emoji);
}


