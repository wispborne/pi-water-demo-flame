// Headless repro: what do the rain columns contain in the grid?
// Run: dart run tool/_raincheck.dart
import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/tower.dart';
import 'package:water_tower/sim.dart';

void main() {
  final w = WorldBuilder('seed-1', const Settings())
      .build(); // floors 30, width 6, rebar — matches the screenshot
  final sim = Sim()..tools.rain = 17;

  // Single-drop fall speed probe: drop in an empty column, watch it.
  w.set(5, 0, Material.water);
  for (var t = 0; t < 10; t++) {
    var y = -1;
    for (var yy = 0; yy < Constants.gridH; yy++) {
      if (w.at(5, yy) == Material.water) {
        y = yy;
        break;
      }
    }
    // ignore: avoid_print
    print('probe t=$t drop at y=$y');
    sim.tick(w);
  }

  // Now 20 sim-seconds of rain at the screenshot's rate.
  for (var t = 0; t < 600; t++) {
    sim.tick(w);
  }

  // ignore: avoid_print
  print('water in grid: ${w.countWater()}');
  final ranges = <String>[];
  for (var x = 0; x < Constants.gridW; x++) {
    var top = -1,
        bottom = -1,
        n = 0;
    for (var y = 0; y < Constants.gridH; y++) {
      if (w.at(x, y) == Material.water) {
        if (top < 0) top = y;
        bottom = y;
        n++;
      }
    }
    if (n > 0) {
      ranges.add('x=$x top=$top bottom=$bottom n=$n');
    }
  }
  // ignore: avoid_print
  print('columns with water: ${ranges.length}');
  for (final r in ranges) {
    // ignore: avoid_print
    print(r);
  }
}
