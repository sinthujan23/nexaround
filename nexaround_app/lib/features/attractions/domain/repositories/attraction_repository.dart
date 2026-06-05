import 'package:dartz/dartz.dart';
import 'package:nexaround_app/core/error/failures.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

abstract class AttractionRepository {
  Future<Either<Failure, List<AttractionEntity>>> getNearbyAttractions({
    required double latitude,
    required double longitude,
    double radius,
    String? categoryId,
    String? categoryName,
    int limit,
    String sort,
    bool useLegacy = false,
  });

  Future<Either<Failure, List<CategoryEntity>>> getCategories();

  Future<Either<Failure, AttractionEntity>> getAttractionDetail(String id);

  Future<Either<Failure, Map<String, dynamic>>> identifyPlace(List<int> imageBytes);
}
