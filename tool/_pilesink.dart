/// Scratch measure: how fast a poured water column spreads (the pile bug),
/// and the per-tick cost on a generated world with a pool and rain.
///
/// Run: dart run tool/_pilesink.dart
import 'dart:io';

import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/water.dart';
import 'package:water_tower/core/world.dart';
import 'package:water_tower/sim.dart';

const _x0 = 60, _x1 = 160, _y0 = 160, _y1 = 239;

const _legend = {
  Material.air: ' ',
  Material.water: '~',
  Material.ground: 'G',
  Material.concrete: '#',
  Material.rubble: 'r',
  Material.debris: 'd',
};

String frame(World w, String title) {
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

/// The tallest water column (consecutive water cells from the floor row up;
/// the floor is row 237 in the pile scenario).
int maxColumnHeight(World w) {
  var best = 0;
  for (var x = 0; x < Constants.gridW; x++) {
    var h = 0;
    for (var y = 237; y >= 0; y--) {
      if (w.at(x, y) == Material.water) {
        h++;
      } else {
        break;
      }
    }
    if (h > best) best = h;
  }
  return best;
}

void main() {
  final out = Directory('out/_pilesink')..createSync(recursive: true);

  // -- 1. pile collapse: a 60-cell column poured at x=110 ----------------
  final w = World(
    const Settings(floors: 1, width: 1, material: 'concrete'),
    'pilesink',
  );
  w.fillRect(0, 238, Constants.gridW - 1, Constants.gridH - 1, Material.ground);
  for (var y = 178; y < 238; y++) {
    w.set(110, y, Material.water);
  }
  final eng = Water();
  final v0 = eng.countWater(w);
  // ignore: avoid_print
  print('pile: 60-cell column at x=110, volume $v0');
  var t = 0;
  for (t = 1; t <= 90; t++) {
    eng.tick(w);
    if (t % 5 == 0 || t <= 3) {
      // ignore: avoid_print
      print('  tick $t: max column height ${maxColumnHeight(w)}');
    }
  }
  if (eng.countWater(w) != v0) {
    // ignore: avoid_print
    print('  VOLUME LOST: ${eng.countWater(w)} != $v0');
  }
  File('${out.path}/pile_t90.txt').writeAsStringSync(
    frame(w, 'pile after 90 ticks'),
  );

  // -- 2. per-tick cost: generated world, pool + rain, settled ----------
  final g = World(
    const Settings(floors: 5, width: 3, material: 'concrete'),
    'pilesink-perf',
  );
  final sim = Sim()..tools.rain = 20;
  sim.advance(g, 2.0); // 60 ticks: the pool fills, rain settles
  final sw = Stopwatch()..start();
  const n = 2000;
  for (var i = 0; i < n; i++) {
    sim.tick(g);
  }
  sw.stop();
  final perTick = sw.elapsedMicroseconds / n;
  final water = g.countWater() + sim.water.totalSpurtCells();
  // ignore: avoid_print
  print(
    'perf: 5-floor world, rain 20 (settling/active), '
    '$n ticks in ${sw.elapsedMilliseconds} ms '
    '(${perTick.toStringAsFixed(1)} us/tick), $water water cells',
  );

  // -- 3. per-tick cost: fully settled (no rain) --------------------------
  final s2 = Sim();
  final g2 = World(
    const Settings(floors: 5, width: 3, material: 'concrete'),
    'pilesink-perf',
  );
  s2.advance(g2, 3.0); // 90 ticks: everything at rest
  final sw2 = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    s2.tick(g2);
  }
  sw2.stop();
  // ignore: avoid_print
  print(
    'perf: settled 5-floor world, '
    '$n ticks in ${sw2.elapsedMilliseconds} ms '
    '(${(sw2.elapsedMicroseconds / n).toStringAsFixed(1)} us/tick)',
  );

  final spread = maxColumnHeight(w);
  // ignore: avoid_print
  print('summary: max height after 90 ticks = $spread (target <= 8)');
  exit(spread <= 8 && perTick < 8000 ? 0 : 1);
}
