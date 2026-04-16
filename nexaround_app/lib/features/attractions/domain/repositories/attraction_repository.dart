import 'package:dartz/dartz.dart';
import 'package:nexaround_app/core/error/failures.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

abstract class AttractionRepository {
  Future<Either<Failure, List<AttractionEntity>>> getNearbyAttractions({
    required double latitude,
    required double longitude,
    double radius,
    String? categoryId,
    int limit,
    String sort,
  });

  Future<Either<Failure, List<CategoryEntity>>> getCategories();

  Future<Either<Failure, AttractionEntity>> getAttractionDetail(String id);
}
