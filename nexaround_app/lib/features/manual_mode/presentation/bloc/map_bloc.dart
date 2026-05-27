import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
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

  Future<void> _onFetchNearbyAttractions(
    FetchNearbyAttractions event,
    Emitter<MapState> emit,
  ) async {
    // If we don't have all categories loaded yet, perform a complete batch fetch first.
    // Check status to prevent infinite loading loops if the API returns an empty list.
    if (state.status == MapStatus.initial || state.status == MapStatus.failure || state.allAttractions.isEmpty) {
      // Load and emit local cache first for instant feedback (zero latency)
      final cached = CacheService.getCachedAttractions();
      if (cached.isNotEmpty) {
        final models = cached.map((json) => AttractionModel.fromJson(json)).toList();
        emit(state.copyWith(
          status: MapStatus.success,
          attractions: models,
          allAttractions: models,
          selectedCategoryId: event.categoryId,
        ));
      } else {
        // Show loading spinner only if there's no cache available
        emit(state.copyWith(status: MapStatus.loading));
      }

      final categoriesToFetch = [
        null,
        'Attractions',
        'Food & Drink',
        'Hotels',
        'Shopping',
        'Experiences',
        'Medical',
      ];

      // Expanded radii up to 50km to support both dense urban areas (finds places at 100m/500m) 
      // and rural areas (finds places up to 10km/50km).
      final searchRadii = [100, 500, 2000, 10000, 50000];
      final Map<String, AttractionEntity> uniqueAttractions = {};

      try {
        for (final radius in searchRadii) {
          final results = await Future.wait(categoriesToFetch.map((cat) {
            return _repository.getNearbyAttractions(
              latitude: event.latitude,
              longitude: event.longitude,
              radius: radius.toDouble(),
              categoryName: cat,
            ).then((res) => res.fold((_) => <AttractionEntity>[], (r) => r));
          }));

          final fetched = results.expand((x) => x).toList();
          for (final a in fetched) {
            uniqueAttractions[a.name] = a;
          }

          // Stop querying larger radii if we already have a robust list of close places to save API costs
          if (uniqueAttractions.length >= 25) {
            break;
          }
        }

        final finalAttractions = uniqueAttractions.values.toList();

        if (finalAttractions.isEmpty) {
          // If network results are completely empty (offline/no network), load cache
          final cached = CacheService.getCachedAttractions();
          if (cached.isNotEmpty) {
            final models = cached.map((json) => AttractionModel.fromJson(json)).toList();
            emit(state.copyWith(
              status: MapStatus.success,
              attractions: models,
              allAttractions: models,
              selectedCategoryId: event.categoryId,
            ));
            return;
          }
        }

        finalAttractions.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));

        // Save successfully loaded network attractions to local persistent cache
        final attractionJsons = finalAttractions.map((a) => _attractionEntityToJson(a)).toList();
        CacheService.cacheAttractions(attractionJsons);

        emit(state.copyWith(
          status: MapStatus.success,
          attractions: finalAttractions,
          allAttractions: finalAttractions,
          selectedCategoryId: event.categoryId,
        ));
      } catch (e) {
        // Fallback to cache if network failed/threw SocketException
        final cached = CacheService.getCachedAttractions();
        if (cached.isNotEmpty) {
          final models = cached.map((json) => AttractionModel.fromJson(json)).toList();
          emit(state.copyWith(
            status: MapStatus.success,
            attractions: models,
            allAttractions: models,
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
