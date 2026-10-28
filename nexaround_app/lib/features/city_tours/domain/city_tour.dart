import 'package:nexaround_app/core/constants/api_constants.dart';

/// Guides written by the content team in the admin panel and approved by an
/// admin: a route through a city, from where to start, through "take this
/// ride" to the next stop, with partner links on the way.
/// Shapes come from GET /city-tours and GET /city-tours/{id}.

String _s(dynamic v) => v is String ? v : '';

/// Uploaded photos arrive as "/static/..." paths on the API host.
String cityTourMediaUrl(String url) =>
    url.startsWith('/') ? '${ApiConstants.baseUrl}$url' : url;

/// A guide in a list.
class CityTourCard {
  final String id;
  final String city;
  final String country;
  final String title;
  final String summary;
  final String coverUrl;
  final String duration;
  final String budget;
  final int stopCount;

  const CityTourCard({
    required this.id,
    required this.city,
    required this.country,
    required this.title,
    required this.summary,
    required this.coverUrl,
    required this.duration,
    required this.budget,
    required this.stopCount,
  });

  factory CityTourCard.fromJson(Map<String, dynamic> json) => CityTourCard(
        id: _s(json['id']),
        city: _s(json['city']),
        country: _s(json['country']),
        title: _s(json['title']),
        summary: _s(json['summary']),
        coverUrl: _s(json['cover_url']),
        duration: _s(json['duration']),
        budget: _s(json['budget']),
        stopCount: (json['stop_count'] as num?)?.toInt() ?? 0,
      );

  /// Guides group into one city however the writer capitalised it.
  String get cityKey =>
      '${city.trim().toLowerCase()}|${country.trim().toLowerCase()}';
}

/// One city and its guides, in the order the server sent them.
class CityTourCity {
  final String city;
  final String country;
  final List<CityTourCard> tours;

  const CityTourCity({
    required this.city,
    required this.country,
    required this.tours,
  });

  String get coverUrl =>
      tours.firstWhere((t) => t.coverUrl.isNotEmpty, orElse: () => tours.first).coverUrl;

  static List<CityTourCity> group(List<CityTourCard> tours) {
    final byKey = <String, List<CityTourCard>>{};
    for (final t in tours) {
      byKey.putIfAbsent(t.cityKey, () => []).add(t);
    }
    final cities = byKey.values
        .map((list) => CityTourCity(
              city: list.first.city,
              country: list.first.country,
              tours: list,
            ))
        .toList()
      ..sort((a, b) => a.city.toLowerCase().compareTo(b.city.toLowerCase()));
    return cities;
  }
}

/// An Experience a guide links to, as its card shows it.
class CityTourPackage {
  final String id;
  final String title;
  final String vendorName;
  final String photoUrl;
  final String priceLabel;

  const CityTourPackage({
    required this.id,
    required this.title,
    required this.vendorName,
    required this.photoUrl,
    required this.priceLabel,
  });

  factory CityTourPackage.fromJson(Map<String, dynamic> json) => CityTourPackage(
        id: _s(json['id']),
        title: _s(json['title']),
        vendorName: _s(json['vendor_name']),
        photoUrl: _s(json['photo_url']),
        priceLabel: _s(json['price_label']),
      );
}

/// A partner button on a step. An affiliate's [url] is our /go address
/// (counts the tap, then the partner's site); an Experience opens in the app.
class CityTourLink {
  final String id;
  final bool isExperience;
  final String partner;
  final String partnerName;
  final String label;
  final String url;
  final CityTourPackage? package;

  const CityTourLink({
    required this.id,
    required this.isExperience,
    required this.partner,
    required this.partnerName,
    required this.label,
    required this.url,
    this.package,
  });

  factory CityTourLink.fromJson(Map<String, dynamic> json) {
    final package = json['package'];
    return CityTourLink(
      id: _s(json['id']),
      isExperience: json['kind'] == 'experience',
      partner: _s(json['partner']),
      partnerName: _s(json['partner_name']),
      label: _s(json['label']),
      url: _s(json['url']),
      package: package is Map
          ? CityTourPackage.fromJson(package.cast<String, dynamic>())
          : null,
    );
  }
}

/// A place to visit ([isStop]) or the way to the next one.
class CityTourStep {
  final String id;
  final bool isStop;

  // A stop.
  final int number;
  final String name;
  final double? lat;
  final double? lng;
  final String photoUrl;
  final String timeHere;
  final String price;

  // The way there.
  final String mode;
  final String modeLabel;
  final String directions;
  final String duration;
  final String cost;

  final String bodyMd;
  final List<CityTourLink> links;

  const CityTourStep({
    required this.id,
    required this.isStop,
    this.number = 0,
    this.name = '',
    this.lat,
    this.lng,
    this.photoUrl = '',
    this.timeHere = '',
    this.price = '',
    this.mode = 'walk',
    this.modeLabel = '',
    this.directions = '',
    this.duration = '',
    this.cost = '',
    this.bodyMd = '',
    this.links = const [],
  });

  bool get hasPin => lat != null && lng != null;

  factory CityTourStep.fromJson(Map<String, dynamic> json) {
    final isStop = json['type'] == 'stop';
    final links = (json['links'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => CityTourLink.fromJson(e.cast<String, dynamic>()))
        .toList();
    return CityTourStep(
      id: _s(json['id']),
      isStop: isStop,
      number: (json['number'] as num?)?.toInt() ?? 0,
      name: _s(json['name']),
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      photoUrl: _s(json['photo_url']),
      timeHere: _s(json['time_here']),
      price: _s(json['price']),
      mode: _s(json['mode']).isEmpty ? 'walk' : _s(json['mode']),
      modeLabel: _s(json['mode_label']),
      directions: isStop ? '' : _s(json['title']),
      duration: _s(json['duration']),
      cost: _s(json['cost']),
      bodyMd: _s(json['body_md']),
      links: links,
    );
  }
}

/// A whole guide.
class CityTour {
  final String id;
  final CityTourCard card;
  final String introMd;
  final List<CityTourStep> steps;

  const CityTour({
    required this.id,
    required this.card,
    required this.introMd,
    required this.steps,
  });

  factory CityTour.fromJson(Map<String, dynamic> json) => CityTour(
        id: _s(json['id']),
        card: CityTourCard.fromJson(json),
        introMd: _s(json['intro_md']),
        steps: (json['steps'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => CityTourStep.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  List<CityTourStep> get stops => steps.where((s) => s.isStop).toList();
}
