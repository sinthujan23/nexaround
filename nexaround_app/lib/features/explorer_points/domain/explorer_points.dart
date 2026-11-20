/// Explorer Points (2026-11-20): travellers earn points for rating places,
/// writing reviews, adding photos and finishing trips; points raise their
/// level, shown next to their name on reviews and photos.
///
/// Every number, name and line of text comes from the server
/// (GET /points/info, GET /points/me), so they can change without a release.

int _int(dynamic v, [int fallback = 0]) => (v is num) ? v.toInt() : fallback;
String _str(dynamic v, [String fallback = '']) => v?.toString() ?? fallback;

class PointsLevel {
  final int level;
  final String name;
  final String badge;
  final int minPoints;
  final String tagline;

  const PointsLevel({
    required this.level,
    required this.name,
    this.badge = '',
    required this.minPoints,
    this.tagline = '',
  });

  /// "📸 Lv 4 · Snaphawk"
  String get label => '${badge.isEmpty ? '' : '$badge '}Lv $level · $name';

  factory PointsLevel.fromJson(Map<String, dynamic> json) => PointsLevel(
        level: _int(json['level'], 1),
        name: _str(json['name']),
        badge: _str(json['badge']),
        minPoints: _int(json['min_points']),
        tagline: _str(json['tagline']),
      );
}

class EarnRule {
  final String key;
  final String label;
  final int points;
  final String note;
  // Reviews: the length that earns it.
  final int minChars;

  const EarnRule({
    required this.key,
    required this.label,
    required this.points,
    this.note = '',
    this.minChars = 0,
  });

  factory EarnRule.fromJson(Map<String, dynamic> json) => EarnRule(
        key: _str(json['key']),
        label: _str(json['label']),
        points: _int(json['points']),
        note: _str(json['note']),
        minChars: _int(json['min_chars']),
      );
}

/// What the "?" explainer shows: public, the same for everyone.
class PointsInfo {
  final String title;
  final String intro;
  final List<EarnRule> earn;
  final List<PointsLevel> levels;
  final List<String> rules;

  const PointsInfo({
    required this.title,
    required this.intro,
    required this.earn,
    required this.levels,
    required this.rules,
  });

  int pointsFor(String key) =>
      earn.firstWhere((e) => e.key == key, orElse: () => const EarnRule(key: '', label: '', points: 0)).points;

  EarnRule? rule(String key) {
    for (final e in earn) {
      if (e.key == key) return e;
    }
    return null;
  }

  PointsLevel? level(int n) {
    for (final l in levels) {
      if (l.level == n) return l;
    }
    return null;
  }

  factory PointsInfo.fromJson(Map<String, dynamic> json) => PointsInfo(
        title: _str(json['title'], 'What are Explorer Points?'),
        intro: _str(json['intro']),
        earn: ((json['earn'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => EarnRule.fromJson(e.cast<String, dynamic>()))
            .toList(),
        levels: ((json['levels'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PointsLevel.fromJson(e.cast<String, dynamic>()))
            .toList(),
        rules: ((json['rules'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
}

/// Where a traveller is on the ladder.
class LevelProgress {
  final int level;
  final String name;
  final String badge;
  final String tagline;
  final int minPoints;
  final int? nextLevel;
  final String? nextName;
  final int? nextMinPoints;
  final int pointsToNext;
  final double progress;

  const LevelProgress({
    required this.level,
    required this.name,
    this.badge = '',
    this.tagline = '',
    this.minPoints = 0,
    this.nextLevel,
    this.nextName,
    this.nextMinPoints,
    this.pointsToNext = 0,
    this.progress = 0,
  });

  bool get isTop => nextLevel == null;

  String get label => '${badge.isEmpty ? '' : '$badge '}Lv $level · $name';

  factory LevelProgress.fromJson(Map<String, dynamic> json) => LevelProgress(
        level: _int(json['level'], 1),
        name: _str(json['name']),
        badge: _str(json['badge']),
        tagline: _str(json['tagline']),
        minPoints: _int(json['min_points']),
        nextLevel: (json['next_level'] as num?)?.toInt(),
        nextName: json['next_name'] as String?,
        nextMinPoints: (json['next_min_points'] as num?)?.toInt(),
        pointsToNext: _int(json['points_to_next']),
        progress: ((json['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      );
}

/// GET /points/me.
class PointsSummary {
  final int total;
  final LevelProgress level;
  final int maxLevel;
  final int pendingPoints;
  final Map<String, int> pointsBy;
  final Map<String, int> counts;

  const PointsSummary({
    required this.total,
    required this.level,
    this.maxLevel = 10,
    this.pendingPoints = 0,
    this.pointsBy = const {},
    this.counts = const {},
  });

  int count(String key) => counts[key] ?? 0;

  static Map<String, int> _intMap(dynamic m) => m is Map
      ? m.map((k, v) => MapEntry(k.toString(), v is num ? v.toInt() : 0))
      : <String, int>{};

  factory PointsSummary.fromJson(Map<String, dynamic> json) => PointsSummary(
        total: _int(json['total']),
        level: LevelProgress.fromJson((json['level'] as Map?)?.cast<String, dynamic>() ?? const {}),
        maxLevel: _int(json['max_level'], 10),
        pendingPoints: _int(json['pending_points']),
        pointsBy: _intMap(json['points_by']),
        counts: _intMap(json['counts']),
      );
}

/// What one action did to the traveller's points (a review's answer).
class PointsChange {
  final int earned;
  final int total;
  final int level;
  final String levelName;
  final bool levelledUp;

  const PointsChange({
    required this.earned,
    required this.total,
    required this.level,
    required this.levelName,
    this.levelledUp = false,
  });

  static PointsChange? fromJson(dynamic json) {
    if (json is! Map) return null;
    final m = json.cast<String, dynamic>();
    return PointsChange(
      earned: _int(m['earned']),
      total: _int(m['total']),
      level: _int(m['level'], 1),
      levelName: _str(m['level_name']),
      levelledUp: m['levelled_up'] == true,
    );
  }
}
