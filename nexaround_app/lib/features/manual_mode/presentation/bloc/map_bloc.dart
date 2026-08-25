import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:nexaround_app/core/constants/place_bands.dart';
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
    on<FetchBandedPlaces>(_onFetchBandedPlaces);
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

  /// Fetch radius for a category, taken from the band table where one applies.
  ///
  /// 'Attractions' still folds into POI, and 'Beach' into Nature. Nature and
  /// Hospital are sections in their own right now and carry their own entries.
  static double _radiusForCategory(String category) {
    switch (category) {
      case 'Food & Drink':
      case 'Food':
        return PlaceBands.maxMetresFor('Food & Drink');
      case 'Shopping':
        return PlaceBands.maxMetresFor('Shopping');
      case 'Medical':
        return PlaceBands.maxMetresFor('Medical');
      case 'Hospital':
        return PlaceBands.maxMetresFor('Hospital');
      case 'Nature':
      case 'Beach':
        return PlaceBands.maxMetresFor('Nature');
      default:
        return PlaceBands.maxMetresFor('POI');
    }
  }

  /// The six sections shown by Around You and the Discovery tabs.
  static const List<String> bandedCategories = PlaceBands.sections;

  Future<void> _onFetchBandedPlaces(
    FetchBandedPlaces event,
    Emitter<MapState> emit,
  ) async {
    emit(state.copyWith(
      loadingBandCategories: bandedCategories.toSet(),
      // forceRefresh on this event only ever means "the user picked a
      // genuinely different location" (see living_map_page.dart's
      // _fetchBandedSections call sites — a plain pull-to-refresh never sets
      // it). The old location's sections are wiped here rather than left in
      // place: without this, a category that comes back empty for the new
      // spot keeps showing the previous location's places under the new
      // "0-50km" label — e.g. Trincomalee hospitals 2,000km away still
      // listed under a Penang search.
      bandedPlaces: event.forceRefresh ? const {} : state.bandedPlaces,
    ));

    // All six in parallel: they hit independent cache keys on the backend and
    // one slow category should not hold up the other five. Each closure emits
    // its own result the moment it lands, rather than the batch waiting for
    // Future.wait to resolve every one of them — so five fast categories show
    // up immediately instead of sitting behind the slowest straggler.
    await Future.wait(
      bandedCategories.map((cat) async {
        final result = await GooglePlacesService.fetchBandedPlaces(
          latitude: event.latitude,
          longitude: event.longitude,
          categoryName: cat,
          forceRefresh: event.forceRefresh,
          // Fetch Discovery-depth once; Around You slices its quota off the top.
          perBand: PlaceBands.fetchPerBand,
        );

        // A category that returned nothing keeps whatever it had rather than
        // blanking the section — a transient failure should not empty the UI.
        final merged = Map<String, List<List<AttractionEntity>>>.from(
          state.bandedPlaces,
        );
        if (result.bands.isNotEmpty) merged[cat] = result.bands;

        final stillLoading = Set<String>.from(state.loadingBandCategories)
          ..remove(cat);

        emit(state.copyWith(
          bandedPlaces: merged,
          loadingBandCategories: stillLoading,
        ));

        if (!result.pending) return;

        // The near band was fast enough to answer with, but the farther bands
        // came up short and are being filled in the background on the server.
        // One best-effort catch-up, not a poll loop: by the time this fires,
        // the background fill has almost always already landed and refreshed
        // the server's own cache, so this re-fetch is a cheap read rather than
        // a new Google call.
        await Future.delayed(const Duration(seconds: 9));

        // Skip the catch-up if the user has since moved somewhere else —
        // otherwise a stale delayed result could overwrite a newer location's
        // data for the same category key.
        final lastLat = CacheService.getLastFetchLat();
        final lastLng = CacheService.getLastFetchLng();
        if (lastLat != null && lastLng != null) {
          final movedM = geo.Geolocator.distanceBetween(
            event.latitude, event.longitude, lastLat, lastLng,
          );
          if (movedM > 1000) return;
        }

        final catchUp = await GooglePlacesService.fetchBandedPlaces(
          latitude: event.latitude,
          longitude: event.longitude,
          categoryName: cat,
          perBand: PlaceBands.fetchPerBand,
        );
        if (catchUp.bands.isNotEmpty) {
          final mergedAgain = Map<String, List<List<AttractionEntity>>>.from(
            state.bandedPlaces,
          );
          mergedAgain[cat] = catchUp.bands;
          emit(state.copyWith(bandedPlaces: mergedAgain));
        }
      }),
    );
  }

  Future<void> _onFetchNearbyAttractions(
    FetchNearbyAttractions event,
    Emitter<MapState> emit,
  ) async {
    // If we don't have all categories loaded yet, perform a complete batch fetch first.
    // Check status to prevent infinite loading loops if the API returns an empty list.
    final lastLat = CacheService.getLastFetchLat();
    final lastLng = CacheService.getLastFetchLng();
    // `allAttractions.isEmpty` alone meant "we hold something" was read as
    // "we are done", so a session that started from a thin cache never went
    // back to the network. Staleness gives it a way out; the write path
    // refreshes the timestamp, so this asks for at most one refetch per TTL.
    bool needsFetch = state.status == MapStatus.initial ||
        state.status == MapStatus.failure ||
        state.allAttractions.isEmpty ||
        !CacheService.isAttractionsCacheFresh();

    // The local cache has no per-location tagging — it's just "every place
    // ever fetched," and _getFilteredCache only narrows it to within 50km of
    // whatever coordinates are asked for right now. So a genuinely new area
    // that happens to sit within 50km of somewhere visited earlier would show
    // a mix of both places instead of just the new area's, unless the stale
    // entries are cleared out when a real relocation is detected.
    bool movedToNewArea = false;

    if (lastLat != null && lastLng != null) {
      final double distM = geo.Geolocator.distanceBetween(
        event.latitude,
        event.longitude,
        lastLat,
        lastLng,
      );
      if (distM > 1000) {
        needsFetch = true;
        movedToNewArea = true;
      }
    }

    if (needsFetch || event.forceRefresh) {
      if (movedToNewArea) {
        await CacheService.cacheAttractions(const []);
      }

      if (lastLat != null && lastLng != null && !event.forceRefresh) {
        final double distM = geo.Geolocator.distanceBetween(
          event.latitude,
          event.longitude,
          lastLat,
          lastLng,
        );
        // Freshness matters as much as proximity here. Standing still is not a
        // reason to keep serving a list captured hours ago — and because this
        // branch returns without touching the network, a thin capture used to
        // persist for as long as the user stayed within 1km.
        if (distM < 1000 && CacheService.isAttractionsCacheFresh()) {
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

      // Feeds the map and its markers, so it stays broader than the six
      // sections: 'Attractions' still carries most of the older rows, and
      // 'Hospital' has to be asked for by name now that Medical's type list no
      // longer includes hospitals.
      final categoriesToFetch = [
        'POI',
        'Attractions',
        'Food & Drink',
        'Shopping',
        'Medical',
        'Hospital',
        'Nature',
      ];

      final Map<String, AttractionEntity> uniqueAttractions = {};
      // Phase A's raw per-category dedup map, carried into Phase B so a
      // category that needs enriching resumes from exactly what Phase A had —
      // not a second, disconnected merge.
      final Map<String, Map<String, AttractionEntity>> categoryMergedMaps = {};
      // Categories whose fast (database) layer alone came up short — same
      // `< 15` threshold the single-phase code always used to decide whether
      // to escalate to Google. These get a background enrichment pass in
      // Phase B instead of making everyone wait for them up front.
      final Set<String> categoriesNeedingEnrichment = {};

      // Writes whatever was newly fetched THIS landing to the local cache
      // (merge-safe — see CacheService.mergeAndCacheAttractions), then reloads
      // the full merged cache and emits it. Called once after Phase A (fast)
      // and again, independently, after each Phase B category that needed
      // enrichment lands — so five fast categories are never held up by a
      // sixth slow one.
      Future<void> persistAndEmit(
        List<AttractionEntity> newlyFetched, {
        required Set<String> enriching,
      }) async {
        if (newlyFetched.isNotEmpty) {
          final jsons = newlyFetched.map((a) => _attractionEntityToJson(a)).toList();
          await CacheService.mergeAndCacheAttractions(jsons);
        }
        final mergedModels = _getFilteredCache(event.latitude, event.longitude);
        final filteredAttractions = (event.categoryName != null && event.categoryName != 'All')
            ? mergedModels.where((a) => _matchesCategory(a, event.categoryName)).toList()
            : mergedModels;
        emit(state.copyWith(
          status: MapStatus.success,
          attractions: filteredAttractions,
          allAttractions: mergedModels,
          selectedCategoryId: event.categoryId,
          enrichingCategories: enriching,
        ));
      }

      try {
        // ── PHASE A — fast layer only, all 7 categories in parallel ────────
        // Just the database/cache step (plus its useLegacy retry) that used to
        // be "step 1" of a 4-step chain. No Google calls here, so this is
        // quick even on a cold location — the map/Around You/Discover paint
        // with whatever the database already has while Phase B (below)
        // quietly enriches whichever categories came up short.
        final phaseAFutures = categoriesToFetch.map((cat) async {
          final targetCategories = ['POI', 'Food & Drink', 'Food', 'Attractions', 'Medical', 'Shopping', 'Hospital', 'Nature'];

          if (targetCategories.contains(cat)) {
            // --- LAYER 1: Backend Database & Cache (Primary — 0 AI cost on hit) ---
            // Radius comes from the band table so the map fetch and the section
            // fetch agree on how far each category reaches. Food & Drink used to
            // be queried at 15 km and then filtered to 12 in the UI, neither of
            // which matched its actual 5 km range.
            final double radius = _radiusForCategory(cat);
            var repoRes = await _repository.getNearbyAttractions(
              latitude: event.latitude,
              longitude: event.longitude,
              radius: radius,
              categoryName: cat,
              useLegacy: event.useLegacy,
            );
            var repoList = repoRes.fold((_) => <AttractionEntity>[], (r) => r);

            if (repoList.isEmpty && !event.useLegacy) {
              repoRes = await _repository.getNearbyAttractions(
                latitude: event.latitude,
                longitude: event.longitude,
                radius: radius,
                categoryName: cat,
                useLegacy: true,
              );
              repoList = repoRes.fold((_) => <AttractionEntity>[], (r) => r);
            }

            final Map<String, AttractionEntity> mergedMap = {};
            void addPlaceToMerged(AttractionEntity p) {
              final normName = p.name.trim().toLowerCase();
              final placeId = p.id.trim();
              String targetKey = normName.isNotEmpty ? normName : placeId;
              for (final existingKey in mergedMap.keys) {
                final item = mergedMap[existingKey]!;
                if ((normName.isNotEmpty && item.name.trim().toLowerCase() == normName) ||
                    (placeId.isNotEmpty && item.id.trim() == placeId)) {
                  targetKey = existingKey;
                  break;
                }
              }
              mergedMap[targetKey] = p;
            }
            for (final p in repoList) {
              addPlaceToMerged(p);
            }
            categoryMergedMaps[cat] = mergedMap;

            // Matches the original "< 15" escalation threshold exactly — this
            // is what used to gate Layer 2 inline; now it gates Phase B.
            final needsEnrichment = repoList.length < 15;
            if (needsEnrichment) categoriesNeedingEnrichment.add(cat);

            // Same value the single-phase code showed when Layer 1 alone was
            // already enough (raw repoList); otherwise the deduped map — Phase
            // B builds further enrichment on top of this same mergedMap.
            var mergedList = needsEnrichment ? mergedMap.values.toList() : repoList;

            if (cat == 'Nature' && mergedList.isNotEmpty) {
              mergedList = mergedList.where((p) => _isValidPlace(p.name, cat)).toList();
            }

            return mergedList.isNotEmpty ? mergedList : <AttractionEntity>[];
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

        final phaseAResults = await Future.wait(phaseAFutures);

        for (final list in phaseAResults) {
          for (final a in list) {
            // Use a composite key of name + categoryName so that the same physical
            // place fetched under different categories is stored separately, each
            // retaining its correct categoryName. Previously using only a.name
            // caused the last-written category to overwrite earlier ones, which
            // was the root cause of non-hospital places appearing in the Hospital tab.
            final dedupeKey = '${a.name.trim().toLowerCase()}__${(a.categoryName ?? '').toLowerCase()}';
            uniqueAttractions[dedupeKey] = a;
          }
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

        // Only a genuine dead end — nothing fetched AND nothing left to try in
        // Phase B — falls back to cache. Checking this against Phase A alone
        // (without categoriesNeedingEnrichment) would wrongly short-circuit a
        // brand-new location before Phase B ever gets a chance to run, which
        // is exactly the case this whole restructuring is for.
        if (attractionsList.isEmpty && categoriesNeedingEnrichment.isEmpty) {
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
        await CacheService.saveLastFetchCoords(event.latitude, event.longitude);
        await persistAndEmit(attractionsList, enriching: categoriesNeedingEnrichment);

        if (categoriesNeedingEnrichment.isEmpty) return;

        // ── PHASE B — background enrichment, one closure per short category ─
        // Same Google-fallback chain the single-phase code always ran for a
        // category under 15 results — just no longer blocking Phase A's emit.
        // Each closure emits for itself the moment it lands, mirroring
        // _onFetchBandedPlaces above.
        await Future.wait(categoriesNeedingEnrichment.map((cat) async {
          try {
            final mergedMap = categoryMergedMaps[cat]!;
            void addPlaceToMerged(AttractionEntity p) {
              final normName = p.name.trim().toLowerCase();
              final placeId = p.id.trim();
              String targetKey = normName.isNotEmpty ? normName : placeId;
              for (final existingKey in mergedMap.keys) {
                final item = mergedMap[existingKey]!;
                if ((normName.isNotEmpty && item.name.trim().toLowerCase() == normName) ||
                    (placeId.isNotEmpty && item.id.trim() == placeId)) {
                  targetKey = existingKey;
                  break;
                }
              }
              mergedMap[targetKey] = p;
            }

            var mergedList = mergedMap.values.toList();

            // POI was missing from this list, so its Google fallback searched
            // 15 km while the primary query searched 50 — the outer band had
            // nothing to draw on whenever the fallback was the path taken.
            final discoveryRadius = _radiusForCategory(cat).round();
            final discoveryCategory = cat == 'Attractions' ? 'Experiences' : (cat == 'Food' ? 'Food & Drink' : cat);

            // Fallback 1: Backend-cached Google Places (fetchNearbyPlaces)
            try {
              print('🔄 Primary method returned only ${mergedList.length} results for $cat. Falling back to fetchNearbyPlaces...');
              final discoveryFallback = await GooglePlacesService.fetchNearbyPlaces(
                latitude: event.latitude,
                longitude: event.longitude,
                categoryName: discoveryCategory,
                radius: discoveryRadius,
              );
              for (final p in discoveryFallback) {
                // Force category name match for UI
                final correctedP = AttractionModel(
                  id: p.id, name: p.name, description: p.description, history: p.history,
                  latitude: p.latitude, longitude: p.longitude, categoryId: p.categoryId,
                  categoryName: cat, address: p.address, openingHours: p.openingHours,
                  entryFee: p.entryFee, currency: p.currency, rating: p.rating, reviewCount: p.reviewCount,
                  photoUrls: p.photoUrls, tags: p.tags, geofenceRadiusM: p.geofenceRadiusM,
                  distanceM: p.distanceM, isActive: p.isActive, createdAt: p.createdAt,
                );
                addPlaceToMerged(correctedP);
              }
              mergedList = mergedMap.values.toList();
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
                  categoryName: discoveryCategory,
                  radius: discoveryRadius,
                );
                for (final p in legacyFallback) {
                  final correctedP = AttractionModel(
                    id: p.id, name: p.name, description: p.description, history: p.history,
                    latitude: p.latitude, longitude: p.longitude, categoryId: p.categoryId,
                    categoryName: cat, address: p.address, openingHours: p.openingHours,
                    entryFee: p.entryFee, currency: p.currency, rating: p.rating, reviewCount: p.reviewCount,
                    photoUrls: p.photoUrls, tags: p.tags, geofenceRadiusM: p.geofenceRadiusM,
                    distanceM: p.distanceM, isActive: p.isActive, createdAt: p.createdAt,
                  );
                  addPlaceToMerged(correctedP);
                }
                mergedList = mergedMap.values.toList();
                print('📊 After Google legacy fallback: ${mergedList.length} results for $cat');
              } catch (e) {
                print('⚠️ Google legacy fallback also failed for $cat: $e');
              }
            }

            // Recalculate distances and sort by proximity
            mergedList = mergedList.map((p) {
              final distM = geo.Geolocator.distanceBetween(
                event.latitude, event.longitude,
                p.latitude, p.longitude,
              );
              return AttractionModel(
                id: p.id, name: p.name, description: p.description, history: p.history,
                latitude: p.latitude, longitude: p.longitude, categoryId: p.categoryId,
                categoryName: p.categoryName, address: p.address, openingHours: p.openingHours,
                entryFee: p.entryFee, currency: p.currency, rating: p.rating, reviewCount: p.reviewCount,
                photoUrls: p.photoUrls, tags: p.tags, geofenceRadiusM: p.geofenceRadiusM,
                distanceM: distM, isActive: p.isActive, createdAt: p.createdAt,
              );
            }).toList();
            mergedList.sort((a, b) => (a.distanceM ?? 0).compareTo(b.distanceM ?? 0));
            print('✅ Final: ${mergedList.length} results for $cat (sorted by distance)');

            if (cat == 'Nature' && mergedList.isNotEmpty) {
              mergedList = mergedList.where((p) => _isValidPlace(p.name, cat)).toList();
              print('🛡️ Exclusion Filter applied for Nature: retained ${mergedList.length} places');
            }

            // Skip the emit if the user has since moved to a different area —
            // otherwise a stale late-arriving result could overwrite a newer
            // location's data for this same category.
            final currentLastLat = CacheService.getLastFetchLat();
            final currentLastLng = CacheService.getLastFetchLng();
            if (currentLastLat != null && currentLastLng != null) {
              final movedM = geo.Geolocator.distanceBetween(
                event.latitude, event.longitude, currentLastLat, currentLastLng,
              );
              if (movedM > 1000) return;
            }

            final stillEnriching = Set<String>.from(state.enrichingCategories)..remove(cat);
            await persistAndEmit(mergedList, enriching: stillEnriching);
          } catch (e) {
            // Never let one category's enrichment failure reach the outer
            // catch below — that one is reserved for "the whole fetch
            // failed," and Phase A has already emitted a good state by now.
            print('⚠️ Phase B enrichment crashed for $cat: $e');
          }
        }));
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
