import 'package:equatable/equatable.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

enum ArStatus { initial, loading, success, failure }

class ArState extends Equatable {
  final ArStatus status;
  final List<AttractionEntity> attractions;
  final AttractionEntity? selectedAttraction;
  final AttractionEntity? detectedAttraction;
  final double detectedDistance;
  final String? aiInsight;
  final bool isLoadingInsight;
  final double currentLatitude;
  final double currentLongitude;
  final double currentHeading;
  final Map<String, dynamic>? identifiedObject;
  final bool isScanning;
  final String? errorMessage;

  const ArState({
    this.status = ArStatus.initial,
    this.attractions = const [],
    this.selectedAttraction,
    this.detectedAttraction,
    this.detectedDistance = 0.0,
    this.aiInsight,
    this.isLoadingInsight = false,
    this.identifiedObject,
    this.isScanning = false,
    this.currentLatitude = 0.0,
    this.currentLongitude = 0.0,
    this.currentHeading = 0.0,
    this.errorMessage,
  });

  ArState copyWith({
    ArStatus? status,
    List<AttractionEntity>? attractions,
    AttractionEntity? selectedAttraction,
    AttractionEntity? detectedAttraction,
    double? detectedDistance,
    String? aiInsight,
    bool? isLoadingInsight,
    Map<String, dynamic>? identifiedObject,
    bool? isScanning,
    double? currentLatitude,
    double? currentLongitude,
    double? currentHeading,
    String? errorMessage,
    bool clearDetected = false,
    bool clearSelected = false,
    bool clearInsight = false,
    bool clearIdentified = false,
  }) {
    return ArState(
      status: status ?? this.status,
      attractions: attractions ?? this.attractions,
      selectedAttraction: clearSelected ? null : (selectedAttraction ?? this.selectedAttraction),
      detectedAttraction: clearDetected ? null : (detectedAttraction ?? this.detectedAttraction),
      detectedDistance: detectedDistance ?? this.detectedDistance,
      aiInsight: clearInsight ? null : (aiInsight ?? this.aiInsight),
      isLoadingInsight: isLoadingInsight ?? this.isLoadingInsight,
      identifiedObject: clearIdentified ? null : (identifiedObject ?? this.identifiedObject),
      isScanning: isScanning ?? this.isScanning,
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
    detectedAttraction,
    detectedDistance,
    aiInsight,
    isLoadingInsight,
    identifiedObject,
    isScanning,
    currentLatitude,
    currentLongitude,
    currentHeading,
    errorMessage,
  ];
}
