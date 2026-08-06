/// Domain models for the Museum Masterpieces feature.
///
/// These map 1:1 to the backend `/museums` API responses.

class MuseumListItem {
  final String id;
  final String slug;
  final String name;
  final String city;
  final String country;
  final int? annualVisitors;
  final int? rank;
  final String? imageUrl;
  final int masterpieceCount;

  const MuseumListItem({
    required this.id,
    required this.slug,
    required this.name,
    required this.city,
    required this.country,
    this.annualVisitors,
    this.rank,
    this.imageUrl,
    this.masterpieceCount = 0,
  });

  factory MuseumListItem.fromJson(Map<String, dynamic> json) => MuseumListItem(
        id: json['id'] as String,
        slug: json['slug'] as String,
        name: json['name'] as String,
        city: json['city'] as String,
        country: json['country'] as String,
        annualVisitors: json['annual_visitors'] as int?,
        rank: json['rank'] as int?,
        imageUrl: json['image_url'] as String?,
        masterpieceCount: (json['masterpiece_count'] as int?) ?? 0,
      );
}

class Masterpiece {
  final String id;
  final int rank;
  final String building;
  final String roomGallery;
  final String mustSeeItem;
  final String? artist;
  final String category;
  final String? description;
  final bool included3h;
  final bool included5h;
  final bool included1d;
  final bool included2d;

  const Masterpiece({
    required this.id,
    required this.rank,
    required this.building,
    required this.roomGallery,
    required this.mustSeeItem,
    this.artist,
    required this.category,
    this.description,
    this.included3h = false,
    this.included5h = false,
    this.included1d = false,
    this.included2d = false,
  });

  factory Masterpiece.fromJson(Map<String, dynamic> json) => Masterpiece(
        id: json['id'] as String,
        rank: json['rank'] as int,
        building: json['building'] as String,
        roomGallery: json['room_gallery'] as String,
        mustSeeItem: json['must_see_item'] as String,
        artist: json['artist'] as String?,
        category: json['category'] as String,
        description: json['description'] as String?,
        included3h: (json['included_3h'] as bool?) ?? false,
        included5h: (json['included_5h'] as bool?) ?? false,
        included1d: (json['included_1d'] as bool?) ?? false,
        included2d: (json['included_2d'] as bool?) ?? false,
      );
}

class BuildingSection {
  final String building;
  final List<Masterpiece> items;

  const BuildingSection({required this.building, required this.items});

  factory BuildingSection.fromJson(Map<String, dynamic> json) =>
      BuildingSection(
        building: json['building'] as String,
        items: (json['items'] as List)
            .map((e) => Masterpiece.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class MuseumItinerary {
  final String museumName;
  final String museumSlug;
  final String duration;
  final int totalItems;
  final List<BuildingSection> buildings;

  const MuseumItinerary({
    required this.museumName,
    required this.museumSlug,
    required this.duration,
    required this.totalItems,
    required this.buildings,
  });

  factory MuseumItinerary.fromJson(Map<String, dynamic> json) =>
      MuseumItinerary(
        museumName: json['museum_name'] as String,
        museumSlug: json['museum_slug'] as String,
        duration: json['duration'] as String,
        totalItems: json['total_items'] as int,
        buildings: (json['buildings'] as List)
            .map((e) => BuildingSection.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class MuseumDetail {
  final String id;
  final String slug;
  final String name;
  final String city;
  final String country;
  final int? annualVisitors;
  final int? rank;
  final String? imageUrl;
  final String? ticketUrl;
  final double? latitude;
  final double? longitude;
  final List<Masterpiece> masterpieces;

  const MuseumDetail({
    required this.id,
    required this.slug,
    required this.name,
    required this.city,
    required this.country,
    this.annualVisitors,
    this.rank,
    this.imageUrl,
    this.ticketUrl,
    this.latitude,
    this.longitude,
    required this.masterpieces,
  });

  factory MuseumDetail.fromJson(Map<String, dynamic> json) => MuseumDetail(
        id: json['id'] as String,
        slug: json['slug'] as String,
        name: json['name'] as String,
        city: json['city'] as String,
        country: json['country'] as String,
        annualVisitors: json['annual_visitors'] as int?,
        rank: json['rank'] as int?,
        imageUrl: json['image_url'] as String?,
        ticketUrl: json['ticket_url'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        masterpieces: (json['masterpieces'] as List)
            .map((e) => Masterpiece.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
