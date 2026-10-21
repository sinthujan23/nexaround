import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:nexaround_app/app/theme/app_colors.dart';
import 'package:nexaround_app/core/error/user_message.dart';
import 'package:nexaround_app/core/services/cache_service.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_api.dart';
import 'package:nexaround_app/features/vendor_portal/data/vendor_portal_models.dart';

import '../vendor_ui.dart';

/// Search a place (Google, through the partner API) or tap the map to put the
/// pin. [onPick] gets the pin, plus the place's address when one was chosen
/// from the search.
class PlacePicker extends StatefulWidget {
  final VendorPortalApi api;
  final double? latitude;
  final double? longitude;
  final void Function(double lat, double lng, VendorPlace? place) onPick;

  const PlacePicker({
    super.key,
    required this.api,
    required this.latitude,
    required this.longitude,
    required this.onPick,
  });

  @override
  State<PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<PlacePicker> {
  final _search = TextEditingController();
  final _map = MapController();
  Timer? _debounce;
  List<VendorPlace> _results = [];
  bool _searching = false;

  LatLng? get _pin => widget.latitude == null || widget.longitude == null
      ? null
      : LatLng(widget.latitude!, widget.longitude!);

  /// Where the app last was, if it knows.
  LatLng? get _lastSeen {
    final lat = CacheService.getLastFetchLat();
    final lng = CacheService.getLastFetchLng();
    return lat == null || lng == null ? null : LatLng(lat, lng);
  }

  /// Where the search looks first: the pin, else where the app last was,
  /// else nowhere in particular.
  LatLng get _bias => _pin ?? _lastSeen ?? const LatLng(20, 0);

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searching = true);
      try {
        final found = await widget.api.searchPlaces(q.trim(), _bias.latitude, _bias.longitude);
        if (mounted) setState(() => _results = found);
      } catch (e) {
        if (mounted) showVendorSnack(context, userMessageFor(e, action: 'search'), error: true);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _choose(VendorPlace place) {
    FocusScope.of(context).unfocus();
    setState(() => _results = []);
    _search.text = place.name ?? place.address ?? '';
    widget.onPick(place.latitude, place.longitude, place);
    _map.move(LatLng(place.latitude, place.longitude), 15);
  }

  @override
  Widget build(BuildContext context) {
    final pin = _pin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          onChanged: _onQuery,
          textInputAction: TextInputAction.search,
          decoration: vendorInput(
            'Search a place',
            hint: 'Pigeon Island, Nilaveli',
            suffix: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : const Icon(Icons.search_rounded),
          ),
        ),
        for (final place in _results.take(5))
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.place_outlined, color: AppColors.brandGreen),
            title: Text(place.name ?? place.address ?? ''),
            subtitle: place.address == null ? null : Text(place.address!, maxLines: 2),
            onTap: () => _choose(place),
          ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 200,
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _bias,
                initialZoom: pin != null ? 15 : (_lastSeen != null ? 10 : 2),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (_, point) => widget.onPick(point.latitude, point.longitude, null),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  maxZoom: 19,
                  userAgentPackageName: 'com.nexaround.app',
                ),
                if (pin != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: pin,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_on, size: 40, color: AppColors.error),
                    ),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          pin == null ? 'No pin yet. Search, or tap the map.' : 'Tap the map to move the pin.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
