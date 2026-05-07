import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexaround_app/app/app.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/app/di/injection.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize DI
  await configureDependencies();

  // Initialize Cache Service
  await CacheService.init();

  // Initialize Mapbox
  MapboxOptions.setAccessToken("pk.eyJ1IjoiaGFzaG5hdGUiLCJhIjoiY21vaWpmd2o5MDNiejJ2cThwZDl5cGI2diJ9.Zat9TI_nSBO6iwTF2_JtQQ");

  // Force dark status bar for futuristic feel
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF06060A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const NexAroundApp());
}
