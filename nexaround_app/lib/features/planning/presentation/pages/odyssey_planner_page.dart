import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/core/utils/number_format.dart';
import 'package:nexaround_app/features/planning/data/odyssey_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_state.dart';
import 'package:nexaround_app/features/living_map/presentation/widgets/location_search_modal.dart';

class OdysseyPlannerPage extends StatefulWidget {
  const OdysseyPlannerPage({super.key});

  @override
  State<OdysseyPlannerPage> createState() => _OdysseyPlannerPageState();
}

class _OdysseyPlannerPageState extends State<OdysseyPlannerPage> {
  String _currency = 'USD';

  final OdysseyRepository _repository = OdysseyRepository();
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _daysController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final TextEditingController _travelersController = TextEditingController();

  int _currentStep = 0; // 0 destination, 1 mood, 2 budget
  int _days = 3;
  double _budget = 50000;
  int _travelers = 1;
  String _selectedMood = 'Adventurous';
  bool _isSubmitting = false;

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
    _daysController.text = _days.toString();
    _budgetController.text = _budget.toInt().toString();
    _travelersController.text = _travelers.toString();
    _prefillDestination();
    _loadUserCurrency();
  }

  void _loadUserCurrency() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final userCurrency = authState.user.preferences['currency']?.toString().toUpperCase();
      if (userCurrency != null && userCurrency.isNotEmpty) {
        setState(() {
          _currency = userCurrency;
        });
      }
    }
  }

  @override
  void dispose() {
    _destinationController.dispose();
    _daysController.dispose();
    _budgetController.dispose();
    _travelersController.dispose();
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

  void _showLocationSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const LocationSearchModal(),
    ).then((result) {
      if (result != null && result is Map<String, dynamic>) {
        setState(() {
          _destinationController.text = result['name'] ?? '';
        });
      }
    });
  }

  // ── Actions ────────────────────────────────────────────────────────────
  void _onPrimaryAction() {
    FocusScope.of(context).unfocus();
    if (_currentStep == 0 && _destinationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Where do you want to go?')),
      );
      return;
    }
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      _submit();
    }
  }

  /// Hand the brief to the server and leave — generation continues in the
  /// background and the finished plan shows up in My Odysseys.
  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      await _repository.requestGeneration(
        destination: _destinationController.text.trim(),
        mood: _selectedMood,
        budget: _budget,
        days: _days,
        currency: _currency,
        travelers: _travelers,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Building your Odyssey — it will appear in My Odysseys shortly.'),
          duration: Duration(seconds: 4),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start generation: $e')),
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
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
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
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Column(
              children: [
                _buildProgressIndicator(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: _buildCurrentStep(),
                  ),
                ),
              ],
            ),
            // iOS number pads have no "return"/Done key, so the keyboard can't be
            // dismissed and the Continue button stays hidden behind it. Show a
            // "Done" bar above the keyboard (iOS only — Android's keyboard already
            // has an enter key) so users can close it and reach Continue.
            if (Theme.of(context).platform == TargetPlatform.iOS &&
                MediaQuery.of(context).viewInsets.bottom > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildKeyboardDoneBar(),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomAction(),
    );
  }

  /// A "Done" accessory bar shown above the iOS keyboard (which lacks a return
  /// key on number pads). Tapping it dismisses the keyboard.
  Widget _buildKeyboardDoneBar() {
    return Material(
      color: const Color(0xFFF2F2F7),
      child: Container(
        height: 44,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.black.withOpacity(0.12))),
        ),
        child: TextButton(
          onPressed: () => FocusScope.of(context).unfocus(),
          child: const Text(
            'Done',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
      ),
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
          GestureDetector(
            onTap: _showLocationSearch,
            child: AbsorbPointer(
              child: TextField(
                controller: _destinationController,
                readOnly: true,
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
                onTap: () => setState(() {
                  _days = d;
                  _daysController.text = d.toString();
                }),
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
          const SizedBox(height: 20),
          TextField(
            controller: _daysController,
            keyboardType: TextInputType.number,
            onChanged: (val) {
              final parsed = int.tryParse(val);
              if (parsed != null && parsed > 0) {
                setState(() => _days = parsed);
              }
            },
            decoration: InputDecoration(
              labelText: 'Or enter custom days',
              hintText: 'e.g. 10',
              prefixIcon: const Icon(Icons.calendar_today_rounded, color: Colors.black54),
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
          ).animate().fade(delay: 300.ms),
          const SizedBox(height: 32),
          const Text(
            'NUMBER OF TRAVELERS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _travelersController,
            keyboardType: TextInputType.number,
            onChanged: (val) {
              final parsed = int.tryParse(val);
              if (parsed != null && parsed > 0) {
                setState(() => _travelers = parsed);
              }
            },
            decoration: InputDecoration(
              labelText: 'How many travelers?',
              hintText: 'e.g. 2',
              prefixIcon: const Icon(Icons.people_rounded, color: Colors.black54),
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
          ).animate().fade(delay: 350.ms),
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
    return LayoutBuilder(
      key: const ValueKey('budget'),
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
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
                  '$_currency ${formatAmount(_budget)}',
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: -1),
                ),
                const Text('ESTIMATED TOTAL BUDGET', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2)),
              ],
            ),
          ).animate().scale(),
          const Spacer(),
          TextField(
            controller: _budgetController,
            keyboardType: TextInputType.number,
            onChanged: (val) {
              final parsed = double.tryParse(val);
              if (parsed != null && parsed > 0) {
                setState(() => _budget = parsed);
              }
            },
            decoration: InputDecoration(
              labelText: 'Or enter custom budget limit',
              hintText: 'e.g. 75000',
              prefixText: '$_currency ',
              prefixIcon: const Icon(Icons.wallet_rounded, color: Colors.black54),
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
          ).animate().fade(delay: 200.ms),
          const SizedBox(height: 24),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.black,
              inactiveTrackColor: Colors.black12,
              thumbColor: Colors.black,
              overlayColor: Colors.black.withOpacity(0.1),
              trackHeight: 8,
            ),
            child: Slider(
              value: _budget.clamp(1000.0, 500000.0),
              min: 1000,
              max: 500000,
              divisions: 499,
              onChanged: (val) {
                setState(() {
                  _budget = val;
                  _budgetController.text = val.toInt().toString();
                });
              },
            ),
          ),
          const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomAction() {
    final String label = _currentStep == 2 ? 'GENERATE ODYSSEY' : 'CONTINUE';
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
            onPressed: _isSubmitting ? null : _onPrimaryAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: _isSubmitting
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
