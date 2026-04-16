import 'package:flutter/material.dart';
import 'package:nexaround_app/app/routes.dart';
import 'package:nexaround_app/app/theme/app_theme.dart';

class NexAroundApp extends StatelessWidget {
  const NexAroundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NexAround',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: AppRouter.router,
      debugShowCheckedModeBanner: false,
    );
  }
}
