
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
import 'package:nexaround_app/core/widgets/country_picker_sheet.dart';

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

  int _currentStep = 0; // 0 destination, 1 flights & hotels, 2 budget
  int _days = 3;
  double _budget = 50000;
  int _travelers = 1;
  final String _selectedMood = 'Adventurous';
  bool _isSubmitting = false;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _includeFlights = true;
  DateTime? _flightStartDate;
  DateTime? _flightEndDate;
  bool _includeHotels = true;
  DateTime? _hotelCheckInDate;
  DateTime? _hotelCheckOutDate;
  bool _hasVisa = false;
  String _departureCity = '';
  String _departureCountry = '';
  String? _nationality;

  @override
  void initState() {
    super.initState();
    _daysController.text = _days.toString();
    _budgetController.text = formatAmount(_budget.toInt());
    _travelersController.text = _travelers.toString();
    _prefillDestination();
    _loadUserCurrency();
    _loadUserNationality();
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

  /// Defaults from the signed-in user's profile, same as currency — still
  /// changeable per trip via the visa guidance card.
  void _loadUserNationality() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final userNationality = authState.user.preferences['nationality']?.toString();
      if (userNationality != null && userNationality.isNotEmpty) {
        setState(() {
          _nationality = userNationality;
        });
      }
    }
  }

  Future<void> _pickNationality() async {
    final picked = await showCountryPickerSheet(
      context,
      selectedCountry: _nationality,
      title: 'Select Nationality',
    );
    if (picked != null) {
      setState(() => _nationality = picked);
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
      
      final details = await GooglePlacesService.reverseGeocodeDetailed(
        pos.latitude,
        pos.longitude,
      );
      
      if (!mounted) return;
      
      final name = details['location_name'] ?? 'Nearby';
      final country = details['country'] ?? 'Nearby';
      
      setState(() {
        _departureCity = name;
        _departureCountry = country;
        if (name.isNotEmpty &&
            name != 'Nearby' &&
            _destinationController.text.trim().isEmpty) {
          _destinationController.text = name;
        }
      });
    } catch (_) {
      // Location unavailable — the user can type a destination instead.
    }
  }

  void _showLocationSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) => const LocationSearchModal(),
    ).then((result) {
      if (result != null && result is Map) {
        setState(() {
          _destinationController.text = result['name']?.toString() ?? '';
        });
      }
    });
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // ── Actions ────────────────────────────────────────────────────────────
  void _onPrimaryAction() {
    FocusScope.of(context).unfocus();
    if (_currentStep == 0) {
      if (_destinationController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Where do you want to go?')),
        );
        return;
      }
      if (_startDate == null || _endDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select your trip start & end dates to continue.'),
            backgroundColor: Color(0xFFE65100),
          ),
        );
        return;
      }
    }
    if (_currentStep == 1) {
      if (_includeFlights && (_flightStartDate == null || _flightEndDate == null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select Departure Date and Return Date for flights.')),
        );
        return;
      }
      if (_includeHotels && (_hotelCheckInDate == null || _hotelCheckOutDate == null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select Check-in Date and Check-out Date for hotels.')),
        );
        return;
      }
      if (!_hasVisa && (_nationality == null || _nationality!.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select your nationality for visa guidance.')),
        );
        return;
      }
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
    if (_includeFlights && (_flightStartDate == null || _flightEndDate == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Departure Date and Return Date for flights.')),
      );
      return;
    }
    if (_includeHotels && (_hotelCheckInDate == null || _hotelCheckOutDate == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Check-in Date and Check-out Date for hotels.')),
      );
      return;
    }
    if (!_hasVisa && (_nationality == null || _nationality!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your nationality for visa guidance.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _repository.requestGeneration(
        destination: _destinationController.text.trim(),
        mood: _selectedMood,
        budget: _budget * _travelers,
        days: _days,
        currency: _currency,
        travelers: _travelers,
        includeFlights: _includeFlights,
        departureCity: _departureCity,
        departureCountry: _departureCountry,
        nationality: !_hasVisa ? (_nationality ?? '') : '',
        hasVisa: _hasVisa,
        flightStartDate: _formatDate(_flightStartDate),
        flightEndDate: _formatDate(_flightEndDate),
        includeHotels: _includeHotels,
        hotelCheckInDate: _formatDate(_hotelCheckInDate),
        hotelCheckOutDate: _formatDate(_hotelCheckOutDate),
        startDate: _formatDate(_startDate ?? _flightStartDate ?? _hotelCheckInDate),
        endDate: _formatDate(_endDate ?? _flightEndDate ?? _hotelCheckOutDate),
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
          onPressed: _isSubmitting
              ? null
              : () {
                  if (_currentStep > 0) {
                    setState(() => _currentStep--);
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

  Widget _buildKeyboardDoneBar() {
    return Material(
      color: const Color(0xFFF2F2F7),
      child: Container(
        height: 44,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.12))),
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
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
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
        return _buildFlightsAndHotelsStep();
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
            'TRIP DATES',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickTripDateRange,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _startDate != null ? Colors.black : Colors.black12,
                  width: _startDate != null ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.date_range_rounded, color: Colors.black54),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _startDate != null && _endDate != null
                          ? '${_formatDateNice(_startDate!)} – ${_formatDateNice(_endDate!)} ($_days ${_days == 1 ? "Day" : "Days"})'
                          : (_startDate != null
                              ? _formatDateNice(_startDate!)
                              : 'Select trip start & end dates'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: _startDate != null ? FontWeight.w700 : FontWeight.w500,
                        color: _startDate != null ? Colors.black : Colors.black45,
                      ),
                    ),
                  ),
                  if (_startDate != null)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _startDate = null;
                          _endDate = null;
                          _days = 3;
                        });
                      },
                      child: const Icon(Icons.close_rounded, size: 20, color: Colors.black54),
                    )
                  else
                    const Icon(Icons.calendar_month_rounded, size: 20, color: Colors.black54),
                ],
              ),
            ),
          ).animate().fade(delay: 250.ms),
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

  Widget _buildFlightsAndHotelsStep() {
    return SingleChildScrollView(
      key: const ValueKey('flights_and_hotels'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Flights, Hotels & Visa\nGuidance',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.15),
          ).animate().fade().slideY(begin: 0.1, end: 0),
          const SizedBox(height: 4),
          const Text(
            'Optional: Enable booking options or visa guidance for this trip.',
            style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.25),
          ),
          const SizedBox(height: 14),
          const Text(
            'FLIGHT RECOMMENDATIONS',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.brandGreen,
                  inactiveThumbColor: Colors.grey.shade400,
                  inactiveTrackColor: Colors.black.withValues(alpha: 0.12),
                  title: const Row(
                    children: [
                      Icon(Icons.flight_takeoff_rounded, color: Colors.black87, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Include Flight Options',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  value: _includeFlights,
                  onChanged: (bool val) {
                    setState(() {
                      _includeFlights = val;
                      if (val && _flightStartDate == null) {
                        _pickFlightDateRange();
                      }
                    });
                  },
                ),
                if (_includeFlights) ...[
                  const Divider(height: 1, indent: 14, endIndent: 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildDatePickerTile(
                            label: 'Start Date',
                            selectedDate: _flightStartDate,
                            onTap: _pickFlightDateRange,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildDatePickerTile(
                            label: 'End Date',
                            selectedDate: _flightEndDate,
                            onTap: _pickFlightDateRange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ).animate().fade(delay: 150.ms),
          const SizedBox(height: 12),
          const Text(
            'HOTEL RECOMMENDATIONS',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.brandGreen,
                  inactiveThumbColor: Colors.grey.shade400,
                  inactiveTrackColor: Colors.black.withValues(alpha: 0.12),
                  title: const Row(
                    children: [
                      Icon(Icons.hotel_rounded, color: Colors.black87, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Include Hotel Options',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  value: _includeHotels,
                  onChanged: (bool val) {
                    setState(() {
                      _includeHotels = val;
                      if (val && _hotelCheckInDate == null && _flightStartDate != null) {
                        _hotelCheckInDate = _flightStartDate;
                        _hotelCheckOutDate = _flightEndDate;
                      } else if (val && _hotelCheckInDate == null) {
                        _pickHotelDateRange();
                      }
                    });
                  },
                ),
                if (_includeHotels) ...[
                  const Divider(height: 1, indent: 14, endIndent: 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildDatePickerTile(
                            label: 'Check-in Date',
                            selectedDate: _hotelCheckInDate,
                            onTap: _pickHotelDateRange,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildDatePickerTile(
                            label: 'Check-out Date',
                            selectedDate: _hotelCheckOutDate,
                            onTap: _pickHotelDateRange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ).animate().fade(delay: 200.ms),
          const SizedBox(height: 12),
          const Text(
            'VISA STATUS & GUIDANCE',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.badge_outlined, color: Colors.black87, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Do you already have a visa for this trip?',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _hasVisa = true),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _hasVisa ? Colors.black : Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _hasVisa ? Colors.black : Colors.transparent,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Yes, I have a visa',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _hasVisa ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _hasVisa = false);
                          if (_nationality == null) {
                            _pickNationality();
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: !_hasVisa ? Colors.black : Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: !_hasVisa ? Colors.black : Colors.transparent,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'No, I need guidance',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: !_hasVisa ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_hasVisa) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF43A047).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You\'re all set! No visa application procedures will be included in your plan.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF1B5E20), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  _buildNationalityTile(),
                  const SizedBox(height: 6),
                  const Text(
                    'Neva AI will analyze entry requirements, application procedures, processing days, and deadlines for your passport.',
                    style: TextStyle(fontSize: 10.5, color: Colors.black54),
                  ),
                ],
              ],
            ),
          ).animate().fade(delay: 250.ms),
        ],
      ),
    );
  }

  Future<void> _pickTripDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialRange = DateTimeRange(
      start: _startDate ?? today,
      end: _endDate ?? today.add(Duration(days: _days > 1 ? _days - 1 : 0)),
    );
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'SELECT TRIP DATES (Tap same date twice for 1-day trip)',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.black,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        final computedDays = picked.end.difference(picked.start).inDays + 1;
        if (computedDays > 0) {
          _days = computedDays;
          _daysController.text = computedDays.toString();
        }
        _flightStartDate ??= picked.start;
        _flightEndDate ??= picked.end;
        _hotelCheckInDate ??= picked.start;
        _hotelCheckOutDate ??= picked.end;
      });
    }
  }

  String _formatDateNice(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _pickFlightDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialRange = DateTimeRange(
      start: _flightStartDate ?? (_startDate ?? today),
      end: _flightEndDate ?? (_endDate ?? today.add(Duration(days: _days > 1 ? _days - 1 : 0))),
    );
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'SELECT FLIGHT DATES',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.black,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _flightStartDate = picked.start;
        _flightEndDate = picked.end;
        // Auto-copy flight dates to hotel check-in / check-out dates
        _hotelCheckInDate = picked.start;
        _hotelCheckOutDate = picked.end;
      });
    }
  }

  Future<void> _pickHotelDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialRange = DateTimeRange(
      start: _hotelCheckInDate ?? (_startDate ?? today),
      end: _hotelCheckOutDate ?? (_endDate ?? today.add(Duration(days: _days > 1 ? _days - 1 : 0))),
    );
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'SELECT HOTEL DATES',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.black,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _hotelCheckInDate = picked.start;
        _hotelCheckOutDate = picked.end;
      });
    }
  }

  Widget _buildDatePickerTile({
    required String label,
    required DateTime? selectedDate,
    required VoidCallback onTap,
  }) {
    final dateStr = selectedDate != null
        ? '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'
        : 'Select Date';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selectedDate != null ? Colors.black : Colors.black12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_rounded, size: 16, color: selectedDate != null ? Colors.black : Colors.black45),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.black54),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selectedDate != null ? FontWeight.bold : FontWeight.normal,
                      color: selectedDate != null ? Colors.black : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Nationality feeds the AI's visa guidance for this trip (needed /
  /// available / not needed, plus processing-time-aware date guidance).
  /// Defaults from the user's profile (see `_loadUserNationality`) but is
  /// changeable per trip, since a plan isn't always for the account holder.
  Widget _buildNationalityTile() {
    return InkWell(
      onTap: _pickNationality,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _nationality != null ? Colors.black : Colors.black12),
        ),
        child: Row(
          children: [
            Icon(Icons.flag_rounded, size: 16, color: _nationality != null ? Colors.black : Colors.black45),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'NATIONALITY (FOR VISA GUIDANCE)',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.black54),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _nationality ?? 'Select nationality',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: _nationality != null ? FontWeight.bold : FontWeight.normal,
                      color: _nationality != null ? Colors.black : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.black45),
          ],
        ),
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
            'What is your budget\nper person?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1),
          ).animate().fade(),
          const SizedBox(height: 12),
          const Text(
            'Your odyssey will be personalized and optimized based on this per-person budget.',
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
                const Text('BUDGET PER PERSON', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2)),
                if (_travelers > 1) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Total for $_travelers travelers: $_currency ${formatAmount(_budget * _travelers)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54),
                  ),
                ],
              ],
            ),
          ).animate().scale(),
          const Spacer(),
          TextField(
            controller: _budgetController,
            keyboardType: TextInputType.number,
            onChanged: (val) {
              final cleanVal = val.replaceAll(',', '').trim();
              final parsed = double.tryParse(cleanVal);
              if (parsed != null && parsed > 0) {
                setState(() => _budget = parsed);
              }
            },
            onEditingComplete: () {
              _budgetController.text = formatAmount(_budget.round());
              FocusScope.of(context).unfocus();
            },
            decoration: InputDecoration(
              labelText: 'Or enter custom budget per person',
              hintText: 'e.g. 75,000',
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
              overlayColor: Colors.black.withValues(alpha: 0.1),
              trackHeight: 8,
            ),
            child: Slider(
              value: _budget.clamp(1000.0, 500000.0),
              min: 1000,
              max: 500000,
              divisions: 499,
              onChanged: (val) {
                final rounded = (val / 1000).round() * 1000.0;
                setState(() {
                  _budget = rounded;
                  _budgetController.text = formatAmount(rounded.round());
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



  bool get _isCurrentStepValid {
    if (_currentStep == 0) {
      return _destinationController.text.trim().isNotEmpty &&
          _startDate != null &&
          _endDate != null;
    }
    if (_currentStep == 1) {
      if (_includeFlights && (_flightStartDate == null || _flightEndDate == null)) {
        return false;
      }
      if (_includeHotels && (_hotelCheckInDate == null || _hotelCheckOutDate == null)) {
        return false;
      }
      if (!_hasVisa && (_nationality == null || _nationality!.isEmpty)) {
        return false;
      }
      return true;
    }
    if (_currentStep == 2) {
      return true;
    }
    return true;
  }

  Widget _buildBottomAction() {
    final String label = _currentStep == 2 ? 'GENERATE ODYSSEY' : 'CONTINUE';
    final blocked = !_isCurrentStepValid;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.05))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: Container(
          decoration: BoxDecoration(
            color: blocked ? Colors.black26 : Colors.black,
            borderRadius: BorderRadius.circular(16),
            boxShadow: blocked
                ? null
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: ElevatedButton(
            onPressed: (_isSubmitting || blocked) ? null : _onPrimaryAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
