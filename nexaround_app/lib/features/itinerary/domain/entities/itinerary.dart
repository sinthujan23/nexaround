import 'package:equatable/equatable.dart';

class ItineraryItem extends Equatable {
  final String attractionId;
  final String? time;
  final String? note;

  const ItineraryItem({
    required this.attractionId,
    this.time,
    this.note,
  });

  @override
  List<Object?> get props => [attractionId, time, note];

  Map<String, dynamic> toJson() => {
    'attraction_id': attractionId,
    'time': time,
    'note': note,
  };
}

class Itinerary extends Equatable {
  final String id;
  final String title;
  final DateTime? tripDate;
  final List<ItineraryItem> items;
  final String status;

  const Itinerary({
    required this.id,
    required this.title,
    this.tripDate,
    required this.items,
    required this.status,
  });

  @override
  List<Object?> get props => [id, title, tripDate, items, status];
}
