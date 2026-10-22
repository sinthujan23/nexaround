import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/features/travel_stories/data/datasources/travel_stories_service.dart';

/// When coming back to the app reloads the Travel Stories row: the fallback
/// for a silent push the phone held back.
void main() {
  final now = DateTime(2026, 10, 22, 12);

  bool reload({Duration? away, bool stale = false}) => TravelStoriesService.shouldReloadOnReturn(
        backgroundedAt: away == null ? null : now.subtract(away),
        now: now,
        stale: stale,
      );

  test('a quick switch to another app does not reload', () {
    expect(reload(away: const Duration(seconds: 20)), isFalse);
    expect(reload(away: const Duration(minutes: 1, seconds: 59)), isFalse);
  });

  test('two minutes or more away reloads', () {
    expect(reload(away: const Duration(minutes: 2)), isTrue);
    expect(reload(away: const Duration(hours: 3)), isTrue);
  });

  test('a silent push that arrived while away reloads at once', () {
    expect(reload(away: const Duration(seconds: 5), stale: true), isTrue);
  });

  test('the notification shade alone (never really backgrounded) does not reload', () {
    expect(reload(), isFalse);
  });
}
