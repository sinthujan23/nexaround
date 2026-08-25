import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';

class LocationSearchModal extends StatefulWidget {
  final double? currentLatitude;
  final double? currentLongitude;

  const LocationSearchModal({
    super.key,
    this.currentLatitude,
    this.currentLongitude,
  });

  @override
  State<LocationSearchModal> createState() => _LocationSearchModalState();
}

class _LocationSearchModalState extends State<LocationSearchModal> {
  static const String _recentSearchesKey = 'recent_location_searches';
  static const int _maxRecentSearches = 10;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  List<Map<String, dynamic>> _recentSearches = [];
  bool _isLoading = false;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Recent Searches Persistence & Cross-Device Cloud Sync ──────────────────

  Future<void> _loadRecentSearches() async {
    // 1. Instant local cache load (0ms offline-first)
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_recentSearchesKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          setState(() {
            _recentSearches = decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading local recent searches: $e');
    }

    // 2. Cross-device cloud sync from user account backend
    try {
      final response = await ApiClient.instance.get(
        '${ApiConstants.apiVersion}/auth/me/recent-locations',
      );
      if (response.statusCode == 200 && response.data is List) {
        final cloudList = (response.data as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        if (cloudList.isNotEmpty && mounted) {
          final merged = <Map<String, dynamic>>[...cloudList];
          for (final local in _recentSearches) {
            final exists = merged.any((c) =>
                c['name']?.toString().toLowerCase() ==
                local['name']?.toString().toLowerCase());
            if (!exists) merged.add(local);
          }
          final finalRecents = merged.take(_maxRecentSearches).toList();
          setState(() {
            _recentSearches = finalRecents;
          });
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_recentSearchesKey, jsonEncode(finalRecents));
        }
      }
    } catch (_) {
      // Offline / guest mode — already showing local cache
    }
  }

  Future<void> _saveRecentSearch(Map<String, dynamic> item) async {
    try {
      final name = item['name'] as String? ?? '';
      if (name.trim().isEmpty) return;

      final normalizedItem = {
        'place_id': item['place_id'] ?? '',
        'name': name,
        'address': item['address'] ?? item['district'] ?? '',
        'district': item['district'] ?? 'Nearby',
        'latitude': (item['latitude'] as num?)?.toDouble() ?? 0.0,
        'longitude': (item['longitude'] as num?)?.toDouble() ?? 0.0,
      };

      // Remove any existing duplicate (matched by name or place_id)
      _recentSearches.removeWhere((e) =>
          (e['name']?.toString().toLowerCase() == name.toLowerCase()) ||
          (e['place_id'] != null &&
              item['place_id'] != null &&
              e['place_id'].toString().isNotEmpty &&
              e['place_id'] == item['place_id']));

      // Insert at the front
      _recentSearches.insert(0, normalizedItem);

      // Keep within max limit
      if (_recentSearches.length > _maxRecentSearches) {
        _recentSearches = _recentSearches.sublist(0, _maxRecentSearches);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recentSearchesKey, jsonEncode(_recentSearches));

      // Asynchronously sync to backend account for cross-device persistence
      ApiClient.instance.post(
        '${ApiConstants.apiVersion}/auth/me/recent-locations',
        data: normalizedItem,
      ).catchError((_) {});
    } catch (e) {
      debugPrint('Error saving recent search: $e');
    }
  }

  Future<void> _removeRecentSearch(int index) async {
    if (index < 0 || index >= _recentSearches.length) return;
    final item = _recentSearches[index];
    final name = item['name'] as String? ?? '';
    final placeId = item['place_id'] as String? ?? '';

    setState(() {
      _recentSearches.removeAt(index);
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recentSearchesKey, jsonEncode(_recentSearches));

      // Asynchronously sync removal to backend
      ApiClient.instance.delete(
        '${ApiConstants.apiVersion}/auth/me/recent-locations',
        queryParameters: {
          if (name.isNotEmpty) 'name': name,
          if (placeId.isNotEmpty) 'place_id': placeId,
        },
      ).catchError((_) {});
    } catch (e) {
      debugPrint('Error removing recent search: $e');
    }
  }

  Future<void> _clearAllRecentSearches() async {
    setState(() {
      _recentSearches.clear();
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentSearchesKey);

      // Asynchronously sync clear all to backend
      ApiClient.instance.delete(
        '${ApiConstants.apiVersion}/auth/me/recent-locations',
      ).catchError((_) {});
    } catch (e) {
      debugPrint('Error clearing recent searches: $e');
    }
  }

  // ── GPS Current Location Fetch ───────────────────────────────────────────

  Future<void> _fetchAndSelectCurrentLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);

    try {
      bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services are disabled on your device.'),
              backgroundColor: Color(0xFFE65100),
            ),
          );
        }
        setState(() => _isLocating = false);
        return;
      }

      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
        if (permission == geo.LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission was denied.'),
                backgroundColor: Color(0xFFE65100),
              ),
            );
          }
          setState(() => _isLocating = false);
          return;
        }
      }

      if (permission == geo.LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are permanently denied. Please enable in Settings.'),
              backgroundColor: Color(0xFFE65100),
            ),
          );
        }
        setState(() => _isLocating = false);
        return;
      }

      final pos = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));

      final details = await GooglePlacesService.reverseGeocodeDetailed(
        pos.latitude,
        pos.longitude,
      );

      final locName = details['location_name'] ?? 'Current Location';
      final district = details['district'] ?? 'Nearby';
      final resolvedName = locName != 'Nearby' ? locName : (district != 'Nearby' ? district : 'Current Location');

      final result = {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'name': resolvedName,
        'district': district,
        'address': district,
      };

      await _saveRecentSearch(result);

      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not obtain current location: $e'),
            backgroundColor: const Color(0xFFE65100),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  // ── Autocomplete Search ──────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _isLoading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 200), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _suggestions = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final results = await GooglePlacesService.getAutocompleteSuggestions(
        input: trimmed,
        latitude: widget.currentLatitude ?? 6.9271,
        longitude: widget.currentLongitude ?? 79.8612,
      );

      if (mounted) {
        setState(() {
          final Set<String> seenKeys = {};
          final List<Map<String, dynamic>> mapped = [];
          for (final item in results) {
            final placeId = (item['place_id'] ?? '').toString().trim().toLowerCase();
            final name = (item['main_text'] ?? item['description'] ?? '').toString().trim();
            final key = placeId.isNotEmpty ? placeId : name.toLowerCase();
            if (key.isNotEmpty && seenKeys.add(key)) {
              mapped.add({
                'place_id': item['place_id'] ?? '',
                'name': name,
                'address': item['secondary_text'] ?? item['description'] ?? '',
                'district': item['secondary_text'] ?? 'Nearby',
                'latitude': 0.0,
                'longitude': 0.0,
              });
            }
          }
          _suggestions = mapped;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Location search error: $e');
      if (mounted) {
        setState(() {
          _suggestions = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onSuggestionTapped(Map<String, dynamic> suggestion) async {
    final placeId = suggestion['place_id'] as String?;
    double lat = (suggestion['latitude'] as num?)?.toDouble() ?? 0.0;
    double lng = (suggestion['longitude'] as num?)?.toDouble() ?? 0.0;
    String name = suggestion['name'] as String? ?? 'Location';

    if ((lat == 0.0 || lng == 0.0) && placeId != null && placeId.isNotEmpty) {
      final details = await GooglePlacesService.getPlaceDetails(placeId);
      if (details != null) {
        lat = details.latitude;
        lng = details.longitude;
        name = details.name;
      }
    }

    final selected = {
      'place_id': placeId ?? '',
      'latitude': lat,
      'longitude': lng,
      'name': name,
      'district': suggestion['district'] ?? 'Nearby',
      'address': suggestion['address'] ?? suggestion['district'] ?? '',
    };

    await _saveRecentSearch(selected);

    if (mounted) {
      Navigator.pop(context, selected);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isQueryEmpty = _searchController.text.trim().isEmpty;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              height: 4.5,
              width: 38,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Title
          const Padding(
            padding: EdgeInsets.only(left: 20, right: 20, top: 2, bottom: 14),
            child: Text(
              'Search Destination',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
                letterSpacing: -0.3,
              ),
            ),
          ),

          // Search Bar Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.search_rounded, color: AppColors.brandGreen, size: 22),
                    onPressed: () => _executeSearch(_searchController.text),
                    tooltip: 'Search',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      cursorColor: AppColors.brandGreen,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchChanged,
                      onSubmitted: (query) => _executeSearch(query),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        fillColor: Colors.transparent,
                        hintText: 'Search city, region, or attraction...',
                        hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.black38, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      tooltip: 'Clear',
                    ),
                  Container(
                    height: 22,
                    width: 1,
                    color: const Color(0xFFCBD5E1),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                  IconButton(
                    icon: _isLocating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandGreen),
                          )
                        : const Icon(Icons.my_location_rounded, color: AppColors.brandGreen, size: 20),
                    onPressed: _fetchAndSelectCurrentLocation,
                    tooltip: 'Use Current Location',
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),

          // Content body: Recent searches & Current location OR Autocomplete Suggestions
          Expanded(
            child: isQueryEmpty
                ? _buildEmptyQueryContent()
                : (_isLoading && _suggestions.isEmpty
                    ? _buildLoading()
                    : (_suggestions.isEmpty ? _buildNoResults() : _buildSuggestionsList())),
          ),
        ],
      ),
    );
  }

  // ── Sub-Views ────────────────────────────────────────────────────────────

  Widget _buildEmptyQueryContent() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // "Use Current Location" Tile
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.brandGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: _isLocating
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandGreen),
                  )
                : const Icon(Icons.near_me_rounded, color: AppColors.brandGreen, size: 20),
          ),
          title: const Text(
            'Use Current Location',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.brandGreen,
            ),
          ),
          subtitle: const Text(
            'Explore places and plan around your GPS position',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          onTap: _fetchAndSelectCurrentLocation,
        ),

        if (_recentSearches.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'RECENT SEARCHES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Color(0xFF64748B),
                  ),
                ),
                TextButton(
                  onPressed: _clearAllRecentSearches,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Clear all',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ..._recentSearches.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final name = item['name'] as String? ?? '';
            final address = item['address'] as String? ?? item['district'] as String? ?? '';

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history_rounded, color: Color(0xFF64748B), size: 20),
              ),
              title: Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              subtitle: address.isNotEmpty
                  ? Text(
                      address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    )
                  : null,
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                onPressed: () => _removeRecentSearch(index),
                tooltip: 'Remove',
              ),
              onTap: () => _onSuggestionTapped(item),
            );
          }),
        ] else ...[
          const SizedBox(height: 48),
          const Center(
            child: Column(
              children: [
                Icon(
                  Icons.travel_explore_rounded,
                  size: 52,
                  color: Colors.black12,
                ),
                SizedBox(height: 12),
                Text(
                  'Search any city, town, or landmark',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSuggestionsList() {
    return ListView.builder(
      itemCount: _suggestions.length,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        return ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.location_on_outlined, color: AppColors.brandGreen, size: 20),
          ),
          title: Text(
            suggestion['name'] ?? '',
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: suggestion['address'] != null && (suggestion['address'] as String).isNotEmpty
              ? Text(
                  suggestion['address'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          onTap: () => _onSuggestionTapped(suggestion),
        );
      },
    );
  }

  Widget _buildLoading() {
    return ListView.builder(
      itemCount: 6,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Shimmer.fromColors(
                baseColor: Colors.grey[200]!,
                highlightColor: Colors.grey[50]!,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Shimmer.fromColors(
                      baseColor: Colors.grey[200]!,
                      highlightColor: Colors.grey[50]!,
                      child: Container(
                        width: double.infinity,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Shimmer.fromColors(
                      baseColor: Colors.grey[200]!,
                      highlightColor: Colors.grey[50]!,
                      child: Container(
                        width: 140,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.location_off_outlined,
            size: 48,
            color: Color(0xFFCBD5E1),
          ),
          const SizedBox(height: 12),
          Text(
            'No places found for "${_searchController.text}"',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Try checking your spelling or search for another city',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
