import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:nexaround_app/features/attractions/domain/repositories/attraction_repository.dart';
import 'package:nexaround_app/features/attractions/data/repositories/attraction_repository_impl.dart';
import 'package:nexaround_app/features/attractions/data/datasources/attraction_remote_datasource.dart';

final getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() async {
  // Manual registration for now
  if (!getIt.isRegistered<AttractionRemoteDatasource>()) {
    getIt.registerLazySingleton<AttractionRemoteDatasource>(() => AttractionRemoteDatasource());
  }
  if (!getIt.isRegistered<AttractionRepository>()) {
    getIt.registerLazySingleton<AttractionRepository>(() => AttractionRepositoryImpl(getIt<AttractionRemoteDatasource>()));
  }
}
