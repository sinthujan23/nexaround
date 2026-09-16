
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
import 'package:nexaround_app/core/constants/countries.dart';
import 'package:nexaround_app/core/widgets/country_picker_sheet.dart';
import 'package:nexaround_app/core/error/user_message.dart';

class OdysseyPlannerPage extends StatefulWidget {
  const OdysseyPlannerPage({super.key});

  @override
  State<OdysseyPlannerPage> createState() => _OdysseyPlannerPageState();
}

class _OdysseyPlannerPageState extends State<OdysseyPlannerPage> {
  // The backend generates the whole Odyssey (every day's activities) in one
  // Gemini call capped at 8192 output tokens. Beyond ~14 days that routinely
  // truncates mid-JSON and the Odyssey comes back as "failed", so trip length
  // is capped here to match the server-side limit in OdysseyGenerateRequest.
  static const int _maxTripDays = 14;

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
  // The point the departure name was derived from. Kept because the name is
  // not always usable: when the reverse geocode fails it yields the literal
  // word "Nearby", which the backend used to hand to the AI as if it were a
  // city — a traveller in Trincomalee was quoted a flight from Chennai. The
  // coordinates let the backend recover at least the country.
  double? _departureLat;
  double? _departureLng;
  String? _nationality;

  // What the place picker knew when the user tapped a destination. The picker
  // has always returned these; they were dropped on the floor, and the backend
  // was left to infer a country from the name alone. That is how a trip to
  // "Sri Vijaya Puram" (Port Blair, in the Andamans) came back as an itinerary
  // for Kandy — the name reads as Sri Lankan.
  //
  // Always written through [_setDestination] so the name and the coordinates
  // cannot drift apart. The field itself is readOnly + AbsorbPointer, so these
  // are the only two ways a destination is ever set.
  /// The country the trip is in, whether it was named outright or read off the
  /// city that was. It holds the entry and exit searches to one country, so
  /// there is nothing to hold them to until it is known.
  String _country = '';

  bool _loadingEntryCities = false;
  String _entryCity = '';
  String _exitCity = '';
  double? _entryLat;
  double? _entryLng;
  double? _exitLat;
  double? _exitLng;

  String get _countryCode => countryCodeFor(_country) ?? '';

  /// Entry and exit are both cities inside the trip's country, so neither can
  /// be offered until that country is known. Restricting the search is how a
  /// trip is kept from starting in one country and finishing in another —
  /// rather than letting the pair be chosen and then refused.
  bool get _canPickEnds => _countryCode.isNotEmpty;

  /// A destination is all that is required. Entry and exit are refinements of
  /// it: given neither, the route planner proposes both and the preview sheet
  /// shows them before anything is generated.
  bool get _hasDestination => _destinationController.text.trim().isNotEmpty;

  String _destPlaceId = '';
  double? _destLat;
  double? _destLng;
  String _destAddress = '';

  /// Set the destination and everything we know about where it is, together.
  void _setDestination(
    String name, {
    String placeId = '',
    double? latitude,
    double? longitude,
    String address = '',
  }) {
    _destinationController.text = name;
    _destPlaceId = placeId;
    // A picker that could not resolve a place reports 0,0 rather than null.
    _destLat = (latitude == null || latitude == 0.0) ? null : latitude;
    _destLng = (longitude == null || longitude == 0.0) ? null : longitude;
    _destAddress = address;
  }

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

      // 'Nearby' is the backend's sentinel for "all three geocoders failed",
      // not a place. Send it as empty so it reads as unknown rather than as a
      // city somewhere for the AI to find an airport near.
      final cityOut = name == 'Nearby' ? '' : name;
      final countryOut = country == 'Nearby' ? '' : country;

      setState(() {
        _departureCity = cityOut;
        _departureCountry = countryOut;
        // Always kept, even when the name resolved — it costs nothing and is
        // the only thing left to work from if the name turns out unusable.
        _departureLat = pos.latitude;
        _departureLng = pos.longitude;
        // The destination field is left blank rather than defaulted to the
        // current area: the location picker already offers "Use Current
        // Location" as an explicit choice, so prefilling it here just made
        // the field look pre-answered with no clear way to tell it apart
        // from an intentional pick.
      });
    } catch (_) {
      // Location unavailable — the user can type a destination instead.
    }
  }

  /// Offer the cities Google confirmed for the chosen country.
  ///
  /// The list is the server's: Gemini proposes and Google decides, so nothing
  /// invented reaches it. It is a starting point, not a cage - "Search a
  /// different city" reopens the search, held to this country and to
  /// settlements, so a city outside the list is still reachable.
  ///
  /// An empty list is not a dead end either: the sheet falls straight through
  /// to that search, which is the same box that was working before any of this
  /// existed.
  Future<void> _offerEntryCities() async {
    final country = _country;
    final code = _countryCode;
    if (country.isEmpty || code.isEmpty) return;

    setState(() => _loadingEntryCities = true);
    final cities = await GooglePlacesService.getCountryCities(
      country: country, countryCode: code,
    );
    if (!mounted) return;
    setState(() => _loadingEntryCities = false);

    if (cities.isEmpty) {
      await _pickEntryCityBySearch();
      return;
    }

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text(
                  'Where does the trip start in $country?',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Pick the city you arrive in. The plan is built around it.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: cities.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 56, color: Color(0xFFEEF1F5)),
                  itemBuilder: (_, i) {
                    final city = cities[i];
                    return ListTile(
                      leading: const Icon(Icons.location_city_rounded,
                          color: AppColors.brandGreen),
                      title: Text(
                        city['name']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(country,
                          style: const TextStyle(fontSize: 12, color: Colors.black45)),
                      onTap: () => Navigator.of(sheetContext).pop(city),
                    );
                  },
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEEF1F5)),
              ListTile(
                leading: const Icon(Icons.search_rounded, color: Colors.black54),
                title: const Text('Search a different city'),
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (picked == null) {
      await _pickEntryCityBySearch();
      return;
    }
    setState(() {
      _entryCity = picked['name']?.toString() ?? '';
      _entryLat = (picked['latitude'] as num?)?.toDouble();
      _entryLng = (picked['longitude'] as num?)?.toDouble();
    });
  }

  /// The country's own search, for a city the list did not offer.
  Future<void> _pickEntryCityBySearch() async {
    final country = _country;
    final code = _countryCode;
    if (code.isEmpty) return;
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationSearchModal(
        restrictToCountryCode: code,
        countryLabel: country,
        placeKinds: '(cities)',
        countryOffersCities: true,
        hintText: 'Which city do you arrive in?',
      ),
    );
    if (result is! Map || !mounted) return;
    final name = result['name']?.toString() ?? '';
    if (name.isEmpty) return;
    setState(() {
      _entryCity = name;
      _entryLat = (result['latitude'] as num?)?.toDouble();
      _entryLng = (result['longitude'] as num?)?.toDouble();
    });
  }

  /// Where the trip is. A country, and only ever a country.
  ///
  /// Picked from the app's own country list rather than searched: a list
  /// cannot return a city, so "cities are not offered here" is a property of
  /// the widget instead of a filter that has to hold. It also costs nothing
  /// and answers instantly, where the search was a billed Places call per
  /// keystroke.
  ///
  /// The country travels as a bare name with no coordinates. That is the
  /// shape the backend already expects for a country — `resolve_destination`
  /// identifies it from the name, and the route planner is told it is "a whole
  /// country" and asked to choose one coherent region inside it.
  Future<void> _pickDestination() async {
    final picked = await showCountryPickerSheet(
      context,
      selectedCountry: _country.isEmpty ? null : _country,
      title: 'Where to?',
    );
    if (picked == null || !mounted) return;
    if (picked == _country) return;

    setState(() {
      _country = picked;
      // A country names no single point, so the place fields are cleared
      // rather than left pointing at whatever was chosen before.
      _setDestination(picked);
      // Ends belonging to the previous country cannot survive this one.
      _entryCity = '';
      _entryLat = null;
      _entryLng = null;
      _exitCity = '';
      _exitLat = null;
      _exitLng = null;
    });
  }

  /// Entry and exit: both optional, both cities, both held to the trip's own
  /// country so a city from anywhere else is never offered in the first place.
  Future<void> _pickEnd({required bool isEntry}) async {
    if (!_canPickEnds) return;
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationSearchModal(
        restrictToCountryCode: _countryCode,
        countryLabel: _country,
        placeKinds: '(cities)',
        // The country is already settled, so its cities are shown the moment
        // the sheet opens, before any typing.
        countryOffersCities: true,
        hintText: isEntry
            ? 'Which city do you arrive in?'
            : 'Which city do you leave from in $_country?',
      ),
    );
    if (result is! Map || !mounted) return;
    final name = result['name']?.toString() ?? '';
    if (name.isEmpty) return;

    final lat = (result['latitude'] as num?)?.toDouble();
    final lng = (result['longitude'] as num?)?.toDouble();

    setState(() {
      if (isEntry) {
        _entryCity = name;
        _entryLat = lat;
        _entryLng = lng;
      } else {
        _exitCity = name;
        _exitLat = lat;
        _exitLng = lng;
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


  /// Ask the server which cities this trip would visit, and let the traveller
  /// settle it before a plan is paid for.
  ///
  /// The route is the biggest decision in a plan and used to be made silently
  /// inside generation — for a country the size of India the difference
  /// between Rajasthan and Kerala is the whole trip. Generation plans this
  /// route anyway, so showing it first costs nothing extra: the approved route
  /// goes back as `presetRoute` and is reused rather than planned again.
  ///
  /// Returns the route to generate with, or null to generate without one —
  /// which is what happens when the preview fails, and is exactly the old
  /// behaviour. [_routePreviewCancelled] distinguishes that from the traveller
  /// backing out, which must not start a generation at all.
  bool _routePreviewCancelled = false;

  Future<Map<String, dynamic>?> _confirmRoute() async {
    _routePreviewCancelled = false;

    Future<Map<String, dynamic>?> fetch(List<String> exclude) => _repository.previewRoute(
          destination: _destinationController.text.trim(),
          mood: _selectedMood,
          days: _days,
          travelers: _travelers,
          includeFlights: _includeFlights,
          departureCity: _departureCity,
          departureCountry: _departureCountry,
          departureLatitude: _departureLat,
          departureLongitude: _departureLng,
          startDate: _formatDate(_startDate ?? _flightStartDate ?? _hotelCheckInDate),
          hotelCheckInDate: _formatDate(_hotelCheckInDate),
          entryCity: _entryCity,
          exitCity: _exitCity,
          entryLatitude: _entryLat,
          entryLongitude: _entryLng,
          exitLatitude: _exitLat,
          exitLongitude: _exitLng,
          destinationPlaceId: _destPlaceId,
          destinationLatitude: _destLat,
          destinationLongitude: _destLng,
          destinationAddress: _destAddress,
          excludeCities: exclude,
        );

    final first = await fetch(const []);
    // No preview, no obstacle: generation plans its own route, as it always did.
    if (first == null || !mounted) return null;

    // Cities the traveller has turned down, carried across re-previews so the
    // planner cannot offer the same place back one shuffle later.
    final turnedDown = <String>[];

    // Held outside the modal's builder on purpose: `showModalBottomSheet`
    // re-invokes that builder when the route rebuilds (a keyboard or a metrics
    // change is enough), which would put a reshuffled route back to the first
    // one it was given.
    var preview = first;
    var busy = false;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final route = (preview['route'] as Map?)?.cast<String, dynamic>() ?? {};
            final legs = ((route['legs'] as List?) ?? const [])
                .whereType<Map>()
                .map((l) => l.cast<String, dynamic>())
                .toList();
            final notice = preview['notice']?.toString() ?? '';
            final region = route['region']?.toString() ?? '';

            Future<void> reload(List<String> exclude) async {
              setSheetState(() => busy = true);
              final next = await fetch(exclude);
              if (!sheetContext.mounted) return;
              setSheetState(() {
                busy = false;
                // A failed reshuffle keeps what is on screen rather than
                // emptying the sheet: the traveller can still accept it.
                if (next != null) preview = next;
              });
              if (next == null && sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(content: Text('Could not find another route just now.')),
                );
              }
            }

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
                      child: Text(
                        legs.length == 1
                            ? 'Your trip stays in ${legs.first['city'] ?? ''}'
                            : 'Your trip visits ${legs.length} cities',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: Text(
                        region.isNotEmpty
                            ? '$region · $_days days'
                            : 'Nothing is booked yet — change it before we build the plan.',
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ),
                    if (notice.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 16, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                notice,
                                style: const TextStyle(fontSize: 12, color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: legs.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1, indent: 56, color: Color(0xFFEEF1F5)),
                        itemBuilder: (_, i) {
                          final leg = legs[i];
                          final city = leg['city']?.toString() ?? '';
                          final start = leg['start_day'];
                          final end = leg['end_day'];
                          final nights = leg['nights'];
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: AppColors.brandGreen.withValues(alpha: 0.12),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.brandGreen),
                              ),
                            ),
                            title: Text(city,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              start == end
                                  ? 'Day $start'
                                  : 'Days $start–$end · $nights ${nights == 1 ? 'night' : 'nights'}',
                              style: const TextStyle(fontSize: 12, color: Colors.black45),
                            ),
                            // Removing a city re-plans around it rather than
                            // editing the days here: the server decides the
                            // route, so what comes back is always coherent.
                            trailing: (legs.length > 1 && !busy)
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 18, color: Colors.black38),
                                    tooltip: 'Not this city',
                                    onPressed: () {
                                      if (city.isNotEmpty) turnedDown.add(city);
                                      reload(List<String>.from(turnedDown));
                                    },
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    const Divider(height: 1, color: Color(0xFFEEF1F5)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () {
                                      // Everything on screen was turned down,
                                      // so none of it may come back.
                                      for (final leg in legs) {
                                        final city = leg['city']?.toString() ?? '';
                                        if (city.isNotEmpty) turnedDown.add(city);
                                      }
                                      reload(List<String>.from(turnedDown));
                                    },
                              icon: const Icon(Icons.shuffle_rounded, size: 18),
                              label: const Text('Somewhere else'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => Navigator.of(sheetContext).pop(route),
                              child: const Text('Use this route'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Centred under the two actions rather than inheriting the
                    // column's left edge, and set apart from them: it leaves
                    // the sheet without generating, so it should not read as a
                    // third button in the same row.
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: TextButton(
                          onPressed: busy
                              ? null
                              : () {
                                  _routePreviewCancelled = true;
                                  Navigator.of(sheetContext).pop();
                                },
                          child: const Text('Back', style: TextStyle(color: Colors.black54)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
    if (_includeFlights && !_hasVisa && (_nationality == null || _nationality!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your nationality for visa guidance.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    // Settle the route before anything is generated. A null route means
    // "carry on without one" — either the preview could not be planned, or
    // this build never had one — and generation plans its own, as before.
    final Map<String, dynamic>? presetRoute = await _confirmRoute();
    if (!mounted) return;
    if (_routePreviewCancelled) {
      // They backed out of the route, not into a different one. Leave them on
      // the form with nothing generated.
      setState(() => _isSubmitting = false);
      return;
    }

    try {
      await _repository.requestGeneration(
        presetRoute: presetRoute,
        destination: _destinationController.text.trim(),
        entryCity: _entryCity,
        exitCity: _exitCity,
        entryLatitude: _entryLat,
        entryLongitude: _entryLng,
        exitLatitude: _exitLat,
        exitLongitude: _exitLng,
        destinationPlaceId: _destPlaceId,
        destinationLatitude: _destLat,
        destinationLongitude: _destLng,
        destinationAddress: _destAddress,
        departureLatitude: _departureLat,
        departureLongitude: _departureLng,
        mood: _selectedMood,
        budget: _budget * _travelers,
        days: _days,
        currency: _currency,
        travelers: _travelers,
        includeFlights: _includeFlights,
        departureCity: _departureCity,
        departureCountry: _departureCountry,
        nationality: (_includeFlights && !_hasVisa) ? (_nationality ?? '') : '',
        hasVisa: !_includeFlights || _hasVisa,
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
        SnackBar(content: Text(userMessageFor(e, action: 'start planning'))),
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
        child: Column(
          children: [
            _buildProgressIndicator(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _buildCurrentStep(),
              ),
            ),
            if (Theme.of(context).platform == TargetPlatform.iOS &&
                MediaQuery.of(context).viewInsets.bottom > 0)
              _buildKeyboardDoneBar(),
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

  /// A tappable field shaped like the destination box above it.
  Widget _pickerField({
    required String label,
    required String? value,
    required IconData icon,
    required VoidCallback? onTap,
    String? helper,
    String? badge,
    bool busy = false,
  }) {
    final enabled = onTap != null;
    final filled = (value ?? '').isNotEmpty;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Colors.black54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      filled ? label : (helper ?? label),
                      style: TextStyle(
                        fontSize: filled ? 11 : 14,
                        fontWeight: filled ? FontWeight.w700 : FontWeight.w400,
                        letterSpacing: filled ? 0.6 : 0,
                        color: filled ? AppColors.textSecondary : Colors.black45,
                      ),
                    ),
                    if (filled) ...[
                      const SizedBox(height: 2),
                      Text(
                        value!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      // The country the city turned out to be in. A traveller
                      // who typed "Kandy" never said "Sri Lanka", and it is
                      // the country - not the city - that Exit is then held
                      // to, so it has to be visible before they wonder why
                      // their exit search finds nothing.
                      if ((badge ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.brandGreen.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.brandGreen.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.public_rounded,
                                  size: 12, color: AppColors.brandGreen),
                              const SizedBox(width: 4),
                              Text(
                                badge!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brandGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.brandGreen),
                )
              else if (enabled)
                const Icon(Icons.chevron_right_rounded, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDestinationStep() {
    return SingleChildScrollView(
      key: const ValueKey('destination'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Where to, and\nfor how long?',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1),
          ).animate().fade().slideY(begin: 0.1, end: 0),
          const SizedBox(height: 8),
          const Text(
            'Choose the country. Arrival and departure cities are optional.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 28),
          // Three fields, in the order the decisions are actually made: where
          // the trip is, then — only if the traveller cares — which city it
          // opens and closes in. Leaving both empty is the normal case: the
          // route preview proposes them and asks before anything is built.
          _pickerField(
            label: 'DESTINATION',
            value: _destinationController.text.trim().isEmpty
                ? null
                : _destinationController.text.trim(),
            icon: Icons.public_rounded,
            helper: 'Pick the country you are travelling to',
            onTap: _pickDestination,
          ).animate().fade(delay: 100.ms),
          const SizedBox(height: 12),
          _pickerField(
            label: 'ARRIVE IN',
            value: _entryCity.isEmpty ? null : _entryCity,
            icon: Icons.flight_land_rounded,
            helper: _canPickEnds
                ? 'Optional — where the trip starts'
                : 'Optional — choose a destination first',
            busy: _loadingEntryCities,
            // Opens the cities Google confirmed for the country, and falls
            // through to a search inside it when the list comes back empty.
            onTap: !_canPickEnds || _loadingEntryCities
                ? null
                : _offerEntryCities,
          ).animate().fade(delay: 130.ms),
          const SizedBox(height: 12),
          _pickerField(
            label: 'LEAVE FROM',
            value: _exitCity.isEmpty ? null : _exitCity,
            icon: Icons.flight_takeoff_rounded,
            helper: _canPickEnds
                ? 'Optional — where the trip finishes'
                : 'Optional — choose a destination first',
            onTap: _canPickEnds ? () => _pickEnd(isEntry: false) : null,
          ).animate().fade(delay: 160.ms),
          const SizedBox(height: 8),
          Text(
            _canPickEnds
                ? 'Both optional, and both searched in $_country only — a trip '
                    'starts and finishes in one country. Leave them empty and '
                    'the route is proposed for you to confirm.'
                : 'Leave these empty and the route is proposed for you to confirm.',
            style: const TextStyle(fontSize: 12, color: Colors.black45),
          ),
          const SizedBox(height: 28),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black12),
            ),
            child: Row(
              children: [
                const Icon(Icons.people_rounded, color: Colors.black54),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'How many travelers?',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  color: _travelers > 1 ? Colors.black87 : Colors.black26,
                  iconSize: 28,
                  splashRadius: 20,
                  tooltip: 'Decrease travelers',
                  onPressed: _travelers > 1
                      ? () {
                          setState(() {
                            _travelers--;
                            _travelersController.text = _travelers.toString();
                          });
                        }
                      : null,
                ),
                SizedBox(
                  width: 36,
                  child: TextField(
                    controller: _travelersController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    scrollPadding: const EdgeInsets.only(bottom: 140),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                    onTap: () {
                      _travelersController.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: _travelersController.text.length,
                      );
                    },
                    onChanged: (val) {
                      final parsed = int.tryParse(val);
                      if (parsed != null && parsed > 0 && parsed <= 20) {
                        setState(() => _travelers = parsed);
                      }
                    },
                    onSubmitted: (_) {
                      final parsed = int.tryParse(_travelersController.text);
                      if (parsed == null || parsed <= 0 || parsed > 20) {
                        _travelersController.text = _travelers.toString();
                      }
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      fillColor: Colors.transparent,
                      hintText: '1',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  color: _travelers < 20 ? Colors.black87 : Colors.black26,
                  iconSize: 28,
                  splashRadius: 20,
                  tooltip: 'Increase travelers',
                  onPressed: _travelers < 20
                      ? () {
                          setState(() {
                            _travelers++;
                            _travelersController.text = _travelers.toString();
                          });
                        }
                      : null,
                ),
              ],
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
          if (_includeFlights) ...[
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
      helpText: 'SELECT TRIP DATES (max $_maxTripDays days)',
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
      final rawDays = picked.end.difference(picked.start).inDays + 1;
      final wasCapped = rawDays > _maxTripDays;
      final end = wasCapped
          ? picked.start.add(Duration(days: _maxTripDays - 1))
          : picked.end;
      setState(() {
        _startDate = picked.start;
        _endDate = end;
        final computedDays = end.difference(picked.start).inDays + 1;
        if (computedDays > 0) {
          _days = computedDays;
          _daysController.text = computedDays.toString();
        }
        _flightStartDate ??= picked.start;
        _flightEndDate ??= end;
        _hotelCheckInDate ??= picked.start;
        _hotelCheckOutDate ??= end;
      });
      if (wasCapped && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Trips are capped at $_maxTripDays days so the AI planner can reliably generate every day — end date adjusted.',
            ),
          ),
        );
      }
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
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
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
            scrollPadding: const EdgeInsets.only(bottom: 140),
            inputFormatters: const [ThousandsSeparatorInputFormatter()],
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
      // A destination and dates. Arrive/leave are refinements, never gates.
      return _hasDestination && _startDate != null && _endDate != null;
    }
    if (_currentStep == 1) {
      if (_includeFlights && (_flightStartDate == null || _flightEndDate == null)) {
        return false;
      }
      if (_includeHotels && (_hotelCheckInDate == null || _hotelCheckOutDate == null)) {
        return false;
      }
      if (_includeFlights && !_hasVisa && (_nationality == null || _nationality!.isEmpty)) {
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
