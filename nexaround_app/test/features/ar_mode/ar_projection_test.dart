import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexaround_app/features/ar_mode/domain/ar_projection.dart';

void main() {
  const double w = 400;
  const double h = 800;

  group('screenXForAngle', () {
    test('centre of view lands at the screen centre', () {
      expect(screenXForAngle(0, w), closeTo(w / 2, 1e-9));
    });

    test('half the FOV lands exactly on the screen edge', () {
      expect(screenXForAngle(kCameraFovDegrees / 2, w), closeTo(w, 1e-6));
      expect(screenXForAngle(-kCameraFovDegrees / 2, w), closeTo(0, 1e-6));
    });

    test('is symmetric about the centre', () {
      for (final a in [5.0, 15.0, 30.0, 45.0]) {
        final double right = screenXForAngle(a, w)! - w / 2;
        final double left = w / 2 - screenXForAngle(-a, w)!;
        expect(right, closeTo(left, 1e-9));
      }
    });

    test('is NOT clamped: a place past the FOV projects off-screen', () {
      expect(screenXForAngle(40, w)!, greaterThan(w));
      expect(screenXForAngle(-40, w)!, lessThan(0));
    });

    test('is monotonic so cards never cross while panning', () {
      double prev = screenXForAngle(-70, w)!;
      for (double a = -69; a <= 70; a += 1) {
        final double x = screenXForAngle(a, w)!;
        expect(x, greaterThan(prev));
        prev = x;
      }
    });

    test('returns null beyond the projectable range', () {
      expect(screenXForAngle(kMaxProjectableAngleDegrees, w), isNull);
      expect(screenXForAngle(-kMaxProjectableAngleDegrees, w), isNull);
      expect(screenXForAngle(150, w), isNull);
      expect(screenXForAngle(double.nan, w), isNull);
    });
  });

  group('screenYForElevation', () {
    test('horizon sits at the screen centre with no bias', () {
      expect(
        screenYForElevation(0, 0, w, h, pitchBiasDegrees: 0),
        closeTo(h / 2, 1e-9),
      );
    });

    test('horizon sits at the screen centre at the biased pitch', () {
      expect(
        screenYForElevation(0, kHorizonPitchBiasDegrees, w, h),
        closeTo(h / 2, 1e-9),
      );
    });

    test('tilting the camera UP moves targets DOWN the screen', () {
      final double level = screenYForElevation(5, 0, w, h)!;
      final double tiltedUp = screenYForElevation(5, 10, w, h)!;
      expect(tiltedUp, greaterThan(level));
    });

    test('a target above the horizon is drawn above the centre', () {
      final double y = screenYForElevation(10, 0, w, h, pitchBiasDegrees: 0)!;
      expect(y, lessThan(h / 2));
    });

    test('uses the same focal length as the horizontal axis', () {
      // 10° up should move exactly as many pixels as 10° right.
      final double dy =
          h / 2 - screenYForElevation(10, 0, w, h, pitchBiasDegrees: 0)!;
      final double dx = screenXForAngle(10, w)! - w / 2;
      expect(dy, closeTo(dx, 1e-9));
      expect(dx, closeTo(tan(10 * pi / 180) * focalPx(w), 1e-9));
    });

    test('returns null beyond the projectable range', () {
      expect(screenYForElevation(0, 85, w, h, pitchBiasDegrees: 0), isNull);
    });
  });

  group('liftDegreesForDistance', () {
    test('stays within [near, far]', () {
      for (final d in [0.0, 1.0, 50.0, 500.0, 5000.0, 20000.0]) {
        final double lift = liftDegreesForDistance(d, 5000);
        expect(lift, greaterThanOrEqualTo(kLiftNearDegrees));
        expect(lift, lessThanOrEqualTo(kLiftFarDegrees));
      }
    });

    test('nearest place hugs the horizon, farthest floats highest', () {
      expect(liftDegreesForDistance(0, 5000), closeTo(kLiftNearDegrees, 1e-9));
      expect(
        liftDegreesForDistance(5000, 5000),
        closeTo(kLiftFarDegrees, 1e-9),
      );
    });

    test('is monotonic in distance', () {
      double prev = liftDegreesForDistance(0, 5000);
      for (double d = 10; d <= 5000; d += 10) {
        final double lift = liftDegreesForDistance(d, 5000);
        expect(lift, greaterThanOrEqualTo(prev));
        prev = lift;
      }
    });

    test('degenerate max distance falls back to the near lift', () {
      expect(liftDegreesForDistance(10, 0), closeTo(kLiftNearDegrees, 1e-9));
      expect(liftDegreesForDistance(10, 1), closeTo(kLiftNearDegrees, 1e-9));
    });
  });
}
