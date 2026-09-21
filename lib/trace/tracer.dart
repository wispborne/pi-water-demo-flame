import 'dart:math' as math;
import 'dart:typed_data';

import '../core/constants.dart';
import '../core/materials.dart';
import '../core/sun.dart';
import '../core/water.dart';
import '../core/world.dart';
import 'field.dart';

/// The per-frame ray budget meter (PLAN decision 2): the traced view stays
/// within 1,500-2,500 pixel-light shadow rays per frame at 1x. A *sustained*
/// overrun — a full 2 s (60-frame) window entirely over the cap — sets
/// [fellBack] (the GUI drops to the plain view and offers a toggle);
/// recovery — a full window back under the cap — clears it (re-enable). A
/// one-off spike (a world rebuild, a big erode) does not fall back.
class TraceBudget {
  /// The per-frame ray cap at 1x.
  static const int cap = 2500;

  /// Window length: 2 sim-seconds at 1x.
  static const int windowFrames = 60;

  final List<int> _counts = [];
  bool fellBack = false;

  /// Ray count of the last recorded frame (0 before the first).
  int get lastFrameRays => _counts.isEmpty ? 0 : _counts.last;

  /// Record one frame's ray count and re-evaluate the fallback.
  void record(int rays) {
    _counts.add(rays);
    if (_counts.length > windowFrames) _counts.removeAt(0);
    if (_counts.length < windowFrames) return;
    var allOver = true;
    for (final c in _counts) {
      if (c <= cap) {
        allOver = false;
        break;
      }
    }
    fellBack = allOver;
  }
}

/// The traced view (SPEC 7, PLAN technique "NEE + MIS"): every grid cell
/// carries a per-cell light estimate built from direct next-event rays to
/// the known lights (the sun + the lit lamps). Rays march deterministically
/// cell by cell through the grid: structure/ground/wood block, glass tints,
/// water tints by wavelength-dependent Beer-Lambert (red dies first).
///
/// The field is progressive: a cell's value is a running mean of its exact
/// sample, so a change never flashes black and converged cells keep their
/// value. Per frame the tracer (1) diffs the world (grid materials, the
/// spurt overlay, lamp positions/states) and marks the changed cells dirty
/// plus a margin, (2) re-samples every dirty cell, and (3) spends the
/// remaining ray budget on a rotating stripe of undirty cells so the field
/// follows the slowly drifting sun — at the 2,500-ray cap that covers the
/// whole field in ~1 s, which is exactly the settle time the spec asks for.
/// Steady state on a settled scene costs ~2,500 rays/frame (the stripe) and
/// never more.
class Tracer {
  final LightField field = LightField();
  final TraceBudget budget = TraceBudget();

  static const int _w = Constants.gridW;
  static const int _h = Constants.gridH;

  /// Shadow edges shift a few cells when a material moves one cell.
  static const int _margin = 2;

  /// A lamp's light is marched for cells within this many cells of it.
  static const int _lampRadius = 48;

  // Sun colour: warm white, slightly over 1 so a clear-sky cell reads bright
  // (the GUI tone-maps with Reinhard).
  static const double _sunR = 1.40;
  static const double _sunG = 1.33;
  static const double _sunB = 1.19;

  // Lamp colour: warm tungsten.
  static const double _lampR = 1.20;
  static const double _lampG = 0.74;
  static const double _lampB = 0.36;

  // Beer-Lambert per water cell traversed: red absorbed fastest, so deep
  // water reads dark blue-green.
  static const double _waterR = 0.62;
  static const double _waterG = 0.88;
  static const double _waterB = 0.80;

  /// Glass transmittance per cell (a slight cool tint).
  static const double _glassT = 0.94;

  // Forward-scattering shafts: extra in-water light, strongest when the sun
  // is high (its rays run through the water column).
  static const double _shaftK = 0.12;

  // Surface glint: a narrow lobe centred on the sun's x (the specular band
  // that glitters under the sun), wobbled by the wave slope so it shimmers
  // with the drawn surface.
  static const double _glintK = 0.90;
  static const double _glintWidth = 7.0;
  static const double _glintSlopeCoupling = 2.5;

  // Caustic: a surface cell's refracted spot lands a few cells over,
  // deflected by the wave slope, so the floor pattern drifts with the waves.
  static const double _causticK = 0.40;
  static const int _causticSpread = 8;
  static const double _waveAmp = 0.75;

  /// The mean weight for the sun-drift stripe pass: a converged cell keeps
  /// following the sun (per-channel first-order lag), with a sub-second
  /// lag over the rotating stripe.
  static const double _trackWeight = 0.25;

  Uint8List? _prevMat;
  Uint8List? _prevSpurt;
  Set<String>? _prevLampSig;
  int _frame = 0;

  /// Trace one frame: diff the world, mark dirty, re-sample dirty cells and
  /// the rotating sun-drift stripe, record the ray count.
  void trace(World w, Water water, Sun sun) {
    final curMat = Uint8List(_w * _h);
    for (var i = 0; i < curMat.length; i++) {
      curMat[i] = w.cells[i].index;
    }
    final curSpurt = _spurtMask(water);
    final curLampSig = _lampSig(w);

    if (_prevMat == null) {
      // First frame (or after [field.clear]): the whole field is dirty.
      field.clear();
    } else {
      final prevMat = _prevMat!;
      for (var i = 0; i < curMat.length; i++) {
        if (curMat[i] != prevMat[i]) _dirtyBox(i, _margin);
      }
      final prevSpurt = _prevSpurt!;
      for (var i = 0; i < curSpurt.length; i++) {
        if (curSpurt[i] != prevSpurt[i]) _dirtyBox(i, _margin);
      }
      final prevLampSig = _prevLampSig!;
      if (!_setEquals(prevLampSig, curLampSig)) {
        final moved = <String>{...prevLampSig, ...curLampSig};
        for (final key in moved) {
          final parts = key.split(':');
          _dirtyBox(w.idx(int.parse(parts[0]), int.parse(parts[1])),
              _lampRadius + _margin);
        }
      }
    }
    _prevMat = curMat;
    _prevSpurt = curSpurt;
    _prevLampSig = curLampSig;

    final (sx, sy) = Sun.position(sun.timeSec);
    var rays = 0;

    // Pass 1: every dirty (never-sampled in this epoch) cell re-converges.
    for (var i = 0; i < field.w * field.h; i++) {
      if (field.count(i) == 0) {
        _sampleCell(i, w, water, sx, sy, sun.timeSec);
        rays++;
      }
    }

    // Pass 2: the remaining budget re-means a rotating stripe of undirty
    // cells — the short lag that follows the drifting sun.
    final remaining = TraceBudget.cap - rays;
    if (remaining > 0) {
      final total = field.w * field.h;
      final stride = (total / remaining).ceil().clamp(1, total);
      for (var k = 0; k < remaining; k++) {
        final i = (k * stride + _frame) % total;
        if (field.count(i) > 0) {
          _sampleCell(i, w, water, sx, sy, sun.timeSec,
              weight: _trackWeight);
          rays++;
        }
      }
    }

    budget.record(rays);
    _frame++;
  }

  /// Mark the box around cell [i] dirty (clamped to the grid).
  void _dirtyBox(int i, int m) {
    final x0 = (i % _w) - m;
    final y0 = (i ~/ _w) - m;
    final x1 = (i % _w) + m;
    final y1 = (i ~/ _w) + m;
    for (var y = y0.clamp(0, _h - 1); y <= y1.clamp(0, _h - 1); y++) {
      for (var x = x0.clamp(0, _w - 1); x <= x1.clamp(0, _w - 1); x++) {
        field.markDirty(field.idx(x, y));
      }
    }
  }

  /// 1 where (x, y) is a spurt overlay cell, else 0 (spurt cells are out of
  /// the grid; they are water for lighting and for the diff).
  Uint8List _spurtMask(Water water) {
    final out = Uint8List(_w * _h);
    for (var y = 0; y < _h; y++) {
      for (var x = 0; x < _w; x++) {
        if (water.isSpurtCell(x, y)) out[y * _w + x] = 1;
      }
    }
    return out;
  }

  Set<String> _lampSig(World w) {
    final sig = <String>{};
    for (final l in w.lamps) {
      sig.add('${l.x}:${l.y}:${l.isLit}');
    }
    return sig;
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final e in a) {
      if (!b.contains(e)) return false;
    }
    return true;
  }

  /// The exact per-cell light estimate: sun (shadow ray + shaft + glint)
  /// plus caustic (floor cells) plus every lit lamp in range (shadow ray
  /// with 1/d^2 falloff). A pure function of (world, water, lamps, sun
  void _sampleCell(int i, World w, Water water, double sx, double sy,
      double tSec, {double? weight}) {
    final x = i % _w;
    final y = i ~/ _w;
    final m = w.at(x, y);
    final inWater = m == Material.water || water.isSpurtCell(x, y);

    var r = 0.0;
    var g = 0.0;
    var b = 0.0;

    // --- Sun ---
    final (sunTr, sunTg, sunTb, sunVisible) =
        _march(x, y, sx, sy, w, water);
    if (sunVisible) {
      r += _sunR * sunTr;
      g += _sunG * sunTg;
      b += _sunB * sunTb;
      final ddx = x - sx;
      final ddy = y - sy;
      final dist = math.sqrt(ddx * ddx + ddy * ddy) + 1e-9;
      if (inWater) {
        // Forward-scattering shafts: brightest when the sun is high.
        final elev = (ddy < 0 ? -ddy : 0.0) / dist;
        r += _sunR * _shaftK * elev;
        g += _sunG * _shaftK * elev;
        b += _sunB * _shaftK * elev;
      }
      if (_isWaterSurface(x, y, w)) {
        final lobe = _glintLobe(x, sx, tSec);
        if (lobe > 0) {
          final elev = ((Constants.sunTopY +
                      Constants.sunArcDepth -
                      sy) /
                  Constants.sunArcDepth)
              .clamp(0.0, 1.0);
          final glint = _glintK * lobe * elev;
          r += _sunR * glint * sunTr;
          g += _sunG * glint * sunTg;
          b += _sunB * glint * sunTb;
        }
      }
    }

    // --- Caustic: floor cells collect the refracted spots from the water
    // surface above them (drifts with the wave slope). ---
    if (!inWater &&
        y > 0 &&
        (w.at(x, y - 1) == Material.water || water.isSpurtCell(x, y - 1))) {
      var top = y - 1;
      while (top > 0 &&
          (w.at(x, top) == Material.water || water.isSpurtCell(x, top))) {
        top--;
      }
      if (w.at(x, top) == Material.water &&
          (top == 0 || w.at(x, top - 1) == Material.air)) {
        final depth = (y - top).toDouble();
        for (var sxx = x - _causticSpread;
            sxx <= x + _causticSpread;
            sxx++) {
          if (sxx < 0 || sxx >= _w) continue;
          if (w.at(sxx, top) != Material.water) continue;
          if (top > 0 && w.at(sxx, top - 1) != Material.air) continue;
          final (cr, cg, cb, vis) = _march(sxx, top, sx, sy, w, water);
          if (!vis) continue;
          final slope = _slope(sxx.toDouble(), tSec);
          final landX = sxx + slope * _waveAmp * depth;
          final off = (x - landX) / (_causticSpread * 0.6);
          final wgt = (1.0 - off * off).clamp(0.0, 1.0);
          if (wgt <= 0) continue;
          r += _sunR * _causticK * wgt * cr;
          g += _sunG * _causticK * wgt * cg;
          b += _sunB * _causticK * wgt * cb;
        }
      }
    }

    // --- Lamps ---
    for (final lamp in w.lamps) {
      if (!lamp.isLit) continue;
      final ddx = lamp.x - x;
      final ddy = lamp.y - y;
      final d2 = ddx * ddx + ddy * ddy;
      if (d2 > _lampRadius * _lampRadius) continue;
      final (lr, lg, lb, vis) =
          _march(x, y, lamp.x.toDouble(), lamp.y.toDouble(), w, water);
      if (!vis) continue;
      final falloff = 1.0 / (1.0 + d2 / 144.0);
      r += _lampR * falloff * lr;
      g += _lampG * falloff * lg;
      b += _lampB * falloff * lb;
    }

    field.sample(i, r, g, b, weight: weight);
  }

  /// True when the cell is a water surface cell: water (or spurt) with air
  /// (or the top edge) above it.
  bool _isWaterSurface(int x, int y, World w) {
    final m = w.at(x, y);
    if (m != Material.water) return false;
    return y == 0 || w.at(x, y - 1) == Material.air;
  }

  /// The glint lobe in (0, 1] at surface column [x]: a narrow band centred
  /// on the sun's x, wobbled by the wave slope (the same [Waves] function the
  /// GUI draws, so the glitter moves with the drawn surface).
  double _glintLobe(int x, double sx, double tSec) {
    final center = (x - sx) + _slope(x.toDouble(), tSec) * _glintSlopeCoupling;
    final v = 1.0 - center * center / (_glintWidth * _glintWidth);
    return v <= 0 ? 0.0 : v * v;
  }

  /// The wave slope (d/dx) at column [x] and sim time [tSec].
  double _slope(double x, double tSec) =>
      Waves.surface(x + 0.5, tSec) - Waves.surface(x - 0.5, tSec);

  /// March from (cx, cy) toward the light at (lx, ly) one cell at a time.
  /// Returns (tr, tg, tb, visible): false for visible when a light-blocking
  /// cell is crossed (transmittances are then meaningless); otherwise the
  /// per-cell transmittances of every glass/water cell traversed (the start
  /// cell and the light cell itself are not attenuated; out-of-grid cells
  /// are sky and terminate the march unattenuated).
  (double, double, double, bool) _march(
      int cx, int cy, double lx, double ly, World w, Water water) {
    var tr = 1.0;
    var tg = 1.0;
    var tb = 1.0;
    var x = cx;
    var y = cy;
    for (var step = 0; step < 512; step++) {
      final rx = x - lx;
      final ry = y - ly;
      if (rx.abs() <= 1 && ry.abs() <= 1) return (tr, tg, tb, true);
      if (rx.abs() > ry.abs()) {
        x += rx > 0 ? -1 : 1;
      } else {
        y += ry > 0 ? -1 : 1;
      }
      if (x < 0 || x >= _w || y < 0 || y >= _h) {
        return (tr, tg, tb, true); // the rest of the path is sky
      }
      final m = w.at(x, y);
      if (Materials.blocksLight(m)) return (0, 0, 0, false);
      if (m == Material.glass) {
        tr *= _glassT;
        tg *= _glassT;
        tb *= _glassT;
      } else if (m == Material.water || water.isSpurtCell(x, y)) {
        tr *= _waterR;
        tg *= _waterG;
        tb *= _waterB;
      }
    }
    return (tr, tg, tb, true);
  }
}
