import 'package:dio/dio.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/features/itinerary/domain/entities/itinerary.dart';

class ItineraryRepository {
  final Dio _dio = ApiClient.instance;

  Future<List<Itinerary>> getMyItineraries() async {
    final response = await _dio.get(ApiConstants.itineraries);
    
    return (response.data as List).map((json) => Itinerary(
      id: json['id'],
      title: json['title'],
      tripDate: json['trip_date'] != null ? DateTime.parse(json['trip_date']) : null,
      status: json['status'],
      items: (json['items'] as List).map((i) => ItineraryItem(
        attractionId: i['attraction_id'],
        time: i['time'],
        note: i['note'],
      )).toList(),
    )).toList();
  }

  Future<Itinerary> createItinerary(String title, {DateTime? date}) async {
    final response = await _dio.post(
      ApiConstants.itineraries,
      data: {
        'title': title,
        'trip_date': date?.toIso8601String().split('T')[0],
        'items': [],
        'status': 'draft',
      },
    );

    final json = response.data;
    return Itinerary(
      id: json['id'],
      title: json['title'],
      tripDate: json['trip_date'] != null ? DateTime.parse(json['trip_date']) : null,
      status: json['status'],
      items: [],
    );
  }

  Future<void> addItemToItinerary(String itineraryId, ItineraryItem item, List<ItineraryItem> currentItems) async {
    final updatedItems = List<ItineraryItem>.from(currentItems)..add(item);
    
    await _dio.put(
      '${ApiConstants.itineraries}/$itineraryId',
      data: {
        'items': updatedItems.map((i) => i.toJson()).toList(),
      },
    );
  }
}
