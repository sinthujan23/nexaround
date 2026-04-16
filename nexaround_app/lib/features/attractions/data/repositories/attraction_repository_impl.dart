import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nexaround_app/core/error/failures.dart';
import 'package:nexaround_app/features/attractions/data/datasources/attraction_remote_datasource.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:nexaround_app/features/attractions/domain/repositories/attraction_repository.dart';

class AttractionRepositoryImpl implements AttractionRepository {
  final AttractionRemoteDatasource _remoteDatasource;

  AttractionRepositoryImpl(this._remoteDatasource);

  @override
  Future<Either<Failure, List<AttractionEntity>>> getNearbyAttractions({
    required double latitude,
    required double longitude,
    double radius = 1000.0,
    String? categoryId,
    int limit = 50,
    String sort = 'proximity',
  }) async {
    try {
      final results = await _remoteDatasource.getNearbyAttractions(
        latitude: latitude,
        longitude: longitude,
        radius: radius,
        categoryId: categoryId,
        limit: limit,
        sort: sort,
      );
      return Right(results);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<CategoryEntity>>> getCategories() async {
    try {
      final results = await _remoteDatasource.getCategories();
      return Right(results);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, AttractionEntity>> getAttractionDetail(String id) async {
    try {
      final result = await _remoteDatasource.getAttractionDetail(id);
      return Right(result);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Failure _handleDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const NetworkFailure('Connection timed out');
    }
    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      final detail = e.response!.data is Map ? e.response!.data['detail'] : null;
      return ServerFailure(detail ?? 'Server error ($statusCode)');
    }
    return const NetworkFailure('No internet connection');
  }
}
