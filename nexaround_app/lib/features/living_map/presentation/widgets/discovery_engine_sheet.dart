import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/discovery_history_service.dart';
import 'package:nexaround_app/features/living_map/presentation/widgets/location_search_modal.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';

enum SheetState { input, loading, result }

class DiscoveryEngineSheet extends StatefulWidget {
  final String locationName;
  final String? district;
  final double? latitude;
  final double? longitude;
  final Function(String)? onPlaceSelected;
  final String? initialResult;

  const DiscoveryEngineSheet({
    super.key,
    required this.locationName,
    this.district,
    this.latitude,
    this.longitude,
    this.onPlaceSelected,
    this.initialResult,
  });

  @override
  State<DiscoveryEngineSheet> createState() => _DiscoveryEngineSheetState();
}

class _DiscoveryEngineSheetState extends State<DiscoveryEngineSheet> {
  late SheetState _sheetState;
  late String _aiResult;

  late String _currentLocationName;
  double? _currentLatitude;
  double? _currentLongitude;
  String _selectedWeather = '🌧️ Rainy';

  @override
  void initState() {
    super.initState();
    _currentLocationName = widget.locationName;
    _currentLatitude = widget.latitude;
    _currentLongitude = widget.longitude;

    if (widget.initialResult != null) {
      _sheetState = SheetState.result;
      _aiResult = widget.initialResult!;
    } else {
      _sheetState = SheetState.input;
      _aiResult = '';
    }
  }

  String _selectedMood = 'Happy';
  String? _selectedMode = 'Explore';
  
  // Details
  String _timeAvailable = '5 Hours';
  String _companions = 'Solo';

  final List<Map<String, dynamic>> _moods = [
    {'label': 'Happy', 'icon': Icons.sentiment_very_satisfied_rounded},
    {'label': 'Relaxed', 'icon': Icons.spa_rounded},
    {'label': 'Adventurous', 'icon': Icons.landscape_rounded},
    {'label': 'Romantic', 'icon': Icons.favorite_rounded},
    {'label': 'Tired', 'icon': Icons.bedtime_rounded},
    {'label': 'Curious', 'icon': Icons.search_rounded},
    {'label': 'Celebrating', 'icon': Icons.celebration_rounded},
    {'label': 'Quiet Day', 'icon': Icons.local_library_rounded},
    {'label': 'Cozy / Rainy', 'icon': Icons.umbrella_rounded},
    {'label': 'Stressed', 'icon': Icons.sentiment_dissatisfied_rounded},
  ];

  final List<Map<String, dynamic>> _modes = [
    {'label': 'Explore', 'desc': 'Discover hidden\ngems nearby', 'icon': Icons.explore_rounded},
    {'label': 'Food Quest', 'desc': 'Best local food\n& cafes', 'icon': Icons.restaurant_menu_rounded},
    {'label': 'Photo Hunt', 'desc': 'Scenic spots &\nperfect views', 'icon': Icons.camera_alt_rounded},
    {'label': 'Family Time', 'desc': 'Fun places for\neveryone', 'icon': Icons.family_restroom_rounded},
    {'label': 'Culture', 'desc': 'Heritage, art &\nlocal stories', 'icon': Icons.account_balance_rounded},
    {'label': 'Surprise Me', 'desc': 'AI picks\nsomething great', 'icon': Icons.card_giftcard_rounded},
  ];

  @override
  Widget build(BuildContext context) {
    final isResult = _sheetState == SheetState.result;

    return Container(
      constraints: BoxConstraints(
        maxHeight: isResult
            ? MediaQuery.of(context).size.height
            : MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: isResult
            ? BorderRadius.zero
            : const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
      ),
      child: Stack(
        children: [
          if (_sheetState == SheetState.input)
            _buildInputView()
          else if (_sheetState == SheetState.loading)
            _buildLoadingView()
          else if (_sheetState == SheetState.result)
            _buildResultView(),
            
          // Close / drag handle on input and loading sheets
          if (!isResult)
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    ).animate().slideY(begin: 1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
  }
  
  Widget _buildInputView() {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100, top: 12),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle(Icons.mood_rounded, 'How are you feeling today?', 'Your mood helps us suggest perfect experiences.'),
                    const SizedBox(height: 12),
                    _buildMoodGrid(),
                    const SizedBox(height: 24),
                    _buildSectionTitle(Icons.tune_rounded, 'Tell us a few details', 'These help us create your personalized itinerary.'),
                    const SizedBox(height: 12),
                    _buildDetailsList(),
                    const SizedBox(height: 24),
                    _buildSectionTitle(Icons.explore_rounded, 'Discovery Mode', 'What kind of experience are you looking for?', tag: 'Optional'),
                    const SizedBox(height: 12),
                    _buildModesList(),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
        
        // Fixed Bottom Button
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.only(
              left: 20, 
              right: 20, 
              bottom: MediaQuery.of(context).padding.bottom > 0
                  ? MediaQuery.of(context).padding.bottom + 6
                  : 16,
              top: 12,
            ),
            decoration: BoxDecoration(
              color: AppColors.background,
              boxShadow: [
                BoxShadow(
                  color: AppColors.textPrimary.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: GestureDetector(
              onTap: _submitToGemini,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.brandGreen,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandGreen.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'Tell me',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ).animate().slideY(begin: 1, end: 0, duration: 400.ms, curve: Curves.easeOutBack),
        ),
      ],
    );
  }
  
  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandGreen.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset('assets/images/neva_avatar.png', fit: BoxFit.cover),
            ),
          ).animate(onPlay: (controller) => controller.repeat(reverse: true))
           .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 1.seconds)
           .shimmer(duration: 2.seconds, color: Colors.white54),
          const SizedBox(height: 32),
          const Text(
            "Neva is crafting your itinerary...",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ).animate(onPlay: (controller) => controller.repeat(reverse: true)).fade(begin: 0.5, end: 1.0),
        ],
      ),
    );
  }
  
  Widget _buildResultView() {
    double topPadding = 0;
    try {
      final view = View.of(context);
      topPadding = view.viewPadding.top / view.devicePixelRatio;
    } catch (_) {
      topPadding = MediaQuery.of(context).padding.top;
    }
    if (topPadding <= 0) {
      topPadding = MediaQuery.viewPaddingOf(context).top;
    }
    if (topPadding <= 0) {
      topPadding = 36.0; // Fail-safe status bar height so it never overlaps
    }

    return Column(
      children: [
        // ── Top Navigation Bar with Back Button ──
        Container(
          padding: EdgeInsets.only(
            left: 12,
            right: 16,
            top: topPadding + 6,
            bottom: 12,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.8), width: 1.0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
                onPressed: () {
                  if (widget.initialResult != null) {
                    Navigator.pop(context);
                  } else {
                    setState(() => _sheetState = SheetState.input);
                  }
                },
                tooltip: 'Back',
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Where to Go Plan",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (_currentLocationName.isNotEmpty)
                      Text(
                        _currentLocationName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandGreen,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Scrollable Plan Content ──
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Plan Hero Banner
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.brandGreen.withValues(alpha: 0.14),
                        AppColors.actionTeal.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.brandGreen.withValues(alpha: 0.3), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brandGreen.withValues(alpha: 0.25),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset('assets/images/neva_avatar.png', fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Neva's Personalized Discovery ✨",
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Mood: $_selectedMood · Mode: ${_selectedMode ?? 'Explore'}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Markdown Itinerary Card
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: AppColors.border, width: 1.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildParsedResult(_aiResult),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _sheetState = SheetState.input);
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('New Plan', style: TextStyle(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      foregroundColor: AppColors.textPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: const BorderSide(color: AppColors.border, width: 1.2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _buildParsedResult(String text) {
    // Strip out Estimated Cost / Budget lines completely
    String cleanedText = text
        .replaceAll(RegExp(r'^\s*[*•-]\s*\*\*Estimated Cost:\*\*.*$', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*[*•-]\s*Estimated Cost:.*$', multiLine: true, caseSensitive: false), '')
        .replaceAll(RegExp(r'\|\s*💰\s*Estimated Budget[^|\n]*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\n{3,}', multiLine: true), '\n\n');

    final markdownText = cleanedText.replaceAllMapped(
      RegExp(r'\[\[(.*?)\]\]'), 
      (match) {
        final placeName = match.group(1) ?? '';
        final encodedPlace = Uri.encodeComponent(placeName);
        return '[$placeName](place:$encodedPlace)';
      }
    );

    return MarkdownBody(
      data: markdownText,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
        strong: const TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.textPrimary, fontWeight: FontWeight.w800),
        h3: const TextStyle(fontSize: 17, height: 1.4, color: AppColors.brandGreen, fontWeight: FontWeight.w800),
        h3Padding: const EdgeInsets.only(top: 20, bottom: 10),
        listBullet: const TextStyle(fontSize: 14.5, color: AppColors.brandGreen),
        a: const TextStyle(
          fontSize: 14.5, 
          height: 1.5, 
          color: AppColors.brandGreen, 
          fontWeight: FontWeight.w800,
          decoration: TextDecoration.underline,
        ),
      ),
      onTapLink: (text, href, title) {
        if (href != null && href.startsWith('place:')) {
          final encodedPlace = href.substring(6);
          final placeName = Uri.decodeComponent(encodedPlace);
          if (widget.onPlaceSelected != null) {
            widget.onPlaceSelected!(placeName);
          }
        }
      },
    );
  }

  Future<void> _submitToGemini() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    final currentLoc = _currentLocationName;
    final currentLat = _currentLatitude;
    final currentLng = _currentLongitude;
    final currentTimeAvailable = _timeAvailable;
    final currentMood = _selectedMood;
    final currentMode = _selectedMode ?? 'Explore';
    final currentCompanions = _companions;
    final currentWeather = _selectedWeather;
    final formattedTime = TimeOfDay.now().format(context);

    // Show immediate feedback and close the sheet
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: const Text('Neva is crafting your itinerary in the background. We\'ll notify you when it\'s ready!'),
        backgroundColor: AppColors.brandGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    
    CacheService.isDiscoveringNotifier.value = true;
    nav.pop();

    try {
      final response = await ApiClient.instance.post(
        ApiConstants.discoveryGenerate,
        data: {
          'location': currentLoc,
          'mode': currentMode,
          'latitude': currentLat ?? 0.0,
          'longitude': currentLng ?? 0.0,
          'companions': currentCompanions,
          'weather': currentWeather,
          'time_available': currentTimeAvailable,
          'mood': currentMood,
          'time_of_day': formattedTime,
        },
      );

      if (response.statusCode != 202) {
        throw Exception('Server returned status: ${response.statusCode}');
      }
    } catch (e) {
      CacheService.isDiscoveringNotifier.value = false;
      CacheService.discoveryResultNotifier.value = "Oops, I hit a snag trying to craft your perfect plan. Mind trying again?";
      
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: const Text('Oops! Neva encountered an error. Check the banner for details.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Where should\nI go today?',
                          style: TextStyle(
                            fontSize: 28,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -1,
                          ),
                        ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.2),
                        GestureDetector(
                          onTap: _showHistorySheet,
                          child: Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppColors.brandGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.brandGreen.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.brandGreen.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.history_rounded,
                                  size: 15,
                                  color: AppColors.brandGreen,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'History',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.brandGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ).animate().fadeIn(delay: 150.ms),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tell us your mood.\nWe\'ll craft the perfect plan for you.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ).animate().fadeIn(delay: 200.ms),
                  ],
                ),
              ),
            ],
          ),
          
          // Close button bar
          Positioned(
            top: -15,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(IconData icon, String title, String subtitle, {String? tag}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 24, color: AppColors.brandGreen),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            if (tag != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brandGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tag,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.brandGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildMoodGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: _moods.map((mood) {
        final isSelected = _selectedMood == mood['label'];
        return GestureDetector(
          onTap: () => setState(() => _selectedMood = mood['label'] as String),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.brandGreen : AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected ? AppColors.brandGreen : AppColors.border.withValues(alpha: 0.5),
                width: 1,
              ),
              boxShadow: isSelected 
                  ? [BoxShadow(color: AppColors.brandGreen.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))] 
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  mood['icon'] as IconData,
                  size: 18,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  mood['label'] as String,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);
  }

  Widget _buildModesList() {
    return GridView.count(
      crossAxisCount: 3,
      childAspectRatio: 0.85,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(_modes.length, (index) {
        final mode = _modes[index];
        final isSelected = _selectedMode == mode['label'];
        
        return GestureDetector(
          onTap: () => setState(() => _selectedMode = mode['label']),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.brandGreen : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? AppColors.brandGreen : AppColors.border.withValues(alpha: 0.5),
                width: 1,
              ),
              boxShadow: isSelected 
                  ? [BoxShadow(color: AppColors.brandGreen.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 3))]
                  : [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.01), blurRadius: 6)],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withValues(alpha: 0.2) : AppColors.brandGreen.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    mode['icon'],
                    color: isSelected ? Colors.white : AppColors.brandGreen,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  mode['label'],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  mode['desc'].replaceAll('\n', ' '),
                  style: TextStyle(
                    fontSize: 9,
                    color: isSelected ? Colors.white70 : AppColors.textSecondary,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1);
  }

  void _showSelectionSheet(String title, List<String> options, String currentValue, Function(String) onSelected) {
    showModalBottomSheet(
      context: context,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            ...options.map((option) {
              final isSelected = option == currentValue;
              return ListTile(
                title: Text(
                  option,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? AppColors.brandGreen : AppColors.textPrimary,
                  ),
                ),
                trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppColors.brandGreen) : null,
                onTap: () {
                  onSelected(option);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsList() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _buildDetailRow(
            Icons.location_on_rounded, 
            'Location', 
            _currentLocationName, 
            AppColors.primary,
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                showDragHandle: false,
                backgroundColor: Colors.transparent,
                builder: (context) => const LocationSearchModal(),
              ).then((result) {
                if (result != null && result is Map<String, dynamic>) {
                  setState(() {
                    _currentLocationName = result['name'] ?? _currentLocationName;
                    _currentLatitude = result['latitude'] as double?;
                    _currentLongitude = result['longitude'] as double?;
                  });
                }
              });
            },
          ),
          const Divider(height: 1, color: AppColors.border),
          _buildDetailRow(
            Icons.cloud_rounded, 
            'Weather', 
            _selectedWeather, 
            Colors.blue,
            onTap: () => _showSelectionSheet(
              'Weather', 
              ['☀️ Sunny', '☁️ Cloudy', '🌧️ Rainy', '🌫️ Foggy / Misty', '🌬️ Windy', '❄️ Snowy'], 
              _selectedWeather, 
              (val) => setState(() => _selectedWeather = val)
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _buildDetailRow(
            Icons.access_time_rounded, 'Time Available', _timeAvailable, Colors.blue,
            onTap: () => _showSelectionSheet(
              'Time Available', 
              ['1 Hour', '3 Hours', '5 Hours', 'Full Day'], 
              _timeAvailable, 
              (val) => setState(() => _timeAvailable = val)
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _buildDetailRow(
            Icons.people_rounded, 'Who\'s with you?', _companions, Colors.orange,
            onTap: () => _showSelectionSheet(
              'Who\'s with you?', 
              ['Solo', 'Couple', 'Family', 'Friends'], 
              _companions, 
              (val) => setState(() => _companions = val)
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1);
  }

  void _showHistorySheet() {
    List<Map<String, dynamic>> history = DiscoveryHistoryService.getCachedHistory();
    bool isLoadingFresh = history.isEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      isScrollControlled: true,
      builder: (modalContext) => StatefulBuilder(
        builder: (modalContext, setModalState) {
          // Trigger background fetch
          DiscoveryHistoryService.fetchHistory().then((fresh) {
            if (modalContext.mounted) {
              setModalState(() {
                history = fresh;
                isLoadingFresh = false;
              });
            }
          });

          return Container(
            height: MediaQuery.of(modalContext).size.height * 0.7,
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Search History',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Builder(
                    builder: (_) {
                      if (isLoadingFresh && history.isEmpty) {
                        return const Center(
                          child: CircularProgressIndicator(color: AppColors.brandGreen),
                        );
                      }
                      if (history.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history_rounded, size: 48, color: AppColors.textTertiary),
                              SizedBox(height: 12),
                              Text('No past itineraries found', style: TextStyle(color: AppColors.textSecondary)),
                            ],
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: history.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (context, index) {
                          final item = history[index];
                          final createdStr = item['created_at'] as String? ?? '';
                          String dateDisplay = '';
                          try {
                            if (createdStr.isNotEmpty) {
                              final parsed = DateTime.parse(createdStr).toLocal();
                              dateDisplay = '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
                            }
                          } catch (_) {
                            dateDisplay = createdStr;
                          }

                          final location = item['location'] as String? ?? 'Unknown Location';
                          final mode = item['mode'] as String? ?? 'Explore';
                          final result = item['result'] as String? ?? '';

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            title: Text(
                              location,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Mode: $mode • $dateDisplay',
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                            onTap: () {
                              // Close history modal
                              Navigator.pop(modalContext);
                              // Show results
                              setState(() {
                                _aiResult = result;
                                _sheetState = SheetState.result;
                              });
                            },
                          );
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

  Widget _buildDetailRow(IconData icon, String title, String value, Color iconColor, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
