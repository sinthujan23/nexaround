import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/attractions/domain/repositories/attraction_repository.dart';
import 'package:nexaround_app/core/services/gemini_service.dart';
import 'package:nexaround_app/features/ar_mode/presentation/bloc/ar_event.dart';
import 'package:nexaround_app/features/ar_mode/presentation/bloc/ar_state.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:nexaround_app/core/utils/geo_calculator.dart';

class ArBloc extends Bloc<ArEvent, ArState> {
  final AttractionRepository _repository;
  final GeminiService _geminiService = GeminiService();

  ArBloc(this._repository) : super(const ArState()) {
    on<ArSessionStarted>(_onSessionStarted);
    on<ArSessionStopped>(_onSessionStopped);
    on<ArUpdateLocation>(_onUpdateLocation);
    on<ArSelectAttraction>(_onSelectAttraction);
    on<ArDetectAttraction>(_onDetectAttraction);
    on<ArFetchAIInsight>(_onFetchAIInsight);
    on<ArClearDetection>(_onClearDetection);
    on<ArVisualScan>(_onVisualScan);
    on<ArToggleMappingMode>(_onToggleMappingMode);
    on<ArSubmitDiscovery>(_onSubmitDiscovery);
  }

  Future<void> _onVisualScan(
    ArVisualScan event,
    Emitter<ArState> emit,
  ) async {
    emit(state.copyWith(isScanning: true, clearIdentified: true));

    final result = await _repository.identifyPlace(event.imageBytes);

    result.fold(
      (failure) => emit(state.copyWith(
        isScanning: false,
        errorMessage: failure.message,
      )),
      (identifiedObject) => emit(state.copyWith(
        isScanning: false,
        identifiedObject: identifiedObject,
      )),
    );
  }

  Future<void> _onSessionStarted(
    ArSessionStarted event,
    Emitter<ArState> emit,
  ) async {
    emit(state.copyWith(status: ArStatus.loading));
    emit(state.copyWith(status: ArStatus.success));
  }

  void _onSessionStopped(ArSessionStopped event, Emitter<ArState> emit) {
    emit(const ArState());
  }

  Future<void> _onUpdateLocation(
    ArUpdateLocation event,
    Emitter<ArState> emit,
  ) async {
    final shouldFetch = state.attractions.isEmpty;

    emit(state.copyWith(
      currentLatitude: event.latitude,
      currentLongitude: event.longitude,
      currentHeading: event.heading,
    ));

    List<AttractionEntity> currentAttractions = state.attractions;

    if (shouldFetch) {
      final result = await _repository.getNearbyAttractions(
        latitude: event.latitude,
        longitude: event.longitude,
        radius: 2000.0, // 2km radius for AR
      );

      result.fold(
        (failure) => emit(state.copyWith(errorMessage: failure.message)),
        (attractions) {
          currentAttractions = attractions;
          emit(state.copyWith(attractions: attractions));
        },
      );
    }

    if (currentAttractions.isNotEmpty) {
      AttractionEntity? closest;
      double closestDistance = double.infinity;

      // Hysteresis: use wider angle to clear than to detect, preventing flicker at boundary
      const double detectAngle = 20.0;
      const double clearAngle = 30.0;
      const double maxDistance = 50000.0;
      final bool alreadyDetected = state.detectedAttraction != null;

      for (final attraction in currentAttractions) {
        final bearing = GeoCalculator.bearing(event.latitude, event.longitude, attraction.latitude, attraction.longitude);
        final distance = GeoCalculator.distance(event.latitude, event.longitude, attraction.latitude, attraction.longitude);

        double diff = (bearing - event.heading).abs();
        if (diff > 180) diff = 360 - diff;

        // Use wider angle if this attraction is already detected (hysteresis)
        final threshold = (alreadyDetected && state.detectedAttraction?.id == attraction.id)
            ? clearAngle
            : detectAngle;

        if (diff <= threshold && distance <= maxDistance) {
          if (distance < closestDistance) {
            closest = attraction;
            closestDistance = distance;
          }
        }
      }

      if (closest != null) {
        if (state.detectedAttraction?.id != closest.id || (state.detectedDistance - closestDistance).abs() > 5.0) {
          emit(state.copyWith(
            detectedAttraction: closest,
            detectedDistance: closestDistance,
            clearInsight: state.detectedAttraction?.id != closest.id,
          ));
        }
      } else {
        if (state.detectedAttraction != null) {
          emit(state.copyWith(
            clearDetected: true,
            clearInsight: true,
          ));
        }
      }
    } else {
      if (state.detectedAttraction != null) {
        emit(state.copyWith(
          clearDetected: true,
          clearInsight: true,
        ));
      }
    }
  }

  void _onSelectAttraction(ArSelectAttraction event, Emitter<ArState> emit) {
    emit(state.copyWith(
      selectedAttraction: event.attraction,
      clearInsight: true,
    ));
  }

  void _onDetectAttraction(ArDetectAttraction event, Emitter<ArState> emit) {
    // Only update if we detected a different attraction
    if (state.detectedAttraction?.id != event.attraction.id) {
      emit(state.copyWith(
        detectedAttraction: event.attraction,
        detectedDistance: event.distance,
        clearInsight: true,
      ));
    }
  }

  void _onClearDetection(ArClearDetection event, Emitter<ArState> emit) {
    emit(state.copyWith(
      clearDetected: true,
      clearInsight: true,
    ));
  }

  Future<void> _onFetchAIInsight(
    ArFetchAIInsight event,
    Emitter<ArState> emit,
  ) async {
    emit(state.copyWith(isLoadingInsight: true));

    try {
      final context =
          'Place: ${event.attraction.name}. '
          'Category: ${event.attraction.categoryName ?? "attraction"}. '
          'Address: ${event.attraction.address ?? "unknown"}. '
          'Rating: ${event.attraction.rating}/5 with ${event.attraction.reviewCount} reviews. '
          'Description: ${event.attraction.description ?? "No description available"}.';

          'Description: ${event.attraction.description ?? "No description available"}.';

      final response = await _geminiService.getResponse(
        'Tell me interesting facts and history about ${event.attraction.name}. '
        'Keep it concise (3-4 sentences) and engaging for a tourist visiting right now.',
        context: context,
      );

      emit(state.copyWith(
        aiInsight: response,
        isLoadingInsight: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        aiInsight: event.attraction.description ?? 
            'Discover ${event.attraction.name} — a ${event.attraction.categoryName ?? "popular"} attraction nearby!',
        isLoadingInsight: false,
      ));
    }
  }

  void _onToggleMappingMode(ArToggleMappingMode event, Emitter<ArState> emit) {
    emit(state.copyWith(
      isMappingMode: !state.isMappingMode,
      clearDetected: true,
      clearSelected: true,
    ));
  }

  Future<void> _onSubmitDiscovery(
    ArSubmitDiscovery event,
    Emitter<ArState> emit,
  ) async {
    emit(state.copyWith(isSavingDiscovery: true));

    // For now, simulate saving and add to local list for immediate feedback
    // In a real app, this would call the repository
    await Future.delayed(const Duration(seconds: 2));

    final newAttraction = AttractionEntity(
      id: 'discovery-${DateTime.now().millisecondsSinceEpoch}',
      name: event.name,
      description: event.description,
      latitude: event.latitude,
      longitude: event.longitude,
      rating: 5.0,
      reviewCount: 1,
      photoUrls: [],
      categoryName: event.categoryId,
      createdAt: DateTime.now(),
    );

    emit(state.copyWith(
      isSavingDiscovery: false,
      isMappingMode: false,
      attractions: [newAttraction, ...state.attractions],
    ));
  }
}
