import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:nexaround_app/features/attractions/domain/repositories/attraction_repository.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_event.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_state.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  final AttractionRepository _repository;

  MapBloc(this._repository) : super(const MapState()) {
    on<FetchNearbyAttractions>(_onFetchNearbyAttractions);
    on<FetchCategories>(_onFetchCategories);
    on<UpdateMapType>(_onUpdateMapType);
    on<SelectAttraction>(_onSelectAttraction);
    on<SearchAttractions>(_onSearchAttractions);
  }

  bool _matchesCategory(AttractionEntity a, String? categoryName) {
    if (categoryName == null || categoryName == 'All') return true;
    
    final catName = (a.categoryName ?? '').toLowerCase();
    final filterName = categoryName.toLowerCase();
    
    if (filterName == 'food & drink' || filterName == 'food') {
      return catName.contains('food') || catName.contains('restaurant') || catName.contains('cafe') || catName.contains('dining') || catName.contains('meal');
    }
    if (filterName == 'shopping') {
      return catName.contains('shop') || catName.contains('store') || catName.contains('mall') || catName.contains('market');
    }
    if (filterName == 'hotels') {
      return catName.contains('hotel') || catName.contains('lodging') || catName.contains('resort') || catName.contains('motel');
    }
    if (filterName == 'medical') {
      return catName.contains('medical') || catName.contains('hospital') || catName.contains('pharmacy') || catName.contains('doctor') || catName.contains('clinic') || catName.contains('health');
    }
    if (filterName == 'attractions' || filterName == 'historical') {
      return catName.contains('attraction') || catName.contains('museum') || catName.contains('temple') || catName.contains('historic') || catName.contains('monument') || catName.contains('landmark');
    }
    if (filterName == 'experiences') {
      return catName.contains('experience') || catName.contains('amusement') || catName.contains('park') || catName.contains('entertainment') || catName.contains('zoo');
    }
    
    return catName.contains(filterName);
  }

  Map<String, dynamic> _attractionEntityToJson(AttractionEntity a) {
    return {
      'id': a.id,
      'name': a.name,
      'description': a.description,
      'history': a.history,
      'latitude': a.latitude,
      'longitude': a.longitude,
      'category_id': a.categoryId,
      'category_name': a.categoryName,
      'address': a.address,
      'opening_hours': a.openingHours,
      'entry_fee': a.entryFee,
      'currency': a.currency,
      'rating': a.rating,
      'review_count': a.reviewCount,
      'photo_urls': a.photoUrls,
      'tags': a.tags,
      'geofence_radius_m': a.geofenceRadiusM,
      'distance_m': a.distanceM,
      'is_active': a.isActive,
      'created_at': a.createdAt.toIso8601String(),
    };
  }

  List<AttractionModel> _getFilteredCache(double lat, double lng) {
    try {
      final cached = CacheService.getCachedAttractions();
      if (cached.isEmpty) return [];
      
      final List<AttractionModel> result = [];
      for (final json in cached) {
        final model = AttractionModel.fromJson(json);
        final double distM = geo.Geolocator.distanceBetween(
          lat,
          lng,
          model.latitude,
          model.longitude,
        );
        if (distM <= 50000) {
          result.add(AttractionModel(
            id: model.id,
            name: model.name,
            description: model.description,
            history: model.history,
            latitude: model.latitude,
            longitude: model.longitude,
            categoryId: model.categoryId,
            categoryName: model.categoryName,
            address: model.address,
            openingHours: model.openingHours,
            entryFee: model.entryFee,
            currency: model.currency,
            rating: model.rating,
            reviewCount: model.reviewCount,
            photoUrls: model.photoUrls,
            tags: model.tags,
            geofenceRadiusM: model.geofenceRadiusM,
            distanceM: distM,
            isActive: model.isActive,
            createdAt: model.createdAt,
          ));
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<void> _onFetchNearbyAttractions(
    FetchNearbyAttractions event,
    Emitter<MapState> emit,
  ) async {
    // If we don't have all categories loaded yet, perform a complete batch fetch first.
    // Check status to prevent infinite loading loops if the API returns an empty list.
    if (state.status == MapStatus.initial || state.status == MapStatus.failure || state.allAttractions.isEmpty) {
      // Check proximity cache first (within 1km) to skip network requests entirely and reduce cost
      final lastLat = CacheService.getLastFetchLat();
      final lastLng = CacheService.getLastFetchLng();
      if (lastLat != null && lastLng != null) {
        final double distM = geo.Geolocator.distanceBetween(
          event.latitude,
          event.longitude,
          lastLat,
          lastLng,
        );
        if (distM < 1000) {
          final cachedModels = _getFilteredCache(event.latitude, event.longitude);
          if (cachedModels.isNotEmpty) {
            emit(state.copyWith(
              status: MapStatus.success,
              attractions: cachedModels,
              allAttractions: cachedModels,
              selectedCategoryId: event.categoryId,
            ));
            return; // Bypass network request entirely
          }
        }
      }

      // Load and emit local cache first for instant feedback (zero latency) if it is nearby
      final cachedModels = _getFilteredCache(event.latitude, event.longitude);
      if (cachedModels.isNotEmpty) {
        emit(state.copyWith(
          status: MapStatus.success,
          attractions: cachedModels,
          allAttractions: cachedModels,
          selectedCategoryId: event.categoryId,
        ));
      } else {
        // Show loading spinner only if there's no cache available
        emit(state.copyWith(status: MapStatus.loading));
      }

      final categoriesToFetch = [
        'Attractions',
        'Food & Drink',
        'Hotels',
        'Shopping',
        'Medical',
        'Hospital',
      ];

      final Map<String, AttractionEntity> uniqueAttractions = {};

      try {
        final mainFutures = categoriesToFetch.map((cat) async {
          // --- BYPASS HYBRID/GEMINI FOR FOOD & ATTRACTIONS ---
          if (cat == 'Food & Drink' || cat == 'Food' || cat == 'Attractions') {
            final discoveryRadius = cat == 'Attractions' ? 50000 : 5000;
            final discoveryCategory = cat == 'Attractions' ? 'Experiences' : 'Food & Drink';
            
            var discoveryList = <AttractionEntity>[];
            try {
              print('🔄 Bypassing AI for $cat. Fetching discovery places...');
              discoveryList = await GooglePlacesService.fetchNearbyPlaces(
                latitude: event.latitude,
                longitude: event.longitude,
                categoryName: discoveryCategory,
                radius: discoveryRadius,
              );
            } catch (e) {
              print('⚠️ Discovery fetch failed for $cat: $e');
            }
            
            if (discoveryList.length < 15) {
              try {
                print('🔄 Still only ${discoveryList.length} for $cat. Falling back to legacy API...');
                final legacyFallback = await GooglePlacesService.fetchNearbyPlacesLegacy(
                  latitude: event.latitude,
                  longitude: event.longitude,
                  categoryName: discoveryCategory,
                  radius: discoveryRadius,
                );
                final Map<String, AttractionEntity> tempMap = {};
                for (final p in discoveryList) tempMap[p.id] = p;
                for (final p in legacyFallback) {
                  if (!tempMap.containsKey(p.id)) tempMap[p.id] = p;
                }
                discoveryList = tempMap.values.toList();
              } catch (e) {
                print('⚠️ Legacy fetch failed: $e');
              }
            }

            final mappedList = discoveryList.map((p) {
              final distM = geo.Geolocator.distanceBetween(
                event.latitude, event.longitude, p.latitude, p.longitude,
              );
              return AttractionModel(
                id: p.id, name: p.name, description: p.description, history: p.history,
                latitude: p.latitude, longitude: p.longitude, categoryId: p.categoryId,
                categoryName: cat, // FORCE CATEGORY MATCH
                address: p.address, openingHours: p.openingHours, entryFee: p.entryFee,
                currency: p.currency, rating: p.rating, reviewCount: p.reviewCount,
                photoUrls: p.photoUrls, tags: p.tags, geofenceRadiusM: p.geofenceRadiusM,
                distanceM: distM, isActive: p.isActive, createdAt: p.createdAt,
              );
            }).toList()..sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));
            
            print('✅ Final Discovery: ${mappedList.length} results for $cat');
            return mappedList;
          }
          // --- END BYPASS ---

          if (cat == 'Medical' || cat == 'Shopping' || cat == 'Hospital') {
            // Retrieve geocoded location name bias
            String locationName = 'Nearby';
            try {
              locationName = await GooglePlacesService.reverseGeocode(event.latitude, event.longitude);
            } catch (_) {}
            if (locationName == 'Nearby' || locationName.trim().isEmpty) {
              locationName = 'current location';
            }
            
            final hybridList = await GooglePlacesService.fetchHybridPlaces(
              latitude: event.latitude,
              longitude: event.longitude,
              categoryName: cat,
              locationName: locationName,
            );
            
            final double radius = (cat == 'Medical' || cat == 'Hospital') ? 50000.0 : 15000.0;
            var repoRes = await _repository.getNearbyAttractions(
              latitude: event.latitude,
              longitude: event.longitude,
              radius: radius,
              categoryName: cat,
              useLegacy: event.useLegacy,
            );
            var fallbackList = repoRes.fold((_) => <AttractionEntity>[], (r) => r);

            if (fallbackList.isEmpty && !event.useLegacy) {
              print('⚠️ Fallback list empty for $cat. Retrying with useLegacy=true');
              repoRes = await _repository.getNearbyAttractions(
                latitude: event.latitude,
                longitude: event.longitude,
                radius: radius,
                categoryName: cat,
                useLegacy: true,
              );
              fallbackList = repoRes.fold((_) => <AttractionEntity>[], (r) => r);
            }

            // Merge fallback and hybrid lists to ensure rich listings
            final Map<String, AttractionEntity> mergedMap = {};
            for (final p in fallbackList) {
              mergedMap[p.id] = p;
              mergedMap[p.name.trim().toLowerCase()] = p;
            }
            for (final p in hybridList) {
              mergedMap[p.id] = p;
              mergedMap[p.name.trim().toLowerCase()] = p;
            }

            var mergedList = mergedMap.values.toSet().toList();

            // Fallback: if primary method returned fewer than 15 results for
            // Shopping, use the discovery-style fetchNearbyPlaces() and Google legacy as fallback.
            if (mergedList.length < 15 && cat == 'Shopping') {
              final discoveryRadius = 15000;

              // Fallback 1: Backend-cached Google Places (fetchNearbyPlaces)
              try {
                print('🔄 Primary method returned only ${mergedList.length} results for $cat. Falling back to fetchNearbyPlaces...');
                final discoveryFallback = await GooglePlacesService.fetchNearbyPlaces(
                  latitude: event.latitude,
                  longitude: event.longitude,
                  categoryName: cat,
                  radius: discoveryRadius,
                );
                for (final p in discoveryFallback) {
                  mergedMap[p.id] = p;
                  mergedMap[p.name.trim().toLowerCase()] = p;
                }
                mergedList = mergedMap.values.toSet().toList();
                print('📊 After fetchNearbyPlaces fallback: ${mergedList.length} results for $cat');
              } catch (e) {
                print('⚠️ fetchNearbyPlaces fallback failed for $cat: $e');
              }

              // Fallback 2: Direct Google Nearby Search legacy API if still under 15
              if (mergedList.length < 15) {
                try {
                  print('🔄 Still only ${mergedList.length} results for $cat. Falling back to Google legacy Nearby Search...');
                  final legacyFallback = await GooglePlacesService.fetchNearbyPlacesLegacy(
                    latitude: event.latitude,
                    longitude: event.longitude,
                    categoryName: cat,
                    radius: discoveryRadius,
                  );
                  for (final p in legacyFallback) {
                    mergedMap[p.id] = p;
                    mergedMap[p.name.trim().toLowerCase()] = p;
                  }
                  mergedList = mergedMap.values.toSet().toList();
                  print('📊 After Google legacy fallback: ${mergedList.length} results for $cat');
                } catch (e) {
                  print('⚠️ Google legacy fallback also failed for $cat: $e');
                }
              }

              // Recalculate distances and sort by proximity so the panel
              // shows a natural progression (0→1→2→3→4→5 km etc.)
              mergedList = mergedList.map((p) {
                final distM = geo.Geolocator.distanceBetween(
                  event.latitude, event.longitude,
                  p.latitude, p.longitude,
                );
                return AttractionModel(
                  id: p.id,
                  name: p.name,
                  description: p.description,
                  history: p.history,
                  latitude: p.latitude,
                  longitude: p.longitude,
                  categoryId: p.categoryId,
                  categoryName: p.categoryName,
                  address: p.address,
                  openingHours: p.openingHours,
                  entryFee: p.entryFee,
                  currency: p.currency,
                  rating: p.rating,
                  reviewCount: p.reviewCount,
                  photoUrls: p.photoUrls,
                  tags: p.tags,
                  geofenceRadiusM: p.geofenceRadiusM,
                  distanceM: distM,
                  isActive: p.isActive,
                  createdAt: p.createdAt,
                );
              }).toList();
              mergedList.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));
              print('✅ Final: ${mergedList.length} results for $cat (sorted by distance)');
            }

            if (mergedList.isNotEmpty) {
              return mergedList;
            }
            return <AttractionEntity>[];
          } else {
            var repoRes = await _repository.getNearbyAttractions(
              latitude: event.latitude,
              longitude: event.longitude,
              radius: 15000.0,
              categoryName: cat,
              useLegacy: event.useLegacy,
            );
            var list = repoRes.fold((_) => <AttractionEntity>[], (r) => r);

            if (list.isEmpty && !event.useLegacy) {
              print('⚠️ Fallback list empty for $cat. Retrying with useLegacy=true');
              repoRes = await _repository.getNearbyAttractions(
                latitude: event.latitude,
                longitude: event.longitude,
                radius: 15000.0,
                categoryName: cat,
                useLegacy: true,
              );
              list = repoRes.fold((_) => <AttractionEntity>[], (r) => r);
            }
            return list;
          }
        }).toList();

        final results = await Future.wait(mainFutures);

        final fetched = results.expand((x) => x).toList();
        for (final a in fetched) {
          uniqueAttractions[a.name] = a;
        }

        // Recompute user-centric distances relative to original lat/lng coordinates
        final List<AttractionEntity> attractionsList = [];
        for (final a in uniqueAttractions.values) {
          final double distM = geo.Geolocator.distanceBetween(
            event.latitude,
            event.longitude,
            a.latitude,
            a.longitude,
          );
          attractionsList.add(AttractionModel(
            id: a.id,
            name: a.name,
            description: a.description,
            history: a.history,
            latitude: a.latitude,
            longitude: a.longitude,
            categoryId: a.categoryId,
            categoryName: a.categoryName,
            address: a.address,
            openingHours: a.openingHours,
            entryFee: a.entryFee,
            currency: a.currency,
            rating: a.rating,
            reviewCount: a.reviewCount,
            photoUrls: a.photoUrls,
            tags: a.tags,
            geofenceRadiusM: a.geofenceRadiusM,
            distanceM: distM,
            isActive: a.isActive,
            createdAt: a.createdAt,
          ));
        }

        if (attractionsList.isEmpty) {
          // If network results are completely empty (offline/no network), load cache
          final cachedModels = _getFilteredCache(event.latitude, event.longitude);
          if (cachedModels.isNotEmpty) {
            emit(state.copyWith(
              status: MapStatus.success,
              attractions: cachedModels,
              allAttractions: cachedModels,
              selectedCategoryId: event.categoryId,
            ));
            return;
          }
        }

        attractionsList.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));

        // Save successfully loaded network attractions to local persistent cache
        final attractionJsons = attractionsList.map((a) => _attractionEntityToJson(a)).toList();
        await CacheService.mergeAndCacheAttractions(attractionJsons);
        await CacheService.saveLastFetchCoords(event.latitude, event.longitude);

        emit(state.copyWith(
          status: MapStatus.success,
          attractions: attractionsList,
          allAttractions: attractionsList,
          selectedCategoryId: event.categoryId,
        ));
      } catch (e) {
        // Fallback to cache if network failed/threw SocketException
        final cachedModels = _getFilteredCache(event.latitude, event.longitude);
        if (cachedModels.isNotEmpty) {
          emit(state.copyWith(
            status: MapStatus.success,
            attractions: cachedModels,
            allAttractions: cachedModels,
            selectedCategoryId: event.categoryId,
          ));
          return;
        }

        emit(state.copyWith(
          status: MapStatus.failure,
          errorMessage: e.toString(),
        ));
      }
      return; // Return early so we don't fall through and emit again
    }

    // Now state.allAttractions is guaranteed to be populated.
    // If a specific category was requested, filter the master list locally.
    if (event.categoryName != null && event.categoryName != 'All') {
      final filtered = state.allAttractions.where((a) => _matchesCategory(a, event.categoryName)).toList();
      emit(state.copyWith(
        status: MapStatus.success,
        attractions: filtered,
        selectedCategoryId: event.categoryId,
      ));
    } else {
      // If 'All' or null is requested, show everything
      emit(state.copyWith(
        status: MapStatus.success,
        attractions: state.allAttractions,
        selectedCategoryId: event.categoryId,
      ));
    }
  }

  Future<void> _onFetchCategories(
    FetchCategories event,
    Emitter<MapState> emit,
  ) async {
    final result = await _repository.getCategories();

    result.fold(
      (failure) => null, // Silently fail for categories or handle error
      (categories) => emit(state.copyWith(categories: categories)),
    );
  }

  void _onUpdateMapType(UpdateMapType event, Emitter<MapState> emit) {
    emit(state.copyWith(isSatellite: event.isSatellite));
  }

  void _onSelectAttraction(SelectAttraction event, Emitter<MapState> emit) {
    emit(state.copyWith(selectedAttraction: event.attraction));
  }

  Future<void> _onSearchAttractions(
    SearchAttractions event,
    Emitter<MapState> emit,
  ) async {
    // Basic search simulation or API call
    if (event.query.isEmpty) {
      // If empty, we could re-fetch nearby, but for now just filter locally or keep existing
      return;
    }
    
    // In a real app, you might call a search API. 
    // For now, we'll assume the nearby attractions are filtered by name locally for immediate feedback
    final filtered = state.attractions.where((a) => 
      a.name.toLowerCase().contains(event.query.toLowerCase())).toList();
    
    emit(state.copyWith(attractions: filtered));
  }
}
