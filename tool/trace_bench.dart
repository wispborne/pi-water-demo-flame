/// Headless tracer benchmark: steady-state per-frame trace cost on a
/// mid-game world (30-floor tower, settled pool, lit lamps, sun mid-arc),
/// against the 33 ms frame budget at 30 ticks/s.
///
/// Run: dart run tool/trace_bench.dart

import 'package:water_tower/core/lamp.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/world.dart';
import 'package:water_tower/sim.dart';
import 'package:water_tower/trace/tracer.dart';

void main() {
  const settings = Settings(floors: 30, width: 3, material: 'rebar');
  final w = World(settings, 'bench');
  final sim = Sim();
  // Settle the world (pool fill, rubble) so the bench measures a
  // realistic mid-game scene.
  for (var i = 0; i < 30 * 60; i++) {
    sim.tick(w);
  }
  sim.sun.timeSec = 105.0; // sun mid-arc
  // Lit lamps (the sweep is built per lit lamp per frame): a spread of
  // ceiling and floor lamps as the tower generation would place.
  for (final (lx, ly) in [(50, 40), (110, 90), (150, 150), (80, 200)]) {
    w.lamps.add(Lamp(LampKind.ceiling, lx, ly));
  }

  final t = Tracer();
  final sw = Stopwatch()..start();
  t.trace(w, sim.water, sim.sun);
  final firstMs = sw.elapsedMicroseconds / 1000;

  var totalUs = 0;
  var lastRays = 0;
  const n = 30;
  for (var i = 0; i < n; i++) {
    sw.reset();
    sw.start();
    t.trace(w, sim.water, sim.sun);
    totalUs += sw.elapsedMicroseconds;
    lastRays = t.budget.lastFrameRays;
  }
  final steadyMs = totalUs / n / 1000;

  print('world: ${w.lamps.length} lamps, settled, sun mid-arc t=105s');
  print('first frame (rebuild + full re-sample): ${firstMs.toStringAsFixed(1)} ms');
  print('steady frame (2,500-ray budget): ${steadyMs.toStringAsFixed(2)} ms  ($lastRays rays)');
  print('frame budget at 30 ticks/s: 33.3 ms');
  print(steadyMs < 33.3 ? 'OK: within budget' : 'OVER BUDGET');
}
