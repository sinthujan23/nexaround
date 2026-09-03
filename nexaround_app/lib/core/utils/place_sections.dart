import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';
import 'package:nexaround_app/features/manual_mode/presentation/bloc/map_state.dart';

/// Which section a place belongs to, and the pool both surfaces draw from.
///
/// Around You and Discovery are the same data at two depths — Around You is the
/// quick-access strip, Discovery is the full list — so a place shown in one must
/// also be reachable in the other. They used to disagree: Discovery merged
/// `bandedPlaces` into `allAttractions` and split the result with these rules,
/// while Around You worked from `allAttractions` alone using its own private
/// copy of the same rules. Different pool, drifted rules — which is why the
/// Nature card showed five weak places while the Nature tab listed far more.
///
/// Both now call [sectionsFrom], so Around You is a subset of Discovery.
class PlaceSections {
  const PlaceSections._();

  /// Must stay equal to `place_bands.allowed_tags_for('Nature')` on the server.
  /// `park`, `garden`, `picnic_ground` and `marina` are deliberately absent:
  /// Google files playgrounds, jogging tracks and cycling parks under the same
  /// generic `park` as a national park. Real reserves still qualify through
  /// national_park/state_park, and lakes and beaches through their own types.
  static const _natureTags = [
    'national_park', 'state_park', 'beach', 'hiking_area',
    'botanical_garden', 'wildlife_park', 'wildlife_refuge',
    'lake', 'river', 'natural_feature', 'campground',
  ];
  /// Words that mark a place as natural when Google typed it vaguely — Google
  /// has no `waterfall` type at all, so names are the only signal for those.
  /// 'park' and 'garden' are excluded: they match playgrounds and city parks.
  static const _natureWords = [
    'beach', 'lake', 'waterfall', 'falls', 'forest',
    'sanctuary', 'lagoon', 'trail', 'island',
  ];
  static const _heritageTags = [
    'museum', 'art_gallery', 'historical_landmark', 'historical_place',
    'cultural_landmark', 'monument', 'castle', 'sculpture', 'cultural_center',
  ];
  static const _heritageWords = [
    'museum', 'monument', 'fort',
    'palace', 'gallery', 'memorial', 'statue',
  ];
  static const _worshipTags = [
    'hindu_temple', 'buddhist_temple', 'church', 'mosque', 'synagogue',
    'place_of_worship',
  ];
  static const _worshipWords = [
    'temple', 'church', 'mosque', 'kovil', 'synagogue', 'cathedral', 'shrine',
  ];
  static const _poiTags = [
    'tourist_attraction', 'zoo', 'aquarium', 'amusement_park', 'water_park',
    'planetarium', 'performing_arts_theater', 'observation_deck',
    'visitor_center', 'point_of_interest_landmark',
  ];
  static const _hospitalWords = ['hospital', 'nursing home', 'infirmary'];
  static const _nonMedicalTags = [
    'school', 'university', 'secondary_school', 'primary_school',
    'bank', 'finance', 'accounting', 'atm',
    'food', 'restaurant', 'bakery', 'cafe', 'bar',
    'clothing_store', 'electronics_store', 'supermarket', 'shopping_mall',
    'lodging', 'real_estate_agency',
    'transit_station', 'bus_station', 'train_station',
    'gym', 'fitness_center', 'spa', 'massage',
  ];
  static const _shoppingTags = [
    'shopping_mall', 'department_store', 'supermarket', 'grocery_store',
    'grocery_or_supermarket', 'convenience_store', 'store', 'market',
    'clothing_store', 'electronics_store', 'shoe_store', 'jewelry_store',
    'book_store', 'gift_shop', 'home_goods_store', 'furniture_store',
    'hardware_store', 'sporting_goods_store', 'pet_store', 'liquor_store',
    'bicycle_store', 'warehouse_store', 'wholesaler', 'discount_store',
  ];
  /// Carry `store` but belong to another section — cafés and chemists above all,
  /// which Google files as `food_store` and `store` respectively.
  static const _nonShoppingTags = [
    'cafe', 'coffee_shop', 'restaurant', 'bar', 'bakery', 'ice_cream_shop',
    'dessert_shop', 'confectionery', 'food', 'food_store', 'meal_takeaway',
    'meal_delivery', 'pharmacy', 'drugstore', 'hospital', 'doctor', 'dentist',
    'medical_clinic', 'school', 'university', 'bank', 'atm', 'finance',
    'lodging', 'hotel', 'spa', 'beauty_salon', 'hair_care', 'body_art_service',
    'real_estate_agency', 'travel_agency', 'car_repair', 'car_dealer',
  ];
  static const _stayWords = [
    'homestay', 'bedroom', 'apartment', 'villa', 'guest house', 'hotel',
    'resort',
  ];

  /// Tags that say nothing about what a place is — mirrors the server's
  /// `_GENERIC_TAGS` in place_bands.py. A row carrying only these (or none at
  /// all) is untyped in practice, and the stored category name is the only
  /// signal left to judge it by.
  static const _genericTags = [
    'point_of_interest', 'establishment', 'premise', 'geocode',
  ];

  static List<String> tagsOf(AttractionEntity a) =>
      a.tags.map((t) => t.toString().toLowerCase()).toList();

  /// Whether Google gave this place no real signal to classify by at all.
  ///
  /// The `cat.contains(...)` fallback below only fires for rows like this —
  /// e.g. admin-curated places with no Google tags. A row that DOES carry
  /// real tags is judged by those, never by a possibly-stale stored category:
  /// the mosque-under-Nature bug was exactly a row whose only "Nature"
  /// evidence was a wrong category name from an old seeding bug, not any real
  /// tag Google ever attached to it.
  static bool _hasNoInformativeTags(AttractionEntity a) =>
      tagsOf(a).where((t) => !_genericTags.contains(t)).isEmpty;

  static bool isWorship(AttractionEntity a) {
    final name = a.name.toLowerCase();
    final tags = tagsOf(a);
    if (_worshipTags.any(tags.contains) || _worshipWords.any(name.contains)) {
      return true;
    }
    final cat = (a.categoryName ?? '').toLowerCase();
    return cat.contains('temple') || cat.contains('church') ||
        cat.contains('mosque') || cat.contains('worship') ||
        cat.contains('religious') || cat.contains('kovil') || cat.contains('synagogue');
  }

  static bool _hasNatureSignal(AttractionEntity a) {
    final name = a.name.toLowerCase();
    final tags = tagsOf(a);
    // `park` is gone from the tag/word test too. Narrowing only the tag list
    // would have let every generic park back in through the category name,
    // which is how "Ezhilarangu Stadium" reached the Nature tab.
    if (_natureTags.any(tags.contains) || _natureWords.any(name.contains)) {
      return true;
    }
    if (!_hasNoInformativeTags(a)) return false;
    final cat = (a.categoryName ?? '').toLowerCase();
    return cat.contains('nature') || cat.contains('beach') ||
        cat.contains('lake') || cat.contains('river') ||
        cat.contains('waterfall') || cat.contains('forest');
  }

  static bool _hasHeritageSignal(AttractionEntity a) {
    final name = a.name.toLowerCase();
    final tags = tagsOf(a);
    if (_heritageTags.any(tags.contains) || _heritageWords.any(name.contains)) {
      return true;
    }
    if (!_hasNoInformativeTags(a)) return false;
    final cat = (a.categoryName ?? '').toLowerCase();
    return cat.contains('museum') || cat.contains('landmark') ||
        cat.contains('culture') || cat.contains('art') || cat.contains('historic');
  }

  /// Somewhere outdoors, and not a place to sleep. Beach resorts and safari
  /// lodges carry `beach` and `wildlife_park` next to `lodging`.
  static bool isNature(AttractionEntity a) {
    if (isWorship(a)) return false;
    if (_stayWords.any(a.name.toLowerCase().contains)) return false;
    if (_hasHeritageSignal(a)) return false;
    if (!_hasNatureSignal(a)) return false;
    final tags = tagsOf(a);
    return !const [
      'lodging', 'hotel', 'resort_hotel', 'guest_house', 'motel', 'hostel',
      'bed_and_breakfast', 'restaurant', 'bar', 'cafe',
    ].any(tags.contains);
  }

  /// Something built and worth going to see. Nature wins any place that reads as
  /// outdoors without also carrying real heritage.
  static bool isPoi(AttractionEntity a) {
    if (isWorship(a)) return false;
    if (_stayWords.any(a.name.toLowerCase().contains)) return false;
    if (isNature(a)) return false;
    final tags = tagsOf(a);
    if (_hasHeritageSignal(a) || _poiTags.any(tags.contains)) return true;
    if (!_hasNoInformativeTags(a)) return false;
    final cat = (a.categoryName ?? '').toLowerCase();
    return cat.contains('experience') || cat.contains('zoo') ||
        cat.contains('attraction');
  }

  static bool _hasMedicalSignal(AttractionEntity a) {
    final name = a.name.toLowerCase();
    final tags = tagsOf(a);
    bool signal = name.contains('medical') || name.contains('hospital') ||
        name.contains('clinic') || name.contains('pharmacy') ||
        name.contains('chemist') || name.contains('drugstore') ||
        name.contains('drug store') ||
        name.contains('dispensary') || name.contains('health centre') ||
        name.contains('health center') || tags.contains('hospital') ||
        tags.contains('pharmacy') || tags.contains('drugstore') || tags.contains('doctor') ||
        tags.contains('dentist') || tags.contains('physiotherapist') ||
        tags.contains('veterinary_care') || tags.contains('health') ||
        tags.contains('medical_center') || tags.contains('medical_clinic');
    if (!signal && _hasNoInformativeTags(a)) {
      final cat = (a.categoryName ?? '').toLowerCase();
      signal = cat == 'medical' || cat == 'hospital' ||
          cat.contains('medical') || cat.contains('hospital') ||
          cat.contains('clinic') || cat.contains('pharmacy') ||
          cat.contains('chemist') || cat.contains('drug') || cat.contains('doctor');
    }
    if (!signal) return false;
    return !_nonMedicalTags.any(tags.contains);
  }

  /// Hospital always wins over Medical: Google types most hospitals as
  /// `hospital` alongside the clinic types, and names the rest without any
  /// distinguishing type at all.
  static bool isHospital(AttractionEntity a) =>
      _hasMedicalSignal(a) &&
      (tagsOf(a).contains('hospital') ||
          _hospitalWords.any(a.name.toLowerCase().contains));

  static bool isMedical(AttractionEntity a) =>
      _hasMedicalSignal(a) && !isHospital(a);

  /// Somewhere you go to buy something that is not food or medicine.
  ///
  /// Matched on Google types, like every other section. The previous filter
  /// tested `categoryName` for 'mall'/'market'/'store' — but categoryName is the
  /// literal string 'Shopping', which contains none of those, so the tab matched
  /// nothing and rendered empty while Around You showed the same places fine.
  static bool isShopping(AttractionEntity a) {
    final tags = tagsOf(a);
    if (_nonShoppingTags.any(tags.contains)) return false;
    if (_stayWords.any(a.name.toLowerCase().contains)) return false;
    if (_shoppingTags.any(tags.contains)) return true;
    if (!_hasNoInformativeTags(a)) return false;
    final cat = (a.categoryName ?? '').toLowerCase();
    return cat.contains('shopping') || cat.contains('mall') ||
        cat.contains('market') || cat.contains('store');
  }
  /// Every place the app knows about, split into the six sections.
  ///
  /// The pool is `allAttractions` (the map's own fetch) merged with
  /// `bandedPlaces` (the backend's distance-banded fetch, which reaches places
  /// a plain radius query never returns). Neither source alone is complete.
  static Map<String, List<AttractionEntity>> sectionsFrom(MapState state) {
    final base = state.allAttractions.isNotEmpty
        ? state.allAttractions
        : state.attractions;
    final banded = state.bandedPlaces.values
        .expand((bands) => bands.expand((band) => band))
        .toList();
    final pool = deduplicate([...base, ...banded]);

    return {
      'Food & Drink': pool.where(isFood).toList(),
      'POI': pool.where(isPoi).toList(),
      'Nature': pool.where(isNature).toList(),
      'Shopping': pool.where(isShopping).toList(),
      'Medical': pool.where(isMedical).toList(),
      'Hospital': pool.where(isHospital).toList(),
    };
  }

  static const _foodTags = [
    'restaurant', 'cafe', 'coffee_shop', 'bakery', 'bar', 'night_club',
    'meal_takeaway', 'meal_delivery', 'ice_cream_shop', 'dessert_shop',
    'tea_house', 'fast_food_restaurant', 'food_court', 'food', 'food_store',
  ];

  static bool isFood(AttractionEntity a) {
    if (_foodTags.any(tagsOf(a).contains)) return true;
    if (!_hasNoInformativeTags(a)) return false;
    final cat = (a.categoryName ?? '').toLowerCase();
    return cat.contains('food') || cat.contains('restaurant') ||
        cat.contains('cafe') || cat.contains('dining') || cat.contains('meal');
  }

  static List<AttractionEntity> deduplicate(List<AttractionEntity> list) {
    final seen = <String>{};
    final result = <AttractionEntity>[];
    for (final a in list) {
      final nameKey = a.name.trim().toLowerCase();
      final idKey = a.id.trim();
      if ((nameKey.isNotEmpty && seen.contains(nameKey)) ||
          (idKey.isNotEmpty && seen.contains(idKey))) {
        continue;
      }
      if (nameKey.isNotEmpty) seen.add(nameKey);
      if (idKey.isNotEmpty) seen.add(idKey);
      result.add(a);
    }
    return result;
  }
}
