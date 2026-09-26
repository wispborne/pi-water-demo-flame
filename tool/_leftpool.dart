/// Headless repro: what sits above the ground on the left of the tower
/// after rain? Dumps that region as ASCII plus the spurt overlay state.
import 'dart:io';

import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/tower.dart';
import 'package:water_tower/core/world.dart';
import 'package:water_tower/sim.dart';

const _legend = {
  Material.air: ' ',
  Material.water: '~',
  Material.ground: 'G',
  Material.concrete: '#',
  Material.rebar: 'R',
  Material.steel: 'S',
  Material.titanium: 'T',
  Material.rubble: 'r',
  Material.debris: 'd',
};

String frame(World w, int x0, int x1, int y0, int y1) {
  final b = StringBuffer();
  for (var y = y0; y <= y1; y++) {
    final row = StringBuffer()..write('y=${y.toString().padLeft(3)}|');
    for (var x = x0; x <= x1; x++) {
      row.write(_legend[w.at(x, y)] ?? '?');
    }
    b.writeln(row);
  }
  b.writeln('      x=$x0..$x1');
  return b.toString();
}

void main(List<String> args) {
  final floors = args.isNotEmpty ? int.parse(args[0]) : 8;
  final bays = args.length > 1 ? int.parse(args[1]) : 3;
  final seed = args.length > 2 ? args[2] : 'demo';
  final ticks = args.length > 3 ? int.parse(args[3]) : 1200;

  final w = WorldBuilder(
    seed,
    Settings(floors: floors, width: bays, material: 'rebar'),
  ).build();
  final sim = Sim()..tools.rain = 40;
  final debug = args.contains('--debug');
  for (var t = 0; t < ticks; t++) {
    if (debug && t % 100 == 0) {
      var maxH = 0;
      for (final s in sim.water.spurts) {
        if (s.h > maxH) maxH = s.h;
      }
      // ignore: avoid_print
      print('t=$t destroyed=${w.destroyedCount} maxSpurtH=$maxH');
    }
    if (debug && t >= ticks - 12) {
      for (final x in const [0, 36, 96, 123]) {
        final s = sim.water.spurts[x];
        var topWater = -1;
        for (var y = 0; y < Constants.gridH; y++) {
          if (w.at(x, y) == Material.water) {
            topWater = y;
            break;
          }
        }
        final above =
            topWater > 0 ? w.at(x, topWater - 1) : Material.air;
        // ignore: avoid_print
        print('t=$t x=$x spurt(h=${s.h},top=${s.top}) '
            'gridTop=$topWater above=${above.name}');
      }
    }
    sim.tick(w);
  }

  final water = w.countWater() + sim.water.totalSpurtCells();
  // ignore: avoid_print
  print('seed=$seed floors=$floors bays=$bays ticks=$ticks '
      'water=$water destroyed=${w.destroyedCount} '
      'groundTopY=${w.groundTopY} tower=${w.towerLeft}..${w.towerRight} '
      'roofY=${w.towerTopY}');

  final spurts = sim.water.spurts
      .asMap()
      .entries
      .where((e) => e.value.active)
      .map((e) => 'x=${e.key}(top=${e.value.top},h=${e.value.h})')
      .join(' ');
  // ignore: avoid_print
  print('active spurts: ${spurts.isEmpty ? 'none' : spurts}');

  final x1 = w.towerRight + 2;
  // ignore: avoid_print
  print('--- rows 20..100 (the sky above the left pool) ---');
  // ignore: avoid_print
  print(frame(w, 0, x1, 20, 100));
  // ignore: avoid_print
  print('--- rows 150..175 (the pool top) ---');
  // ignore: avoid_print
  print(frame(w, 0, x1, 150, 175));
}
