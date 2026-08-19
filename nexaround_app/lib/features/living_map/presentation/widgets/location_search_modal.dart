import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:shimmer/shimmer.dart';

class LocationSearchModal extends StatefulWidget {
  const LocationSearchModal({super.key});

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

    _debounce = Timer(const Duration(milliseconds: 500), () {
      _executeSearch(query);
    });
  }

  Future<void> _executeSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await Dio().get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': query,
          'format': 'jsonv2',
          'addressdetails': 1,
          'limit': 5,
          'featuretype': 'city', // Prefer cities/districts for global search
          'accept-language': 'en',
        },
        options: Options(
          headers: {
            'User-Agent': 'NexAroundApp/1.0',
            'Accept-Language': 'en',
          },
        ),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        final List<Map<String, dynamic>> results = data.map((item) {
          final addr = item['address'] as Map<String, dynamic>?;
          final city = addr?['city'] ?? addr?['town'] ?? addr?['village'] ?? item['name'] ?? item['display_name']?.split(',')[0] ?? 'Unknown';
          final country = addr?['country'];
          final displayName = country != null ? '$city, $country' : city;

          return {
            'latitude': double.tryParse(item['lat'] ?? '0') ?? 0.0,
            'longitude': double.tryParse(item['lon'] ?? '0') ?? 0.0,
            'name': displayName,
            'address': item['display_name'] ?? '',
            'district': addr?['county'] ?? addr?['state_district'] ?? addr?['city'] ?? item['name'],
          };
        }).toList();

        if (mounted) {
          setState(() {
            _suggestions = results;
            _isLoading = false;
          });
        }
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

  void _onSuggestionTapped(Map<String, dynamic> suggestion) {
    Navigator.pop(context, {
      'latitude': suggestion['latitude'] as double,
      'longitude': suggestion['longitude'] as double,
      'name': suggestion['name'], // Display name from suggestion
      'district': suggestion['district'] ?? 'Nearby',
    });
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
