import 'package:equatable/equatable.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

abstract class ArEvent extends Equatable {
  const ArEvent();

  @override
  List<Object?> get props => [];
}

class ArSessionStarted extends ArEvent {}

class ArSessionStopped extends ArEvent {}

class ArUpdateLocation extends ArEvent {
  final double latitude;
  final double longitude;
  final double heading;

  const ArUpdateLocation({
    required this.latitude,
    required this.longitude,
    required this.heading,
  });

  @override
  List<Object?> get props => [latitude, longitude, heading];
}

class ArSelectAttraction extends ArEvent {
  final AttractionEntity? attraction;
  const ArSelectAttraction(this.attraction);

  @override
  List<Object?> get props => [attraction];
}

/// Fired when the compass heading matches a nearby attraction's bearing
class ArDetectAttraction extends ArEvent {
  final AttractionEntity attraction;
  final double distance;
  const ArDetectAttraction(this.attraction, this.distance);

  @override
  List<Object?> get props => [attraction, distance];
}

/// Fired to fetch AI insight about a detected/selected attraction
class ArFetchAIInsight extends ArEvent {
  final AttractionEntity attraction;
  const ArFetchAIInsight(this.attraction);

  @override
  List<Object?> get props => [attraction];
}

/// Clear the detected attraction (user moved phone away)
class ArClearDetection extends ArEvent {}

/// Fired when user captures a camera frame for AI evaluation
class ArVisualScan extends ArEvent {
  final List<int> imageBytes;
  const ArVisualScan(this.imageBytes);

  @override
  List<Object?> get props => [imageBytes];
}
