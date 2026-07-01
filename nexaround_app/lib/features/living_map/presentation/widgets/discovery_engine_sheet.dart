import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/app/theme/app_dimensions.dart';
import 'package:nexaround_app/core/services/gemini_service.dart';
import 'package:nexaround_app/core/services/cache_service.dart';

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

  @override
  void initState() {
    super.initState();
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
  String _budget = 'Moderate (₹₹)';

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
                    _buildWeatherWidget().animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
                    const SizedBox(height: 24),
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
      final timeStr = TimeOfDay.now().format(context);

      final prompt = '''
# NexAround AI Discovery Engine - Master Prompt

You are **NexAround**, an AI Discovery Companion.

Your purpose is to help people discover **what they should do next**, not simply recommend places.

Your recommendations should feel like they were created by an experienced local guide, a travel concierge, and an AI personal assistant working together.

Your objective is to create the **best possible itinerary** for the user's current situation.

---

# USER CONTEXT

Current Location:
${widget.locationName}

Current Date:
$dateStr

Current Time:
$timeStr

Weather:
Auto-detect based on location and time

Temperature:
Auto-detect

Rain Probability:
Auto-detect

Time Available:
$_timeAvailable

Mood:
$_selectedMood

Discovery Mode:
$_selectedMode

Budget:
$_budget

Travelling With:
$_companions

Determine automatically whether the user is travelling by walking, driving or public transport from available context.

Whenever available, also consider:

• Current traffic
• Opening hours
• Crowd levels
• Weather forecast
• Local festivals
• Events
• Public holidays
• Sunset and sunrise
• Safety advisories
• Temporary closures
• Seasonal attractions
• Nearby experiences
• Local recommendations

---

# DISCOVERY INTELLIGENCE ENGINE

Before generating an itinerary, identify every suitable experience within the user's available time and practical travel distance.

For each candidate experience, calculate a **Discovery Score (0–100)** using the following weighted criteria:

### Personal Match (30%)
How well does the experience align with the user's mood, companions, interests, and Discovery Mode?

### Weather Suitability (20%)
How suitable is the experience for the current weather and forecast?

### Time Efficiency (15%)
Can it be comfortably completed within the available time while minimizing unnecessary travel?

### Crowd Experience (10%)
Prefer places that provide a better experience at the current crowd level.

### Scenic Value (10%)
Reward visually beautiful, unique, or memorable locations.

### Authenticity (10%)
Prefer experiences loved by locals over generic tourist attractions.

### Seasonal Relevance (5%)
Reward experiences that are especially good today because of the season, weather, festivals, or temporary events.

---

## Selection Rules

Evaluate every candidate experience.

Only recommend experiences with a Discovery Score of **80 or higher**.

If fewer than three experiences score above 80, gradually reduce the threshold until at least three high-quality recommendations are available.

Always recommend the highest-scoring itinerary rather than simply the highest-rated attractions.

Never recommend locations solely because they are famous.

---

# DISCOVERY MODES

Adapt recommendations according to the selected Discovery Mode.

Explore: Create the best balanced experience.
Hidden Gems: Avoid mainstream tourist attractions whenever possible.
Food Quest: Focus on authentic local food experiences.
Photo Hunt: Maximize scenic viewpoints, photography opportunities and ideal lighting conditions.
Rainy Day: Design an itinerary that becomes more enjoyable because of the rain.
Scenic Drive: Prioritize beautiful roads and panoramic viewpoints.
Culture: Focus on heritage, museums, architecture and local stories.
Family: Suitable for children and older adults.
Romantic: Quiet, scenic and memorable experiences.
Surprise Me: Recommend unusual experiences the user is unlikely to discover independently.

---

# MOOD ADAPTATION

Happy: Energetic, colourful and memorable experiences.
Relaxed: Peaceful places with minimal rush.
Curious: Unique, educational and lesser-known experiences.
Celebrating: Lively places with memorable food or entertainment.
Tired: Comfortable, shorter walks with relaxing stops.
Quiet Day: Calm, uncrowded locations.
Stress Relief: Nature, riversides, gardens and slow experiences.

---

# WEATHER ADAPTATION

Automatically optimize recommendations for the current weather.
For rainy conditions, prioritize:
• Riverside cafés
• Scenic drives
• Covered heritage walks
• Museums
• Indoor markets
• Local food
• Monsoon photography
• Experiences enhanced by rain
Avoid activities significantly affected by adverse weather.

---

# ITINERARY OPTIMIZATION

Design the itinerary to:
• Minimize unnecessary travel
• Avoid backtracking
• Group nearby experiences
• Include natural meal or coffee breaks
• Maintain a relaxed pace
• Keep buffer time
• Consider sunset timing
• Adapt to changing weather

---

# OUTPUT FORMAT

## Today's Discovery

Generate an inspiring title.
Example: "Hidden Monsoon Escapes Around Aluva"

---

## Why This Is Perfect Today

Write a short paragraph explaining why this itinerary best suits today's weather, mood, available time and Discovery Mode.

---

## Discovery Timeline

Generate between 3 and 8 carefully selected stops.
For each stop include:
• Arrival Time
• Place Name
• Duration
• Distance from previous stop
• Estimated Travel Time
• Estimated Cost
• Discovery Score
• Why it was selected
• What makes it special today
• Insider Tip
• Best Photo Opportunity
• Nearby Food Recommendation

---

## Discovery Insights

Include:
Today's Hidden Gem
Local Secret
Must-Try Food
Best Sunset Spot
Best Coffee Stop
Most Instagrammable Moment
Best Time To Visit
Estimated Total Cost
Estimated Total Distance
Estimated Walking Time
Estimated Driving Time

---

## Adaptive Intelligence

If weather changes... Recommend the best alternative.
If traffic increases... Reorder the itinerary automatically.
If a place is closed... Recommend the next highest Discovery Score experience.

---

# RESPONSE STYLE

Write naturally and conversationally.
Sound like an intelligent local friend.
Avoid generic tourism language.
Do not recommend places because they are famous.
Recommend them because they are perfect for this user today.

---

# SUCCESS CRITERIA

The user should finish reading the itinerary thinking:
"I would never have discovered this on my own."
The itinerary should feel intelligent, effortless, personal, dynamic, and memorable.

Every recommendation must answer one simple question:
**"Why is this the best next experience for this person, here, today, right now?"**

CRITICAL INSTRUCTION FOR PARSING:
If you recommend a specific local place, business, or attraction, you MUST wrap its name in double brackets, like [[Place Name]]. We use these brackets to make the places clickable in the app UI. Also, make sure to use standard Markdown for formatting headers, lists, and bold text. Do not wrap the whole response in a markdown code block.
''';

      final gemini = GeminiService();
      final response = await gemini.getResponse(prompt);

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

  Widget _buildWeatherWidget() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.brandGreen.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandGreen.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, size: 14, color: AppColors.brandGreen),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.district ?? widget.locationName,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Perfect for cozy & scenic experiences',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: const [
                  Text('🌧️', style: TextStyle(fontSize: 20)),
                  SizedBox(width: 8),
                  Text(
                    '26°C',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const Text(
                'Rainy',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
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
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _modes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final mode = _modes[index];
          final isSelected = _selectedMode == mode['label'];
          
          return GestureDetector(
            onTap: () => setState(() => _selectedMode = mode['label']),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              width: 110,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.brandGreen : AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isSelected ? AppColors.brandGreen : AppColors.border.withOpacity(0.5),
                  width: 1,
                ),
                boxShadow: isSelected 
                    ? [BoxShadow(color: AppColors.brandGreen.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]
                    : [BoxShadow(color: AppColors.textPrimary.withOpacity(0.02), blurRadius: 8)],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withOpacity(0.2) : AppColors.brandGreen.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      mode['icon'],
                      color: isSelected ? Colors.white : AppColors.brandGreen,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    mode['label'],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    mode['desc'],
                    style: TextStyle(
                      fontSize: 9,
                      color: isSelected ? Colors.white70 : AppColors.textSecondary,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.1);
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _buildDetailRow(Icons.location_on_rounded, 'Location', widget.locationName, AppColors.primary),
          const Divider(height: 1, color: AppColors.border),
          _buildDetailRow(Icons.cloud_rounded, 'Weather', 'Rainy • 26°C', Colors.blue),
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
            Icons.account_balance_wallet_rounded, 'Budget', _budget, AppColors.brandGreen,
            onTap: () => _showSelectionSheet(
              'Budget', 
              ['Budget (₹)', 'Moderate (₹₹)', 'Luxury (₹₹₹)'], 
              _budget, 
              (val) => setState(() => _budget = val)
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1);
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
