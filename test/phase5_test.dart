import 'package:test/test.dart';
import 'package:water_tower/core/lamp.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/sun.dart';
import 'package:water_tower/core/world.dart';
import 'package:water_tower/sim.dart';
import 'package:water_tower/trace/tracer.dart';

/// Phase 5 contract (PHASES.md standing checks, verbatim):
/// 1. lamp light never crosses a solid wall (incl. one-cell partitions);
/// 2. light passes through furniture;
/// 3. a roofed pool's surface is static across the sun's arc;
/// 4. an open pool glitters brightest under the sun;
/// plus: the field settles to a steady picture in ~1 s and re-converges
/// only in the places that changed; a submerged lamp reads warm amber;
/// and the ray budget falls back on sustained overrun and recovers.

const _settings = Settings(floors: 30, width: 3, material: 'rebar');

/// Sim time whose sun sits off-grid at the right edge (x = 220, y ~ 6) —
/// the "tail" of the day cycle, so the sun can only enter a scene through
/// a genuine opening.
const _sunOff = 841.0;

/// Trace [n] frames with the sun frozen at [tSec] (static scene: no water
/// motion, no sun drift).
void run(Tracer t, World w, double tSec, int n) {
  final sim = Sim();
  sim.sun.timeSec = tSec;
  for (var i = 0; i < n; i++) {
    t.trace(w, sim.water, sim.sun);
  }
}

/// A sealed box on the right of the grid (walls run to the top row so the
/// off-grid sun at x = 220 cannot get in) with a one-cell partition at
/// x = 195 and a lit floor lamp on the left side at (188, 228).
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

/// A pool dug into the ground: water x 100..120, y 230..235, concrete side
/// walls, ground floor; [roofed] adds a slab at y = 226 over the pool.
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

/// Max surface-row luminance over the pool columns at the frozen sun time.
double surfaceMax(Tracer t, World w, double tSec) {
  run(t, w, tSec, 30);
  var m = 0.0;
  for (var x = 100; x <= 120; x++) {
    m = (m > t.field.luminance(w.idx(x, 230))
        ? m
        : t.field.luminance(w.idx(x, 230)));
  }
  return m;
}

void main() {
  test('lamp light never crosses a one-cell solid partition', () {
    final w = boxScene(Material.concrete);
    final t = Tracer();
    run(t, w, _sunOff, 30);
    // Beside the lamp, on the near side of the partition: lit.
    final near = t.field.luminance(w.idx(190, 228));
    expect(near, greaterThan(0.3));
    // Far side of the one-cell partition: the only possible light source is
    // the lamp (the sun is sealed out), so it must read dark.
    final far = t.field.luminance(w.idx(202, 230));
    expect(far, lessThan(0.02));
  });

  test('lamp light passes through furniture', () {
    final w = boxScene(Material.chair);
    final t = Tracer();
    run(t, w, _sunOff, 30);
    // Behind the chair column: lit by the lamp (a chair does not block
    // light), at the expected 1/d^2 falloff level.
    final behind = t.field.luminance(w.idx(202, 230));
    expect(behind, greaterThan(0.15));
    expect(behind, lessThan(0.6));
  });

  test('a roofed pool surface is static across the sun arc', () {
    // The slab seals the pool from the sun, so the surface carries no sun
    // light (no glint) at any time: its brightness is the same across the
    // arc.
    final roofedMax = <double>[];
    for (final tSec in [60.0, 140.0, 210.0, 280.0, 360.0]) {
      roofedMax.add(surfaceMax(Tracer(), poolScene(true), tSec));
    }
    final roofedSpread = (roofedMax.reduce((a, b) => a > b ? a : b) -
            roofedMax.reduce((a, b) => a < b ? a : b))
        .abs();
    expect(roofedSpread, lessThan(0.05));
    // Control: the same pool open to the sky varies strongly (the glint
    // band sweeps the surface as the sun moves) — the check above is not
    // vacuous.
    final openMax = <double>[];
    for (final tSec in [60.0, 140.0, 210.0, 280.0, 360.0]) {
      openMax.add(surfaceMax(Tracer(), poolScene(false), tSec));
    }
    final openSpread = (openMax.reduce((a, b) => a > b ? a : b) -
            openMax.reduce((a, b) => a < b ? a : b))
        .abs();
    expect(openSpread, greaterThan(0.5));
  });

  test('an open pool glitters brightest under the sun', () {
    for (final tSec in [200.0, 210.0, 220.0]) {
      final t = Tracer();
      final w = poolScene(false);
      run(t, w, tSec, 30);
      var bestX = 100;
      for (var x = 101; x <= 120; x++) {
        if (t.field.luminance(w.idx(x, 230)) >
            t.field.luminance(w.idx(bestX, 230))) {
          bestX = x;
        }
      }
      final (sunX, _) = Sun.position(tSec);
      expect((bestX - sunX).abs(), lessThanOrEqualTo(4),
          reason: 'surface argmax at $bestX for sun at $sunX (t=$tSec)');
    }
  });

  test('field settles, then re-converges only where the world changed', () {
    final w = boxScene(Material.concrete);
    final t = Tracer();
    run(t, w, _sunOff, 30);
    final n = t.field.w * t.field.h;
    final snap = List<double>.filled(3 * n, 0);
    for (var i = 0; i < n; i++) {
      snap[3 * i] = t.field.r(i);
      snap[3 * i + 1] = t.field.g(i);
      snap[3 * i + 2] = t.field.b(i);
    }
    // Steady: ten more frames at the frozen sun change nothing.
    run(t, w, _sunOff, 10);
    var maxDelta = 0.0;
    for (var i = 0; i < n; i++) {
      for (var c = 0; c < 3; c++) {
        final f = c == 0 ? t.field.r(i) : c == 1 ? t.field.g(i) : t.field.b(i);
        final d = (f - snap[3 * i + c]).abs();
        if (d > maxDelta) maxDelta = d;
      }
    }
    expect(maxDelta, lessThan(1e-12));

    // Local edit: the partition cells the lamp's ray to (202, 230) can
    // cross turn to glass (the straight line crosses at (195, 229); the
    // cell below is included so the dirty boxes cover both). Only their
    // margin boxes re-converge immediately; every other cell keeps its
    // value bit-identically (no global re-sweep, no black flash).
    w.set(195, 229, Material.glass);
    w.set(195, 230, Material.glass);
    run(t, w, _sunOff, 1);
    final inBox = (int i) {
      final x = i % t.field.w;
      final y = i ~/ t.field.w;
      return x >= 193 && x <= 197 && y >= 227 && y <= 232;
    };
    var outsideDelta = 0.0;
    for (var i = 0; i < n; i++) {
      if (inBox(i)) continue;
      for (var c = 0; c < 3; c++) {
        final f = c == 0 ? t.field.r(i) : c == 1 ? t.field.g(i) : t.field.b(i);
        final d = (f - snap[3 * i + c]).abs();
        if (d > outsideDelta) outsideDelta = d;
      }
    }
    expect(outsideDelta, lessThan(1e-12));
    // The edited cell itself is re-lit through the glass.
    expect(t.field.luminance(w.idx(195, 230)), greaterThan(0.05));
    // A far cell whose light path crosses the glass is not in the dirty
    // box: it keeps its stale (dark) value for now...
    expect(t.field.luminance(w.idx(202, 230)), lessThan(0.02));
    // ...and the rotating stripe carries the new light to it within ~1 s.
    run(t, w, _sunOff, 30);
    expect(t.field.luminance(w.idx(202, 230)), greaterThan(0.1));
  });

  test('a submerged lamp reads warm amber near itself', () {
    final w = boxScene(Material.air);
    // Fill the box interior with water and put the lamp in it.
    w.fillRect(181, 216, 209, 237, Material.water);
    w.lamps.add(Lamp(LampKind.floor, 195, 230));
    final t = Tracer();
    run(t, w, _sunOff, 30);
    // One cell above the lamp: essentially pure tungsten — red over green,
    // red far over blue.
    final iNear = w.idx(195, 229);
    final rN = t.field.r(iNear);
    final gN = t.field.g(iNear);
    final bN = t.field.b(iNear);
    expect(rN, greaterThan(gN));
    expect(rN / bN, greaterThanOrEqualTo(2.0));
    // Deep in the column the red has been absorbed (Beer-Lambert): green
    // dominates and the cell reads dark blue-green.
    final iDeep = w.idx(195, 217);
    expect(t.field.g(iDeep), greaterThan(t.field.r(iDeep)));
    expect(t.field.g(iDeep), greaterThan(t.field.b(iDeep)));
  });

  test('ray budget falls back on sustained overrun and recovers', () {
    final b = TraceBudget();
    // A one-off spike does not fall back.
    for (var i = 0; i < 59; i++) {
      b.record(1000);
    }
    b.record(5000);
    expect(b.fellBack, isFalse);
    // A full window over the cap does.
    for (var i = 0; i < 60; i++) {
      b.record(2600);
    }
    expect(b.fellBack, isTrue);
    // A full window back under the cap recovers.
    for (var i = 0; i < 60; i++) {
      b.record(1000);
    }
    expect(b.fellBack, isFalse);
  });
}
