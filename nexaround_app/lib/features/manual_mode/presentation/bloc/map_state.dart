import 'package:equatable/equatable.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

enum MapStatus { initial, loading, success, failure }

class MapState extends Equatable {
  final MapStatus status;
  final List<AttractionEntity> attractions;
  final List<CategoryEntity> categories;
  final String? selectedCategoryId;
  final String? errorMessage;
  final bool isSatellite;

  const MapState({
    this.status = MapStatus.initial,
    this.attractions = const [],
    this.categories = const [],
    this.selectedCategoryId,
    this.errorMessage,
    this.isSatellite = false,
  });

  MapState copyWith({
    MapStatus? status,
    List<AttractionEntity>? attractions,
    List<CategoryEntity>? categories,
    String? selectedCategoryId,
    String? errorMessage,
    bool? isSatellite,
  }) {
    return MapState(
      status: status ?? this.status,
      attractions: attractions ?? this.attractions,
      categories: categories ?? this.categories,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      errorMessage: errorMessage ?? this.errorMessage,
      isSatellite: isSatellite ?? this.isSatellite,
    );
  }

  @override
  List<Object?> get props => [
    status, 
    attractions, 
    categories, 
    selectedCategoryId, 
    errorMessage,
    isSatellite
  ];
}
