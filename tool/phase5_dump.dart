/// Phase 5 user-verifiable artifact (PHASES.md): the traced view, headless.
///
/// Builds the four standing-check scenes, converges the light field on
/// each, and renders the grid as materials (legend) overlaid with a
/// luminance ramp (" .:-=+*#%@" scaled by the field's luminance), so the
/// ASCII picture IS the traced light:
///
///   1_wall.txt           lamp light stops at a one-cell partition
///   2_furniture.txt      the same partition in chair material passes light
///   3_roofed_t100/200/300.txt  roofed pool surface, static across the arc
///   4_open_t150/200/250.txt    open pool, brightest band under the sun
///
/// Run: dart run tool/phase5_dump.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:water_tower/core/lamp.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/sun.dart';
import 'package:water_tower/core/world.dart';
import 'package:water_tower/sim.dart';
import 'package:water_tower/trace/tracer.dart';

const _x0 = 92, _x1 = 212, _y0 = 216, _y1 = 239;

const _legend = {
  Material.air: ' ',
  Material.water: '~',
  Material.ground: 'G',
  Material.concrete: '#',
  Material.rebar: 'R',
  Material.steel: 'S',
  Material.glass: 'g',
  Material.chair: 'c',
  Material.lamp: 'l',
};

/// The luminance ramp: dark to bright, tone-mapped with a square root so
/// lamp light and sky land on distinct characters (~1.5 = a fully lit sky
/// cell, ~2.4 = a glint peak).
const _ramp = ' .:-=+*%#@';
const _rampMax = 2.6;

const _settings = Settings(floors: 30, width: 3, material: 'rebar');

/// Trace [n] frames with the sun frozen at [tSec].
void run(Tracer t, World w, double tSec, int n) {
  final sim = Sim();
  sim.sun.timeSec = tSec;
  for (var i = 0; i < n; i++) {
    t.trace(w, sim.water, sim.sun);
  }
}

/// Render the scene: material glyphs where the cell is solid, the
/// luminance ramp on air/water (the traced light is the picture).
String frame(Tracer t, World w) {
  final buf = StringBuffer();
  for (var y = _y0; y <= _y1; y++) {
    buf.write('y=${y.toString().padLeft(3)} ');
    for (var x = _x0; x <= _x1; x++) {
      final m = w.at(x, y);
      if (m != Material.air && m != Material.water) {
        buf.write(_legend[m] ?? '?');
        continue;
      }
      final lum = t.field.luminance(w.idx(x, y));
      final k = (math.sqrt(lum / _rampMax) * (_ramp.length - 1)).round()
          .clamp(0, _ramp.length - 1);
      buf.write(_ramp[k]);
    }
    buf.write('\n');
  }
  buf.writeln('light ramp:  $_ramp');
  return buf.toString();
}
/// A sealed box (walls to the top row; the sun at t=841 sits low on the
/// right, so it cannot reach the floor beside the lamp) with a one-cell
/// partition at x=195 and a lit lamp at (188, 228).
World boxScene(Material partition) {
  final w = World(_settings, 'phase5');
  w.fillRect(0, 238, 219, 239, Material.ground);
  w.fillRect(180, 0, 180, 237, Material.concrete);
  w.fillRect(210, 0, 210, 237, Material.concrete);
  w.fillRect(180, 0, 210, 0, Material.concrete);
  if (partition != Material.air) {
    w.fillRect(195, 0, 195, 237, partition);
  }
  w.lamps.add(Lamp(LampKind.floor, 188, 228));
  return w;
}

/// A pool in the ground: water x 100..120, y 230..235, concrete sides,
/// ground floor; [roofed] adds a slab at y=226.
World poolScene(bool roofed) {
  final w = World(_settings, 'phase5');
  w.fillRect(0, 236, 219, 239, Material.ground);
  w.fillRect(99, 228, 99, 235, Material.concrete);
  w.fillRect(121, 228, 121, 235, Material.concrete);
  w.fillRect(100, 230, 120, 235, Material.water);
  if (roofed) {
    w.fillRect(98, 226, 122, 226, Material.concrete);
  }
  return w;
}

void dump(String path, String header, Tracer t, World w) {
  File(path).writeAsStringSync('$header\n\n${frame(t, w)}\n');
  stdout.writeln('wrote $path');
}

void main() {
  final out = Directory('out/phase5')
    ..createSync(recursive: true);

  // 1. The lamp's light stops at a one-cell partition (dark far side).
  {
    final w = boxScene(Material.concrete);
    final t = Tracer();
    run(t, w, 841.0, 30);
    dump('${out.path}/1_wall.txt',
        'CHECK 1: a one-cell concrete partition at x=195. The lamp (188, 228) '
        'lights the near side; the far side (x>195) stays dark.',
        t, w);
  }
  // 2. The same partition in chair material: light passes through.
  {
    final w = boxScene(Material.chair);
    final t = Tracer();
    run(t, w, 841.0, 30);
    dump('${out.path}/2_furniture.txt',
        'CHECK 2: the partition is a chair column (furniture). The lamp\'s '
        'light passes through it — the far side is lit.',
        t, w);
  }
  // 3. Roofed pool: the surface is static across the sun's arc.
  for (final tSec in [60.0, 210.0, 360.0]) {
    final w = poolScene(true);
    final t = Tracer();
    run(t, w, tSec, 30);
    dump('${out.path}/3_roofed_t${tSec.toStringAsFixed(0)}.txt',
        'CHECK 3: the pool is roofed (slab at y=226) at t=${tSec.toStringAsFixed(0)}s. '
        'The surface row (y=230, the ~ marks) is the same in all three files — '
        'a roofed surface is static across the sun\'s arc.',
        t, w);
  }
  // 4. Open pool: the brightest band sits under the sun.
  for (final tSec in [180.0, 200.0, 220.0]) {
    final w = poolScene(false);
    final t = Tracer();
    run(t, w, tSec, 30);
    final (sunX, _) = Sun.position(tSec);
    dump('${out.path}/4_open_t${tSec.toStringAsFixed(0)}.txt',
        'CHECK 4: the pool is open at t=${tSec.toStringAsFixed(0)}s (sun at x=${sunX.toStringAsFixed(0)}). '
        'The brightest cells of the surface row (~) sit under the sun; the '
        'band moves between the three files.',
        t, w);
  }
}
