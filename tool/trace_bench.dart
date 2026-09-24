/// Headless tracer benchmark: steady-state per-frame trace cost on the real
/// generated world (30-floor, 6-bay rebar tower with its full lamp set and
/// pool water), against the 33 ms frame budget at 30 ticks/s.
///
/// Run: dart run tool/trace_bench.dart

import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/tower.dart';
import 'package:water_tower/sim.dart';
import 'package:water_tower/trace/tracer.dart';

void main() {
  final w = WorldBuilder('seed-1', const Settings()).build();
  final sim = Sim();
  // Settle the world (pool fill, rubble) so the bench measures a
  // realistic mid-game scene.
  for (var i = 0; i < 30 * 60; i++) {
    sim.tick(w);
  }
  sim.sun.timeSec = 105.0; // sun mid-arc

  final t = Tracer();
  final sw = Stopwatch()..start();
  t.trace(w, sim.water, sim.sun);
  final firstMs = sw.elapsedMicroseconds / 1000;

  // Warm-up frames: the lamp sweeps build once here, so the steady frames
  // below measure what the app pays per frame.
  for (var i = 0; i < 5; i++) {
    t.trace(w, sim.water, sim.sun);
  }

  var totalUs = 0;
  var lastRays = 0;
  var maxUs = 0;
  const n = 30;
  for (var i = 0; i < n; i++) {
    sw.reset();
    sw.start();
    sim.tick(w); // the app ticks the sim in the same frame
    t.trace(w, sim.water, sim.sun);
    final us = sw.elapsedMicroseconds;
    totalUs += us;
    if (us > maxUs) maxUs = us;
    lastRays = t.budget.lastFrameRays;
  }
  final steadyMs = totalUs / n / 1000;

  print(
    'world: ${w.lamps.length} lamps, settled pool, sun mid-arc t=105s',
  );
  print('first frame (rebuild + full re-sample): ${firstMs.toStringAsFixed(1)} ms');
  print(
    'steady frame (2,500-ray budget): ${steadyMs.toStringAsFixed(2)} ms  '
    '(max ${maxUs.toStringAsFixed(1)} ms, $lastRays rays)',
  );
  print('frame budget at 30 ticks/s: 33.3 ms');
  print(steadyMs < 33.3 ? 'OK: within budget' : 'OVER BUDGET');
}
