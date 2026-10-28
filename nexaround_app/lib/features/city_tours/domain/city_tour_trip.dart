import 'package:nexaround_app/features/city_tours/domain/city_tour.dart';

/// A traveller following one day of a guide ([dayId]): "Start trip" saved [startedAt], and each
/// "Mark done" saved when a step ended. The server reads every step's planned
/// minutes from the guide ("1.5–2 hours" → 105) and sends them in [minutes],
/// so the app and the server's reminders plan with the same numbers.
/// Shape from GET/POST /city-tours/{id}/trip.
class CityTourTrip {
  final String id;
  final String dayId;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final Map<String, DateTime> done;
  final Map<String, int> minutes;

  const CityTourTrip({
    required this.id,
    this.dayId = '',
    required this.startedAt,
    required this.finishedAt,
    required this.done,
    required this.minutes,
  });

  bool get isFinished => finishedAt != null;

  static DateTime? _time(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  factory CityTourTrip.fromJson(Map<String, dynamic> json) {
    final done = <String, DateTime>{};
    (json['done'] as Map? ?? const {}).forEach((k, v) {
      final at = _time(v);
      if (at != null) done[k.toString()] = at;
    });
    final minutes = <String, int>{};
    (json['minutes'] as Map? ?? const {}).forEach((k, v) {
      if (v is num) minutes[k.toString()] = v.toInt();
    });
    return CityTourTrip(
      id: (json['id'] ?? '').toString(),
      dayId: (json['day_id'] ?? '').toString(),
      startedAt: _time(json['started_at']) ?? DateTime.now(),
      finishedAt: _time(json['finished_at']),
      done: done,
      minutes: minutes,
    );
  }

  int minutesFor(CityTourStep step) => minutes[step.id] ?? cityTourPlannedMinutes(step);

  /// Every step's times as of [now]. A step starts when the one before it was
  /// marked done (the first, at the start); the step in hand runs its planned
  /// minutes, or on until now when it runs over; the rest follow on.
  CityTourSchedule schedule(List<CityTourStep> steps, DateTime now) {
    final times = <String, CityTourStepTime>{};
    CityTourStep? current;
    var cursor = startedAt;
    var planned = startedAt;
    for (final step in steps) {
      final length = Duration(minutes: minutesFor(step));
      planned = planned.add(length);
      final doneAt = done[step.id];
      if (doneAt != null) {
        times[step.id] = CityTourStepTime(start: cursor, end: doneAt, doneAt: doneAt);
        cursor = doneAt;
      } else if (current == null) {
        current = step;
        final end = cursor.add(length);
        times[step.id] = CityTourStepTime(start: cursor, end: end, isCurrent: true);
        cursor = now.isAfter(end) ? now : end;
      } else {
        times[step.id] = CityTourStepTime(start: cursor, end: cursor.add(length));
        cursor = cursor.add(length);
      }
    }
    return CityTourSchedule(
      times: times,
      current: current,
      finish: cursor,
      behindMinutes: cursor.difference(planned).inMinutes,
    );
  }
}

/// One step's place in the day.
class CityTourStepTime {
  final DateTime start;
  final DateTime end;
  final DateTime? doneAt;
  final bool isCurrent;

  const CityTourStepTime({
    required this.start,
    required this.end,
    this.doneAt,
    this.isCurrent = false,
  });

  bool get isDone => doneAt != null;
}

/// The day laid out: each step's times, the step in hand ([current], null
/// once all are done), when the trip should end, and how far that is behind
/// the plan made at the start (negative: ahead).
class CityTourSchedule {
  final Map<String, CityTourStepTime> times;
  final CityTourStep? current;
  final DateTime finish;
  final int behindMinutes;

  const CityTourSchedule({
    required this.times,
    required this.current,
    required this.finish,
    required this.behindMinutes,
  });
}

/// A step's planned minutes when no trip says otherwise: the server's number,
/// else its defaults (stop 30, ride 15, break 45).
int cityTourPlannedMinutes(CityTourStep step) {
  if (step.minutes > 0) return step.minutes;
  if (step.isStop) return 30;
  return step.isBreak ? 45 : 15;
}

/// A day's planned times from its own start time ("9:00 AM – 11:45 AM"),
/// for a day nobody is following yet. Empty when the day has no start time.
Map<String, CityTourStepTime> cityTourDayPlan(CityTourDay day, DateTime today) {
  final start = day.startOn(today);
  if (start == null) return const {};
  var cursor = start;
  final times = <String, CityTourStepTime>{};
  for (final step in day.steps) {
    final end = cursor.add(Duration(minutes: cityTourPlannedMinutes(step)));
    times[step.id] = CityTourStepTime(start: cursor, end: end);
    cursor = end;
  }
  return times;
}

