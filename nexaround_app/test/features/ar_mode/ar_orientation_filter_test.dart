import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/features/ar_mode/domain/ar_orientation_tracker.dart';

/// Feeds [seconds] of a constant gyro rate in [steps] ticks (default 20 ms).
void spin(
  ArOrientationFilter f, {
  double x = 0,
  double y = 0,
  double z = 0,
  double seconds = 1,
  double dt = 0.02,
}) {
  final int steps = (seconds / dt).round();
  for (int i = 0; i < steps; i++) {
    f.onGyro(x, y, z, dt);
  }
}

/// Phone held upright in portrait, camera on the horizon.
void upright(ArOrientationFilter f) => f.onAccel(0, 9.81, 0);

void main() {
  group('angle helpers', () {
    test('wrapDegrees normalises to [0, 360)', () {
      expect(wrapDegrees(370), closeTo(10, 1e-9));
      expect(wrapDegrees(-10), closeTo(350, 1e-9));
      expect(wrapDegrees(360), closeTo(0, 1e-9));
    });

    test('signedAngleDelta takes the short way round', () {
      expect(signedAngleDelta(350, 10), closeTo(20, 1e-9));
      expect(signedAngleDelta(10, 350), closeTo(-20, 1e-9));
      expect(signedAngleDelta(0, 180), closeTo(180, 1e-9));
    });
  });

  group('compass', () {
    test('first reading snaps regardless of accuracy', () {
      final f = ArOrientationFilter();
      f.onCompass(123.4, 45); // poor accuracy still snaps on first fix
      expect(f.heading, closeTo(123.4, 1e-9));
      expect(f.hasCompassFix, isTrue);
    });

    test('later readings pull the heading by kCompassGain', () {
      final f = ArOrientationFilter();
      f.onCompass(100, 15);
      f.onCompass(110, 15);
      expect(f.heading, closeTo(100 + 10 * kCompassGain, 1e-9));
    });

    test('converges onto a steady compass', () {
      final f = ArOrientationFilter();
      f.onCompass(100, 15);
      for (int i = 0; i < 100; i++) {
        f.onCompass(110, 15);
      }
      expect(f.heading, closeTo(110, 0.01));
    });

    test('correction crosses north the short way', () {
      final f = ArOrientationFilter();
      f.onCompass(355, 15);
      f.onCompass(5, 15);
      expect(f.heading, closeTo(wrapDegrees(355 + 10 * kCompassGain), 1e-9));
    });

    test('readings worse than the accuracy limit are ignored', () {
      final f = ArOrientationFilter(maxUsableCompassAccuracy: 35);
      f.onCompass(100, 15);
      f.onCompass(150, 45);
      expect(f.heading, closeTo(100, 1e-9));
      expect(f.compassAccuracy, 45);
    });

    test('persistent large disagreement snaps after the streak', () {
      final f = ArOrientationFilter();
      f.onCompass(0, 15);
      for (int i = 0; i < kCompassSnapStreak - 1; i++) {
        f.onCompass(90, 15);
      }
      expect(f.heading, lessThan(45)); // still slewing, not snapped
      f.onCompass(90, 15);
      expect(f.heading, closeTo(90, 1e-9)); // snapped
    });

    test('reset() makes the next reading snap again', () {
      final f = ArOrientationFilter();
      f.onCompass(10, 15);
      f.reset();
      f.onCompass(200, 15);
      expect(f.heading, closeTo(200, 1e-9));
    });

    test('no-gyro fallback low-passes the compass', () {
      final f = ArOrientationFilter(hasGyro: false);
      f.onCompass(100, 15);
      f.onCompass(110, 15);
      expect(f.heading, closeTo(100 + 10 * kCompassOnlyAlpha, 1e-9));
    });
  });

  group('gyro yaw', () {
    test('turning right (clockwise from above) increases the heading', () {
      final f = ArOrientationFilter();
      upright(f);
      f.onCompass(120, 15);
      // Upright: world-up is device +Y. Clockwise seen from above is a
      // negative rotation about +Y (right-hand rule).
      spin(f, y: -pi / 2, seconds: 1); // 90°/s for 1 s
      expect(f.heading, closeTo(210, 0.5));
    });

    test('turning left decreases the heading and wraps through north', () {
      final f = ArOrientationFilter();
      upright(f);
      f.onCompass(10, 15);
      spin(f, y: pi / 6, seconds: 1); // 30°/s left for 1 s
      expect(f.heading, closeTo(340, 0.5));
    });

    test('yaw is taken about world-up even when the camera is pitched', () {
      final f = ArOrientationFilter();
      // Camera pointed 45° down: up = (0, cos45, sin45) * g.
      f.onAccel(0, 9.81 * cos(pi / 4), 9.81 * sin(pi / 4));
      f.onCompass(0, 15);
      // Rotate 90°/s about world-up (spread across device Y and Z).
      final double rate = pi / 2;
      spin(f, y: -rate * cos(pi / 4), z: -rate * sin(pi / 4), seconds: 1);
      expect(f.heading, closeTo(90, 0.5));
    });

    test('ignores gyro before any gravity estimate', () {
      final f = ArOrientationFilter();
      f.onCompass(50, 15);
      spin(f, y: -pi / 2, seconds: 1);
      expect(f.heading, closeTo(50, 1e-9));
    });

    test('ignores implausible dt gaps', () {
      final f = ArOrientationFilter();
      upright(f);
      f.onCompass(50, 15);
      f.onGyro(0, -pi / 2, 0, kMaxGyroDtSeconds + 0.5);
      f.onGyro(0, -pi / 2, 0, 0);
      expect(f.heading, closeTo(50, 1e-9));
    });

    test('learns and cancels a constant gyro bias while still', () {
      final f = ArOrientationFilter();
      upright(f);
      f.onCompass(100, 15);
      // A raw iOS gyro sitting still with a 0.04 rad/s (2.3°/s) bias would
      // walk 46° in 20 s if integrated blindly.
      spin(f, y: 0.04, seconds: 15);
      final double after15 = f.heading;
      spin(f, y: 0.04, seconds: 5);
      expect(signedAngleDelta(100, f.heading).abs(), lessThan(6));
      expect(signedAngleDelta(after15, f.heading).abs(), lessThan(0.01));
    });

    test('sub-degree-per-second noise is not integrated', () {
      final f = ArOrientationFilter();
      upright(f);
      f.onCompass(100, 15);
      spin(f, y: 0.015, seconds: 10); // below kGyroDeadZoneRadPerSec
      expect(f.heading, closeTo(100, 1e-9));
    });

    test('no-gyro mode ignores gyro samples', () {
      final f = ArOrientationFilter(hasGyro: false);
      upright(f);
      f.onCompass(50, 15);
      spin(f, y: -pi / 2, seconds: 1);
      expect(f.heading, closeTo(50, 1e-9));
    });
  });

  group('pitch', () {
    test('upright phone has the camera on the horizon', () {
      final f = ArOrientationFilter();
      upright(f);
      expect(f.pitch, closeTo(0, 1e-9));
    });

    test('phone flat with the screen up points the camera at the ground', () {
      final f = ArOrientationFilter();
      f.onAccel(0, 0, 9.81);
      expect(f.pitch, closeTo(-90, 1e-9));
    });

    test('phone flat with the screen down points the camera at the sky', () {
      final f = ArOrientationFilter();
      f.onAccel(0, 0, -9.81);
      expect(f.pitch, closeTo(90, 1e-9));
    });

    test('top edge leaned away from the user tilts the camera up 45°', () {
      final f = ArOrientationFilter();
      f.onAccel(0, 9.81 * cos(pi / 4), -9.81 * sin(pi / 4));
      expect(f.pitch, closeTo(45, 1e-9));
    });

    test('gyro about +X (top toward the user) tilts the camera down', () {
      final f = ArOrientationFilter();
      upright(f);
      spin(f, x: pi / 4, seconds: 1); // 45°/s for 1 s
      expect(f.pitch, closeTo(-45, 0.5));
    });

    test('accelerometer pulls gyro-integrated pitch back over time', () {
      final f = ArOrientationFilter();
      upright(f);
      spin(f, x: pi / 4, seconds: 1); // drift to -45 while accel says 0
      for (int i = 0; i < 400; i++) {
        upright(f); // ~8 s of "phone is upright"
      }
      expect(f.pitch.abs(), lessThan(0.1));
    });

    test('no-gyro fallback tracks the accelerometer quickly', () {
      final f = ArOrientationFilter(hasGyro: false);
      upright(f);
      for (int i = 0; i < 100; i++) {
        f.onAccel(0, 0, -9.81); // camera to the sky (~2 s at 50 Hz)
      }
      expect(f.pitch, closeTo(90, 1));
    });
  });

  test('pose snapshot mirrors the filter state', () {
    final f = ArOrientationFilter();
    upright(f);
    f.onCompass(42, 30);
    final ArPose p = f.pose;
    expect(p.heading, closeTo(42, 1e-9));
    expect(p.pitch, closeTo(0, 1e-9));
    expect(p.compassAccuracy, 30);
    expect(p.hasGyro, isTrue);
    expect(p.hasCompassFix, isTrue);
  });
}
