import 'package:test/test.dart';
import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/water.dart';
import 'package:water_tower/core/world.dart';

/// Phase 2 contract (PHASES.md): water falls, flows, exerts per-body pressure
/// that erodes material; the pool reaches equilibrium; volume is conserved.
///
/// Scenarios build on a bare (ungenerated) world + a ground slab so the
/// geometry is exact and independent of the seeded tower.
void main() {
  World bare() =>
      World(const Settings(floors: 30, width: 3, material: 'concrete'), 'phase2');

  /// Fill rows [topY]..239 with ground (the scenario floor).
  void ground(World w, int topY) {
    w.fillRect(0, topY, Constants.gridW - 1, Constants.gridH - 1, Material.ground);
  }

  int _surfaceRow(World w, int x) {
    for (var y = 0; y < Constants.gridH; y++) {
      if (w.at(x, y) == Material.water) return y;
    }
    return -1;
  }

  test('a spawned water column falls and settles at the basin floor', () {
    final w = bare();
    ground(w, 238);
    w.fillRect(100, 210, 100, 237, Material.titanium);
    w.fillRect(110, 210, 110, 237, Material.titanium);
    for (var y = 210; y < 234; y++) {
      w.set(105, y, Material.water);
    }
    final eng = Water();
    for (var t = 0; t < 300; t++) eng.tick(w);
    for (var i = 0; i < w.cells.length; i++) {
      if (w.cells[i] != Material.water) continue;
      final y = i ~/ Constants.gridW;
      expect(y, greaterThanOrEqualTo(230),
          reason: 'water cell at row $y above the basin floor');
    }
  });

  test('a contained pool reaches a level surface at exactly its depth', () {
    final w = bare();
    ground(w, 238);
    w.fillRect(95, 230, 95, 237, Material.concrete);
    w.fillRect(136, 230, 136, 237, Material.concrete);
    for (var x = 96; x < 136; x++) {
      for (var y = 234; y < 238; y++) {
        w.set(x, y, Material.water);
      }
    }
    final eng = Water();
    for (var t = 0; t < 200; t++) eng.tick(w);
    var topRow = 999, total = 0, inExtent = true;
    for (var x = 0; x < Constants.gridW; x++) {
      for (var y = 228; y < 238; y++) {
        if (w.at(x, y) != Material.water) continue;
        total++;
        if (y < topRow) topRow = y;
        if (x < 96 || x > 135) inExtent = false;
      }
    }
    expect(total, 160, reason: 'pool volume changed: $total != 160');
    expect(topRow, 234, reason: 'surface not level at the fill row');
    expect(inExtent, isTrue, reason: 'water leaked outside the basin walls');
  });

  test('a thin sheet running off a wall pushes with the deep body\'s head', () {
    final w = bare();
    ground(w, 238);
    // A 30-deep reservoir (x 10..29, rows 208..237) with titanium walls and a
    // 1-wide outlet at the bottom row; a 9-cell channel ends at a glass
    // partition (tolerance 2 << body head 29).
    w.fillRect(9, 208, 9, 237, Material.titanium);
    w.fillRect(30, 208, 30, 236, Material.titanium);
    for (var x = 10; x < 30; x++) {
      for (var y = 208; y < 238; y++) {
        w.set(x, y, Material.water);
      }
    }
    w.set(40, 237, Material.glass);
    final eng = Water();
    for (var t = 0; t < 800; t++) eng.tick(w);
    expect(w.at(40, 237), isNot(Material.glass),
        reason: 'the sheet did not erode the low-tolerance partition');
    expect(w.destroyedCount, greaterThanOrEqualTo(1));
  });

  test('a wall whose tolerance exceeds the head is untouched', () {
    final w = bare();
    ground(w, 238);
    // An 8-deep tank; the right wall is steel (tolerance 30 > head 8).
    w.fillRect(9, 230, 9, 237, Material.concrete);
    w.fillRect(21, 230, 21, 237, Material.steel);
    for (var x = 10; x < 21; x++) {
      for (var y = 230; y < 238; y++) {
        w.set(x, y, Material.water);
      }
    }
    final eng = Water();
    for (var t = 0; t < 400; t++) eng.tick(w);
    for (var y = 230; y < 238; y++) {
      expect(w.at(21, y), Material.steel,
          reason: 'steel wall eroded at row $y under head 8');
    }
  });

  test('a wall whose tolerance is below the head erodes', () {
    final w = bare();
    ground(w, 238);
    // Same 8-deep tank, right wall glass (tolerance 2 < head 8).
    w.fillRect(9, 230, 9, 237, Material.concrete);
    w.fillRect(21, 230, 21, 237, Material.glass);
    for (var x = 10; x < 21; x++) {
      for (var y = 230; y < 238; y++) {
        w.set(x, y, Material.water);
      }
    }
    final eng = Water();
    for (var t = 0; t < 400; t++) eng.tick(w);
    var eroded = false;
    for (var y = 230; y < 238; y++) {
      if (w.at(21, y) != Material.glass) eroded = true;
    }
    expect(eroded, isTrue, reason: 'glass wall survived head 8');
  });

  test('a confined body with head >= 8 jets upward out of an open crack', () {
    final w = bare();
    ground(w, 238);
    // A 16-deep tank (x 20..39, rows 222..237) under a titanium roof
    // (confined), with a single open crack at (20, 221).
    w.fillRect(19, 222, 19, 237, Material.titanium);
    w.fillRect(40, 222, 40, 237, Material.titanium);
    for (var x = 19; x < 41; x++) {
      w.set(x, 221, Material.titanium);
    }
    w.set(20, 221, Material.air);
    for (var x = 20; x < 40; x++) {
      for (var y = 222; y < 238; y++) {
        w.set(x, y, Material.water);
      }
    }
    final eng = Water();
    for (var t = 0; t < 400; t++) eng.tick(w);
    final s = eng.spurts[20];
    final surf = _surfaceRow(w, 20);
    expect(s.active, isTrue, reason: 'no spurt at the crack column');
    expect(s.h, greaterThanOrEqualTo(5), reason: 'spurt too short: ${s.h}');
    expect(s.h, lessThanOrEqualTo(
        (16 ~/ 2) > Constants.jetMaxHeight ? Constants.jetMaxHeight : 16 ~/ 2));
    // The spurt column is contiguous on top of the dropping pool surface.
    expect(s.top, surf - s.h,
        reason: 'spurt top ${s.top} != surface $surf minus height ${s.h}');
    expect(eng.isSpurtCell(20, surf - 1), isTrue);
    expect(eng.isSpurtCell(20, s.top), isTrue);
  });

  test('water volume is conserved (grid + spurt overlay) over a long run', () {
    final w = bare();
    ground(w, 238);
    w.fillRect(104, 200, 104, 237, Material.titanium);
    w.fillRect(106, 200, 106, 237, Material.titanium);
    for (var y = 200; y < 224; y++) {
      w.set(105, y, Material.water);
    }
    final eng = Water();
    final v0 = eng.countWater(w);
    for (var t = 0; t < 500; t++) {
      eng.tick(w);
      expect(eng.countWater(w), v0,
          reason: 'volume changed at tick $t: ${eng.countWater(w)} != $v0');
    }
  });
}
