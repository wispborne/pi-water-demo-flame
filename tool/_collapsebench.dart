// Throwaway: reproduce the collapse freeze. Builds the largest tower
// (50 floors x 10 bays), breaks the foundation (3 rows of base structure),
// and times sim ticks through the full 60-tick slump + rubble settle.
import 'dart:io';

import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/tower.dart';
import 'package:water_tower/core/world.dart';
import 'package:water_tower/sim.dart';

void main() {
  final settings = const Settings(floors: 50, width: 10, material: 'rebar');
  final world = WorldBuilder('seed-1', settings).build();
  final sim = Sim();

  // Warm up: 1 second of idle sim (water settles, sun advances).
  for (var i = 0; i < 30; i++) {
    sim.tick(world);
  }

  final structural = world.countStructural();
  // Break the foundation: the base slab row plus the 2 rows above it
  // (the wall bases), so the whole tower loses its load path (gap >= 3).
  var broken = 0;
  for (var dy = 0; dy < 3; dy++) {
    final y = world.towerBottomY - dy;
    for (var x = world.towerLeft; x <= world.towerRight; x++) {
      if (Materials.structure.contains(world.at(x, y))) {
        world.cells[world.idx(x, y)] = Material.air;
        world.strength[world.idx(x, y)] = 0;
        broken++;
      }
    }
  }
  stdout.writeln('structure=$structural broken=$broken');

  var maxMs = 0.0;
  var sumMs = 0.0;
  const ticks = 300; // 10 sim-seconds: full slump + rubble settle
  for (var t = 0; t < ticks; t++) {
    final sw = Stopwatch()..start();
    sim.tick(world);
    sw.stop();
    final ms = sw.elapsedMicroseconds / 1000;
    if (ms > maxMs) maxMs = ms;
    sumMs += ms;
    if (t % 30 == 0 || ms > 5.0) {
      stdout.writeln(
        't=${t} ${ms.toStringAsFixed(2)} ms  '
        'slumping=${sim.structure.slumping.length} '
        'rubble=${_count(world, Material.rubble)}',
      );
    }
  }
  stdout.writeln(
    'avg=${(sumMs / ticks).toStringAsFixed(2)} ms/tick '
    'max=${maxMs.toStringAsFixed(2)} ms/tick',
  );
}

int _count(World w, Material m) {
  var n = 0;
  for (final c in w.cells) {
    if (c == m) n++;
  }
  return n;
}
