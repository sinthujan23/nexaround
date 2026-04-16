import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_bloc.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_event.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_state.dart';
import 'package:nexaround_app/features/manual_mode/presentation/widgets/map_search_bar.dart';
import 'package:nexaround_app/features/manual_mode/presentation/widgets/category_chips.dart';
import 'package:nexaround_app/features/attractions/presentation/pages/attraction_detail_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  AttractionEntity? _selectedAttraction;

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

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

    final position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });

    if (mounted) {
      context.read<MapBloc>().add(FetchNearbyAttractions(
        latitude: position.latitude,
        longitude: position.longitude,
      ));
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _setMapStyle();
  }

  void _setMapStyle() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      // Small delay to ensure controller is ready
      await Future.delayed(const Duration(milliseconds: 100));
      // In a real app, you'd load a JSON style here
      // For now we'll just use the default
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          BlocBuilder<MapBloc, MapState>(
            builder: (context, state) {
              return GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: CameraPosition(
                  target: _currentPosition ?? const LatLng(6.9271, 79.8612), // Default Colombo
                  zoom: 14,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapType: state.isSatellite ? MapType.satellite : MapType.normal,
                markers: _buildMarkers(state.attractions),
                onTap: (_) {
                  setState(() {
                    _selectedAttraction = null;
                  });
                },
              );
            },
          ),

          // Search Bar
          const Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: MapSearchBar(),
          ),

          // Category Filters
          Positioned(
            top: 132,
            left: 0,
            right: 0,
            child: BlocBuilder<MapBloc, MapState>(
              builder: (context, state) {
                return CategoryChips(
                  categories: state.categories,
                  selectedCategoryId: state.selectedCategoryId,
                  onSelected: (id) {
                    if (_currentPosition != null) {
                      context.read<MapBloc>().add(FetchNearbyAttractions(
                        latitude: _currentPosition!.latitude,
                        longitude: _currentPosition!.longitude,
                        categoryId: id,
                      ));
                    }
                  },
                );
              },
            ),
          ),

          // Status & FABs
          Positioned(
            right: 16,
            bottom: _selectedAttraction != null ? 220 : 100,
            child: Column(
              children: [
                _MapFab(
                  icon: Icons.layers_rounded,
                  onPressed: () {
                    final isSatellite = context.read<MapBloc>().state.isSatellite;
                    context.read<MapBloc>().add(UpdateMapType(!isSatellite));
                  },
                ),
                const SizedBox(height: 12),
                _MapFab(
                  icon: Icons.my_location_rounded,
                  onPressed: _determinePosition,
                ),
              ],
            ),
          ),

          // Selected Attraction Card
          if (_selectedAttraction != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: 40,
              child: _AttractionPreviewCard(
                attraction: _selectedAttraction!,
                onClose: () => setState(() => _selectedAttraction = null),
              ),
            ),
          
          // Loading Indicator
          BlocBuilder<MapBloc, MapState>(
            builder: (context, state) {
              if (state.status == MapStatus.loading) {
                return const Positioned(
                  top: 180,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Set<Marker> _buildMarkers(List<AttractionEntity> attractions) {
    return attractions.map((a) {
      return Marker(
        markerId: MarkerId(a.id),
        position: LatLng(a.latitude, a.longitude),
        infoWindow: InfoWindow(title: a.name),
        onTap: () {
          setState(() {
            _selectedAttraction = a;
          });
        },
      );
    }).toSet();
  }
}

class _MapFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _MapFab({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FloatingActionButton.small(
      heroTag: null,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      foregroundColor: isDark ? Colors.white : AppColors.textPrimary,
      elevation: 4,
      onPressed: onPressed,
      child: Icon(icon),
    );
  }
}

class _AttractionPreviewCard extends StatelessWidget {
  final AttractionEntity attraction;
  final VoidCallback onClose;

  const _AttractionPreviewCard({
    required this.attraction,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AttractionDetailPage(attraction: attraction),
          ),
        ),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  // Image
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                    ),
                    child: Container(
                      width: 140,
                      height: 160,
                      color: AppColors.primary.withOpacity(0.1),
                      child: attraction.photoUrls.isNotEmpty
                          ? Image.network(attraction.photoUrls.first, fit: BoxFit.cover)
                          : const Icon(Icons.image_outlined, color: AppColors.primary),
                    ),
                  ),
                  // Details
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            attraction.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, color: AppColors.accent, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                attraction.rating.toString(),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '(${attraction.reviewCount})',
                                style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                              ),
                            ],
                          ),
                          const Spacer(),
                          ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              minimumSize: const Size(double.infinity, 40),
                            ),
                            child: const Text('AI Guide'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onClose,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
