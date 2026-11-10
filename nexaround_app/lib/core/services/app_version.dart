import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// This build's version ("1.0.17"), read once at startup. Sent to the backend
/// as X-App-Version and compared with its `min_app_version`.
class AppVersion {
  AppVersion._();

  static String version = '';
  static String get platform =>
      kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other'));

  static Future<void> load() async {
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (e) {
      debugPrint('AppVersion.load failed: $e');
    }
  }

  /// True when [version] is older than [minimum] ("1.0.18" > "1.0.17").
  /// Unknown or empty versions never count as too old.
  static bool isOlderThan(String minimum) {
    if (minimum.trim().isEmpty || version.isEmpty) return false;
    List<int> parts(String v) =>
        v.split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final a = parts(version), b = parts(minimum);
    for (var i = 0; i < 4; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x < y;
    }
    return false;
  }
}
