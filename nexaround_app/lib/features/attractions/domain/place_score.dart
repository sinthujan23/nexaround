import 'package:nexaround_app/features/attractions/domain/entities/attraction.dart';

/// One ranking score for any place, whatever it is rated by — the same rule
/// the server ranks Around You with (place_bands.combined_score):
///
/// - Google rating: that rating, with our travellers' ratings counted in like
///   extra Google reviews, pulled toward 4.0 while there are few reviews.
///   Our popularity score, when the place has one too, adds at most 0.2.
/// - No Google rating but ratings from our travellers: their rating, blended
///   with the popularity score while there are only a few of them.
/// - Neither: the popularity score (0..100) on a 0..4 scale.
///
/// With no ratings of ours this is the old order.
class PlaceScore {
  PlaceScore._();

  /// A rating shrunk toward 4.0 by how little it is backed up.
  static double quality(double rating, int count) {
    if (rating <= 0) return 0.0;
    const priorWeight = 30.0;
    const priorMean = 4.0;
    return (count * rating + priorWeight * priorMean) / (count + priorWeight);
  }

  static double combined(AttractionEntity p) {
    final g = p.rating;
    final gv = p.reviewCount;
    final o = p.ourRating ?? 0.0;
    final ov = o > 0 ? p.ourReviewCount : 0;
    final pop = p.popularity.toDouble();
    // A free-map-data place has no Google rating, whatever its rating field holds.
    if (!p.isFreeData && g > 0) {
      final total = gv + ov;
      final mixed = total > 0 ? (g * gv + o * ov) / total : g;
      return quality(mixed, total) + (pop / 100.0) * 0.2;
    }
    if (ov > 0) {
      final ours = quality(o, ov);
      if (pop > 0) {
        final weight = ov / (ov + 5.0);
        return weight * ours + (1.0 - weight) * (pop / 25.0);
      }
      return ours;
    }
    return pop / 25.0;
  }

  /// How many ratings stand behind a place: Google's and ours together.
  static int reviews(AttractionEntity p) =>
      (p.isFreeData ? 0 : p.reviewCount) + p.ourReviewCount;
}
