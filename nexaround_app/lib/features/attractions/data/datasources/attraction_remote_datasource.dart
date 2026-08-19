import 'package:dio/dio.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';
import 'package:nexaround_app/core/services/google_places_service.dart';

class AttractionRemoteDatasource {
  final Dio _dio = ApiClient.instance;

  Future<List<AttractionModel>> getNearbyAttractions({
    required double latitude,
    required double longitude,
    double radius = 1000.0,
    String? categoryId,
    String? categoryName,
    int limit = 50,
    String sort = 'proximity',
    bool useLegacy = false,
  }) async {
    // If categoryName is provided directly, use it. Otherwise fallback to heuristic.
    String? resolvedCategoryName = categoryName;
    if (resolvedCategoryName == null && categoryId != null) {
      if (categoryId.contains('1')) resolvedCategoryName = 'POI';
      else if (categoryId.contains('2')) resolvedCategoryName = 'Food & Drink';
      else if (categoryId.contains('3')) resolvedCategoryName = 'Hotels';
      else if (categoryId.contains('4')) resolvedCategoryName = 'Shopping';
      else if (categoryId.contains('5')) resolvedCategoryName = 'Experiences';
      else if (categoryId.contains('6')) resolvedCategoryName = 'Transport';
    }

    try {
      final entities = await GooglePlacesService.fetchNearbyPlaces(
        latitude: latitude,
        longitude: longitude,
        categoryName: resolvedCategoryName,
        radius: radius.toInt(),
        useLegacy: useLegacy,
      );
      
      final models = entities.map((e) => e as AttractionModel).toList();
      print('Fetched ${models.length} places from Google');
      
      if (models.isNotEmpty) {
        return models;
      }
    } catch (e) {
      print('Error in getNearbyAttractions: $e');
    }

    // Fallback to backend API if Google Places fails (e.g., billing not enabled)
    print('Falling back to backend data...');
    final response = await _dio.get(
      ApiConstants.attractionsNearby,
      queryParameters: {
        'lat': latitude,
        'lng': longitude,
        'radius': radius,
        if (categoryId != null) 'category_id': categoryId,
        'limit': limit,
        'sort': sort,
      },
    );
    
    final List<dynamic> data = response.data;
    return data.map((json) => AttractionModel.fromJson(json)).toList();
  }

  Future<List<CategoryModel>> getCategories() async {
    final response = await _dio.get(ApiConstants.categories);
    final List<dynamic> data = response.data;
    return data.map((json) => CategoryModel.fromJson(json)).toList();
  }

  Future<AttractionModel> getAttractionDetail(String id) async {
    final response = await _dio.get('${ApiConstants.apiVersion}/attractions/$id');
    return AttractionModel.fromJson(response.data);
  }

  Future<Map<String, dynamic>> identifyPlace(List<int> imageBytes) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        imageBytes,
        filename: 'scan.jpg',
      ),
    });

    final response = await _dio.post(
      '${ApiConstants.apiVersion}/ar/identify',
      data: formData,
    );
    
    return response.data;
  }
}
