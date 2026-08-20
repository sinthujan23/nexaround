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

  static const _natureTags = [
    'park', 'national_park', 'state_park', 'beach', 'hiking_area',
    'botanical_garden', 'garden', 'wildlife_park', 'wildlife_refuge',
    'lake', 'river', 'marina', 'picnic_ground', 'natural_feature', 'campground',
  ];
  static const _natureWords = [
    'beach', 'park', 'lake', 'waterfall', 'falls', 'garden', 'forest',
    'sanctuary', 'lagoon', 'trail', 'island',
  ];
  static const _heritageTags = [
    'museum', 'art_gallery', 'historical_landmark', 'historical_place',
    'cultural_landmark', 'monument', 'castle', 'sculpture', 'cultural_center',
    'hindu_temple', 'buddhist_temple', 'church', 'mosque', 'synagogue',
    'place_of_worship',
  ];
  static const _heritageWords = [
    'museum', 'temple', 'church', 'mosque', 'kovil', 'monument', 'fort',
    'palace', 'gallery', 'memorial', 'statue',
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
    'store', 'shopping_mall', 'grocery_or_supermarket',
    'lodging', 'real_estate_agency',
    'transit_station', 'bus_station', 'train_station',
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

  static List<String> tagsOf(AttractionEntity a) =>
      a.tags.map((t) => t.toString().toLowerCase()).toList();

  static bool _hasNatureSignal(AttractionEntity a) {
    final cat = (a.categoryName ?? '').toLowerCase();
    final name = a.name.toLowerCase();
    final tags = tagsOf(a);
    return _natureTags.any(tags.contains) ||
        _natureWords.any(name.contains) ||
        cat.contains('nature') || cat.contains('beach') || cat.contains('park') ||
        cat.contains('garden') || cat.contains('lake') || cat.contains('river') ||
        cat.contains('waterfall') || cat.contains('forest');
  }

  static bool _hasHeritageSignal(AttractionEntity a) {
    final cat = (a.categoryName ?? '').toLowerCase();
    final name = a.name.toLowerCase();
    final tags = tagsOf(a);
    return _heritageTags.any(tags.contains) ||
        _heritageWords.any(name.contains) ||
        cat.contains('museum') || cat.contains('landmark') ||
        cat.contains('culture') || cat.contains('temple') ||
        cat.contains('art') || cat.contains('historic');
  }

  /// Somewhere outdoors, and not a place to sleep. Beach resorts and safari
  /// lodges carry `beach` and `wildlife_park` next to `lodging`.
  static bool isNature(AttractionEntity a) {
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
    if (_stayWords.any(a.name.toLowerCase().contains)) return false;
    if (isNature(a)) return false;
    final cat = (a.categoryName ?? '').toLowerCase();
    final tags = tagsOf(a);
    return _hasHeritageSignal(a) ||
        _poiTags.any(tags.contains) ||
        cat.contains('experience') || cat.contains('zoo') ||
        cat.contains('attraction');
  }

  static bool _hasMedicalSignal(AttractionEntity a) {
    final cat = (a.categoryName ?? '').toLowerCase();
    final name = a.name.toLowerCase();
    final tags = tagsOf(a);
    final bool signal = cat == 'medical' || cat == 'hospital' ||
        name.contains('medical') || name.contains('hospital') ||
        name.contains('clinic') || name.contains('pharmacy') ||
        name.contains('dispensary') || name.contains('health centre') ||
        name.contains('health center') || tags.contains('hospital') ||
        tags.contains('pharmacy') || tags.contains('doctor') ||
        tags.contains('dentist') || tags.contains('physiotherapist') ||
        tags.contains('veterinary_care') || tags.contains('health') ||
        tags.contains('medical_center') || tags.contains('medical_clinic') ||
        cat.contains('medical') || cat.contains('hospital') ||
        cat.contains('clinic') || cat.contains('pharmacy') || cat.contains('doctor');
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
