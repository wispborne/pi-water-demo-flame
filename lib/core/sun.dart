import 'constants.dart';

/// The day-sky sun (SPEC 6): a warm disc on a [Constants.sunCycleSec]
/// (420 sim-second) arc — rise, across the sky (passing behind the tower),
/// set, then it loops immediately. The scene never goes dark.
///
/// The sun's position is a pure function of sim time: the sim driver
/// advances [Sun.timeSec] by [speedScale] per tick, so a paused world
/// (scale 0) freezes the sun, and 2x carries it twice as fast as 1x.
class Sun {
  /// Sim-seconds elapsed since cycle start.
  double timeSec = 0;

  /// Sun position as a pure function of [tSec]:
  /// x across the full grid width (rise at the left edge, set at the right,
  /// wrapping each cycle), y an arc that peaks at the top of the sky.
  static (double, double) position(double tSec) {
    final phase = (tSec % Constants.sunCycleSec) / Constants.sunCycleSec;
    // The phase 1..2 tail is the brief gap between set and rise: the disc
    // sits just below the horizon at the right, about to wrap.
    final x = phase <= 1
        ? (phase * (Constants.gridW - 1)).toDouble()
        : Constants.gridW.toDouble();
    final y = (Constants.sunTopY +
            Constants.sunArcDepth * (2 * phase - 1) * (2 * phase - 1))
        .clamp(0.0, (Constants.gridH - 1).toDouble());
    return (x, y);
  }
}
