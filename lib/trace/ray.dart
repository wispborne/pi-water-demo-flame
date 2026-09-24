import 'dart:math' as math;
import 'dart:typed_data';

import '../core/constants.dart';
import '../core/materials.dart';
import '../core/water.dart';
import '../core/world.dart';

/// A ray in grid units: P(t) = (ox + dx*t, oy + dy*t). The direction is not
/// normalized; t is in cell units (a ray aimed at a point L built with
/// dir = L - origin reaches it at t = 1).
class Ray {
  final double ox, oy, dx, dy;
  Ray(this.ox, this.oy, this.dx, this.dy);
}

/// The first light-blocking hit of a ray (occlusion queries).
class OcclHit {
  final double t;
  final int x, y;
  final double nx, ny; // surface normal, pointing back at the ray

  OcclHit(this.t, this.x, this.y, this.nx, this.ny);
}

/// Beer-Lambert extinction per unit cell length, derived from the old
/// per-cell factors: transmittance over a path of length L is
/// exp(-sigma * L), so a diagonal path is attenuated by its geometric
/// length, not by the number of cells it crosses.
class Extinction {
  final double r, g, b;
  const Extinction(this.r, this.g, this.b);
}

final Extinction waterSigma = Extinction(
  -math.log(0.62),
  -math.log(0.88),
  -math.log(0.80),
);
final Extinction glassSigma = Extinction(
  -math.log(0.94),
  -math.log(0.94),
  -math.log(0.94),
);

/// Per-column contiguous spans for the three light categories: occluders
/// (structure, ground, wood), water (grid water plus the spurt overlay),
/// and glass. A span is a run of rows [y0, y1] (inclusive) in one column.
///
/// The queries march over *columns* (Amanatides & Woo stepping in the
/// column index), and per crossed column test only that column's spans, so
/// a ray costs the number of columns it crosses (about its width), not its
/// length in cells. Rebuilt from the world on demand; a settled scene
/// rebuilds nothing.
class SceneSpans {
  final int w = Constants.gridW;
  final int h = Constants.gridH;
  final List<Uint16List> occl = [];
  final List<Uint16List> water = [];
  final List<Uint16List> glass = [];

  void rebuildAll(World world, Water wt) {
    occl.clear();
    water.clear();
    glass.clear();
    for (var x = 0; x < w; x++) {
      occl.add(Uint16List(0));
      water.add(Uint16List(0));
      glass.add(Uint16List(0));
      _buildColumn(x, world, wt);
    }
  }

  void rebuildColumn(int x, World world, Water wt) {
    _buildColumn(x, world, wt);
  }

  void _buildColumn(int x, World world, Water wt) {
    final o = <int>[];
    final wa = <int>[];
    final g = <int>[];
    var cur = 0;
    var lo = 0;
    for (var y = 0; y < h; y++) {
      final m = world.at(x, y);
      final c =
          m == Material.water || wt.isSpurtCell(x, y)
              ? 1
              : m == Material.glass
              ? 2
              : Materials.blocksLightByIndex[m.index]
              ? 3
              : 0;
      if (c == cur) continue;
      if (cur != 0) _emit(o, wa, g, cur, lo, y - 1);
      cur = c;
      lo = y;
    }
    if (cur != 0) _emit(o, wa, g, cur, lo, h - 1);
    occl[x] = Uint16List.fromList(o);
    water[x] = Uint16List.fromList(wa);
    glass[x] = Uint16List.fromList(g);
  }

  static void _emit(
    List<int> o,
    List<int> wa,
    List<int> g,
    int cur,
    int lo,
    int hi,
  ) {
    final packed = (lo << 8) | hi;
    if (cur == 1) wa.add(packed);
    else if (cur == 2) g.add(packed);
    else o.add(packed);
  }

  /// Transmittance (tr, tg, tb) along [r] over [0, tMax]. The start cell is
  /// not attenuated (the light at a point is not filtered by the cell it
  /// sits in, matching the old march); [tMax] is typically clipped to just
  /// before the light's own cell. When [waterOnly] is set, only water is
  /// attenuated (the shaft term needs the pure water fraction).
  (double, double, double) transmittance(
    Ray r, {
    double tMax = double.infinity,
    bool waterOnly = false,
  }) {
    var lr = 0.0, lg = 0.0, lb = 0.0; // log transmittance
    // The ray direction is not normalized, so a t-range maps to geometric
    // length by the direction's magnitude (a ray aimed at a light with
    // dir = light - origin has magnitude = the light distance).
    final mag = math.sqrt(r.dx * r.dx + r.dy * r.dy);
    _forEachColumn(r, tMax, true, (int col, double t0, double t1) {
      final yA = r.oy + r.dy * t0;
      final yB = r.oy + r.dy * t1;
      final lo = yA < yB ? yA : yB;
      final hi = yA < yB ? yB : yA;
      _accumulate(r, col, lo, hi, mag, water, waterSigma, (double v) {
        lr += v;
      }, (double v) {
        lg += v;
      }, (double v) {
        lb += v;
      });
      if (!waterOnly) {
        _accumulate(r, col, lo, hi, mag, glass, glassSigma, (double v) {
          lr += v;
        }, (double v) {
          lg += v;
        }, (double v) {
          lb += v;
        });
      }
    });
    return (math.exp(lr), math.exp(lg), math.exp(lb));
  }

  void _accumulate(
    Ray r,
    int col,
    double yLo,
    double yHi,
    double mag,
    List<Uint16List> spans,
    Extinction sigma,
    void Function(double) addR,
    void Function(double) addG,
    void Function(double) addB,
  ) {
    final list = spans[col];
    final ady = r.dy.abs();
    if (ady == 0) return;
    for (var s = 0; s < list.length; s++) {
      final packed = list[s];
      final a = packed >>> 8;
      final b = (packed & 0xFF) + 1; // geometric span [a, b)
      final lo = yLo > a.toDouble() ? yLo : a.toDouble();
      final hi = yHi < b.toDouble() ? yHi : b.toDouble();
      if (hi <= lo) continue;
      // Geometric length of the segment inside the span: the y-range
      // scaled by the direction's magnitude (t-units become cells).
      final len = (hi - lo) * mag / ady;
      addR(-sigma.r * len);
      addG(-sigma.g * len);
      addB(-sigma.b * len);
    }
  }

  /// The first light-blocking hit along [r] before [tMax], or null.
  OcclHit? firstOccluder(Ray r, {double tMax = double.infinity}) {
    double? bestT;
    OcclHit? best;
    _forEachColumn(r, tMax, false, (int col, double t0, double t1) {
      final list = occl[col];
      if (list.isEmpty) return;
      final y0 = r.oy + r.dy * t0;
      for (var s = 0; s < list.length; s++) {
        final packed = list[s];
        final a = packed >>> 8;
        final b = (packed & 0xFF) + 1;
        double? t;
        double nx = 0, ny = 0;
        var row = a;
        if (t0 > 1e-9 && y0 >= a.toDouble() && y0 < b.toDouble()) {
          // Entering through the column face, already inside the span.
          t = t0;
          nx = r.dx < 0 ? 1 : -1;
          ny = 0;
          row = y0.toInt().clamp(a, b - 1);
        } else if (r.dy > 0) {
          final tTop = (a.toDouble() - r.oy) / r.dy;
          if (tTop > t0 && tTop < t1) {
            t = tTop;
            ny = -1; // top face, pointing up
          }
        } else if (r.dy < 0) {
          final tBot = (b.toDouble() - r.oy) / r.dy;
          if (tBot > t0 && tBot < t1) {
            t = tBot;
            ny = 1; // bottom face, pointing down
            row = b - 1;
          }
        }
        if (t != null && (bestT == null || t < bestT!)) {
          bestT = t;
          best = OcclHit(t, col, row, nx, ny);
        }
      }
    });
    return best;
  }

  /// The end t of the last water span the ray [r] passes through (the exit
  /// from the water), or null when the ray never enters water. Used for
  /// caustic landing points.
  double? waterExit(Ray r, {double tMax = double.infinity}) {
    double? lastEnd;
    _forEachColumn(r, tMax, false, (int col, double t0, double t1) {
      final list = water[col];
      if (list.isEmpty) return;
      final yA = r.oy + r.dy * t0;
      final yB = r.oy + r.dy * t1;
      final lo = yA < yB ? yA : yB;
      final hi = yA < yB ? yB : yA;
      final ady = r.dy.abs();
      if (ady == 0) return;
      for (var s = 0; s < list.length; s++) {
        final packed = list[s];
        final a = packed >>> 8;
        final b = (packed & 0xFF) + 1;
        final sLo = lo > a.toDouble() ? lo : a.toDouble();
        final sHi = hi < b.toDouble() ? hi : b.toDouble();
        if (sHi <= sLo) continue;
        // t of the segment's far end (in the ray's direction of travel).
        final tEnd = r.dy > 0
            ? (sHi - r.oy) / r.dy
            : (sLo - r.oy) / r.dy;
        final prev = lastEnd;
        if (prev == null) {
          lastEnd = tEnd;
        } else if (tEnd > prev) {
          lastEnd = tEnd;
        }
      }
    });
    return lastEnd;
  }

  /// Call [cb] for every column [col] the ray crosses with the t-range
  /// [t0, t1) of the ray inside that column. When [skipStartCell] is set,
  /// the portion of the start cell the ray leaves is excluded (the start
  /// cell is not part of the path, matching the old march).
  void _forEachColumn(
    Ray r,
    double tMax,
    bool skipStartCell,
    void Function(int col, double t0, double t1) cb,
  ) {
    final dx = r.dx;
    final dy = r.dy;
    double tExit = double.infinity;
    if (skipStartCell) {
      if (dx > 0) tExit = math.min(tExit, (r.ox.floorToDouble() + 1 - r.ox) / dx);
      if (dx < 0) tExit = math.min(tExit, (r.ox.floorToDouble() - r.ox) / dx);
      if (dy > 0) tExit = math.min(tExit, (r.oy.floorToDouble() + 1 - r.oy) / dy);
      if (dy < 0) tExit = math.min(tExit, (r.oy.floorToDouble() - r.oy) / dy);
      if (tExit < 0) tExit = 0;
    }
    if (dx == 0) {
      final col = r.ox.floor();
      if (col < 0 || col >= w) return;
      var t0 = skipStartCell ? tExit : 0.0;
      if (t0 < 0) t0 = 0;
      if (t0 >= tMax) return;
      cb(col, t0, tMax);
      return;
    }
    var xB = dx > 0 ? r.ox.floorToDouble() + 1 : r.ox.ceilToDouble();
    if (dx * (xB - r.ox) <= 0) xB += dx > 0 ? 1 : -1;
    var t0 = (xB - r.ox) / dx;
    while (t0 < tMax) {
      final col = xB.toInt();
      if (col < 0 || col >= w) return;
      var t1 = t0 + 1 / dx.abs();
      if (t1 > tMax) t1 = tMax;
      if (t0 < t1) cb(col, t0, t1);
      xB += dx > 0 ? 1 : -1;
      t0 = t1;
    }
  }
}
