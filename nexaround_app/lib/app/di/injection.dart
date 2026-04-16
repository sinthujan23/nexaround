import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

final getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() async {
  // We'll generate the DI code later using build_runner
  // For now, it's a placeholder
}
