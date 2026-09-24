// Headless repro: a released ceiling lamp falls and the traced light
// follows it, with the per-frame ray cost staying at the 2,500 cap
// (regression check for the budget fallback that killed the traced view
// mid-fall: a moving lamp dirtied ~20,000 cells, cost ~27,000 rays/frame,
// and the fallback never recovered because record() only ran in trace()).
//
// Builds the app's default world (seed 'seed-1'), releases the highest
// ceiling lamp (clearing the slab above it and the column below), and runs
// 240 frames of (sim tick + trace) exactly like the GUI at 1x.
import 'package:water_tower/core/lamp.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/tower.dart';
import 'package:water_tower/sim.dart';
import 'package:water_tower/trace/tracer.dart';

void main() {
  final world = WorldBuilder('seed-1', const Settings()).build();
  final sim = Sim();
  final t = Tracer();

  // Settle the field with the world frozen (like the app's first seconds).
  for (var i = 0; i < 90; i++) {
    t.trace(world, sim.water, sim.sun);
  }

  var lamp = world.lamps.firstWhere((l) => l.kind == LampKind.ceiling);
  for (final l in world.lamps) {
    if (l.kind == LampKind.ceiling && l.y < lamp.y) lamp = l;
  }
  final start = (lamp.x, lamp.y);
  world.set(lamp.x, lamp.y - 1, Material.air);
  for (var y = lamp.y + 1; y < world.groundTopY; y++) {
    world.set(lamp.x, y, Material.air);
  }
  print('released ceiling lamp at $start, ground at ${world.groundTopY}');

  var over = 0;
  for (var f = 1; f <= 240; f++) {
    sim.tick(world);
    // The GUI only traces while the traced view is active.
    if (!t.budget.fellBack) {
      t.trace(world, sim.water, sim.sun);
    }
    if (t.budget.lastFrameRays > TraceBudget.cap) over++;
    if (f % 20 == 0) {
      print(
          'f=$f lamp=(${lamp.x},${lamp.y}) fellBack=${t.budget.fellBack} '
          'rays=${t.budget.lastFrameRays} '
          'lum@lamp=${t.field.luminance(world.idx(lamp.x, lamp.y)).toStringAsFixed(2)} '
          'lum@start=${t.field.luminance(world.idx(start.$1, start.$2)).toStringAsFixed(2)}');
    }
  }
  print('frames over the ray cap: $over; fellBack at the end: '
      '${t.budget.fellBack}');
}
