import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/features/attractions/domain/repositories/attraction_repository.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_event.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_state.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  final AttractionRepository _repository;

  MapBloc(this._repository) : super(const MapState()) {
    on<FetchNearbyAttractions>(_onFetchNearbyAttractions);
    on<FetchCategories>(_onFetchCategories);
    on<UpdateMapType>(_onUpdateMapType);
  }

  Future<void> _onFetchNearbyAttractions(
    FetchNearbyAttractions event,
    Emitter<MapState> emit,
  ) async {
    emit(state.copyWith(status: MapStatus.loading));

    final result = await _repository.getNearbyAttractions(
      latitude: event.latitude,
      longitude: event.longitude,
      radius: event.radius,
      categoryId: event.categoryId,
    );

    result.fold(
      (failure) => emit(state.copyWith(
        status: MapStatus.failure,
        errorMessage: failure.message,
      )),
      (attractions) => emit(state.copyWith(
        status: MapStatus.success,
        attractions: attractions,
        selectedCategoryId: event.categoryId,
      )),
    );
  }

  Future<void> _onFetchCategories(
    FetchCategories event,
    Emitter<MapState> emit,
  ) async {
    final result = await _repository.getCategories();

    result.fold(
      (failure) => null, // Silently fail for categories or handle error
      (categories) => emit(state.copyWith(categories: categories)),
    );
  }

  void _onUpdateMapType(UpdateMapType event, Emitter<MapState> emit) {
    emit(state.copyWith(isSatellite: event.isSatellite));
  }
}
