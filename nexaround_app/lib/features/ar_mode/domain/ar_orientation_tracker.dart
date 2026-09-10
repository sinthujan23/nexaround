import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Where the back camera is pointing, fused from gyroscope + accelerometer +
/// compass so AR cards track the phone at gyro rate (~50 Hz) instead of the
/// laggy, jittery compass-only heading we had before.
///
/// Axis conventions (sensors_plus normalises iOS to match Android):
///   X = right across the screen, Y = up the screen, Z = out of the screen
///   toward the user. The back camera looks along -Z. Gyroscope is rad/s,
///   right-hand rule about each axis. The accelerometer at rest reports the
///   *up* vector (+9.81 on whichever axis points at the sky).
///
/// [kYawSign] / [kPitchSign] are the first thing to flip if the on-device
/// check shows cards moving the wrong way: turning right must slide cards
/// left, tilting the camera up must slide cards down.

/// Rotation about world-up is positive counter-clockwise seen from above
/// (turning left), while compass heading grows clockwise — hence -1.
const double kYawSign = -1.0;

/// Positive rotation about +X tips the top of the phone toward the user,
/// which points the back camera down — hence -1 for "elevation".
const double kPitchSign = -1.0;

/// How hard each compass reading pulls the gyro-integrated heading back
/// toward it. Android's compass is already sensor-fused and fires 20–50×/s so
/// this locks in well under a second; iOS fires ~1–10×/s and the gyro covers
/// the gaps.
const double kCompassGain = 0.1;

/// If the compass disagrees with the integrated heading by more than this for
/// [kCompassSnapStreak] consecutive readings, the gyro has drifted (or the
/// phone was moved while paused) and we snap instead of slewing.
const double kCompassSnapDegrees = 45.0;
const int kCompassSnapStreak = 5;

/// Low-pass on the accelerometer used as the gravity estimate. Higher =
/// faster but more shake from walking.
const double kGravityAlpha = 0.1;

/// Per-accelerometer-tick pull of the gyro-integrated pitch toward the
/// accelerometer's absolute pitch (drift correction).
const double kPitchAccelBlend = 0.02;

/// Fallback smoothing when the device has no gyroscope: plain low-pass on the
/// compass / accelerometer (replaces the old 0.2 which lagged badly).
const double kCompassOnlyAlpha = 0.35;
const double kPitchOnlyAlpha = 0.3;

/// Ignore gyro gaps longer than this (app paused, sensor stall) rather than
/// integrating one huge step.
const double kMaxGyroDtSeconds = 0.1;

/// Raw gyroscopes (iOS hands us uncalibrated CMGyroData) carry a constant
/// bias that would walk the heading a few degrees per second while the phone
/// sits still. Below this rate (rad/s, ~3°/s) we treat the phone as still and
/// slowly learn the bias, which is then subtracted from every sample.
const double kGyroStillRadPerSec = 0.05;
const double kGyroBiasAlpha = 0.005;

/// Bias-corrected rates below this (rad/s, ~1°/s) are sensor noise, not
/// motion, and are not integrated — the compass owns very slow drift.
const double kGyroDeadZoneRadPerSec = 0.02;

const double _radToDeg = 180.0 / pi;

/// Normalise any angle to [0, 360).
double wrapDegrees(double degrees) {
  double d = degrees % 360.0;
  if (d < 0) d += 360.0;
  return d;
}

/// Signed angular distance from [from] to [to] in degrees, normalised to
/// (-180, 180]. Positive = [to] is clockwise (right) of [from].
double signedAngleDelta(double from, double to) {
  double d = (to - from) % 360.0;
  if (d > 180) d -= 360;
  if (d <= -180) d += 360;
  return d;
}

/// Immutable snapshot of the camera orientation.
@immutable
class ArPose {
  /// Compass heading of the back camera, degrees 0..360, 0 = north.
  final double heading;

  /// Elevation of the camera's optical axis above the horizon, degrees.
  /// Positive = pointing up at the sky, negative = down at the ground.
  final double pitch;

  /// Last reported compass accuracy in degrees (null = unknown).
  final double? compassAccuracy;

  /// False when the device has no usable gyroscope and we fell back to
  /// compass + accelerometer only.
  final bool hasGyro;

  /// True once the first compass reading has been applied; before that the
  /// heading is meaningless (0 = north by default).
  final bool hasCompassFix;

  const ArPose({
    required this.heading,
    required this.pitch,
    required this.compassAccuracy,
    required this.hasGyro,
    required this.hasCompassFix,
  });

  static const ArPose initial = ArPose(
    heading: 0,
    pitch: 0,
    compassAccuracy: null,
    hasGyro: true,
    hasCompassFix: false,
  );
}

/// The fusion maths, kept free of streams so it can be unit-tested with
/// synthetic sensor data.
class ArOrientationFilter {
  ArOrientationFilter({
    this.maxUsableCompassAccuracy = 35.0,
    this.hasGyro = true,
  });

  /// Compass readings with a reported accuracy worse than this are not used
  /// to correct the heading (the gyro keeps relative motion right meanwhile).
  final double maxUsableCompassAccuracy;

  bool hasGyro;

  double heading = 0.0;
  double pitch = 0.0;
  double? compassAccuracy;
  bool hasCompassFix = false;

  // Gravity (= "up") estimate in device coordinates, low-passed accelerometer.
  double _gx = 0.0, _gy = 0.0, _gz = 0.0;
  bool _hasGravity = false;
  // Learned gyroscope bias (rad/s), see [kGyroStillRadPerSec].
  double _bx = 0.0, _by = 0.0, _bz = 0.0;
  bool _hasPitch = false;
  int _snapStreak = 0;

  ArPose get pose => ArPose(
        heading: heading,
        pitch: pitch,
        compassAccuracy: compassAccuracy,
        hasGyro: hasGyro,
        hasCompassFix: hasCompassFix,
      );

  /// Forget the compass fix so the next reading snaps straight to it. Call
  /// when the AR view comes back after being hidden — the phone may have been
  /// turned any amount while we weren't integrating.
  void reset() {
    hasCompassFix = false;
    _snapStreak = 0;
  }

  /// Accelerometer sample (m/s², Android sign convention: up is positive).
  void onAccel(double x, double y, double z) {
    if (x.isNaN || y.isNaN || z.isNaN) return;
    if (!_hasGravity) {
      _gx = x;
      _gy = y;
      _gz = z;
      _hasGravity = true;
    } else {
      _gx += (x - _gx) * kGravityAlpha;
      _gy += (y - _gy) * kGravityAlpha;
      _gz += (z - _gz) * kGravityAlpha;
    }
    final double n = sqrt(_gx * _gx + _gy * _gy + _gz * _gz);
    if (n < 1e-3) return;

    // Camera looks along -Z; its elevation is the angle between -Z and the
    // horizontal plane, i.e. asin(dot(-Z, up)).
    final double accelPitch = asin((-_gz / n).clamp(-1.0, 1.0)) * _radToDeg;
    if (!_hasPitch) {
      pitch = accelPitch;
      _hasPitch = true;
    } else if (hasGyro) {
      pitch += (accelPitch - pitch) * kPitchAccelBlend;
    } else {
      pitch += (accelPitch - pitch) * kPitchOnlyAlpha;
    }
  }

  /// Gyroscope sample (rad/s about device X/Y/Z) integrated over [dtSeconds].
  void onGyro(double x, double y, double z, double dtSeconds) {
    if (!hasGyro || !_hasGravity) return;
    if (x.isNaN || y.isNaN || z.isNaN || dtSeconds.isNaN) return;
    if (dtSeconds <= 0 || dtSeconds > kMaxGyroDtSeconds) return;

    final double n = sqrt(_gx * _gx + _gy * _gy + _gz * _gz);
    if (n < 1e-3) return;

    // Learn the bias while the phone is (nearly) still, then remove it.
    final double cx = x - _bx, cy = y - _by, cz = z - _bz;
    if (sqrt(cx * cx + cy * cy + cz * cz) < kGyroStillRadPerSec) {
      _bx += cx * kGyroBiasAlpha;
      _by += cy * kGyroBiasAlpha;
      _bz += cz * kGyroBiasAlpha;
    }
    final double rx = x - _bx, ry = y - _by, rz = z - _bz;

    // Component of angular velocity about world-up: this is the yaw rate no
    // matter how the phone is tilted (upright, looking down at the ground…).
    final double yawRate = (rx * _gx + ry * _gy + rz * _gz) / n;
    if (yawRate.abs() >= kGyroDeadZoneRadPerSec) {
      heading =
          wrapDegrees(heading + kYawSign * yawRate * dtSeconds * _radToDeg);
    }

    // Pitch rate is rotation about the device's right-pointing X axis. Good
    // enough while the phone is held roughly portrait; the accelerometer
    // blend in onAccel keeps it honest over time.
    if (rx.abs() >= kGyroDeadZoneRadPerSec) {
      pitch += kPitchSign * rx * dtSeconds * _radToDeg;
      pitch = pitch.clamp(-90.0, 90.0);
    }
  }

  /// Compass reading in degrees (0 = north) with optional accuracy.
  void onCompass(double headingDeg, double? accuracy) {
    if (headingDeg.isNaN) return;
    compassAccuracy = accuracy;

    if (!hasCompassFix) {
      // First fix: snap even if accuracy is poor — a rough heading beats
      // opening the AR view pointing at "north" and slewing round.
      heading = wrapDegrees(headingDeg);
      hasCompassFix = true;
      _snapStreak = 0;
      return;
    }

    if (accuracy != null && accuracy > maxUsableCompassAccuracy) return;

    final double delta = signedAngleDelta(heading, headingDeg);

    if (!hasGyro) {
      heading = wrapDegrees(heading + delta * kCompassOnlyAlpha);
      return;
    }

    if (delta.abs() > kCompassSnapDegrees) {
      _snapStreak++;
      if (_snapStreak >= kCompassSnapStreak) {
        heading = wrapDegrees(headingDeg);
        _snapStreak = 0;
        return;
      }
    } else {
      _snapStreak = 0;
    }
    heading = wrapDegrees(heading + delta * kCompassGain);
  }
}

/// Owns the sensor subscriptions and publishes [ArPose] snapshots on [pose].
/// Listen with a `ValueListenableBuilder` around the AR marker layer only, so
/// the ~50 Hz stream never rebuilds the rest of the page.
class ArOrientationTracker {
  ArOrientationTracker({double maxUsableCompassAccuracy = 35.0})
      : _filter = ArOrientationFilter(
          maxUsableCompassAccuracy: maxUsableCompassAccuracy,
        );

  final ArOrientationFilter _filter;
  final ValueNotifier<ArPose> pose = ValueNotifier<ArPose>(ArPose.initial);

  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<CompassEvent>? _compassSub;
  DateTime? _lastGyroAt;
  bool _running = false;
  bool _disposed = false;

  bool get isRunning => _running;

  /// Forget the compass fix so the next reading re-snaps. Safe while stopped.
  void reset() {
    _filter.reset();
    _lastGyroAt = null;
  }

  void start() {
    if (_running || _disposed) return;
    _running = true;
    _lastGyroAt = null;

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((e) {
      _filter.onAccel(e.x, e.y, e.z);
      // With no gyro the accelerometer is the only thing moving pitch, so it
      // has to publish; with a gyro the gyro tick publishes ~50×/s already.
      if (!_filter.hasGyro) _publish();
    }, onError: (Object _) {});

    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((e) {
      final DateTime now = e.timestamp;
      final DateTime? prev = _lastGyroAt;
      _lastGyroAt = now;
      if (prev != null) {
        final double dt = now.difference(prev).inMicroseconds / 1e6;
        _filter.onGyro(e.x, e.y, e.z, dt);
      }
      _publish();
    }, onError: (Object err) {
      // Device without a gyroscope (or the sensor failed): fall back to the
      // compass + accelerometer path instead of freezing.
      debugPrint('ArOrientationTracker: gyroscope unavailable ($err)');
      _filter.hasGyro = false;
      _gyroSub?.cancel();
      _gyroSub = null;
      _publish();
    });

    final Stream<CompassEvent>? compass = FlutterCompass.events;
    _compassSub = compass?.listen((e) {
      final double? h = e.heading;
      if (h == null) return;
      _filter.onCompass(h, e.accuracy);
      if (!_filter.hasGyro) _publish();
    }, onError: (Object _) {});
  }

  void stop() {
    if (!_running) return;
    _running = false;
    _gyroSub?.cancel();
    _accelSub?.cancel();
    _compassSub?.cancel();
    _gyroSub = null;
    _accelSub = null;
    _compassSub = null;
    _lastGyroAt = null;
  }

  void dispose() {
    stop();
    _disposed = true;
    pose.dispose();
  }

  /// Skip publishing sub-visible changes so a phone lying still doesn't
  /// rebuild the marker layer 50×/s on sensor noise.
  static const double _publishThresholdDegrees = 0.05;

  void _publish() {
    if (!_running || _disposed) return;
    final ArPose prev = pose.value;
    final ArPose next = _filter.pose;
    final bool moved =
        signedAngleDelta(prev.heading, next.heading).abs() >=
                _publishThresholdDegrees ||
            (next.pitch - prev.pitch).abs() >= _publishThresholdDegrees;
    final bool flagsChanged = prev.hasGyro != next.hasGyro ||
        prev.hasCompassFix != next.hasCompassFix ||
        prev.compassAccuracy != next.compassAccuracy;
    if (!moved && !flagsChanged) return;
    pose.value = next;
  }
}
