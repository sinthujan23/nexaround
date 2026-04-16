import 'package:equatable/equatable.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

enum ArStatus { initial, loading, success, failure }

class ArState extends Equatable {
  final ArStatus status;
  final List<AttractionEntity> attractions;
  final AttractionEntity? selectedAttraction;
  final double currentLatitude;
  final double currentLongitude;
  final double currentHeading;
  final String? errorMessage;

  const ArState({
    this.status = ArStatus.initial,
    this.attractions = const [],
    this.selectedAttraction,
    this.currentLatitude = 0.0,
    this.currentLongitude = 0.0,
    this.currentHeading = 0.0,
    this.errorMessage,
  });

  ArState copyWith({
    ArStatus? status,
    List<AttractionEntity>? attractions,
    AttractionEntity? selectedAttraction,
    double? currentLatitude,
    double? currentLongitude,
    double? currentHeading,
    String? errorMessage,
  }) {
    return ArState(
      status: status ?? this.status,
      attractions: attractions ?? this.attractions,
      selectedAttraction: selectedAttraction ?? this.selectedAttraction,
      currentLatitude: currentLatitude ?? this.currentLatitude,
      currentLongitude: currentLongitude ?? this.currentLongitude,
      currentHeading: currentHeading ?? this.currentHeading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    attractions,
    selectedAttraction,
    currentLatitude,
    currentLongitude,
    currentHeading,
    errorMessage,
  ];
}
