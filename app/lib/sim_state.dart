import 'dart:math' as math;

import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/tools.dart';
import 'package:water_tower/core/tower.dart';
import 'package:water_tower/core/world.dart';
import 'package:water_tower/sim.dart';
import 'package:water_tower/trace/tracer.dart';

/// The app's simulation state: the seeded world, the traced-light state,
/// the tool settings, and the view switches. Pure Dart (testable
/// headless): the Flame layer only renders and routes input.
class SimState {
  SimState(this.seed) {
    settings = const Settings();
    _rebuild();
  }

  /// The seed name (shared string; a blank name yields a random one).
  String seed;

  late Settings settings;
  late World world;
  late Sim sim;
  late Tracer tracer;
  bool _paused = false;
  bool get paused => _paused;
  set paused(bool v) {
    _paused = v;
    sim.speedScale = speedScale;
  }
  int _speedIndex = 1; // 0 = 0.5x, 1 = 1x, 2 = 2x
  int get speedIndex => _speedIndex;
  set speedIndex(int v) {
    _speedIndex = v;
    sim.speedScale = speedScale;
  }
  bool glow = true;
  bool pathTrace = false; // the traced view (SPEC 7: default off, ADR 0004)

  double fps = 0;

  Tools get tools => sim.tools;

  Tool get tool => sim.tools.tool;

  String get speedLabel => paused ? '0' : ['0.5', '1', '2'][speedIndex];
  double get speedScale => paused ? 0.0 : [0.5, 1.0, 2.0][speedIndex];

  int get waterCount => sim.water.countWater(world);

  /// Building damage %: damaged structural cells / the original total
  /// (SPEC 10).
  double get damagePercent => world.originalStructuralCount == 0
      ? 0
      : (world.originalStructuralCount - world.countStructural()) * 100 /
          world.originalStructuralCount;

  void togglePause() => paused = !paused;

  void cycleSpeed() {
    if (paused) return; // pause is its own state (SPEC 9)
    speedIndex = (speedIndex + 1) % 3;
  }

  void toggleGlow() => glow = !glow;

  void togglePathTrace() => pathTrace = !pathTrace;

  /// The sliders: the world is rebuilt at t=0 (SPEC 2/9). One rebuild
  /// per settings change (the HUD debounces slider drag to one call).
  void applySettings(int? floors, int? width, String? material) =>
      _setSettings(floors: floors, width: width, material: material);

  void setBrush(int v) => sim.tools.brushSize = v;

  void setRain(int v) => sim.tools.rain = v;

  /// Reset: rebuild the current seed, exact t=0 (SPEC 9).
  void reset() => _rebuild();

  /// New seed: a fresh seed (a random name when the name is blank).
  void newSeed([String? name]) {
    final n = (name ?? '').trim();
    seed = n.isEmpty ? _randomSeed() : n;
    _rebuild();
  }

  void _setSettings({int? floors, int? width, String? material}) {
    settings = Settings.validate(
      floors: floors ?? settings.floors,
      width: width ?? settings.width,
      material: material ?? settings.material,
    );
    _rebuild();
  }

  void _rebuild() {
    settings = Settings.validate(
      floors: settings.floors,
      width: settings.width,
      material: settings.material,
    );
    world = WorldBuilder(seed, settings).build();
    sim = Sim();
    tracer = Tracer();
    sim.speedScale = speedScale;
  }
}

String _randomSeed() =>
    'seed-${math.Random().nextInt(1 << 30).toRadixString(16).padLeft(8, '0')}';
