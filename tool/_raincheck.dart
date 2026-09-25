// Headless repro: a falling TV (1 cell/tick) holds a water cell above it
// (blocked, so it falls at 1/tick too). A rain drop (6 cells/tick) in the
// same column catches up and lands on it -> a 2-cell water column in the
// mid sky. Evaluates: old test, current fix (top cell over water/wall),
// extended fix (first non-water under the run is a permanent wall).
import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/tower.dart';
import 'package:water_tower/core/world.dart';
import 'package:water_tower/sim.dart';

void main() {
  final w = WorldBuilder('seed-1', const Settings()).build();
  final sim = Sim();

  // A free TV in the open sky with a water cell riding above it, plus a
  // rain drop in the same column.
  w.set(100, 100, Material.tv);
  w.set(100, 98, Material.water);
  w.set(100, 0, Material.water);
  sim.buoyancy.resync(w);

  for (var t = 0; t < 120; t++) {
    sim.tick(w);
    if (t % 10 == 0) {
      final sb = StringBuffer('t=$t col100:');
      for (var y = 90; y < 130; y++) {
        final m = w.at(100, y);
        if (m == Material.air) continue;
        sb.write(' ${y}:${m.name}');
      }
      for (var y = 0; y < 90; y++) {
        if (w.at(100, y) != Material.air) {
          sb.write(' hi${y}:${w.at(100, y).name}');
        }
      }
      // ignore: avoid_print
      print(sb);
    }
    // Find the water run in column 100 in the mid sky.
    int top = -1, bottom = -1;
    for (var y = 0; y < 120; y++) {
      if (w.at(100, y) == Material.water) {
        if (top < 0) top = y;
        bottom = y;
      }
    }
    if (top < 0 || bottom - top < 1) continue; // no multi-cell column yet
    final belowRun = bottom + 1 < Constants.gridH ? w.at(100, bottom + 1) : Material.ground;
    final tv = w.at(100, bottom + 2);
    final oldFlag = w.at(100, top + 1) != Material.air;
    final curFlag = w.at(100, top + 1) == Material.water ||
        Materials.blocksWaterByIndex[w.at(100, top + 1).index];
    final extFlag = Materials.blocksWaterByIndex[belowRun.index] ||
        belowRun == Material.ground;
    // ignore: avoid_print
    print('t=$t run y=$top..$bottom belowRun=$belowRun '
        '(tv@=${tv.name}@${bottom + 2}) old=$oldFlag cur=$curFlag ext=$extFlag');
    if (t > 60) break;
  }
}
