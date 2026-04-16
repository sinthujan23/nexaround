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

  const FetchNearbyAttractions({
    required this.latitude,
    required this.longitude,
    this.radius = 1000.0,
    this.categoryId,
  });

  @override
  List<Object?> get props => [latitude, longitude, radius, categoryId];
}

class FetchCategories extends MapEvent {}

class UpdateMapType extends MapEvent {
  final bool isSatellite;
  const UpdateMapType(this.isSatellite);

  @override
  List<Object?> get props => [isSatellite];
}
