import 'package:nexaround_app/features/city_tours/domain/city_tour.dart';

/// A traveller following one day of a guide ([dayId]): "Start trip" saved [startedAt], and each
/// "Mark done" saved when a step ended. "Skip" ends a step the same way and
/// is listed in [skipped] too. The server reads every step's planned
/// minutes from the guide ("1.5–2 hours" → 105) and sends them in [minutes],
/// so the app and the server's reminders plan with the same numbers.
/// Shape from GET/POST /city-tours/{id}/trip.
class CityTourTrip {
  final String id;
  final String dayId;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final Map<String, DateTime> done;
  final Set<String> skipped;
  final Map<String, int> minutes;

  const CityTourTrip({
    required this.id,
    this.dayId = '',
    required this.startedAt,
    required this.finishedAt,
    required this.done,
    this.skipped = const {},
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
      skipped: {for (final id in json['skipped'] as List? ?? const []) id.toString()},
      minutes: minutes,
    );
  }

  int minutesFor(CityTourStep step) => minutes[step.id] ?? cityTourPlannedMinutes(step);

  /// Every step's times as of [now]. Only stops are ticked, in any order
  /// (rides and breaks ticked by an app from before still count): the stop
  /// in hand is the first stop after the furthest step marked, and the
  /// stretch to it starts when that one was marked (or at the start); the
  /// rides and breaks on the way run their minutes, the stop runs its own, or
  /// on until now when it runs over, and the rest follow on. Steps before the
  /// furthest one left unmarked were passed over: a stop is [missed] (still to
  /// visit, and can be ticked), a ride or break [passed]. A skipped or missed
  /// stop's minutes leave the plan the pace is measured against. Matches the
  /// server's due_step.
  CityTourSchedule schedule(List<CityTourStep> steps, DateTime now) {
    final times = <String, CityTourStepTime>{};
    var furthest = -1;
    for (var i = 0; i < steps.length; i++) {
      if (done.containsKey(steps[i].id)) furthest = i;
    }
    CityTourStep? current;
    for (var i = furthest + 1; i < steps.length && current == null; i++) {
      if (steps[i].isStop) current = steps[i];
    }
    var cursor = startedAt;
    var planned = startedAt;
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final length = Duration(minutes: minutesFor(step));
      final doneAt = done[step.id];
      final wasSkipped = doneAt != null && skipped.contains(step.id);
      final missed = doneAt == null && i < furthest && step.isStop;
      if (!wasSkipped && !missed) planned = planned.add(length);
      if (doneAt != null) {
        // A stop ticked late, after one further on, starts no later than it ends.
        final start = doneAt.isBefore(cursor) ? doneAt : cursor;
        times[step.id] = CityTourStepTime(start: start, end: doneAt, doneAt: doneAt, skipped: wasSkipped);
        cursor = doneAt;
      } else if (i < furthest) {
        times[step.id] = CityTourStepTime(start: cursor, end: cursor, missed: missed, passed: !missed);
      } else if (step.id == current?.id) {
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

  /// Done by "Skip" rather than "Mark done".
  final bool skipped;

  /// A stop passed over: one further on was ticked first. Still to visit,
  /// and can be ticked.
  final bool missed;

  /// A ride or break before the furthest step ticked, left unmarked: counted
  /// done, but nothing to take back.
  final bool passed;

  const CityTourStepTime({
    required this.start,
    required this.end,
    this.doneAt,
    this.isCurrent = false,
    this.skipped = false,
    this.missed = false,
    this.passed = false,
  });

  bool get isDone => doneAt != null;
}

/// The day laid out: each step's times, the step in hand ([current], null
/// once the last step is marked), when the trip should end, and how far that is behind
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

