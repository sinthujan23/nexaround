import 'dart:math';

/// Pure pinhole-camera projection used to pin AR place cards to the live
/// camera image. Nothing here clamps to the screen: a place that sits outside
/// the lens's field of view projects to a coordinate outside the screen, and
/// it is the caller's job to cull it — that is what makes a card glide off the
/// edge as the phone turns (instead of sticking to the edge and popping).
///
/// One focal length is used for both axes (square pixels), so a card moves at
/// exactly the same rate as the camera image whether the phone pans or tilts.

/// Horizontal field of view of the camera *as shown on screen*. Phones vary
/// 60–75° at the sensor, and the preview is cropped with BoxFit.cover, so 65°
/// is a safe visible-on-screen default. Tune this if cards consistently lead
/// or trail the real place while panning.
const double kCameraFovDegrees = 65.0;

/// Elevation (degrees above the horizon) at which the nearest card floats.
const double kLiftNearDegrees = 2.0;

/// Elevation at which the farthest card floats. Far places drift up into the
/// sky, near ones hug the horizon, which layers cards by depth like Live View.
const double kLiftFarDegrees = 18.0;

/// Camera pitch at which the horizon sits at the exact screen centre. People
/// naturally hold a phone tilted a little downward, so a small negative bias
/// keeps the card band in the clear middle of the screen at a natural grip
/// instead of tucked under the top HUD. Vertical motion still tracks the
/// camera 1:1 — this only shifts the zero point. Set to 0 for strictly
/// physical placement.
const double kHorizonPitchBiasDegrees = -8.0;

/// Beyond this angle off-centre `tan()` explodes and the value is meaningless;
/// anything this far round is off-screen at any sane FOV anyway.
const double kMaxProjectableAngleDegrees = 80.0;

const double _degToRad = pi / 180.0;

/// Focal length in pixels for a screen [screenW] px wide: the distance from
/// the eye to the image plane such that the half-FOV lands on the screen edge.
double focalPx(double screenW, {double fovDegrees = kCameraFovDegrees}) {
  return (screenW / 2) / tan((fovDegrees / 2) * _degToRad);
}

/// Screen X (px, unclamped) of a target [dAzimuthDeg] degrees clockwise of the
/// camera's heading. 0° is the screen centre; positive = right of centre.
/// Returns null when the target is so far round that projection is undefined.
double? screenXForAngle(
  double dAzimuthDeg,
  double screenW, {
  double fovDegrees = kCameraFovDegrees,
}) {
  if (dAzimuthDeg.isNaN || dAzimuthDeg.abs() >= kMaxProjectableAngleDegrees) {
    return null;
  }
  return screenW / 2 +
      tan(dAzimuthDeg * _degToRad) * focalPx(screenW, fovDegrees: fovDegrees);
}

/// Screen Y (px, unclamped) of a target [elevationDeg] degrees above the
/// horizon when the camera itself is pitched [pitchDeg] above the horizon.
/// Tilting the camera up (pitch increases) moves every target *down* the
/// screen, exactly like the camera image. Returns null when the relative
/// angle is outside the projectable range. See [kHorizonPitchBiasDegrees]
/// for [pitchBiasDegrees].
double? screenYForElevation(
  double elevationDeg,
  double pitchDeg,
  double screenW,
  double screenH, {
  double fovDegrees = kCameraFovDegrees,
  double pitchBiasDegrees = kHorizonPitchBiasDegrees,
}) {
  final double rel = elevationDeg - (pitchDeg - pitchBiasDegrees);
  if (rel.isNaN || rel.abs() >= kMaxProjectableAngleDegrees) return null;
  return screenH / 2 -
      tan(rel * _degToRad) * focalPx(screenW, fovDegrees: fovDegrees);
}

/// Elevation (degrees above the horizon) a card should float at for a place
/// [distanceM] metres away, given the farthest place in the set is [maxDistM]
/// away. Log-scaled so a cluster of nearby places still spreads out instead
/// of piling on the horizon. Always within [kLiftNearDegrees, kLiftFarDegrees].
double liftDegreesForDistance(double distanceM, double maxDistM) {
  if (maxDistM <= 1.0 || distanceM.isNaN) return kLiftNearDegrees;
  final double d = distanceM.clamp(0.0, maxDistM);
  final double norm = (log(d + 1) / log(maxDistM + 1)).clamp(0.0, 1.0);
  return kLiftNearDegrees + norm * (kLiftFarDegrees - kLiftNearDegrees);
}
