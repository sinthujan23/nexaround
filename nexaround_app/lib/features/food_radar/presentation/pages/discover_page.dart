import 'dart:math';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/utils/number_format.dart';
import 'package:nexaround_app/core/widgets/glass_card.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/attractions/presentation/pages/attraction_detail_page.dart';
import 'package:nexaround_app/features/budget/presentation/bloc/budget_bloc.dart';
import 'package:nexaround_app/features/budget/presentation/bloc/budget_state.dart';
import 'package:nexaround_app/features/budget/presentation/bloc/budget_event.dart';
import 'package:nexaround_app/features/budget/domain/entities/budget.dart' as budget_entity;
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nexaround_app/core/utils/place_image_helper.dart';

import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_bloc.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_event.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_state.dart';
import 'package:nexaround_app/features/auth/presentation/pages/login_page.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexaround_app/core/services/gemini_service.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> with TickerProviderStateMixin {
  int _selectedTab = 0;
  late AnimationController _radarController;
  Position? _currentPosition;

  // Real data lists for each category to avoid mixing
  List<AttractionEntity> _foodList = [];
  List<AttractionEntity> _experienceList = [];
  List<AttractionEntity> _shoppingList = [];

  // Emergency tab state
  List<Map<String, dynamic>> _nearbyHospitals = [];
  Map<String, dynamic>? _emergencyInfo;
  bool _isLoadingEmergency = false;

  final List<String> _tabs = ['Food', 'Experiences', 'Shopping', 'Budget', 'Emergency'];

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _initLocationAndFetch();
  }

  Future<void> _initLocationAndFetch() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _currentPosition = position);
      _fetchForTab(0); // Fetch food initially
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  void _fetchForTab(int index) {
    if (_currentPosition == null) return;

    String? category;
    if (index == 0) category = 'Food & Drink';
    if (index == 1) category = 'Attractions';
    if (index == 2) category = 'Shopping';

    if (category != null) {
      context.read<MapBloc>().add(FetchNearbyAttractions(
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        categoryName: category,
      ));
    }
  }


  static const String _emergencyCacheKey = 'cached_emergency_data';

  Future<void> _loadEmergencyCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_emergencyCacheKey);
      if (raw == null || !mounted) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final hospitals = (data['hospitals'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? [];
      final info = data['info'] != null
          ? Map<String, dynamic>.from(data['info'] as Map)
          : null;
      if (mounted) {
        setState(() {
          _nearbyHospitals = hospitals;
          _emergencyInfo = info;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveEmergencyCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_emergencyCacheKey, jsonEncode({
        'hospitals': _nearbyHospitals,
        'info': _emergencyInfo,
      }));
    } catch (_) {}
  }

  Future<void> _fetchEmergencyData() async {
    if (_currentPosition == null || _isLoadingEmergency) return;
    // Load cache first for instant display
    await _loadEmergencyCache();
    setState(() => _isLoadingEmergency = true);

    try {
      // Fetch nearby hospitals via Google Places API proxy
      final lat = _currentPosition!.latitude;
      final lng = _currentPosition!.longitude;
      final response = await ApiClient.instance.get(
        '${ApiConstants.googleMapsProxy}/place/nearbysearch/json',
        queryParameters: {
          'location': '$lat,$lng',
          'radius': 5000,
          'type': 'hospital',
        },
      );
      final List<Map<String, dynamic>> hospitals = [];
      if (response.statusCode == 200) {
        final data = response.data;
        final results = data['results'] as List? ?? [];
        for (final place in results.take(5)) {
          final placeLocation = place['geometry']?['location'];
          double? distKm;
          if (placeLocation != null) {
            final d = Geolocator.distanceBetween(
              lat, lng,
              (placeLocation['lat'] as num).toDouble(),
              (placeLocation['lng'] as num).toDouble(),
            );
            distKm = d / 1000;
          }
          hospitals.add({
            'name': place['name'] ?? 'Hospital',
            'address': place['vicinity'] ?? '',
            'dist': distKm != null ? '${distKm.toStringAsFixed(1)} km' : '',
            'open': place['opening_hours']?['open_now'],
            'placeId': place['place_id'] ?? '',
            'lat': (placeLocation?['lat'] as num?)?.toDouble() ?? lat,
            'lng': (placeLocation?['lng'] as num?)?.toDouble() ?? lng,
          });
        }
        hospitals.sort((a, b) {
          final da = double.tryParse((a['dist'] as String).replaceAll(' km', '')) ?? 999;
          final db = double.tryParse((b['dist'] as String).replaceAll(' km', '')) ?? 999;
          return da.compareTo(db);
        });
      }

      // Fetch emergency numbers + phrases for this location via Gemini
      final geminiPrompt =
          'I am a traveller at GPS coordinates ($lat, $lng). '
          'What country/city am I likely in? '
          'Give me ONLY a JSON object with these fields (no markdown): '
          '{ "country": "...", "city": "...", "emergency_numbers": [{"label":"Police","number":"..."},{"label":"Ambulance","number":"..."},{"label":"Fire","number":"..."},{"label":"Tourist Helpline","number":"..."}], '
          '"phrases": [{"english":"Help!","local":"..."},{"english":"I need a doctor","local":"..."},{"english":"Where is the hospital?","local":"..."},{"english":"Call the police","local":"..."}] }';

      final rawGemini = await GeminiService().getResponse(geminiPrompt);
      Map<String, dynamic>? info;
      try {
        String json = rawGemini.trim();
        if (json.contains('```')) {
          json = json.replaceAll(RegExp(r'```json?\n?'), '').replaceAll(RegExp(r'\n?```'), '');
        }
        info = jsonDecode(json) as Map<String, dynamic>;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _nearbyHospitals = hospitals;
          _emergencyInfo = info;
          _isLoadingEmergency = false;
        });
        _saveEmergencyCache();
      }
    } catch (e) {
      debugPrint('Emergency fetch error: $e');
      if (mounted) setState(() => _isLoadingEmergency = false);
    }
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
        child: BlocListener<MapBloc, MapState>(
          listener: (context, state) {},
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
                        onTap: () {
                          setState(() => _selectedTab = index);
                          _fetchForTab(index);
                          if (index == 4) _fetchEmergencyData();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: isActive ? AppColors.brandGreen : AppColors.surfaceVariant,
                            border: Border.all(color: isActive ? Colors.transparent : AppColors.border),
                            boxShadow: isActive
                                ? [BoxShadow(color: AppColors.brandGreen.withOpacity(0.3), blurRadius: 10)]
                                : null,
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
                child: BlocBuilder<MapBloc, MapState>(
                  builder: (context, state) {
                    final isLoading = _selectedTab < 3 && state.status == MapStatus.loading;
                    
                    // Populate lists from state.allAttractions (master cached list) or fallback to state.attractions
                    final masterList = state.allAttractions.isNotEmpty ? state.allAttractions : state.attractions;
                    
                    // Filter Food List
                    _foodList = masterList.where((a) {
                      final cat = (a.categoryName ?? '').toLowerCase();
                      final name = a.name.toLowerCase();
                      return cat.contains('food') || cat.contains('restaurant') || cat.contains('cafe') || 
                             cat.contains('dining') || cat.contains('meal') || name.contains('restaurant') || name.contains('cafe');
                    }).toList();
                    _foodList.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));

                    // Filter Experiences List
                    _experienceList = masterList.where((a) {
                      final cat = (a.categoryName ?? '').toLowerCase();
                      final name = a.name.toLowerCase();
                      return cat.contains('attraction') || cat.contains('museum') || cat.contains('park') || 
                             cat.contains('experience') || cat.contains('landmark') || cat.contains('culture') ||
                             cat.contains('temple') || cat.contains('art') || cat.contains('zoo') ||
                             name.contains('temple') || name.contains('park') || name.contains('museum');
                    }).toList();
                    _experienceList.sort((a, b) {
                      int ratingComp = b.rating.compareTo(a.rating);
                      if (ratingComp != 0) return ratingComp;
                      return (a.distanceM ?? 0).compareTo(b.distanceM ?? 0);
                    });

                    // Filter Shopping List
                    _shoppingList = masterList.where((a) {
                      final cat = (a.categoryName ?? '').toLowerCase();
                      return cat.contains('shop') || cat.contains('mall') || cat.contains('market') || 
                             cat.contains('store') || cat.contains('fashion');
                    }).toList();
                    _shoppingList.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));

                    return Column(
                      children: [
                        if (isLoading)
                          LinearProgressIndicator(
                            minHeight: 2,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: _buildTabContent(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
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
  Widget _buildFoodTab_PLACEHOLDER_DELETE_ME() {
    return const SizedBox.shrink();
  }

  Widget _buildScanResultCard_PLACEHOLDER_DELETE_ME() {
    return const SizedBox.shrink();
  }

  Widget _buildFoodTab_PLACEHOLDER_DELETE_ME_ORIGINAL() {
    return const SizedBox.shrink();
  }

  Widget _buildFoodTab_PLACEHOLDER_DELETE_ME_ORIGINAL_BODY() {
    return const SizedBox.shrink();
  }

  Widget _buildFoodTab_PLACEHOLDER_DELETE_ME_ORIGINAL_BODY_REAL() {
    return const SizedBox.shrink();
  }

  Widget _buildFoodTab_DEAD_CODE_DO_NOT_CALL() {
    return const SizedBox.shrink();
  }

  Widget _buildFoodTab_DEAD_CODE_BODY() {
    return const SizedBox.shrink();
  }

  Widget _buildFoodTab_DEAD_CODE_BODY_REAL() {
    return const SizedBox.shrink();
  }

  Widget _buildScanResultCard_UNUSED_DO_NOT_CALL() {
    return const SizedBox.shrink();
  }

  Widget _buildScanResultCard_UNUSED_DO_NOT_CALL_BODY() {
    final Map<String, dynamic> result = {};
    final name = result['name'] ?? 'Unknown Place';
    final category = result['category'] ?? 'Place';
    final description = result['description'] ?? '';
    final funFact = result['fun_fact'] ?? '';
    final tips = result['tips'] ?? '';
    final confidence = (result['confidence'] ?? 0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Place name + category
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${(confidence * 100).toInt()}%',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  category.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 200.ms).slideX(begin: 0.1, end: 0),

        const SizedBox(height: 16),

        // Description
        if (description.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_stories_rounded, size: 18, color: AppColors.textSecondary),
                    SizedBox(width: 8),
                    Text('About', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: const TextStyle(fontSize: 14, height: 1.6, color: AppColors.textSecondary),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1, end: 0),

        const SizedBox(height: 12),

        // Fun Fact
        if (funFact.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.amber.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💡', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Fun Fact', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text(funFact, style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.1, end: 0),

        const SizedBox(height: 12),

        // Tips
        if (tips.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.blue.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🎒', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Visitor Tip', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text(tips, style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.1, end: 0),

        const SizedBox(height: 20),
      ],
    );
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
        if (_foodList.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('No real food places found nearby.', style: TextStyle(color: AppColors.textTertiary))),
          )
        else
          ..._foodList.asMap().entries.map((e) {
            final a = e.value;
            return _buildRestaurantCard(a, e.key);
          }),
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

            // Food dots (Real)
            ..._foodList.take(5).toList().asMap().entries.map((e) {
              final a = e.value;
              // Generate pseudo-random coordinates for the radar based on attraction ID
              final random = Random(a.id.hashCode);
              final dx = random.nextDouble() * 0.8 - 0.4;
              final dy = random.nextDouble() * 0.8 - 0.4;
              return _buildRadarDot(dx, dy, a, AppColors.primary);
            }),

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

  Widget _buildRadarDot(double dx, double dy, AttractionEntity place, Color color) {
    return Positioned(
      left: 110 + dx * 200 - 16,
      top: 110 + dy * 200 - 16,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.2),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: PlaceImageHelper.buildPlaceImage(
            imagePath: place.photoUrls.isNotEmpty ? place.photoUrls.first : null,
            category: place.categoryName ?? 'Food',
            name: place.name,
          ),
        ),
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

  Widget _buildRestaurantCard(AttractionEntity a, int index) {
    final dist = _currentPosition != null
        ? (Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, a.latitude, a.longitude) / 1000).toStringAsFixed(1)
        : ((a.distanceM ?? 0) / 1000).toStringAsFixed(1);
    
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AttractionDetailPage(
          id: a.id,
          name: a.name,
          category: a.categoryName ?? 'Restaurant',
          rating: a.rating,
          distance: '$dist km',
          emoji: '🍽',
          imageUrl: a.photoUrls.isNotEmpty ? a.photoUrls.first : null,
          latitude: a.latitude,
          longitude: a.longitude,
        )),
      ),
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppColors.surfaceVariant,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: PlaceImageHelper.buildPlaceImage(
                imagePath: a.photoUrls.isNotEmpty ? a.photoUrls.first : null,
                category: a.categoryName ?? 'Food',
                name: a.name,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(a.categoryName ?? 'Restaurant', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
                    const SizedBox(width: 3),
                    Text('${a.rating}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(width: 12),
                    Icon(Icons.near_me_rounded, size: 12, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text('$dist km', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              GestureDetector(
                onTap: () async {
                  await CacheService.toggleSavedPlace((a as AttractionModel).toJson());
                  setState(() {}); // Refresh UI
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CacheService.isPlaceSaved(a.id) ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
                  ),
                  child: Icon(
                    CacheService.isPlaceSaved(a.id) ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                    color: CacheService.isPlaceSaved(a.id) ? AppColors.primary : AppColors.textTertiary,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: AppColors.primaryGradient,
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10)],
                ),
                child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 18),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildExperiencesTab() {
    final featuredExperiences = _experienceList.take(5).toList();
    final remainingExperiences = _experienceList.skip(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Featured Experiences (Horizontal Carousel like Homepage)
        const Text('Featured Experiences', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 16),
        if (featuredExperiences.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('Searching for experiences...', style: TextStyle(color: AppColors.textTertiary))),
          )
        else
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: featuredExperiences.length,
              itemBuilder: (context, index) {
                final p = featuredExperiences[index];
                return _buildFeaturedExperienceCard(p, index);
              },
            ),
          ),
        
        const SizedBox(height: 32),

        // Interests/Categories
        const Text('Browse by Interest', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        Row(
          children: [
            _buildFoodCategory('🏛', 'Museums', const Color(0xFFEAF2FF)),
            const SizedBox(width: 10),
            _buildFoodCategory('🌳', 'Parks', const Color(0xFFEAFFAA)),
            const SizedBox(width: 10),
            _buildFoodCategory('🗿', 'Culture', const Color(0xFFF2EAFF)),
          ],
        ),
        const SizedBox(height: 32),

        // Curated List
        const Text('Curated for You', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        if (remainingExperiences.isEmpty && featuredExperiences.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('No real experiences found nearby.', style: TextStyle(color: AppColors.textTertiary))),
          )
        else
          ...remainingExperiences.asMap().entries.map((e) {
            final a = e.value;
            return _buildExperienceCard(a, e.key);
          }),
      ],
    );
  }

  Widget _buildFeaturedExperienceCard(AttractionEntity place, int index) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AttractionDetailPage(
          id: place.id,
          name: place.name,
          category: place.categoryName ?? 'Attraction',
          rating: place.rating,
          distance: '${((place.distanceM ?? 0) / 1000).toStringAsFixed(1)} km',
          emoji: '📍',
          imageUrl: place.photoUrls.isNotEmpty ? place.photoUrls.first : null,
          latitude: place.latitude,
          longitude: place.longitude,
        )),
      ),
      child: Container(
        width: 260,
        margin: const EdgeInsets.only(right: 16),
      child: Stack(
        children: [
          // Background Image
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              image: DecorationImage(
                image: _getImageProvider(
                  place.photoUrls.isNotEmpty ? place.photoUrls.first : null,
                  place.categoryName ?? 'Attraction',
                  place.name,
                ),
                fit: BoxFit.cover,
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8)),
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
                    Colors.black.withOpacity(0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white.withOpacity(0.2),
                  ),
                  child: Text(
                    place.categoryName?.toUpperCase() ?? 'EXPERIENCE',
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1),
                  ),
                ),
                const Spacer(),
                Text(
                  place.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, height: 1.2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: AppColors.ratingGold),
                    const SizedBox(width: 4),
                    Text('${place.rating}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(width: 12),
                    Icon(Icons.location_on_rounded, size: 12, color: Colors.white.withOpacity(0.7)),
                    const SizedBox(width: 3),
                    Text(
                      '${((place.distanceM ?? 0) / 1000).toStringAsFixed(1)} km',
                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildExperienceCard(AttractionEntity a, int index) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AttractionDetailPage(
          id: a.id,
          name: a.name,
          category: a.categoryName ?? 'Attraction',
          rating: a.rating,
          distance: '${((a.distanceM ?? 0) / 1000).toStringAsFixed(1)} km',
          emoji: '📍',
          imageUrl: a.photoUrls.isNotEmpty ? a.photoUrls.first : null,
          latitude: a.latitude,
          longitude: a.longitude,
        )),
      ),
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      glowColor: index % 2 == 0 ? AppColors.secondary : AppColors.primary,
      child: Row(
        children: [
          // Thumbnail
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              image: DecorationImage(
                image: _getImageProvider(
                  a.photoUrls.isNotEmpty ? a.photoUrls.first : null,
                  a.categoryName ?? 'Food',
                  a.name,
                ),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 16),
          
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      a.categoryName?.toUpperCase() ?? 'ATTRACTION',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 1),
                    ),
                    GestureDetector(
                      onTap: () async {
                        await CacheService.toggleSavedPlace((a as AttractionModel).toJson());
                        setState(() {});
                      },
                      child: Icon(
                        CacheService.isPlaceSaved(a.id) ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                        color: CacheService.isPlaceSaved(a.id) ? AppColors.primary : AppColors.textTertiary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  a.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
                    Text(' ${a.rating}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(width: 10),
                    Icon(Icons.near_me_rounded, size: 12, color: AppColors.textTertiary),
                    Text(' ${((a.distanceM ?? 0) / 1000).toStringAsFixed(1)} km', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  a.description ?? 'Discover this unique location near you.',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    ).animate().fade(delay: Duration(milliseconds: 100 * index)).slideY(begin: 0.05, end: 0);
  }

  // ═══════════════════════════════════════
  // SHOPPING TAB
  // ═══════════════════════════════════════
  Widget _buildShoppingTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick categories for shopping
        const Text('Explore Retail', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        Row(
          children: [
            _buildFoodCategory('👕', 'Fashion', const Color(0xFFF2EAFF)),
            const SizedBox(width: 10),
            _buildFoodCategory('💻', 'Tech', const Color(0xFFEAF2FF)),
            const SizedBox(width: 10),
            _buildFoodCategory('🏺', 'Local', const Color(0xFFFFF8EA)),
          ],
        ),
        const SizedBox(height: 28),
        const Text('Markets & Shops', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        if (_shoppingList.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('No real shops found nearby.', style: TextStyle(color: AppColors.textTertiary))),
          )
        else
          ..._shoppingList.asMap().entries.map((e) {
            final a = e.value;
            return _buildShopItem(a, e.key);
          }),
      ],
    );
  }

  Widget _buildShopItem(AttractionEntity shop, int index) {
    final dist = _currentPosition != null
        ? (Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, shop.latitude, shop.longitude) / 1000).toStringAsFixed(1)
        : ((shop.distanceM ?? 0) / 1000).toStringAsFixed(1);
    
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AttractionDetailPage(
          id: shop.id,
          name: shop.name,
          category: shop.categoryName ?? 'Shopping',
          rating: shop.rating,
          distance: '$dist km',
          emoji: '🛍',
          imageUrl: shop.photoUrls.isNotEmpty ? shop.photoUrls.first : null,
          latitude: shop.latitude,
          longitude: shop.longitude,
        )),
      ),
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Text('🛍', style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shop.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Text(shop.categoryName ?? 'Shopping', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                ],
              ),
            ),
            Text('$dist km', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
          ],
        ),
      ).animate().fade(delay: Duration(milliseconds: 80 * index)).slideX(begin: 0.05, end: 0),
    );
  }

  // ═══════════════════════════════════════
  // BUDGET TAB
  // ═══════════════════════════════════════
  Widget _buildBudgetTab() {
    return BlocListener<BudgetBloc, BudgetState>(
      listener: (context, state) {
        if (state is BudgetError) {
          if (state.message.contains('401') || state.message.contains('token')) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
            );
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (state is BudgetClosed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Budget closed successfully! You can now start a new one.'),
              backgroundColor: AppColors.secondary,
              behavior: SnackBarBehavior.floating,
            ),
          );
          // Refresh to show NoBudgetFound state
          context.read<BudgetBloc>().add(FetchBudget());
        }
      },
      child: BlocBuilder<BudgetBloc, BudgetState>(
        buildWhen: (previous, current) => 
            current is! BudgetHistoryLoaded && 
            current is! BudgetDetailLoaded && 
            current is! BudgetHistoryLoading && 
            current is! BudgetDetailLoading,
        builder: (context, state) {
          if (state is BudgetLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is BudgetLoaded) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.isFromCache)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                        const SizedBox(width: 8),
                        const Text('Refreshing...', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                      ],
                    ),
                  ),
                Expanded(child: _buildBudgetUI(state.budget)),
              ],
            );
          } else if (state is BudgetClosed || state is NoBudgetFound) {
            return _buildNoBudgetUI();
          } else if (state is BudgetError) {
            return _buildErrorUI(state.message);
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Widget _buildNoBudgetUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Icon(Icons.account_balance_wallet_rounded, size: 80, color: AppColors.primary.withOpacity(0.3)),
        const SizedBox(height: 24),
        const Text(
          'No Budget Set Yet',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        const Text(
          'Setup a budget to track your spending and get AI suggestions for your trip.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: AppColors.primaryGradient,
            ),
            child: ElevatedButton(
              onPressed: () => _showSetupBudgetModal(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('SETUP BUDGET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: () {
            context.read<BudgetBloc>().add(FetchBudgetHistory());
            _showHistoryModal();
          },
          icon: const Icon(Icons.history_rounded, size: 20, color: AppColors.secondary),
          label: const Text('VIEW BUDGET HISTORY', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ],
    ).animate().fade().slideY(begin: 0.1, end: 0);
  }

  void _showHistoryModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Budget History', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            Expanded(
              child: BlocBuilder<BudgetBloc, BudgetState>(
                buildWhen: (previous, current) => current is BudgetHistoryLoaded || current is BudgetHistoryLoading,
                builder: (context, state) {
                  if (state is BudgetHistoryLoaded) {
                    if (state.budgets.isEmpty) {
                      return const Center(child: Text('No past budgets', style: TextStyle(color: AppColors.textTertiary)));
                    }
                    return ListView.builder(
                      itemCount: state.budgets.length,
                      itemBuilder: (context, index) {
                        final b = state.budgets[index];
                        return InkWell(
                          onTap: () {
                            context.read<BudgetBloc>().add(FetchBudgetById(b.id));
                            _showBudgetDetailModal(b.name);
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: GlassCard(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: b.isActive ? AppColors.primary.withOpacity(0.1) : AppColors.textTertiary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    b.isActive ? Icons.account_balance_wallet_rounded : Icons.history_rounded,
                                    color: b.isActive ? AppColors.primary : AppColors.textTertiary,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(b.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                      Text(
                                        '${DateFormat('MMM d').format(b.startDate)} - ${DateFormat('MMM d').format(b.endDate)}',
                                        style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${b.currency} ${formatAmount(b.totalSpent)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: b.totalSpent > b.totalAmount ? AppColors.error : AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '/ ${formatAmount(b.totalAmount)}',
                                      style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  } else if (state is BudgetHistoryLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBudgetDetailModal(String budgetName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textPrimary),
                ),
                Text(budgetName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: BlocBuilder<BudgetBloc, BudgetState>(
                buildWhen: (previous, current) => current is BudgetDetailLoaded || current is BudgetDetailLoading,
                builder: (context, state) {
                  if (state is BudgetDetailLoaded) {
                    final budget = state.budget;
                    if (budget.expenses.isEmpty) {
                      return const Center(child: Text('No expenses recorded for this budget', style: TextStyle(color: AppColors.textTertiary)));
                    }
                    return Column(
                      children: [
                        _buildCategoryBreakdown(budget),
                        const SizedBox(height: 20),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Expenses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView.builder(
                            itemCount: budget.expenses.length,
                            itemBuilder: (context, index) {
                              final e = budget.expenses[index];
                              return _buildTransaction(
                                e.description ?? e.category,
                                _getCategoryEmoji(e.category),
                                '-${budget.currency} ${formatAmount(e.amount)}',
                                DateFormat('MMM d, hh:mm a').format(e.spentAt),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  } else if (state is BudgetDetailLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetUI(budget_entity.Budget budget) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Today's budget overview
        GlassCard(
          padding: const EdgeInsets.all(20),
          glowColor: budget.isOverBudget ? AppColors.error : AppColors.primary,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(budget.name.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textTertiary, letterSpacing: 2)),
                        const SizedBox(height: 4),
                        Text(
                          budget.isExpired ? 'EXPIRED' : '${budget.daysLeft} DAYS LEFT',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: budget.isExpired ? AppColors.error : AppColors.secondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: AppColors.surface,
                          title: const Text('Close Budget', style: TextStyle(color: Colors.white)),
                          content: const Text('Are you sure you want to close this budget? You can start a new one after closing.', style: TextStyle(color: AppColors.textSecondary)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
                            ElevatedButton(
                              onPressed: () {
                                context.read<BudgetBloc>().add(CloseBudgetEvent());
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                              child: const Text('CLOSE', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ShaderMask(
                shaderCallback: (b) => (budget.isOverBudget ? const LinearGradient(colors: [AppColors.error, AppColors.error]) : AppColors.primaryGradient).createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
                child: Text(
                  '${budget.currency} ${formatAmount(budget.spentAmount)}',
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              if (budget.isOverBudget)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '+${budget.currency} ${formatAmount(budget.overAmount)} OVER BUDGET',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.error),
                  ),
                ),
              const SizedBox(height: 12),
              Text('of ${budget.currency} ${formatAmount(budget.totalAmount)} total budget', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
              const SizedBox(height: 16),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  children: [
                    Container(height: 8, color: AppColors.surfaceVariant),
                    FractionallySizedBox(
                      widthFactor: budget.spentPercentage.clamp(0.0, 1.0),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: budget.isOverBudget 
                            ? const LinearGradient(colors: [AppColors.error, AppColors.error]) 
                            : AppColors.primaryGradient,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${(budget.spentPercentage * 100).toStringAsFixed(0)}% used', style: TextStyle(fontSize: 11, color: budget.isOverBudget ? AppColors.error : AppColors.primary, fontWeight: FontWeight.w600)),
                  InkWell(
                    onTap: () {
                      context.read<BudgetBloc>().add(FetchBudgetHistory());
                      _showHistoryModal();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Row(
                        children: [
                          const Icon(Icons.history_rounded, size: 14, color: AppColors.secondary),
                          const SizedBox(width: 4),
                          const Text('HISTORY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.secondary, letterSpacing: 1)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ).animate().fade(),
        const SizedBox(height: 24),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            TextButton.icon(
              onPressed: () => _showAddExpenseModal(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Expense', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildCategoryBreakdown(budget),

        const SizedBox(height: 24),
        const Text('Recent Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        if (budget.expenses.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('No transactions yet', style: TextStyle(color: AppColors.textTertiary))),
          )
        else
          ...budget.expenses.take(10).map((e) => _buildTransaction(
                e.description ?? e.category,
                _getCategoryEmoji(e.category),
                '-${budget.currency} ${formatAmount(e.amount)}',
                DateFormat('hh:mm a').format(e.spentAt),
              )),
        
        const SizedBox(height: 30),
        // AI Suggestion Box (Future placeholder)
        _buildAISuggestionBox(budget),
      ],
    );
  }

  Widget _buildCategoryBreakdown(budget_entity.Budget budget) {
    final categories = ['Food', 'Transport', 'Shopping', 'Activities', 'Other'];
    final Map<String, double> totals = {};
    for (var cat in categories) {
      totals[cat] = budget.expenses
          .where((e) => e.category == cat)
          .fold(0.0, (sum, e) => sum + e.amount);
    }

    return Column(
      children: [
        _buildBudgetCategory('🍽', 'Food', '${budget.currency} ${formatAmount(totals['Food']!)}', (totals['Food']! / budget.totalAmount).clamp(0.0, 1.0), AppColors.accent, 0),
        _buildBudgetCategory('🚕', 'Transport', '${budget.currency} ${formatAmount(totals['Transport']!)}', (totals['Transport']! / budget.totalAmount).clamp(0.0, 1.0), AppColors.secondary, 1),
        _buildBudgetCategory('🛍', 'Shopping', '${budget.currency} ${formatAmount(totals['Shopping']!)}', (totals['Shopping']! / budget.totalAmount).clamp(0.0, 1.0), AppColors.warning, 2),
        _buildBudgetCategory('🎫', 'Activities', '${budget.currency} ${formatAmount(totals['Activities']!)}', (totals['Activities']! / budget.totalAmount).clamp(0.0, 1.0), AppColors.neonGreen, 3),
      ],
    );
  }

  String _getCategoryEmoji(String category) {
    switch (category) {
      case 'Food': return '🍽';
      case 'Transport': return '🚕';
      case 'Shopping': return '🛍';
      case 'Activities': return '🎫';
      default: return '💰';
    }
  }

  Widget _buildAISuggestionBox(budget_entity.Budget budget) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      glowColor: AppColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.secondary, size: 20),
              const SizedBox(width: 8),
              const Text('AI BUDGET ADVISOR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.secondary, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Based on your spending, you are doing great! Try to limit food expenses to LKR 2,000 for the next 2 days to stay within budget.',
            style: TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.5),
          ),
        ],
      ),
    ).animate().shimmer(delay: 2.seconds);
  }

  void _showSetupBudgetModal() {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final daysController = TextEditingController(text: '1');
    final budgetBloc = context.read<BudgetBloc>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BlocProvider.value(
        value: budgetBloc,
        child: StatefulBuilder(
          builder: (context, setModalState) => Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Setup Budget', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                const Text('Plan your journey by setting a total budget.', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.black, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'Budget Name',
                    labelStyle: const TextStyle(color: AppColors.textTertiary),
                    prefixIcon: const Icon(Icons.edit_note_rounded, color: AppColors.primary),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.black, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'Total Amount (LKR)',
                    labelStyle: const TextStyle(color: AppColors.textTertiary),
                    prefixIcon: const Icon(Icons.payments_rounded, color: AppColors.primary),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: daysController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    labelText: 'Duration (Days)',
                    labelStyle: const TextStyle(color: AppColors.textTertiary),
                    prefixIcon: const Icon(Icons.calendar_today_rounded, color: AppColors.primary),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      final name = nameController.text.isNotEmpty ? nameController.text : 'My Budget';
                      final amount = double.tryParse(amountController.text) ?? 0;
                      final days = int.tryParse(daysController.text) ?? 1;
                      if (amount > 0) {
                        final authState = context.read<AuthBloc>().state;
                        String userCurrency = 'USD';
                        if (authState is AuthAuthenticated) {
                          userCurrency = authState.user.preferences['currency']?.toString().toUpperCase() ?? 'USD';
                        }
                        budgetBloc.add(SetupBudgetEvent(
                          name: name,
                          totalAmount: amount,
                          startDate: DateTime.now(),
                          endDate: DateTime.now().add(Duration(days: days)),
                          currency: userCurrency,
                        ));
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('CONFIRM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddExpenseModal() {
    final amountController = TextEditingController();
    final descController = TextEditingController();
    final budgetBloc = context.read<BudgetBloc>();
    String selectedCategory = 'Food';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BlocProvider.value(
        value: budgetBloc,
        child: StatefulBuilder(
          builder: (context, setModalState) => Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add Expense', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 24),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.black, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'Amount (LKR)',
                    labelStyle: const TextStyle(color: AppColors.textTertiary),
                    prefixIcon: const Icon(Icons.remove_circle_outline, color: AppColors.error),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.error)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  style: const TextStyle(color: Colors.black),
                  decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    labelStyle: const TextStyle(color: AppColors.textTertiary),
                    prefixIcon: const Icon(Icons.description_outlined, color: AppColors.textTertiary),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Category', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var cat in ['Food', 'Transport', 'Shopping', 'Activities', 'Other'])
                      GestureDetector(
                        onTap: () => setModalState(() => selectedCategory = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedCategory == cat ? AppColors.primary : AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: selectedCategory == cat ? Colors.transparent : AppColors.border),
                          ),
                          child: Text(cat, style: TextStyle(color: selectedCategory == cat ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      final amount = double.tryParse(amountController.text) ?? 0;
                      if (amount > 0) {
                        budgetBloc.add(AddExpenseEvent(
                          amount: amount,
                          category: selectedCategory,
                          description: descController.text.isEmpty ? null : descController.text,
                        ));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Expense of ${formatAmount(amount)} LKR added successfully!'),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('ADD EXPENSE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBudgetCategory(String emoji, String title, String amount, double progress, Color color, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text(amount, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate(delay: (index * 100).milliseconds).fade().slideX(begin: 0.05, end: 0);
  }

  Widget _buildTransaction(String title, String emoji, String amount, String time) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(12)),
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(time, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
              ],
            ),
          ),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.error, fontSize: 14)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // EMERGENCY TAB
  // ═══════════════════════════════════════
  Widget _buildEmergencyTab() {
    final numbers = (_emergencyInfo?['emergency_numbers'] as List?)?.cast<Map>() ?? [];
    final phrases = (_emergencyInfo?['phrases'] as List?)?.cast<Map>() ?? [];
    final city = _emergencyInfo?['city'] as String?;
    final country = _emergencyInfo?['country'] as String?;
    final locationLabel = [city, country].where((s) => s != null && s.isNotEmpty).join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // SOS button
        Center(
          child: GestureDetector(
            onTap: () async {
              final firstNumber = numbers.isNotEmpty ? numbers[0]['number'] as String? : null;
              if (firstNumber != null) {
                final uri = Uri.parse('tel:${firstNumber.replaceAll(' ', '')}');
                if (await canLaunchUrl(uri)) launchUrl(uri);
              }
            },
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

        if (locationLabel.isNotEmpty) ...[
          const SizedBox(height: 12),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on_rounded, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Text(locationLabel, style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
              ],
            ),
          ),
        ],

        const SizedBox(height: 28),

        // Loading state — full spinner only when no cache, else subtle banner
        if (_isLoadingEmergency && _nearbyHospitals.isEmpty && _emergencyInfo == null)
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Fetching emergency info for your location...', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ))
        else ...[
          if (_isLoadingEmergency)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  ),
                  const SizedBox(width: 8),
                  const Text('Updating location data...', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                ],
              ),
            ),
          // Nearby Hospitals
          const Text('Nearby Hospitals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          if (_nearbyHospitals.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('No hospitals found nearby.', style: TextStyle(color: AppColors.textTertiary)),
            )
          else
            ...List.generate(_nearbyHospitals.length, (i) {
              final h = _nearbyHospitals[i];
              return _buildHospitalCard(h['name'], h['dist'], h['address'], h['lat'], h['lng'], i);
            }),

          const SizedBox(height: 24),

          // Emergency Numbers
          const Text('Emergency Numbers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          if (numbers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('Could not fetch emergency numbers.', style: TextStyle(color: AppColors.textTertiary)),
            )
          else
            ...numbers.map((n) {
              final label = n['label'] as String? ?? '';
              final number = n['number'] as String? ?? '';
              final icon = _emergencyIcon(label);
              return _buildEmergencyNumber(label, number, icon);
            }),

          const SizedBox(height: 24),

          // Emergency Phrases
          const Text('Emergency Phrases', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          if (phrases.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('Could not fetch local phrases.', style: TextStyle(color: AppColors.textTertiary)),
            )
          else
            ...phrases.map((p) => _buildPhrase(
              p['english'] as String? ?? '',
              p['local'] as String? ?? '',
            )),
        ],
      ],
    );
  }

  IconData _emergencyIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('police')) return Icons.local_police_rounded;
    if (l.contains('ambulance') || l.contains('medical')) return Icons.medical_services_rounded;
    if (l.contains('fire')) return Icons.local_fire_department_rounded;
    if (l.contains('tourist') || l.contains('helpline')) return Icons.support_agent_rounded;
    return Icons.phone_rounded;
  }

  Widget _buildHospitalCard(String name, String dist, String address, double lat, double lng, int index) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      glowColor: AppColors.error,
      child: Row(
        children: [
          const Text('🏥', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                if (dist.isNotEmpty)
                  Text(dist, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                if (address.isNotEmpty)
                  Text(address, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
              if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppColors.error.withOpacity(0.15),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.directions_rounded, color: AppColors.error, size: 14),
                  const SizedBox(width: 4),
                  Text('Go', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.error)),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fade(delay: Duration(milliseconds: 100 * index));
  }

  Widget _buildEmergencyNumber(String label, String number, IconData icon) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse('tel:${number.replaceAll(' ', '')}');
        if (await canLaunchUrl(uri)) launchUrl(uri);
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.error),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
              Text(number, style: TextStyle(fontSize: 14, color: AppColors.primary, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Icon(Icons.phone_rounded, size: 16, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhrase(String english, String local) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(english, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(local, style: TextStyle(fontSize: 13, color: AppColors.primary)),
        ],
      ),
    );
  }
  Widget _buildErrorUI(String message) {
    bool isAuthError = message.contains('401') || message.contains('token');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Icon(
          isAuthError ? Icons.lock_person_rounded : Icons.error_outline_rounded,
          size: 80,
          color: AppColors.error.withOpacity(0.3),
        ),
        const SizedBox(height: 24),
        Text(
          isAuthError ? 'Authentication Required' : 'Something went wrong',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            isAuthError ? 'Please log in to your account to use the budget tracking feature.' : message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ),
        if (isAuthError)
          const Center(child: CircularProgressIndicator())
        else
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                context.read<BudgetBloc>().add(FetchBudget());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                'RETRY',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: () {
            context.read<BudgetBloc>().add(FetchBudgetHistory());
            _showHistoryModal();
          },
          icon: const Icon(Icons.history_rounded, size: 18),
          label: const Text('VIEW PAST BUDGETS'),
          style: TextButton.styleFrom(foregroundColor: AppColors.textTertiary),
        ),
      ],
    ).animate().fade().slideY(begin: 0.1, end: 0);
  }

  ImageProvider _getImageProvider(String? url, String category, String name) {
    return PlaceImageHelper.getImageProvider(url, category, name);
  }

  Widget _buildImageWidget(String? url, String category, String name, {BoxFit fit = BoxFit.cover}) {
    return PlaceImageHelper.buildPlaceImage(
      imagePath: url, 
      category: category, 
      name: name,
      fit: fit,
    );
  }
}
