import 'dart:typed_data';

import '../core/constants.dart';
import '../core/materials.dart';
import '../core/sun.dart';
import '../core/water.dart';
import '../core/world.dart';
import 'field.dart';
import 'ray.dart';
import 'shadows.dart';
import 'transport.dart';

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

/// The traced view (SPEC 7): every grid cell carries a per-cell light
/// estimate from direct next-event estimation to the known lights (the sun
/// plus the lit lamps), the true caustic gathered from sun rays refracted
/// at the water surface, single-scatter shafts, and two diffuse bounces.
///
/// Geometry is precomputed per frame from the diffed world:
///
/// * [SceneSpans] — per-column contiguous spans of occluder/water/glass
///   cells; a ray costs the columns it crosses, not its length in cells.
/// * [ShadowSweep]s — one angular sweep per light (Eberly's 2-D shadow
///   map): light visibility is an O(log B) angle lookup instead of a DDA
///   march.
///
/// The field stays progressive exactly as before: a cell's value is a
/// running mean of its (exact, deterministic) sample, so a change never
/// flashes black. Per frame the tracer (1) diffs the world (grid
/// materials, the spurt overlay, lamp positions/states) and marks the
/// changed cells dirty plus a margin, (2) re-samples dirty cells within
/// the frame's ray budget, and (3) spends the remaining budget on a
/// rotating stripe of undirty cells so the field follows the slowly
/// drifting sun. Steady state on a settled scene costs ~2,500 rays/frame
/// and never more.
class Tracer {
  final LightField field = LightField();
  final TraceBudget budget = TraceBudget();

  static const int _w = Constants.gridW;
  static const int _h = Constants.gridH;

  /// Shadow edges shift a few cells when a material moves one cell.
  static const int _margin = 2;

  /// A lamp's light is sampled for cells within this many cells of it.
  static const int _lampRadius = 48;

  /// The mean weight for the sun-drift stripe pass: a converged cell keeps
  /// following the sun (per-channel first-order lag), with a sub-second
  /// lag over the rotating stripe.
  static const double _trackWeight = 0.25;

  final SceneSpans _spans = SceneSpans();
  final ShadowSweep _sunSweep = ShadowSweep();
  final List<ShadowSweep> _lampSweeps = [];
  final List<int> _lampX = [];
  final List<int> _lampY = [];

  Uint8List? _prevMat;
  Uint8List? _prevSpurt;
  Set<String>? _prevLampSig;
  int _frame = 0;

  /// The occluder cell list shared by every sweep. Rebuilt only when a
  /// light-blocking material moves (a spurt change never touches it).
  List<(int, int)>? _blockers;

  /// The lamp sweeps are valid while the lamp set and the occluders are.
  /// Rebuilding 120 sweeps per frame costs tens of ms; a settled tower
  /// rebuilds them only when a lamp moves/toggles or structure changes.
  bool _lampSweepsValid = false;

  /// Trace one frame: diff the world, mark dirty, re-sample dirty cells and
  /// the rotating sun-drift stripe, record the ray count.
  void trace(World w, Water water, Sun sun) {
    final curMat = Uint8List(_w * _h);
    for (var i = 0; i < curMat.length; i++) {
      curMat[i] = w.cells[i].index;
    }
    final curSpurt = _spurtMask(water);
    final curLampSig = _lampSig(w);

    final firstFrame = _prevMat == null;
    (int, int)? lampFocus;
    final changedCols = <int>{};
    if (firstFrame) {
      // First frame (or after [field.clear]): the whole field is dirty.
      field.clear();
      _spans.rebuildAll(w, water);
      _blockers = null;
      _lampSweepsValid = false;
    } else {
      final prevMat = _prevMat!;
      var occludersChanged = false;
      for (var i = 0; i < curMat.length; i++) {
        if (curMat[i] != prevMat[i]) {
          _dirtyBox(i, _margin);
          changedCols.add(i % _w);
          // Only light-blocking cells feed the occluder list; a water/air
          // cell moving changes no sweep, so the lamp sweeps stay valid
          // while the pool surface sloshes.
          if (Materials.blocksLightByIndex[curMat[i]] ||
              Materials.blocksLightByIndex[prevMat[i]]) {
            occludersChanged = true;
          }
        }
      }
      final prevSpurt = _prevSpurt!;
      for (var i = 0; i < curSpurt.length; i++) {
        if (curSpurt[i] != prevSpurt[i]) {
          _dirtyBox(i, _margin);
          changedCols.add(i % _w);
        }
      }
      final prevLampSig = _prevLampSig!;
      if (!_setEquals(prevLampSig, curLampSig)) {
        _lampSweepsValid = false;
        final moved = <String>{...prevLampSig, ...curLampSig};
        for (final key in moved) {
          final parts = key.split(':');
          _dirtyBox(w.idx(int.parse(parts[0]), int.parse(parts[1])),
              _lampRadius + _margin);
        }
        // The lamp's new position (its lit state may have changed too): the
        // pass-1 budget goes to the cells nearest it first.
        for (final key in curLampSig) {
          if (!prevLampSig.contains(key)) {
            final parts = key.split(':');
            lampFocus = (int.parse(parts[0]), int.parse(parts[1]));
            break;
          }
        }
      }
      for (final c in changedCols) {
        _spans.rebuildColumn(c, w, water);
      }
      if (occludersChanged) {
        _blockers = null;
        _lampSweepsValid = false;
      }
    }
    _prevMat = curMat;
    _prevSpurt = curSpurt;
    _prevLampSig = curLampSig;

    final (sx, sy) = Sun.position(sun.timeSec);
    _buildSunSweep(sx, sy);
    if (!_lampSweepsValid) {
      _buildLampSweeps(w);
      _lampSweepsValid = true;
    }

    final transport = Transport(
      _spans,
      _sunSweep,
      _lampSweeps,
      _lampX,
      _lampY,
      w,
      water,
      sx,
      sy,
    );
    var rays = 0;

    // Pass 1: dirty (never-sampled in this epoch) cells re-converge. The
    // first frame after a [field.clear] re-samples the whole field in one
    // go (the one-off spike the budget tolerates); afterwards pass 1 spends
    // at most the frame's budget, so a big change (a falling lamp) settles
    // over ~1 s like the sun drift instead of blowing the frame. When a
    // lamp moved, the cells nearest it are resampled first, so its light
    // follows radially instead of being swept row by row.
    final total = field.w * field.h;
    final dirty = <int>[];
    for (var i = 0; i < total; i++) {
      if (field.count(i) == 0) dirty.add(i);
    }
    final focus = lampFocus;
    if (focus != null && dirty.length > 1) {
      dirty.sort((a, b) {
        final ax = a % _w - focus.$1, ay = a ~/ _w - focus.$2;
        final bx = b % _w - focus.$1, by = b ~/ _w - focus.$2;
        final da = ax * ax + ay * ay, db = bx * bx + by * by;
        return da == db ? a - b : da - db;
      });
    }
    for (final i in dirty) {
      if (!firstFrame && rays >= TraceBudget.cap) break;
      _sampleCell(transport, i);
      rays++;
    }

    // Pass 2: the remaining budget re-means a rotating stripe of undirty
    // cells — the short lag that follows the drifting sun.
    final remaining = TraceBudget.cap - rays;
    if (remaining > 0) {
      final stride = (total / remaining).ceil().clamp(1, total);
      for (var k = 0; k < remaining; k++) {
        final i = (k * stride + _frame) % total;
        if (field.count(i) > 0) {
          _sampleCell(transport, i, weight: _trackWeight);
          rays++;
        }
      }
    }

    budget.record(rays);
    _frame++;
  }

  void _sampleCell(Transport t, int i, {double? weight}) {
    final x = i % _w;
    final y = i ~/ _w;
    final (r, g, b) = t.sample(x, y);
    field.sample(i, r, g, b, weight: weight);
  }

  /// Every light-blocking cell as a (x, y) pair, cached across frames.
  List<(int, int)> _blockersFor() {
    var b = _blockers;
    if (b == null) {
      b = <(int, int)>[];
      for (var x = 0; x < _w; x++) {
        final runs = _spans.occl[x];
        for (var s = 0; s < runs.length; s++) {
          final packed = runs[s];
          final lo = packed >>> 8;
          final hi = (packed & 0xFF) + 1;
          for (var y = lo; y < hi; y++) {
            b.add((x, y));
          }
        }
      }
      _blockers = b;
    }
    return b;
  }

  /// The angular shadow map for the sun at (sx, sy): every light-blocking
  /// cell is a disc occluder around its centre. The sun moves every frame,
  /// so this one sweep is rebuilt every frame (the lamp sweeps are not).
  void _buildSunSweep(double sx, double sy) {
    _sunSweep.build(sx, sy, _blockersFor());
  }

  /// One sweep per lit lamp (their light is static between world diffs).
  void _buildLampSweeps(World w) {
    _lampSweeps.clear();
    _lampX.clear();
    _lampY.clear();
    final blockers = _blockersFor();
    for (final lamp in w.lamps) {
      if (!lamp.isLit) continue;
      final sweep = ShadowSweep();
      sweep.build(lamp.x + 0.5, lamp.y + 0.5, blockers);
      _lampSweeps.add(sweep);
      _lampX.add(lamp.x);
      _lampY.add(lamp.y);
    }
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
}
