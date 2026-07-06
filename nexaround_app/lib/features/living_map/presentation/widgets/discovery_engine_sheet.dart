import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';
import 'package:nexaround_app/core/services/gemini_service.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/discovery_history_service.dart';
import 'package:nexaround_app/features/living_map/presentation/widgets/location_search_modal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/core/services/currency_service.dart';
import 'package:nexaround_app/core/services/place_verifier_service.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';

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
  String? _currentDistrict;
  String _selectedWeather = '🌧️ Rainy';

  @override
  void initState() {
    super.initState();
    _currentLocationName = widget.locationName;
    _currentLatitude = widget.latitude;
    _currentLongitude = widget.longitude;
    _currentDistrict = widget.district;

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
  int _budgetLevel = 1; // 0 = Budget, 1 = Moderate, 2 = Luxury

  String _getBudgetString(String symbol) {
    if (_budgetLevel == 0) return 'Budget ($symbol)';
    if (_budgetLevel == 2) return 'Luxury ($symbol$symbol$symbol)';
    return 'Moderate ($symbol$symbol)';
  }

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
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.only(
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
            
          // Close button bar
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withOpacity(0.3),
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
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 120, top: 12),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle(Icons.mood_rounded, 'How are you feeling today?', 'Your mood helps us suggest perfect experiences.'),
                    const SizedBox(height: 12),
                    _buildMoodGrid(),
                    const SizedBox(height: 24),
                    _buildSectionTitle(Icons.explore_rounded, 'Discovery Mode', 'What kind of experience are you looking for?', tag: 'Optional'),
                    const SizedBox(height: 12),
                    _buildModesList(),
                    const SizedBox(height: 24),
                    _buildSectionTitle(Icons.tune_rounded, 'Tell us a few details', 'These help us create your personalized itinerary.'),
                    const SizedBox(height: 12),
                    _buildDetailsList(),
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
              bottom: MediaQuery.of(context).padding.bottom + 20,
              top: 20,
            ),
            decoration: BoxDecoration(
              color: AppColors.background,
              boxShadow: [
                BoxShadow(
                  color: AppColors.textPrimary.withOpacity(0.05),
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
                      color: AppColors.brandGreen.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text('✨', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 8),
                    Text(
                      'Tell me',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
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
                  color: AppColors.brandGreen.withOpacity(0.3),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 40, bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandGreen.withOpacity(0.2),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset('assets/images/neva_avatar.png', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  "Neva's Discovery",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandGreen.withOpacity(0.12),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(color: AppColors.brandGreen.withOpacity(0.3), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.format_quote_rounded, color: AppColors.brandGreen.withOpacity(0.4), size: 36),
                const SizedBox(height: 12),
                _buildParsedResult(_aiResult),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() => _sheetState = SheetState.input);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    side: const BorderSide(color: AppColors.border, width: 1.5),
                  ),
                  child: const Text('Try Again', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.brandGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('Let\'s Go!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Widget _buildParsedResult(String text) {
    final markdownText = text.replaceAllMapped(
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
        p: const TextStyle(fontSize: 16, height: 1.6, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
        strong: const TextStyle(fontSize: 16, height: 1.6, color: AppColors.textPrimary, fontWeight: FontWeight.w800),
        a: const TextStyle(
          fontSize: 16, 
          height: 1.6, 
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

    // Get currency symbol
    final authState = context.read<AuthBloc>().state;
    String currencySymbol = '₹';
    if (authState is AuthAuthenticated) {
      final userCurrencyCode = authState.user.preferences['currency']?.toString().toUpperCase() ?? 'USD';
      final currencyInfo = CurrencyService.supportedCurrencies.firstWhere(
        (c) => c['code'] == userCurrencyCode,
        orElse: () => {'symbol': '\$'},
      );
      currencySymbol = currencyInfo['symbol'] ?? '\$';
    }

    final currentLoc = _currentLocationName;
    final currentLat = _currentLatitude;
    final currentLng = _currentLongitude;
    final currentTimeAvailable = _timeAvailable;
    final currentMood = _selectedMood;
    final currentMode = _selectedMode ?? 'Explore';
    final currentBudget = _getBudgetString(currencySymbol);
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
      final dateStr = DateTime.now().toLocal().toString().split(' ')[0];

      final prompt = '''
# NexAround AI Discovery Engine

You are **NexAround**, an AI Discovery Companion.

Your purpose is simple:
Help people discover what they should do next.
Don't just recommend famous places. Create experiences that feel personal, timely, and worth remembering.
Think like a local friend, an experienced travel concierge, and an intelligent AI assistant.

# User Context

Current Location:
$currentLoc

CRITICAL BOUNDARY REQUIREMENT:
You MUST ONLY recommend places, attractions, restaurants, and activities that are located in or extremely close to (strictly within a 15km radius of) $currentLoc.
Do NOT recommend places in other cities, even if they are in the same country. For example, if the current location is Kinniya, you must NOT recommend places in Colombo or Trincomalee. Focus purely on local, nearby options. If there are few commercial attractions, suggest scenic views, local bridges, local beaches, local street food spots, nature walks, or community spaces in $currentLoc.

Current Date:
$dateStr

Current Time:
$formattedTime

Weather:
$currentWeather

Temperature:
Auto-detect

Time Available:
$currentTimeAvailable

Mood:
$currentMood

Discovery Mode:
$currentMode

Budget:
$currentBudget

Travelling With:
$currentCompanions

Transportation:
Determine automatically (walking, driving or public transport).

Also consider whenever available:
• Current traffic
• Opening hours
• Weather forecast
• Public holidays
• Local events
• Sunset time
• Seasonal experiences
• Temporary closures

# Discovery Modes

Adapt recommendations based on the selected mode.
• Explore – A balanced day with a mix of popular and lesser-known experiences.
• Hidden Gems – Focus on places locals love.
• Food Quest – Build the itinerary around authentic local food.
• Photo Hunt – Prioritize scenic viewpoints and beautiful lighting.
• Rainy Day – Suggest experiences that are better in the rain.
• Scenic Drive – Choose beautiful routes and viewpoints.
• Culture – Heritage, architecture, museums and local stories.
• Family – Comfortable for all ages.
• Romantic – Relaxed and memorable experiences.
• Surprise Me – Recommend places most visitors never discover.

# Build the Best Day

Create the most enjoyable itinerary by:
- Minimizing travel time
- Grouping nearby places together
- Avoiding unnecessary backtracking
- Keeping a relaxed pace
- Including natural breaks for food or coffee
- Considering the weather
- Making the day feel effortless

Recommend between 4 and 7 stops, depending on the available time.
Choose places because they are the best fit today, not because they are famous.

# Output Format

🌟 Today's Discovery
Give the itinerary an engaging title.
Then explain in 2–3 sentences why this plan is perfect for today.

Your Journey
For each stop include:
- Time: [Arrival Time]
- Place Name: [Place Name] (Make sure to wrap the place name in double brackets, like [[Place Name]])
- Time to Spend: [Duration]
- Estimated Cost: [Cost]
- Travel Time from Previous Stop: [Travel Time]
- Why You'll Love It: [Short, friendly explanation.]
- Don't Miss: [A unique experience or local tip.]
- Nearby Food: [One recommended café, restaurant or local specialty.]

Before You Go
Include:
- 🍽 Must-Try Food
- ☕ Best Coffee Stop
- 📸 Best Photo Spot
- 🌅 Best Sunset Location (if applicable)
- 💰 Estimated Budget
- 🚗 Total Travel Distance
- ⏳ Total Travel Time

If it starts raining:
Suggest the best indoor alternative.

If traffic becomes heavy:
Reorder the itinerary.

If a place is closed:
Recommend the next best nearby experience.

# Style

Write naturally and conversationally.
Avoid generic tourism language.
Keep descriptions short and engaging.
Use actual place names. Only recommend real, existing places that can be found on Google Maps. Do NOT invent or hallucinate places.
Do NOT include any raw Google Maps URLs or external HTTP/HTTPS links in your response. Instead, wrap the place names in double brackets like [[Place Name]] so the app can handle opening the map natively.
Make the itinerary feel like it was created by someone who truly knows the city.

# Goal

When the user finishes reading, they should feel:
"I wouldn't have found this on my own—and I can't wait to go."

# CRITICAL INSTRUCTION FOR PARSING:
If you recommend a specific local place, business, or attraction, you MUST wrap its name in double brackets, like [[Place Name]] (e.g. [[South Kitchen + Bar]] or [[Hotel Radhakrishna]]) when writing the "Place Name" section, so they are clickable in the app UI. Also, make sure to use standard Markdown for formatting headers, lists, and bold text. Do not wrap the whole response in a markdown code block.
''';

      final gemini = GeminiService();
      print('🔍 DiscoveryEngine: Submitting prompt to Gemini...');
      final rawResponse = await gemini.getResponse(prompt);
      print('🔍 DiscoveryEngine: Received raw response from Gemini (${rawResponse.length} chars)');
      print('🔍 DiscoveryEngine: Current Location: "$currentLoc", Lat: $currentLat, Lng: $currentLng');
      print('🔍 DiscoveryEngine: API Key length: ${ApiConstants.googleMapsApiKey.length}');
      
      // Filter out hallucinated places
      final hallucinatedPlaces = await PlaceVerifierService.findHallucinatedPlaces(
        rawResponse, 
        currentLoc,
        centerLat: currentLat,
        centerLng: currentLng,
      );
      print('🔍 DiscoveryEngine: Hallucinated/Far-away places identified to filter: $hallucinatedPlaces');
      
      final response = PlaceVerifierService.cleanRawUrls(
        PlaceVerifierService.filterHallucinatedStops(
          rawResponse, 
          hallucinatedPlaces,
        ),
      );
      print('🔍 DiscoveryEngine: Final filtered response size: ${response.length} chars');

      // Save to backend database history
      await DiscoveryHistoryService.saveHistoryItem(
        location: currentLoc,
        mode: currentMode,
        result: response,
      );

      CacheService.discoveryResultNotifier.value = response;
      CacheService.isDiscoveringNotifier.value = false;

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: const Text('✨ Neva\'s Discovery Itinerary is ready! Tap the Neva banner to view it.'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ),
      );
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
        color: AppColors.surface.withOpacity(0.5),
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
                        TextButton(
                          onPressed: _showHistorySheet,
                          child: const Text(
                            'History',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.brandGreen,
                            ),
                          ),
                        ),
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
                  color: AppColors.textSecondary.withOpacity(0.3),
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
                  color: AppColors.brandGreen.withOpacity(0.1),
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
                color: isSelected ? AppColors.brandGreen : AppColors.border.withOpacity(0.5),
                width: 1,
              ),
              boxShadow: isSelected 
                  ? [BoxShadow(color: AppColors.brandGreen.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] 
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
                color: isSelected ? AppColors.brandGreen : AppColors.border.withOpacity(0.5),
                width: 1,
              ),
              boxShadow: isSelected 
                  ? [BoxShadow(color: AppColors.brandGreen.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 3))]
                  : [BoxShadow(color: AppColors.textPrimary.withOpacity(0.01), blurRadius: 6)],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withOpacity(0.2) : AppColors.brandGreen.withOpacity(0.05),
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
            }).toList(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsList() {
    final authState = context.read<AuthBloc>().state;
    String currencySymbol = '₹';
    if (authState is AuthAuthenticated) {
      final userCurrencyCode = authState.user.preferences['currency']?.toString().toUpperCase() ?? 'USD';
      final currencyInfo = CurrencyService.supportedCurrencies.firstWhere(
        (c) => c['code'] == userCurrencyCode,
        orElse: () => {'symbol': '\$'},
      );
      currencySymbol = currencyInfo['symbol'] ?? '\$';
    }

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
                backgroundColor: Colors.transparent,
                builder: (context) => const LocationSearchModal(),
              ).then((result) {
                if (result != null && result is Map<String, dynamic>) {
                  setState(() {
                    _currentLocationName = result['name'] ?? _currentLocationName;
                    _currentLatitude = result['latitude'] as double?;
                    _currentLongitude = result['longitude'] as double?;
                    _currentDistrict = result['district'] as String?;
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
          const Divider(height: 1, color: AppColors.border),
          _buildDetailRow(
            Icons.account_balance_wallet_rounded, 'Budget', _getBudgetString(currencySymbol), AppColors.brandGreen,
            onTap: () => _showSelectionSheet(
              'Budget', 
              ['Budget ($currencySymbol)', 'Moderate ($currencySymbol$currencySymbol)', 'Luxury ($currencySymbol$currencySymbol$currencySymbol)'], 
              _getBudgetString(currencySymbol), 
              (val) {
                setState(() {
                  if (val.startsWith('Budget')) {
                    _budgetLevel = 0;
                  } else if (val.startsWith('Luxury')) {
                    _budgetLevel = 2;
                  } else {
                    _budgetLevel = 1;
                  }
                });
              }
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1);
  }

  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
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
                color: AppColors.textSecondary.withOpacity(0.3),
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
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: DiscoveryHistoryService.fetchHistory(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.brandGreen),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return const Center(
                      child: Text('Error loading history', style: TextStyle(color: AppColors.textSecondary)),
                    );
                  }
                  final history = snapshot.data!;
                  if (history.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_rounded, size: 48, color: AppColors.textTertiary),
                          const SizedBox(height: 12),
                          Text('No past itineraries found', style: TextStyle(color: AppColors.textSecondary)),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: history.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
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
                          Navigator.pop(context);
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
