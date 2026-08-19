import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:shimmer/shimmer.dart';

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
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 300), () {
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
          _suggestions = results.map((item) {
            return {
              'place_id': item['place_id'] ?? '',
              'name': item['main_text'] ?? item['description'] ?? '',
              'address': item['secondary_text'] ?? item['description'] ?? '',
              'district': item['secondary_text'] ?? 'Nearby',
              'latitude': 0.0,
              'longitude': 0.0,
            };
          }).toList();
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

    if (mounted) {
      Navigator.pop(context, {
        'latitude': lat,
        'longitude': lng,
        'name': name,
        'district': suggestion['district'] ?? 'Nearby',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Single Clean Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              height: 5,
              width: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          
          // Header
          const Padding(
            padding: EdgeInsets.only(left: 20, right: 20, top: 2, bottom: 14),
            child: Text(
              'Explore Anywhere',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
                letterSpacing: -0.3,
              ),
            ),
          ),
          
          // Floating Search Bar Card with Inline GPS Action
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
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
                        hintText: 'Search city, area, or country...',
                        hintStyle: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
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
                    height: 24,
                    width: 1,
                    color: Colors.grey.shade200,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                  IconButton(
                    icon: const Icon(Icons.my_location_rounded, color: AppColors.brandGreen, size: 20),
                    onPressed: () {
                      Navigator.pop(context, 'clear_override');
                    },
                    tooltip: 'Use Current Location',
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          
          // Current Location Quick Chip
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 8),
            child: InkWell(
              onTap: () => Navigator.pop(context, 'clear_override'),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.brandGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.near_me_rounded, size: 14, color: AppColors.brandGreen),
                    SizedBox(width: 6),
                    Text(
                      'Use Current Location',
                      style: TextStyle(
                        color: AppColors.brandGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const Divider(height: 1, color: AppColors.border),
          
          // Results
          Expanded(
            child: _isLoading && _suggestions.isEmpty
                ? _buildLoading()
                : _suggestions.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: _suggestions.length,
                        itemBuilder: (context, index) {
                          final suggestion = _suggestions[index];
                          return ListTile(
                            leading: const Icon(
                              Icons.location_on_outlined,
                              color: AppColors.textSecondary,
                            ),
                            title: Text(
                              suggestion['name'] ?? '',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: suggestion['address'] != null && 
                                      (suggestion['address'] as String).isNotEmpty
                                ? Text(
                                    suggestion['address'],
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                            onTap: () => _onSuggestionTapped(suggestion),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLoading() {
    return ListView.builder(
      itemCount: 5,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Shimmer.fromColors(
                baseColor: Colors.grey[200]!,
                highlightColor: Colors.grey[50]!,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 16),
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
                    const SizedBox(height: 8),
                    Shimmer.fromColors(
                      baseColor: Colors.grey[200]!,
                      highlightColor: Colors.grey[50]!,
                      child: Container(
                        width: 150,
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.explore_outlined,
            size: 64,
            color: AppColors.textSecondary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          const Text(
            'Search for a destination',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
