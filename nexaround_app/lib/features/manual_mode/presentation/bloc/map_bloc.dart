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
    if (filterName == 'medical' || filterName == 'hospital') {
      return catName.contains('medical') || catName.contains('hospital') || catName.contains('pharmacy') || catName.contains('doctor') || catName.contains('clinic') || catName.contains('health');
    }
    if (filterName == 'poi' || filterName == 'attractions' || filterName == 'historical' || filterName == 'nature') {
      return catName.contains('poi') || catName.contains('attraction') || catName.contains('museum') || catName.contains('temple') || catName.contains('historic') || catName.contains('monument') || catName.contains('landmark') || catName.contains('nature') || catName.contains('park') || catName.contains('beach') || catName.contains('lake') || catName.contains('garden');
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

  bool _isValidPlace(String name, String categoryName) {
    if (categoryName.toLowerCase().contains('nature')) {
      final blacklist = ['hotel', 'hostel', 'residency', 'mall', 'shop', 'store', 'hospital', 'clinic', 'stay', 'inn', 'apartments', 'villa', 'toilet', 'bathroom'];
      final pinCodeRegex = RegExp(r'^\d+$');
      if (pinCodeRegex.hasMatch(name.trim())) return false;
      
      final nameLower = name.toLowerCase();
      for (final word in blacklist) {
        if (nameLower.contains(word)) return false;
      }
    }
    return true;
  }

  List<AttractionModel> _getFilteredCache(double lat, double lng) {
    try {
      final cached = CacheService.getCachedAttractions();
      if (cached.isEmpty) return [];
      
      final List<AttractionModel> result = [];
      for (final json in cached) {
        final model = AttractionModel.fromJson(json);
        
        if (!_isValidPlace(model.name, model.categoryName ?? '')) continue;
        
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
    final lastLat = CacheService.getLastFetchLat();
    final lastLng = CacheService.getLastFetchLng();
    bool needsFetch = state.status == MapStatus.initial || state.status == MapStatus.failure || state.allAttractions.isEmpty;

    if (!needsFetch && lastLat != null && lastLng != null) {
      final double distM = geo.Geolocator.distanceBetween(
        event.latitude,
        event.longitude,
        lastLat,
        lastLng,
      );
      if (distM > 1000) {
        needsFetch = true;
      }
    }

    if (needsFetch || event.forceRefresh) {
      if (lastLat != null && lastLng != null && !event.forceRefresh) {
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

      // Emit loading state so that the UI shows the shimmer/spinner while we fetch the fresh 3-zone data.
      // If the network request fails (e.g. offline), we will fall back to cache in the catch block.
      emit(state.copyWith(
        status: MapStatus.loading,
        attractions: const [],
        allAttractions: const [],
      ));

      const categoriesToFetch = [
        'POI',
        'Food & Drink',
        'Shopping',
        'Medical',
      ];

      final Map<String, AttractionEntity> uniqueAttractions = {};

      try {
        // --- PRIMARY: Single Unified Batch Fetch (1 Network Call for all 4 Categories) ---
        List<AttractionEntity> fetched = [];
        final batchMap = await GooglePlacesService.fetchNearbyPlacesBatch(
          latitude: event.latitude,
          longitude: event.longitude,
          categories: categoriesToFetch,
          radius: 50000,
          useLegacy: event.useLegacy,
        );

        if (batchMap.isNotEmpty && batchMap.values.any((l) => l.isNotEmpty)) {
          for (final entry in batchMap.entries) {
            final cat = entry.key;
            for (final p in entry.value) {
              fetched.add(AttractionModel(
                id: p.id,
                name: p.name,
                description: p.description,
                history: p.history,
                latitude: p.latitude,
                longitude: p.longitude,
                categoryId: p.categoryId,
                categoryName: cat,
                address: p.address,
                openingHours: p.openingHours,
                entryFee: p.entryFee,
                currency: p.currency,
                rating: p.rating,
                reviewCount: p.reviewCount,
                photoUrls: p.photoUrls,
                tags: p.tags,
                geofenceRadiusM: p.geofenceRadiusM,
                distanceM: p.distanceM,
                isActive: p.isActive,
                createdAt: p.createdAt,
              ));
            }
          }
        } else {
          // --- FALLBACK: Query 4 categories from repository ---
          final mainFutures = categoriesToFetch.map((cat) async {
            final double radius = (cat == 'Medical' || cat == 'POI') ? 50000.0 : 15000.0;
            final repoRes = await _repository.getNearbyAttractions(
              latitude: event.latitude,
              longitude: event.longitude,
              radius: radius,
              categoryName: cat,
              useLegacy: event.useLegacy,
            );
            return repoRes.fold((_) => <AttractionEntity>[], (r) => r);
          }).toList();

          final results = await Future.wait(mainFutures);
          fetched = results.expand((x) => x).toList();
        }
        for (final a in fetched) {
          // Use a composite key of name + categoryName so that the same physical
          // place fetched under different categories is stored separately, each
          // retaining its correct categoryName. Previously using only a.name
          // caused the last-written category to overwrite earlier ones, which
          // was the root cause of non-hospital places appearing in the Hospital tab.
          final dedupeKey = '${a.name.trim().toLowerCase()}__${(a.categoryName ?? '').toLowerCase()}';
          uniqueAttractions[dedupeKey] = a;
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
          if (distM <= 50000) {
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

        // Load the fully merged cache so we don't lose categories that failed to fetch this time
        final mergedModels = _getFilteredCache(event.latitude, event.longitude);

        final filteredAttractions = (event.categoryName != null && event.categoryName != 'All')
            ? mergedModels.where((a) => _matchesCategory(a, event.categoryName)).toList()
            : mergedModels;

        emit(state.copyWith(
          status: MapStatus.success,
          attractions: filteredAttractions,
          allAttractions: mergedModels,
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
