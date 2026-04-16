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
