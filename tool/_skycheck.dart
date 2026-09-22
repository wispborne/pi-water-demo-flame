// Throwaway: reproduce the black right-side sky from the GUI screenshot.
// Builds the same world the app boots with (floors 30, width 3, rebar,
// seed 'seed-1'), advances the sim to ~10 sim-seconds (sun left, like the
// screenshot), settles the traced field, and dumps the whole 220x240 light
// field as a luminance ramp so the black region is visible in ASCII.
import 'dart:io';
import 'dart:math' as math;

import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/tower.dart';
import 'package:water_tower/core/sun.dart';
import 'package:water_tower/core/water.dart';
import 'package:water_tower/sim.dart';
import 'package:water_tower/trace/tracer.dart';

const _ramp = ' .:-=+*%#@';
const _rampMax = 2.6;

const _mat = {
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

void main() {
  final settings = const Settings();
  final world = WorldBuilder('seed-1', settings).build();
  final sim = Sim();
  // ~10 sim-seconds (matches the screenshot's sun position, ~4.8% of cycle).
  for (var i = 0; i < 300; i++) {
    sim.tick(world);
  }
  final t = Tracer();
  final w = Water();
  // Settle: ~5s of tracing at the sun's current position (world frozen).
  for (var i = 0; i < 150; i++) {
    t.trace(world, w, sim.sun);
  }
  final (sx, sy) = Sun.position(sim.sun.timeSec);
  stdout.writeln('t=${sim.sun.timeSec}  sun=($sx,$sy)');

  final lbuf = StringBuffer();
  for (var y = 0; y < Constants.gridH; y += 2) {
    for (var x = 0; x < Constants.gridW; x++) {
      final lum = t.field.luminance(world.idx(x, y));
      final k = (math.sqrt((lum / _rampMax).clamp(0.0, 1.0)) *
              (_ramp.length - 1))
          .round()
          .clamp(0, _ramp.length - 1);
      lbuf.write(_ramp[k]);
    }
    lbuf.write('\n');
  }
  stdout.writeln('--- light field (y step 2) ---');
  stdout.writeln(lbuf.toString());

  final mbuf = StringBuffer();
  for (var y = 0; y < 120; y += 4) {
    for (var x = 0; x < Constants.gridW; x++) {
      mbuf.write(_mat[world.at(x, y)] ?? '?');
    }
    mbuf.write('\n');
  }
  stdout.writeln('--- materials y 0..119 (x 0..219) ---');
  stdout.writeln(mbuf.toString());

  var blackFrom = -1;
  for (var x = 0; x < Constants.gridW; x++) {
    var mn = 1e9;
    for (var y = 8; y <= 100; y += 4) {
      final l = t.field.luminance(world.idx(x, y));
      if (l < mn) mn = l;
    }
    if (mn < 0.05 && blackFrom < 0) blackFrom = x;
  }
  stdout.writeln('first column with a black sky cell (y 8..100): $blackFrom');
}
