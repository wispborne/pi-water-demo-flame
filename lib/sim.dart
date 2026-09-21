import 'core/buoyancy.dart';
import 'core/constants.dart';
import 'core/sun.dart';
import 'core/structure.dart';
import 'core/tools.dart';
import 'core/water.dart';
import 'core/world.dart';

/// The sim driver (PLAN decision 4): a fixed-timestep accumulator at
/// [Constants.physicsTicksPerSec] (30) ticks per sim-second. Speed is a
/// scale of the sim clock — 0.5x, 1x, 2x (pause = 0) — so every subsystem
/// (water, structure, buoyancy, rain, and the sun) is driven by one clock
/// and scales together; a paused world is exactly frozen.
///
/// [advance] is the single entry point the GUI calls once per frame with
/// the wall-clock delta; [tick] is the single entry point tests call with
/// one full tick.
class Sim {
  final Water water = Water();
  final Structure structure = Structure();
  final Buoyancy buoyancy = Buoyancy();
  final Tools tools = Tools();
  final Sun sun = Sun();

  /// Current speed scale: 0 (paused), 0.5, 1, or 2.
  double speedScale = 1.0;

  /// Wall-time accumulator in fractions of a sim tick.
  double _acc = 0;

  /// One full physics tick: rain, water, structure, buoyancy — and the
  /// sun's clock, which advances by one tick's sim-time ([stepSec]).
  void tick(World w, {double stepSec = 1 / Constants.physicsTicksPerSec}) {
    tools.rainTick(w, stepSec);
    water.tick(w);
    structure.tick(w);
    buoyancy.resync(w);
    buoyancy.tick(w);
    sun.timeSec += stepSec;
  }

  /// Advance the world by the wall-clock [dtSec] at the current
  /// [speedScale]: the accumulator converts wall seconds into fixed ticks,
  /// and every tick advances the sim clock, so 2x runs the world twice as
  /// fast per wall second, and 0 (pause) runs it not at all.
  void advance(World w, double dtSec) {
    _acc += dtSec * speedScale * Constants.physicsTicksPerSec;
    var ticks = _acc.floor();
    if (ticks <= 0) return;
    _acc -= ticks;
    for (var i = 0; i < ticks; i++) {
      tick(w);
    }
  }

  /// The current speed label: '0' (paused), '0.5', '1', '2'.
  String get speedLabel =>
      speedScale == 0 ? '0' : speedScale == 0.5 ? '0.5' : speedScale.toInt().toString();

  /// Cycle the speed 0.5 -> 1 -> 2 (SPEC 9); pause (scale 0) is set
  /// directly.
  void cycleSpeed() {
    switch (speedScale) {
      case 0.5:
        speedScale = 1;
      case 1:
        speedScale = 2;
      default:
        speedScale = 0.5;
    }
  }
}
