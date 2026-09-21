/// Phase 3 user-verifiable artifact (PHASES.md): a headless collapse demo.
///
/// Builds a small scene (two concrete columns + a slab with a ceiling lamp,
/// over a flooded basin with a sofa, a fridge and a TV), severs both columns
/// by a 3-cell gap, and dumps the world as ASCII frames:
///
///   out/phase3/f0_intact.txt      t=0, before severance
///   out/phase3/f1_midslump.txt    mid-slump (the section is breaking)
///   out/phase3/f2_broken.txt      the instant after the section breaks
///   out/phase3/f3_settled.txt     rubble settled, floats at the surface,
///                                 heavies on the floor, lamp down
///
/// Run: dart run tool/phase3_dump.dart
import 'dart:io';

import 'package:water_tower/core/buoyancy.dart';
import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/lamp.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/structure.dart';
import 'package:water_tower/core/water.dart';
import 'package:water_tower/core/world.dart';

const _x0 = 74, _x1 = 126, _y0 = 200, _y1 = 239;

const _legend = {
  Material.air: ' ',
  Material.water: '~',
  Material.ground: 'G',
  Material.concrete: '#',
  Material.titanium: 'T',
  Material.rubble: 'r',
  Material.debris: 'd',
  Material.sofa: 'S',
  Material.fridge: 'F',
  Material.tv: 'V',
  Material.lamp: '*',
};

String frame(World w) {
  final b = StringBuffer();
  b.writeln('30 Floors & a Pool — Phase 3: structure fails, things float');
  b.writeln(
    'legend: # concrete  T titanium  ~ water  G ground  r rubble  '
    'd debris',
  );
  b.writeln('        S sofa  F fridge  V tv  * lamp');
  for (var y = _y0; y <= _y1; y++) {
    var line = y.toString().padLeft(3) + ' ';
    for (var x = _x0; x <= _x1; x++) {
      line += (_legend[w.at(x, y)] ?? '?');
    }
    b.writeln(line);
  }
  return b.toString();
}

void main() {
  final w = World(
    const Settings(floors: 30, width: 3, material: 'concrete'),
    'phase3',
  );
  w.fillRect(0, 238, 219, 239, Material.ground);
  // The structure: two columns + a slab, with a ceiling lamp under it.
  w.fillRect(88, 209, 112, 209, Material.concrete);
  w.set(100, 210, Material.lamp);
  w.lamps.add(
    Lamp(LampKind.ceiling, 100, 210, state: LampState.fixed, lit: true),
  );
  // The flooded basin under the structure.
  w.fillRect(78, 215, 78, 237, Material.titanium);
  w.fillRect(122, 215, 122, 237, Material.titanium);
  w.fillRect(79, 237, 121, 237, Material.titanium);
  w.fillRect(79, 225, 121, 236, Material.water);
  w.fillRect(90, 210, 90, 237, Material.concrete);
  w.fillRect(110, 210, 110, 237, Material.concrete);
  w.fillRect(95, 228, 97, 228, Material.sofa);
  w.fillRect(85, 228, 86, 229, Material.fridge);
  w.set(115, 228, Material.tv);

  final out = Directory('out/phase3')..createSync(recursive: true);
  void dump(String name) {
    final f = frame(w);
    File('${out.path}/$name').writeAsStringSync(f);
    // ignore: avoid_print
    print(f);
    // ignore: avoid_print
    print('');
  }

  final water = Water();
  final structure = Structure();
  final buoy = Buoyancy();
  void tick() {
    water.tick(w);
    structure.tick(w);
    buoy.resync(w);
    buoy.tick(w);
  }

  dump('f0_intact.txt');
  // Sever both columns by a 3-cell gap (rows 232..234): the section above
  // loses its load path.
  w.fillRect(90, 232, 90, 234, Material.air);
  w.fillRect(110, 232, 110, 234, Material.air);
  // Mid-slump: the section is breaking but not broken yet.
  for (var t = 0; t < Constants.slumpTicks ~/ 2; t++) {
    tick();
  }
  dump('f1_midslump.txt');
  // Run to just after the section has broken into rubble.
  for (var t = 0; t < Constants.slumpTicks + 2; t++) {
    tick();
  }
  dump('f2_broken.txt');
  // Let the rubble settle and the water find its level.
  for (var t = 0; t < 400; t++) {
    tick();
  }
  dump('f3_settled.txt');
  final lamp = w.lamps.single;
  // ignore: avoid_print
  print(
    'lamp: $lamp (released: ${lamp.state == LampState.free}, '
    'fell to row ${lamp.y})',
  );
  // ignore: avoid_print
  print(
    'destroyed cells: ${w.destroyedCount}, '
    'rubble: ${[for (final c in w.cells)
      if (c == Material.rubble) 1].length}, '
    'water: ${water.countWater(w)}',
  );
}
