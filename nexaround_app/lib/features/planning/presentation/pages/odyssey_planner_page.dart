import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/features/planning/data/odyssey_repository.dart';
import 'package:nexaround_app/features/planning/data/odyssey_service.dart';
import 'package:nexaround_app/features/planning/domain/odyssey.dart';
import 'package:nexaround_app/features/planning/presentation/widgets/odyssey_plan_view.dart';

class OdysseyPlannerPage extends StatefulWidget {
  const OdysseyPlannerPage({super.key});

  @override
  State<OdysseyPlannerPage> createState() => _OdysseyPlannerPageState();
}

class _OdysseyPlannerPageState extends State<OdysseyPlannerPage> {
  static const String _currency = 'LKR';

  final OdysseyService _service = OdysseyService();
  final OdysseyRepository _repository = OdysseyRepository();
  final TextEditingController _destinationController = TextEditingController();

  int _currentStep = 0; // 0 destination, 1 mood, 2 budget
  int _days = 3;
  double _budget = 50000;
  String _selectedMood = 'Adventurous';

  bool _isGenerating = false;
  bool _isSaving = false;
  Odyssey? _result;

  final List<int> _dayOptions = const [2, 3, 4, 5, 7];

  final List<Map<String, dynamic>> _moods = const [
    {'name': 'Affordable', 'icon': Icons.savings_rounded, 'desc': 'Focus on local gems'},
    {'name': 'Luxury', 'icon': Icons.diamond_rounded, 'desc': 'Premium experiences'},
    {'name': 'Adventurous', 'icon': Icons.terrain_rounded, 'desc': 'Unexplored trails'},
    {'name': 'Cultural', 'icon': Icons.museum_rounded, 'desc': 'Deep heritage'},
  ];

  @override
  void initState() {
    super.initState();
    _prefillDestination();
  }

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  /// Best-effort reverse-geocode of the current location into the destination
  /// field. Never prompts for permission and never blocks the UI.
  Future<void> _prefillDestination() async {
    try {
      final perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied ||
          perm == geo.LocationPermission.deniedForever) {
        return;
      }
      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 6));
      final name = await GooglePlacesService.reverseGeocode(
        pos.latitude,
        pos.longitude,
      );
      if (!mounted) return;
      if (name.isNotEmpty &&
          name != 'Nearby' &&
          _destinationController.text.trim().isEmpty) {
        setState(() => _destinationController.text = name);
      }
    } catch (_) {
      // Location unavailable — the user can type a destination instead.
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────
  void _onPrimaryAction() {
    FocusScope.of(context).unfocus();
    if (_result != null) {
      _save();
      return;
    }
    if (_currentStep == 0 && _destinationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Where do you want to go?')),
      );
      return;
    }
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      _generate();
    }
  }

  Future<void> _generate() async {
    setState(() => _isGenerating = true);
    try {
      final odyssey = await _service.generate(
        destination: _destinationController.text.trim(),
        mood: _selectedMood,
        budget: _budget,
        days: _days,
        currency: _currency,
      );
      if (!mounted) return;
      setState(() {
        _result = odyssey;
        _isGenerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is OdysseyGenerationException ? e.message : 'Generation failed: $e'),
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_result == null) return;
    setState(() => _isSaving = true);
    try {
      await _repository.save(_result!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to My Odysseys')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 20),
          onPressed: () {
            if (_result != null && !_isSaving) {
              setState(() => _result = null); // back to wizard from result
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: const Text(
          'NEXUS ODYSSEY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.black,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
      bottomNavigationBar: _isGenerating ? null : _buildBottomAction(),
    );
  }

  Widget _buildBody() {
    if (_isGenerating) return _buildGenerating();
    if (_result != null) return OdysseyPlanView(odyssey: _result!);
    return Column(
      children: [
        _buildProgressIndicator(),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _buildCurrentStep(),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Row(
        children: List.generate(3, (index) {
          final isActive = index <= _currentStep;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isActive ? Colors.black : Colors.black12,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildDestinationStep();
      case 1:
        return _buildMoodStep();
      case 2:
        return _buildBudgetStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildDestinationStep() {
    return SingleChildScrollView(
      key: const ValueKey('destination'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Where to, and\nfor how long?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1),
          ).animate().fade().slideY(begin: 0.1, end: 0),
          const SizedBox(height: 8),
          const Text(
            'We prefilled your current area — change it to anywhere.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _destinationController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'e.g. Kandy, Ella, Galle',
              prefixIcon: const Icon(Icons.place_rounded, color: Colors.black54),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: Colors.black12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: Colors.black, width: 1.5),
              ),
            ),
          ).animate().fade(delay: 150.ms),
          const SizedBox(height: 32),
          const Text(
            'DURATION',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _dayOptions.map((d) {
              final selected = _days == d;
              return GestureDetector(
                onTap: () => setState(() => _days = d),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: selected ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: selected ? Colors.black : Colors.black12),
                  ),
                  child: Text(
                    '$d Days',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              );
            }).toList(),
          ).animate().fade(delay: 250.ms),
        ],
      ),
    );
  }

  Widget _buildMoodStep() {
    return SingleChildScrollView(
      key: const ValueKey('mood'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How do you want to\nexperience the world?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1),
          ).animate().fade().slideY(begin: 0.1, end: 0),
          const SizedBox(height: 32),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: _moods.length,
            itemBuilder: (context, index) {
              final mood = _moods[index];
              final isSelected = _selectedMood == mood['name'];
              return GestureDetector(
                onTap: () => setState(() => _selectedMood = mood['name'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: isSelected ? Colors.black : Colors.black12),
                    boxShadow: isSelected
                        ? [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(mood['icon'] as IconData, color: isSelected ? Colors.white : Colors.black, size: 36),
                      const SizedBox(height: 12),
                      Text(
                        mood['name'] as String,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isSelected ? Colors.white : Colors.black),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mood['desc'] as String,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: isSelected ? Colors.white60 : Colors.black54),
                      ),
                    ],
                  ),
                ),
              );
            },
          ).animate().fade(delay: 200.ms),
        ],
      ),
    );
  }

  Widget _buildBudgetStep() {
    return Padding(
      key: const ValueKey('budget'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What is your\naffordable limit?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1),
          ).animate().fade(),
          const SizedBox(height: 12),
          const Text(
            'AI will optimize the odyssey based on this cap.',
            style: TextStyle(color: Colors.black54),
          ),
          const Spacer(),
          Center(
            child: Column(
              children: [
                Text(
                  '$_currency ${_budget.toInt()}',
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: -1),
                ),
                const Text('ESTIMATED TOTAL BUDGET', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2)),
              ],
            ),
          ).animate().scale(),
          const Spacer(),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.black,
              inactiveTrackColor: Colors.black12,
              thumbColor: Colors.black,
              overlayColor: Colors.black.withOpacity(0.1),
              trackHeight: 8,
            ),
            child: Slider(
              value: _budget,
              min: 10000,
              max: 500000,
              divisions: 49,
              onChanged: (val) => setState(() => _budget = val),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildGenerating() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3),
          ),
          const SizedBox(height: 28),
          const Text(
            'Designing your Odyssey…',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.5, end: 1, duration: 900.ms),
          const SizedBox(height: 8),
          Text(
            '$_selectedMood · $_days days · ${_destinationController.text.trim()}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomAction() {
    final String label = _result != null
        ? 'SAVE TO MY ODYSSEYS'
        : (_currentStep == 2 ? 'GENERATE ODYSSEY' : 'CONTINUE');

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black.withOpacity(0.05))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: ElevatedButton(
            onPressed: _isSaving ? null : _onPrimaryAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1.5),
                  ),
          ),
        ),
      ),
    );
  }
}
