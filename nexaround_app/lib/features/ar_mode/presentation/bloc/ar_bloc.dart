import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/attractions/domain/repositories/attraction_repository.dart';
import 'package:nexaround_app/features/ar_mode/presentation/bloc/ar_event.dart';
import 'package:nexaround_app/features/ar_mode/presentation/bloc/ar_state.dart';

class ArBloc extends Bloc<ArEvent, ArState> {
  final AttractionRepository _repository;

  ArBloc(this._repository) : super(const ArState()) {
    on<ArSessionStarted>(_onSessionStarted);
    on<ArSessionStopped>(_onSessionStopped);
    on<ArUpdateLocation>(_onUpdateLocation);
    on<ArSelectAttraction>(_onSelectAttraction);
  }

  Future<void> _onSessionStarted(
    ArSessionStarted event,
    Emitter<ArState> emit,
  ) async {
    emit(state.copyWith(status: ArStatus.loading));
    
    // Initial fetch of attractions will happen when location is updated
    emit(state.copyWith(status: ArStatus.success));
  }

  void _onSessionStopped(ArSessionStopped event, Emitter<ArState> emit) {
    emit(const ArState());
  }

  Future<void> _onUpdateLocation(
    ArUpdateLocation event,
    Emitter<ArState> emit,
  ) async {
    // Only fetch if moved significantly or if attractions list is empty
    final shouldFetch = state.attractions.isEmpty; 
    
    emit(state.copyWith(
      currentLatitude: event.latitude,
      currentLongitude: event.longitude,
      currentHeading: event.heading,
    ));

    if (shouldFetch) {
      final result = await _repository.getNearbyAttractions(
        latitude: event.latitude,
        longitude: event.longitude,
        radius: 2000.0, // 2km radius for AR
      );

      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message)),
        (attractions) => emit(state.copyWith(attractions: attractions)),
      );
    }
  }

  void _onSelectAttraction(ArSelectAttraction event, Emitter<ArState> emit) {
    emit(state.copyWith(selectedAttraction: event.attraction));
  }
}
