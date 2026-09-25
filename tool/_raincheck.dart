// Headless repro: a falling drop above a pool in the same column must
// keep the pool's surface point (the pool line must not gap out under
// the drop), while a drop in open sky gets no point. Mirrors the
// painter's column scan in app/lib/render/grid_painter.dart.
// Run: dart run tool/_raincheck.dart
import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/tower.dart';
import 'package:water_tower/core/world.dart';

/// The painter's column scan: top of the first at-rest water run.
int surface(World w, int x) {
  var surf = -1;
  var y = 0;
  while (surf < 0 && y < Constants.gridH) {
    if (w.at(x, y) != Material.water) {
      y++;
      continue;
    }
    var bottom = y;
    while (bottom + 1 < Constants.gridH && w.at(x, bottom + 1) == Material.water) {
      bottom++;
    }
    final below = bottom + 1 < Constants.gridH
        ? w.at(x, bottom + 1)
        : Material.ground;
    if (below == Material.water ||
        Materials.blocksWaterByIndex[below.index]) {
      surf = y;
    }
    y = bottom + 1;
  }
  return surf;
}

void main() {
  final w = WorldBuilder('seed-1', const Settings()).build();

  // Ground surface is y=228; the built world's pool (222..227) spans
  // columns 59..78.
  // Drop above a pool in the same column (the reported case).
  w.set(65, 30, Material.water);
  // Drop in open sky (nothing below in this column).
  w.set(45, 30, Material.water);
  // Pool with a sinking grain inside (top run over a grain, bottom run
  // over the ground): grain at 224 splits 222..227 into 222..223 and 225..227.
  w.set(75, 224, Material.rubble);

  final a = surface(w, 65); // drop + world pool 222..227
  final b = surface(w, 45); // open-sky drop, no pool in column 45
  final c = surface(w, 70); // plain world pool 222..227
  final d = surface(w, 75); // pool split by a grain

  final cols = <int>[];
  for (var x = 0; x < Constants.gridW; x++) {
    if (w.at(x, 222) == Material.water) cols.add(x);
  }
  // ignore: avoid_print
  print('pool cols: $cols');
  // ignore: avoid_print
  print('drop+pool: $a (want 222)  open-sky drop: $b (want -1)  '
      'plain pool: $c (want 222)  pool+grain: $d (want 225)');
  final ok = a == 222 && b == -1 && c == 222 && d == 225;
  // ignore: avoid_print
  print(ok ? 'PASS' : 'FAIL');
}
