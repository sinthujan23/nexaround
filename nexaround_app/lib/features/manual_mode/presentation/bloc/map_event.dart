import 'package:equatable/equatable.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

abstract class MapEvent extends Equatable {
  const MapEvent();

  @override
  List<Object?> get props => [];
}

class FetchNearbyAttractions extends MapEvent {
  final double latitude;
  final double longitude;
  final double radius;
  final String? categoryId;
  final String? categoryName;
  final bool useLegacy;
  final bool forceRefresh;

  const FetchNearbyAttractions({
    required this.latitude,
    required this.longitude,
    this.radius = 50000.0,
    this.categoryId,
    this.categoryName,
    this.useLegacy = false,
    this.forceRefresh = false,
  });

  @override
  List<Object?> get props => [latitude, longitude, radius, categoryId, categoryName, useLegacy, forceRefresh];
}

/// Load the six Around You / Discovery sections, each already split into
/// three distance bands by the backend.
///
/// Separate from [FetchNearbyAttractions] on purpose: that one feeds the map
/// and its markers, which want everything nearby. The sections want places
/// spread deliberately across distance, which is a different query and
/// a different cost profile.
class FetchBandedPlaces extends MapEvent {
  final double latitude;
  final double longitude;
  final bool forceRefresh;

  /// Which sections to fetch, or null for all six.
  ///
  /// Opening the screen used to fetch all six at once, and each one costs up to
  /// three Google calls on a cold tile — most of them for cards the user has
  /// not scrolled to yet. The map now asks for the two above the fold and
  /// requests the rest as they come into view.
  final List<String>? categories;

  const FetchBandedPlaces({
    required this.latitude,
    required this.longitude,
    this.forceRefresh = false,
    this.categories,
  });

  @override
  List<Object?> get props => [latitude, longitude, forceRefresh, categories];
}

class FetchCategories extends MapEvent {
  const FetchCategories();
}

class UpdateMapType extends MapEvent {
  final bool isSatellite;
  const UpdateMapType(this.isSatellite);

  @override
  List<Object?> get props => [isSatellite];
}

class SelectAttraction extends MapEvent {
  final AttractionEntity? attraction;
  const SelectAttraction(this.attraction);

  @override
  List<Object?> get props => [attraction];
}

class SearchAttractions extends MapEvent {
  final String query;
  const SearchAttractions(this.query);

  @override
  List<Object?> get props => [query];
}
