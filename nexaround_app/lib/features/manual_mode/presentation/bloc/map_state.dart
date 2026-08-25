import 'package:equatable/equatable.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

enum MapStatus { initial, loading, success, failure }

class MapState extends Equatable {
  final MapStatus status;
  final List<AttractionEntity> attractions;
  final List<AttractionEntity> allAttractions;
  final List<CategoryEntity> categories;
  final AttractionEntity? selectedAttraction;
  final String? selectedCategoryId;
  final String? errorMessage;
  final bool isSatellite;

  /// Around You / Discovery sections, keyed by category name. The inner lists
  /// are the three distance bands, in order, each holding up to five places.
  /// Empty until [FetchBandedPlaces] completes; the sections fall back to
  /// grouping [allAttractions] themselves until then.
  final Map<String, List<List<AttractionEntity>>> bandedPlaces;

  /// Category names whose banded fetch is still in flight. A category is
  /// removed from this set the moment its OWN fetch resolves, independent of
  /// the other five — so a card/tab can show its data as soon as it's ready
  /// instead of waiting for the slowest category in the batch.
  final Set<String> loadingBandCategories;

  /// Category names whose base fetch (`FetchNearbyAttractions`) came back thin
  /// from the database and is being enriched from Google in the background. A
  /// category leaves this set the moment its own enrichment lands (or gives
  /// up). Lets a card/tab that's genuinely still filling show its shimmer a
  /// little longer instead of briefly flashing "nothing found" before the
  /// richer result arrives.
  final Set<String> enrichingCategories;

  const MapState({
    this.status = MapStatus.initial,
    this.attractions = const [],
    this.allAttractions = const [],
    this.categories = const [],
    this.selectedAttraction,
    this.selectedCategoryId,
    this.errorMessage,
    this.isSatellite = false,
    this.bandedPlaces = const {},
    this.loadingBandCategories = const {},
    this.enrichingCategories = const {},
  });

  MapState copyWith({
    MapStatus? status,
    List<AttractionEntity>? attractions,
    List<AttractionEntity>? allAttractions,
    List<CategoryEntity>? categories,
    AttractionEntity? selectedAttraction,
    String? selectedCategoryId,
    String? errorMessage,
    bool? isSatellite,
    Map<String, List<List<AttractionEntity>>>? bandedPlaces,
    Set<String>? loadingBandCategories,
    Set<String>? enrichingCategories,
  }) {
    return MapState(
      status: status ?? this.status,
      attractions: attractions ?? this.attractions,
      allAttractions: allAttractions ?? this.allAttractions,
      categories: categories ?? this.categories,
      selectedAttraction: selectedAttraction ?? this.selectedAttraction,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      errorMessage: errorMessage ?? this.errorMessage,
      isSatellite: isSatellite ?? this.isSatellite,
      bandedPlaces: bandedPlaces ?? this.bandedPlaces,
      loadingBandCategories: loadingBandCategories ?? this.loadingBandCategories,
      enrichingCategories: enrichingCategories ?? this.enrichingCategories,
    );
  }

  @override
  List<Object?> get props => [
    status,
    attractions,
    allAttractions,
    categories,
    selectedAttraction,
    selectedCategoryId,
    errorMessage,
    isSatellite,
    bandedPlaces,
    loadingBandCategories,
    enrichingCategories,
  ];
}
