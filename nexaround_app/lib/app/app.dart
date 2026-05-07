import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nexaround_app/app/routes.dart';
import 'package:nexaround_app/app/theme/app_theme.dart';
import 'package:nexaround_app/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:nexaround_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:nexaround_app/features/auth/presentation/bloc/auth_event.dart';
import 'package:nexaround_app/features/budget/data/repositories/budget_repository_impl.dart';
import 'package:nexaround_app/features/budget/presentation/bloc/budget_bloc.dart';
import 'package:nexaround_app/features/budget/presentation/bloc/budget_event.dart';

import 'package:nexaround_app/features/ar_mode/presentation/bloc/ar_bloc.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_bloc.dart';
import 'package:nexaround_app/features/attractions/data/repositories/attraction_repository_impl.dart';
import 'package:nexaround_app/features/attractions/data/datasources/attraction_remote_datasource.dart';
import 'package:nexaround_app/features/chat/data/repositories/chat_repository.dart';

class NexAroundApp extends StatelessWidget {
  const NexAroundApp({super.key});

  @override
  Widget build(BuildContext context) {
    // We provide the repositories here to be shared if needed, 
    // or just instantiate them directly in the BlocProvider
    final attractionRepo = AttractionRepositoryImpl(AttractionRemoteDatasource());
    final chatRepo = ChatRepository();

    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc(
            AuthRepositoryImpl(AuthRemoteDatasource()),
          )..add(const AuthCheckStatus()),
        ),
        BlocProvider<BudgetBloc>(
          create: (context) => BudgetBloc(
            BudgetRepositoryImpl(),
          )..add(FetchBudget()),
        ),
        BlocProvider<MapBloc>(
          create: (context) => MapBloc(attractionRepo),
        ),
        BlocProvider<ArBloc>(
          create: (context) => ArBloc(attractionRepo),
        ),
      ],
      child: const AppView(),
    );
  }
}

class AppView extends StatefulWidget {
  const AppView({super.key});

  @override
  State<AppView> createState() => _AppViewState();
}

class _AppViewState extends State<AppView> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = AppRouter.createRouter(context.read<AuthBloc>());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NexAround',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
