import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/app/theme/app_theme.dart';
import 'package:nexaround_app/features/onboarding/presentation/pages/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force dark status bar for futuristic feel
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF06060A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const NexAroundApp());
}

class NexAroundApp extends StatelessWidget {
  const NexAroundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NexAround – AI Tourism Companion',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AnimatedSplashScreen(),
    );
  }
}
