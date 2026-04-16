import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexaround_app/app/theme/app_theme.dart';
import 'package:nexaround_app/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:nexaround_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_event.dart';
import 'package:nexaround_app/features/attractions/data/datasources/attraction_remote_datasource.dart';
import 'package:nexaround_app/features/attractions/data/repositories/attraction_repository_impl.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_bloc.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_event.dart';
import 'package:nexaround_app/features/ar_mode/presentation/bloc/ar_bloc.dart';
import 'package:nexaround_app/features/chat/data/repositories/chat_repository.dart';
import 'package:nexaround_app/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:nexaround_app/features/itinerary/data/repositories/itinerary_repository.dart';
import 'package:nexaround_app/features/itinerary/presentation/bloc/itinerary_bloc.dart';
import 'package:nexaround_app/features/attractions/data/repositories/review_repository_impl.dart';
import 'package:nexaround_app/features/attractions/presentation/bloc/review_bloc.dart';
import 'package:nexaround_app/features/onboarding/presentation/pages/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Create dependencies
  final authRemoteDatasource = AuthRemoteDatasource();
  final authRepository = AuthRepositoryImpl(authRemoteDatasource);

  final attractionRemoteDatasource = AttractionRemoteDatasource();
  final attractionRepository =
      AttractionRepositoryImpl(attractionRemoteDatasource);
  final chatRepository = ChatRepository();
  final itineraryRepository = ItineraryRepository();
  final reviewRepository = ReviewRepository();

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => AuthBloc(authRepository)..add(const AuthCheckStatus()),
        ),
        BlocProvider(
          create: (_) => MapBloc(attractionRepository)..add(FetchCategories()),
        ),
        BlocProvider(
          create: (_) => ArBloc(attractionRepository),
        ),
        BlocProvider(
          create: (_) => ChatBloc(chatRepository),
        ),
        BlocProvider(
          create: (_) => ItineraryBloc(itineraryRepository)..add(FetchItineraries()),
        ),
        BlocProvider(
          create: (_) => ReviewBloc(reviewRepository),
        ),
      ],
      child: const NexAroundApp(),
    ),
  );
}

class NexAroundApp extends StatelessWidget {
  const NexAroundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NexAround',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AnimatedSplashScreen(),
    );
  }
}
