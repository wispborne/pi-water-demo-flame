/// Phase 4 user-verifiable artifact (PHASES.md): a headless timeline demo.
///
/// Builds a small scene (a concrete column, a rebar block, a pool), then:
///   * plots the sun's 420 s arc (rise -> peak -> set, looping),
///   * hammers the column cell by cell until it breaks into rubble,
///   * bombs the rebar block (decaying falloff; two blasts destroy the core),
///   * rains at 30 cells/s at 0.5x / 1x / 2x for the same sim-time and
///     shows the sim clock (and the water) advancing at the right rate.
///
/// Writes to out/phase4/:
///   timeline.txt         the full text timeline (sun arc + damage + rain)
///   f0_initial.txt       the scene at t=0
///   f1_hammered.txt      after the column is hammered into rubble
///   f2_bombed.txt        after two bombs on the rebar block
///   f3_rain_1x.txt       after 3 sim-seconds of rain driven at 1x
///   f3_rain_half.txt     1.5 wall-seconds driven at 0.5x (half the water)
///   f3_rain_2x.txt       1.5 wall-seconds driven at 2x (double the water)
///
/// Run: dart run tool/phase4_dump.dart
import 'dart:io';

import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/sun.dart';
import 'package:water_tower/core/tools.dart';
import 'package:water_tower/core/world.dart';
import 'package:water_tower/sim.dart';

const _x0 = 92, _x1 = 199, _y0 = 198, _y1 = 239;

const _legend = {
  Material.air: ' ',
  Material.water: '~',
  Material.ground: 'G',
  Material.concrete: '#',
  Material.rebar: 'R',
  Material.steel: 'S',
  Material.rubble: 'r',
  Material.debris: 'd',
};

String frame(World w) {
  final b = StringBuffer();
  b.writeln('30 Floors & a Pool — Phase 4: sun, tools, sim driver');
  b.writeln(
    'legend: # concrete  R rebar  ~ water  G ground  r rubble  d debris',
  );
  for (var y = _y0; y <= _y1; y++) {
    final row = StringBuffer()
      ..write('y=${y.toString().padLeft(3)}|');
    for (var x = _x0; x <= _x1; x++) {
      row.write(_legend[w.at(x, y)] ?? '?');
    }
    b.writeln(row);
  }
  b.writeln('      x=${_x0}..$_x1');
  return b.toString();
}

/// The demo scene: a concrete column, a rebar block, and an empty pool.
World scene() {
  final w = World(
    const Settings(floors: 1, width: 1, material: 'concrete'),
    'phase4',
  );
  w.fillRect(0, 230, 219, 239, Material.ground);
  w.fillRect(100, 206, 100, 229, Material.concrete); // the column
  w.fillRect(135, 221, 147, 229, Material.rebar); // the bomb target (13x9)
  w.fillRect(170, 220, 170, 229, Material.concrete); // pool walls + floor
  w.fillRect(194, 220, 194, 229, Material.concrete);
  w.fillRect(171, 229, 193, 229, Material.concrete);
  return w;
}

/// Plot the sun's full arc as a small ASCII sky (width 56, height 9):
/// 12 samples from rise to set, plus the wrap (the set-to-rise tail).
String sunArc() {
  const cols = 56, rows = 9;
  final grid = List.generate(rows, (_) => List.filled(cols, ' '));
  const samples = 13;
  for (var i = 0; i < samples; i++) {
    final t = Constants.sunCycleSec * i / (samples - 1);
    final (px, py) = Sun.position(t);
    final c = (px / (Constants.gridW - 1) * (cols - 1)).round();
    final r = ((py / (Constants.sunTopY + Constants.sunArcDepth)) *
            (rows - 1))
        .clamp(0, rows - 1)
        .round();
    grid[r][c] = 'o';
  }
  final b = StringBuffer()
    ..writeln('sun arc (420 s cycle; o = the disc, left = rise, right = set)');
  for (final row in grid) {
    b.writeln('|${row.join('')}|');
  }
  b.writeln('|${'-' * cols}|');
  return b.toString();
}

void main() {
  final out = Directory('out/phase4')..createSync(recursive: true);
  final text = StringBuffer();
  void dump(String name, World w, String label) {
    final f = frame(w);
    File('${out.path}/$name').writeAsStringSync(f);
    text.writeln('=== $label ===\n');
    text.writeln(f);
    // ignore: avoid_print
    print(f);
    // ignore: avoid_print
    print('');
  }

  var w = scene();
  dump('f0_initial.txt', w, 't=0: the scene');

  text.writeln(sunArc());
  text.writeln();

  // -- hammer: 8 hits on the column (concrete hp 8) -------------------
  final sim = Sim();
  sim.tools.tool = Tool.hammer;
  for (var i = 1; i <= 8; i++) {
    sim.tools.apply(w, 100, 210);
    text.writeln(
      'hammer hit $i: cell (100,210) '
      '${w.at(100, 210) == Material.concrete ? 'strength '
          '${w.strength[w.idx(100, 210)]}'
        : w.at(100, 210)}',
    );
  }
  for (var t = 0; t < 60; t++) {
    sim.tick(w); // the rubble falls into place
  }
  dump('f1_hammered.txt', w, 'after 8 hammer hits: the column cells broke');

  // -- bomb: two blasts on the rebar block -----------------------------
  sim.tools.selectByKey(1); // key 2 -> bomb
  sim.tools.apply(w, 141, 225);
  text.writeln(
    'bomb 1: centre strength ${w.strength[w.idx(141, 225)]}, '
    'edge (146,225) strength ${w.strength[w.idx(146, 225)]}, '
    'outside (147,225) strength ${w.strength[w.idx(147, 225)]}',
  );
  sim.tools.apply(w, 141, 225);
  text.writeln(
    'bomb 2: the core ${w.at(141, 225)}, destroyed cells '
    '${w.destroyedCount}',
  );
  for (var t = 0; t < 60; t++) {
    sim.tick(w);
  }
  dump('f2_bombed.txt', w, 'after 2 bombs: the core is rubble');

  // -- rain at 0.5x / 1x / 2x: 3 sim-seconds each ----------------------
  // 3 sim-seconds of rain = 90 drops at 30 cells/s.
  text.writeln(
    'rain at 30 cells/s, 3 sim-seconds each '
    '(0.5x takes 6 wall-seconds, 1x takes 3, 2x takes 1.5):',
  );
  for (final (scale, wallSec, name) in [
    (0.5, 6.0, 'f3_rain_half.txt'),
    (1.0, 3.0, 'f3_rain_1x.txt'),
    (2.0, 1.5, 'f3_rain_2x.txt'),
  ]) {
    final rw = scene();
    final rs = Sim()
      ..speedScale = scale
      ..tools.rain = 30;
    rs.advance(rw, wallSec);
    final water = rw.countWater() + rs.water.totalSpurtCells();
    text.writeln(
      '  ${scale}x: ${wallSec} wall-seconds -> sun at '
      '${rs.sun.timeSec.toStringAsFixed(2)} sim-s, $water water cells',
    );
    if (scale == 1.0) {
      dump(name, rw, 'after 3 sim-seconds of rain at 1x');
    } else {
      File('${out.path}/$name').writeAsStringSync(frame(rw));
    }
  }

  File('${out.path}/timeline.txt').writeAsStringSync(text.toString());
  // ignore: avoid_print
  print(text);
}
