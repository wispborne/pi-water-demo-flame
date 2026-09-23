import 'package:test/test.dart';
import 'package:water_tower/core/buoyancy.dart';
import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/lamp.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/structure.dart';
import 'package:water_tower/core/water.dart';
import 'package:water_tower/core/world.dart';

/// Phase 3 contract (PHASES.md): structural failure (a severed section
/// slumps into rubble over ~2 s; a small gap still bridges) and buoyancy
/// (floats rise to the surface, heavies sink, water is displaced, ceiling
/// lamps release when their slab breaks).

World ground() {
  final w = World(
    const Settings(floors: 30, width: 3, material: 'concrete'),
    'phase3',
  );
  w.fillRect(0, 238, 219, 239, Material.ground);
  return w;
}

/// Slab x 98..102 at row 229 + grounded column at x=100, so the load path
/// between slab and column is exactly [gap] air cells (column rows
/// 229+gap..237).
void buildColumnSlab(World w, Material m, int gap) {
  w.fillRect(98, 229, 102, 229, m);
  w.fillRect(100, 230 + gap, 100, 237, m);
}

/// Drive water (optional) + structure + buoyancy for [n] ticks.
void drive(World w, Water? water, Structure s, int n) {
  final buoy = Buoyancy();
  for (var t = 0; t < n; t++) {
    water?.tick(w);
    s.tick(w);
    buoy.resync(w);
    buoy.tick(w);
  }
}

int countMaterial(World w, Material m) {
  var n = 0;
  for (final c in w.cells) {
    if (c == m) n++;
  }
  return n;
}

int countAtRow(World w, Material m, int y) {
  var n = 0;
  for (var x = 0; x < Constants.gridW; x++) {
    if (w.at(x, y) == m) n++;
  }
  return n;
}

int countMaterialWithX(World w, Material m, int xmin) {
  var n = 0;
  for (var i = 0; i < w.cells.length; i++) {
    if (w.cells[i] == m && i % Constants.gridW >= xmin) n++;
  }
  return n;
}

void main() {
  test('severing the load path by 3 cells slumps the slab into rubble', () {
    final w = ground();
    buildColumnSlab(w, Material.concrete, 3);
    drive(w, null, Structure(), Constants.slumpTicks + 40);
    // The grounded column stays; the severed slab breaks cell by cell.
    expect(countMaterial(w, Material.concrete), 5);
    expect(countMaterial(w, Material.rubble), 5);
    expect(w.destroyedCount, 5);
    // The rubble has fallen out of the slab row, into the gap.
    expect(countAtRow(w, Material.rubble, 229), 0);
    expect(w.at(100, 232), Material.rubble); // piled on the column top
  });

  test('a 2-cell support gap still bridges: nothing breaks', () {
    final w = ground();
    buildColumnSlab(w, Material.concrete, 2);
    drive(w, null, Structure(), 2 * Constants.slumpTicks);
    expect(countMaterial(w, Material.rubble), 0);
    expect(w.destroyedCount, 0);
    expect(w.at(100, 229), Material.concrete);
  });

  test(
    'flooded room: sofa floats up, fridge and TV sink, volume conserved',
    () {
      final w = ground();
      // Titanium basin (tolerance 40 > head 36: no erosion): walls x=80/120
      // rows 199..237, floor row 237.
      w.fillRect(80, 199, 80, 237, Material.titanium);
      w.fillRect(120, 199, 120, 237, Material.titanium);
      w.fillRect(81, 237, 119, 237, Material.titanium);
      w.fillRect(81, 200, 119, 236, Material.water);
      w.fillRect(95, 230, 97, 230, Material.sofa);
      w.fillRect(85, 205, 86, 206, Material.fridge);
      w.set(110, 205, Material.tv);
      final water = Water();
      final before = water.countWater(w);
      drive(w, water, Structure(), 300);
      // The sofa rests at the surface: air above, water below.
      expect(w.at(96, 200), Material.sofa);
      expect(w.at(96, 199), Material.air);
      expect(w.at(96, 201), Material.water);
      // The heavy items reach the basin floor (row 236, above floor 237).
      expect(w.at(85, 236), Material.fridge);
      expect(w.at(86, 236), Material.fridge);
      expect(w.at(110, 236), Material.tv);
      // Water only moved, never appeared or vanished.
      expect(water.countWater(w), before);
      // The basin itself is untouched.
      expect(w.at(80, 237), Material.titanium);
      expect(w.destroyedCount, 0);
    },
  );

  test('broken structure becomes rubble (the heavy broken form)', () {
    final wc = ground();
    buildColumnSlab(wc, Material.concrete, 3);
    drive(wc, null, Structure(), Constants.slumpTicks + 40);
    expect(countMaterial(wc, Material.rubble), 5);
    expect(countMaterial(wc, Material.debris), 0);
    expect(wc.destroyedCount, 5);
  });

  test('granular debris submerged under water floats to the surface', () {
    final w = ground();
    w.fillRect(80, 199, 80, 237, Material.titanium);
    w.fillRect(120, 199, 120, 237, Material.titanium);
    w.fillRect(81, 237, 119, 237, Material.titanium);
    w.fillRect(81, 200, 119, 236, Material.water);
    w.set(100, 210, Material.debris);
    final water = Water();
    drive(w, water, Structure(), 200);
    expect(w.at(100, 200), Material.debris);
    expect(w.at(100, 210), Material.water);
    expect(water.countWater(w), 1442);
  });

  test('falling rubble drops at the settling rate, not one cell per tick',
      () {
    final w = ground();
    // 137 cells above the floor: a 1-cell-per-tick grain could not reach it
    // within 60 ticks.
    w.set(100, 100, Material.rubble);
    drive(w, null, Structure(), 60);
    expect(
      w.at(100, 237),
      Material.rubble,
      reason: 'rubble had not reached the floor within 60 ticks',
    );
  });

  test('a ceiling lamp is released when its slab breaks and falls lit', () {
    final w = ground();
    w.fillRect(98, 229, 102, 229, Material.concrete); // unsupported slab
    w.set(100, 230, Material.lamp);
    w.lamps.add(
      Lamp(LampKind.ceiling, 100, 230, state: LampState.fixed, lit: true),
    );
    drive(w, null, Structure(), Constants.slumpTicks + 60);
    final lamp = w.lamps.single;
    expect(lamp.state, LampState.free);
    expect(lamp.lit, isTrue);
    expect(lamp.y, greaterThan(230));
    expect(w.at(lamp.x, lamp.y), Material.lamp);
  });
  test('deep water washes rubble sideways out of a vertical column', () {
    final w = ground();
    // Floor + left wall (titanium, head 11 < tolerance 40: no erosion), open
    // to the right.
    w.fillRect(80, 237, 119, 237, Material.titanium);
    w.fillRect(80, 220, 80, 237, Material.titanium);
    // Water body on the left: x 81..98, surface row 225 (head 11).
    w.fillRect(81, 225, 98, 236, Material.water);
    // Rubble column at x=99, rows 226..236 (sticking up into the pool).
    w.fillRect(99, 226, 99, 236, Material.rubble);
    final water = Water();
    final before = water.countWater(w);
    drive(w, water, Structure(), 300);
    // Volume conserved: water and rubble only move, never appear/vanish.
    expect(water.countWater(w), before);
    expect(countMaterial(w, Material.rubble), 11);
    // The wash: rubble no longer sits in a single vertical column — some of
    // it has been pushed sideways out of the x=99 line.
    expect(countMaterialWithX(w, Material.rubble, 100), greaterThan(0));
  });
}
