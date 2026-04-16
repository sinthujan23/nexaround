import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nexaround_app/features/itinerary/data/repositories/itinerary_repository.dart';
import 'package:nexaround_app/features/itinerary/domain/entities/itinerary.dart';

// Events
abstract class ItineraryEvent extends Equatable {
  const ItineraryEvent();
  @override
  List<Object?> get props => [];
}

class FetchItineraries extends ItineraryEvent {}

class CreateItinerary extends ItineraryEvent {
  final String title;
  final DateTime? date;
  const CreateItinerary(this.title, {this.date});
}

class AddToItinerary extends ItineraryEvent {
  final String itineraryId;
  final ItineraryItem item;
  final List<ItineraryItem> currentItems;
  const AddToItinerary(this.itineraryId, this.item, this.currentItems);
}

// State
class ItineraryState extends Equatable {
  final List<Itinerary> itineraries;
  final bool isLoading;
  final String? errorMessage;

  const ItineraryState({
    this.itineraries = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  ItineraryState copyWith({
    List<Itinerary>? itineraries,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ItineraryState(
      itineraries: itineraries ?? this.itineraries,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [itineraries, isLoading, errorMessage];
}

// Bloc
class ItineraryBloc extends Bloc<ItineraryEvent, ItineraryState> {
  final ItineraryRepository _repository;

  ItineraryBloc(this._repository) : super(const ItineraryState()) {
    on<FetchItineraries>(_onFetchItineraries);
    on<CreateItinerary>(_onCreateItinerary);
    on<AddToItinerary>(_onAddToItinerary);
  }

  Future<void> _onFetchItineraries(FetchItineraries event, Emitter<ItineraryState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final results = await _repository.getMyItineraries();
      emit(state.copyWith(isLoading: false, itineraries: results));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onCreateItinerary(CreateItinerary event, Emitter<ItineraryState> emit) async {
    try {
      await _repository.createItinerary(event.title, date: event.date);
      add(FetchItineraries());
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> _onAddToItinerary(AddToItinerary event, Emitter<ItineraryState> emit) async {
    try {
      await _repository.addItemToItinerary(event.itineraryId, event.item, event.currentItems);
      add(FetchItineraries());
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }
}
