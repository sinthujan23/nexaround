import 'package:flutter/material.dart';
import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:nexaround_app/features/mini_tour/presentation/pages/mini_tour_game_page.dart';

/// Directly launches the Mini Tour around the user's current GPS location.
/// Discovers famous tourist spots within 2–3 km and builds a mini tour from them.
/// Shared by the home-map "START TOUR" button and the Plans "Mini Tour" card.
Future<void> launchMiniTour(
  BuildContext context, {
  double? lat,
  double? lng,
  String? areaName,
  List<AttractionEntity>? preFetchedPlaces,
}) async {
  if (!context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MiniTourGamePage(
        startLat: lat,
        startLng: lng,
        areaName: areaName,
        preFetchedPlaces: preFetchedPlaces,
      ),
    ),
  );
}
