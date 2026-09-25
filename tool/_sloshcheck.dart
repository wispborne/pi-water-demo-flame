/// Scratch measure: the damped surface motion (SPEC 4/7). A calm pool's
/// surface is flat; a poured column and rain stir it into ripples that
/// decay to flat again; the motion is deterministic and conserves volume.
///
/// Run: dart run tool/_sloshcheck.dart
import 'dart:io';

import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/water.dart';
import 'package:water_tower/core/world.dart';
import 'package:water_tower/sim.dart';

const _x0 = 90, _x1 = 141, _y0 = 195, _y1 = 239;

const _legend = {
  Material.air: ' ',
  Material.water: '~',
  Material.ground: 'G',
  Material.concrete: '#',
  Material.rubble: 'r',
  Material.debris: 'd',
};

/// The contained pool: walls at x=95 and x=136 (rows 230..237), ground
/// floor, 40 columns of water 4 rows deep (rows 234..237).
World pool() {
  final w = World(
    const Settings(floors: 30, width: 3, material: 'concrete'),
    'slosh',
  );
  w.fillRect(0, 238, Constants.gridW - 1, Constants.gridH - 1, Material.ground);
  w.fillRect(95, 230, 95, 237, Material.concrete);
  w.fillRect(136, 230, 136, 237, Material.concrete);
  for (var x = 96; x < 136; x++) {
    for (var y = 234; y < 238; y++) {
      w.set(x, y, Material.water);
    }
  }
  return w;
}

int maxAbs(Water eng) {
  var m = 0;
  for (var x = 0; x < Constants.gridW; x++) {
    final e = eng.elev[x];
    if (e.abs() > m) m = e.abs();
  }
  return m;
}

/// The surface displacement line: rows of 1/4 cell (+1..-1), '~' marks the
/// per-column offset; the 's' line marks each column's at-rest surface
/// relative to the shallowest column in the frame.
String surfLine(Water eng, String title) {
  final b = StringBuffer()..writeln(title);
  for (var r = 4; r >= -4; r--) {
    final row = StringBuffer()
      ..write('d=${(r / 4.0).toStringAsFixed(2).padLeft(5)}|');
    for (var x = _x0; x <= _x1; x++) {
      final d = (eng.elev[x] / 4).clamp(-4, 4).round();
      row.write(d == r ? '~' : ' ');
    }
    b.writeln(row);
  }
  var minSurf = Constants.gridH;
  for (var x = _x0; x <= _x1; x++) {
    if (eng.surfRow[x] >= 0 && eng.surfRow[x] < minSurf) {
      minSurf = eng.surfRow[x];
    }
  }
  final srow = StringBuffer()..write('        s|');
  for (var x = _x0; x <= _x1; x++) {
    final s = eng.surfRow[x];
    srow.write(s < 0 ? ' ' : (s - minSurf).toString().padLeft(2) + 'o');
  }
  b.writeln(srow);
  b.writeln('         x=${_x0}..$_x1');
  return b.toString();
}

String gridFrame(World w, String title) {
  final b = StringBuffer()..writeln(title);
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

/// One pour run from a fresh world: settle, pour a 34-cell column at
/// x=115, tick 240 more. Returns the per-tick (maxAbs, elevSum) trace so
/// two runs can be compared for determinism.
(List<String>, int) pourRun() {
  final w = pool();
  final eng = Water();
  for (var t = 0; t < 30; t++) eng.tick(w);
  for (var y = 200; y < 234; y++) {
    w.set(115, y, Material.water);
  }
  final trace = <String>[];
  for (var t = 1; t <= 240; t++) {
    eng.tick(w);
    var sum = 0;
    for (var x = 0; x < Constants.gridW; x++) {
      sum += eng.elev[x];
    }
    trace.add('${maxAbs(eng)}:$sum');
  }
  return (trace, eng.countWater(w));
}

void main() {
  final out = Directory('out/_sloshcheck')..createSync(recursive: true);
  var fail = false;

  // -- 1. settled pool: the surface is exactly flat ----------------------
  {
    final w = pool();
    final eng = Water();
    for (var t = 0; t < 200; t++) eng.tick(w);
    final m = maxAbs(eng);
    // ignore: avoid_print
    print('settled: max |d| = ${m / 16.0} cell after 200 ticks (target 0)');
    if (m != 0) fail = true;
    File('${out.path}/settled_t200.txt')
        .writeAsStringSync(surfLine(eng, 'settled pool, tick 200'));
  }

  // -- 2. poured column: stirs, decays, conserves -------------------------
  {
    final w = pool();
    final eng = Water();
    final v0 = eng.countWater(w);
    for (var t = 0; t < 30; t++) eng.tick(w);
    for (var y = 200; y < 234; y++) {
      w.set(115, y, Material.water);
    }
    var peak = 0;
    var decayedAt = -1;
    for (var t = 1; t <= 240; t++) {
      eng.tick(w);
      final m = maxAbs(eng);
      if (m > peak) peak = m;
      if (decayedAt < 0 && t > 60 && m < 2) decayedAt = t;
      if (t == 12) {
        File('${out.path}/pour_t12_grid.txt')
            .writeAsStringSync(gridFrame(w, 'pour at tick 12'));
        File('${out.path}/pour_t12_surf.txt')
            .writeAsStringSync(surfLine(eng, 'pour, tick 12'));
      }
      if (t % 30 == 0) {
        // ignore: avoid_print
        print('  tick $t: max |d| = ${(m / 16.0).toStringAsFixed(3)} cell');
      }
    }
    final v1 = eng.countWater(w);
    // ignore: avoid_print
    print(
      'pour: peak |d| = ${(peak / 16.0).toStringAsFixed(3)} cell, '
      'flat (|d| < 1/8 cell) at tick $decayedAt, volume $v0 -> $v1 '
      '(+34 poured)',
    );
    if (peak < 4) fail = true; // < 1/4 cell: the pour did not stir
    if (v1 != v0 + 34) fail = true;
    if (decayedAt < 0 || decayedAt > 180) fail = true;
    File('${out.path}/pour_t240_surf.txt')
        .writeAsStringSync(surfLine(eng, 'pour, tick 240'));
  }

  // -- 3. rain: the pool surface is stirred by the falling drops ----------
  {
    final w = pool();
    final sim = Sim()..tools.rain = 40;
    for (var i = 0; i < 120; i++) sim.tick(w); // 4 sim seconds
    final m = maxAbs(sim.water);
    // ignore: avoid_print
    print('rain: after 4 s at 40/s, max |d| = ${(m / 16.0).toStringAsFixed(3)} cell');
    if (m <= 0) fail = true;
    File('${out.path}/rain_t120_surf.txt')
        .writeAsStringSync(surfLine(sim.water, 'rain, tick 120'));
  }

  // -- 4. determinism: the pour run twice is the same, tick for tick ------
  {
    final (a, va) = pourRun();
    final (b, vb) = pourRun();
    var same = va == vb;
    for (var t = 0; t < a.length && same; t++) {
      if (a[t] != b[t]) same = false;
    }
    // ignore: avoid_print
    print('determinism: ${a.length}-tick pour trace identical = $same');
    if (!same) fail = true;
  }

  // ignore: avoid_print
  print('summary: ${fail ? 'FAIL' : 'ok'}');
  exit(fail ? 1 : 0);
}
