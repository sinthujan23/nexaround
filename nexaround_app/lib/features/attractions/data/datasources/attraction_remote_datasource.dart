import 'package:dio/dio.dart';
import 'package:nexaround_app/core/constants/api_constants.dart';
import 'package:nexaround_app/core/network/api_client.dart';
import 'package:nexaround_app/features/attractions/data/models/attraction_model.dart';

class AttractionRemoteDatasource {
  final Dio _dio = ApiClient.instance;

  Future<List<AttractionModel>> getNearbyAttractions({
    required double latitude,
    required double longitude,
    double radius = 1000.0,
    String? categoryId,
    int limit = 50,
    String sort = 'proximity',
  }) async {
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
