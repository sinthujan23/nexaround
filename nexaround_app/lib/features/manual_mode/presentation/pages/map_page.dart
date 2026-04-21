import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong2.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_bloc.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_event.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_state.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexaround_app/features/attractions/presentation/pages/attraction_detail_page.dart';

enum MapStyle { streets, light, dark, satellite }

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  String? _selectedCategoryId;
  MapStyle _currentStyle = MapStyle.light;
  bool _showStylePicker = false;
  bool _is3DMode = false;
  late AnimationController _tiltController;

  @override
  void initState() {
    super.initState();
    _tiltController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _determinePosition();
    context.read<MapBloc>().add(FetchCategories());
  }

  @override
  void dispose() {
    _tiltController.dispose();
    super.dispose();
  }

  Matrix4 get _perspectiveMatrix {
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.001) // perspective
      ..rotateX(_is3DMode ? -0.5 : 0.0); // 30 degree tilt
    return matrix;
  }

  String get _currentTileUrl {
    if (_is3DMode) return ApiConstants.mapboxSatellite;
    switch (_currentStyle) {
      case MapStyle.streets:
        return ApiConstants.mapboxStreets;
      case MapStyle.light:
        return ApiConstants.mapboxLight;
      case MapStyle.dark:
        return ApiConstants.mapboxDark;
      case MapStyle.satellite:
        return ApiConstants.mapboxSatellite;
    }
  }

  // Fallback tile URL if Mapbox token is not set
  String get _tileUrl {
    if (ApiConstants.mapboxAccessToken == 'YOUR_MAPBOX_ACCESS_TOKEN_HERE') {
      if (_is3DMode) return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      
      switch (_currentStyle) {
        case MapStyle.dark:
          return 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
        case MapStyle.light:
          return 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
        case MapStyle.streets:
          return 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
        case MapStyle.satellite:
          return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      }
    }
    return _currentTileUrl;
  }

  bool get _isDarkStyle => _currentStyle == MapStyle.dark;

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    
    if (!mounted) return;

    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });

    _mapController.move(_currentPosition!, 14);

    if (mounted) {
      context.read<MapBloc>().add(FetchNearbyAttractions(
        latitude: position.latitude,
        longitude: position.longitude,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // The Map
          _buildMap(),
          
          // Floating Search Bar
          _buildFloatingSearch(),
          
          // Category Chips
          _buildCategoryFilters(),

          // Map Style Switcher
          _buildStyleSwitcher(),

          // Bottom Info Card
          _buildBottomPanel(),
          
          // My Location Button
          _buildLocationButton(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return BlocBuilder<MapBloc, MapState>(
      builder: (context, state) {
        return Stack(
          children: [
            // perspective transformation
            AnimatedContainer(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutQuart,
              transform: _perspectiveMatrix,
              transformAlignment: Alignment.center,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentPosition ?? LatLng(8.57, 81.23),
                  initialZoom: 14.0,
                  onTap: (_, __) {
                    context.read<MapBloc>().add(SelectAttraction(null));
                    setState(() => _showStylePicker = false);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: _tileUrl,
                    subdomains: const ['a', 'b', 'c', 'd'],
                    maxZoom: 19,
                    userAgentPackageName: 'com.nexaround.app',
                  ),
                  // Demo Neural Grid for "3D" feel
                  if (_is3DMode)
                    _buildNeuralGrid(),
                  MarkerLayer(
                    markers: _buildMarkers(state),
                  ),
                ],
              ),
            ),
            // Gradient overlays to hide seams of tilted map
            if (_is3DMode) ...[
              Positioned(
                top: 0, left: 0, right: 0, height: 200,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.background, AppColors.background.withOpacity(0)],
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildNeuralGrid() {
    return Opacity(
      opacity: 0.1,
      child: CustomPaint(
        painter: _NeuralGridPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }

  List<Marker> _buildMarkers(MapState state) {
    List<Marker> markers = [];
    
    // Current Location Marker
    if (_currentPosition != null) {
      markers.add(
        Marker(
          point: _currentPosition!,
          width: 60,
          height: 60,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 3),
              boxShadow: [
                BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 12, spreadRadius: 2),
              ],
            ),
            child: const Icon(Icons.person_rounded, color: AppColors.primary, size: 20),
          ),
        ),
      );
    }

    // Attraction Markers
    for (final attraction in state.attractions) {
      final isSelected = state.selectedAttraction?.id == attraction.id;
      markers.add(
        Marker(
          point: LatLng(attraction.latitude, attraction.longitude),
          width: isSelected ? 56 : 44,
          height: isSelected ? 56 : 44,
          child: GestureDetector(
            onTap: () {
              context.read<MapBloc>().add(SelectAttraction(attraction));
              _mapController.move(LatLng(attraction.latitude, attraction.longitude), 15);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.white : AppColors.primary,
                  width: isSelected ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isSelected ? AppColors.primary : Colors.black).withOpacity(isSelected ? 0.4 : 0.15),
                    blurRadius: isSelected ? 16 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.place_rounded,
                color: isSelected ? Colors.white : AppColors.primary,
                size: isSelected ? 28 : 20,
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  Widget _buildFloatingSearch() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 20,
      right: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 8)),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: AppColors.textTertiary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    onChanged: (val) {
                      context.read<MapBloc>().add(SearchAttractions(val));
                    },
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: 'Discover a place...',
                      hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tune_rounded, color: AppColors.primary, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fade(duration: 600.ms).slideY(begin: -0.3, end: 0);
  }

  Widget _buildCategoryFilters() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 80,
      left: 0,
      right: 0,
      child: BlocBuilder<MapBloc, MapState>(
        builder: (context, state) {
          if (state.categories.isEmpty) return const SizedBox.shrink();
          return SizedBox(
            height: 40,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: state.categories.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildCategoryChip('All', null, Icons.grid_view_rounded);
                }
                final cat = state.categories[index - 1];
                return _buildCategoryChip(cat.name, cat.id, Icons.explore_outlined);
              },
            ),
          );
        },
      ),
    ).animate().fade(delay: 200.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildCategoryChip(String label, String? id, IconData icon) {
    final isSelected = _selectedCategoryId == id;
    return GestureDetector(
      onTap: () async {
        setState(() => _selectedCategoryId = id);
        final pos = await Geolocator.getCurrentPosition();
        if (mounted) {
          context.read<MapBloc>().add(FetchNearbyAttractions(
            latitude: pos.latitude,
            longitude: pos.longitude,
            categoryId: id,
          ));
        }
      },
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : AppColors.textTertiary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Map Style Switcher ---
  Widget _buildStyleSwitcher() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 130,
      right: 20,
      child: Column(
        children: [
          // 3D Toggle Button
          GestureDetector(
            onTap: () => setState(() => _is3DMode = !_is3DMode),
            child: Container(
              width: 44,
              height: 44,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: _is3DMode ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _is3DMode ? AppColors.primary : AppColors.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Icon(
                _is3DMode ? Icons.view_in_ar_rounded : Icons.threed_rotation_rounded,
                color: _is3DMode ? Colors.white : AppColors.primary,
                size: 20,
              ),
            ),
          ).animate().fade(delay: 350.ms).scale(),

          // Style Toggle Button (Existing)
          GestureDetector(
            onTap: () => setState(() => _showStylePicker = !_showStylePicker),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: const Icon(Icons.layers_rounded, color: AppColors.primary, size: 20),
            ),
          ).animate().fade(delay: 400.ms).scale(),

          // Style Options
          if (_showStylePicker) ...[
            const SizedBox(height: 8),
            _buildStyleOption('Streets', MapStyle.streets, Icons.map_rounded),
            _buildStyleOption('Light', MapStyle.light, Icons.wb_sunny_rounded),
            _buildStyleOption('Dark', MapStyle.dark, Icons.nightlight_rounded),
            _buildStyleOption('Satellite', MapStyle.satellite, Icons.satellite_alt_rounded),
          ],
        ],
      ),
    );
  }

  Widget _buildStyleOption(String label, MapStyle style, IconData icon) {
    final isActive = _currentStyle == style;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentStyle = style;
          _showStylePicker = false;
        });
      },
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isActive ? AppColors.primary : AppColors.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Tooltip(
          message: label,
          child: Icon(icon, color: isActive ? Colors.white : AppColors.textSecondary, size: 18),
        ),
      ),
    ).animate().fade(duration: 200.ms).slideX(begin: 0.3, end: 0);
  }

  // --- Bottom Info Panel ---
  Widget _buildBottomPanel() {
    return BlocBuilder<MapBloc, MapState>(
      builder: (context, state) {
        if (state.selectedAttraction == null) return const SizedBox.shrink();
        
        final attraction = state.selectedAttraction!;
        return Positioned(
          bottom: 120,
          left: 20,
          right: 20,
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => AttractionDetailPage(
                name: attraction.name,
                category: attraction.categoryName ?? 'Attraction',
                rating: attraction.rating,
                distance: '${((attraction.distanceM ?? 0) / 1000).toStringAsFixed(1)} km',
                emoji: '🏛',
              )),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 30, offset: const Offset(0, -5)),
                    ],
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          attraction.photoUrls.isNotEmpty 
                            ? attraction.photoUrls.first 
                            : 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=500&q=80',
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              attraction.name,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${((attraction.distanceM ?? 0) / 1000).toStringAsFixed(1)} km · ${attraction.categoryName}',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'EXPLORE →',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.directions_rounded, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ).animate().slideY(begin: 1, end: 0, duration: 400.ms, curve: Curves.easeOutQuart);
      },
    );
  }

  Widget _buildLocationButton() {
    return Positioned(
      bottom: 240,
      right: 20,
      child: GestureDetector(
        onTap: _determinePosition,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: const Icon(Icons.my_location_rounded, color: AppColors.primary, size: 22),
        ),
      ),
    ).animate().fade(delay: 600.ms).scale();
  }
}

class _NeuralGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 0.5;

    const spacing = 40.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
