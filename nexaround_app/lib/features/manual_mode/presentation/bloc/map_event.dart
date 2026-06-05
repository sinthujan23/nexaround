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

  const FetchNearbyAttractions({
    required this.latitude,
    required this.longitude,
    this.radius = 50000.0,
    this.categoryId,
    this.categoryName,
    this.useLegacy = false,
  });

  @override
  List<Object?> get props => [latitude, longitude, radius, categoryId, categoryName, useLegacy];
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
