import 'dart:math' as math;

import '../core/constants.dart';
import '../core/materials.dart';
import '../core/water.dart';
import '../core/world.dart';
import 'field.dart';

/// The water surface as a continuous function of (x, t): the per-column top
/// row (a step) plus the same wave offset the GUI draws
/// (surf - 0.12 + Waves.surface(x, t) * 0.35), so traced glint, caustics
/// and bounces move with the drawn line.
class Surface {
  static const double _twoPi = 6.283185307179586;
  static const double _offset = -0.12;
  static const double _amp = 0.35;

  /// The drawn surface's top row at column [col] and sim time [tSec]; -1
  /// when the column holds no water.
  static double topY(int col, double tSec, World w, Water water) {
    final s = water.spurts[col];
    if (s.active) return s.top.toDouble();
    for (var y = 0; y < Constants.gridH; y++) {
      if (w.at(col, y) == Material.water &&
          (y == 0 || w.at(col, y - 1) != Material.water)) {
        return y.toDouble();
      }
    }
    return -1;
  }

  /// The continuous surface y at (x, tSec) for the column under [x]; null
  /// when that column holds no water.
  static double? surfY(double x, double tSec, World w, Water water) {
    final col = x.floor();
    if (col < 0 || col >= Constants.gridW) return null;
    final top = topY(col, tSec, w, water);
    if (top < 0) return null;
    return top + _offset + _amp * Waves.surface(x, tSec);
  }

  /// The surface y restricted to column [col] (its own top step plus the
  /// wave at x).
  static double? surfIn(int col, double x, double tSec, World w, Water water) {
    final top = topY(col, tSec, w, water);
    if (top < 0) return null;
    return top + _offset + _amp * Waves.surface(x, tSec);
  }

  /// d/dx of the wave part of the surface at (x, tSec) (analytic).
  static double dSurf(double x, double tSec) {
    final a = _twoPi;
    return _amp *
        (0.50 * a / 24 * math.cos(a * (x / 24 + tSec / 9)) +
            0.30 * a / 9 * math.cos(a * (x / 9 - tSec / 3.5 + 0.31)) +
            0.20 * a / 5 * math.cos(a * (x / 5 + tSec / 1.7 + 0.73)));
  }

  /// The upward surface normal (out of the water) at (x, tSec), unit
  /// length.
  static (double, double) normal(double x, double tSec) {
    final s = dSurf(x, tSec);
    final len = math.sqrt(s * s + 1);
    return (s / len, -1 / len);
  }

  /// The t at which the ray P(t) = (ox + dx*t, oy + dy*t) crosses the
  /// surface, or null. Solved per column by bisection (the surface is
  /// smooth inside a column). [fromAbove] true = air-to-water crossings
  /// only, false = water-to-air only.
  static double? intersect(
    double ox,
    double oy,
    double dx,
    double dy, {
    double tMax = double.infinity,
    required bool fromAbove,
    required double tSec,
    required World w,
    required Water water,
  }) {
    if (dx == 0) {
      if (dy == 0) return null;
      final s = surfY(ox, tSec, w, water);
      if (s == null) return null;
      final t = (s - oy) / dy;
      if (t <= 0 || t > tMax) return null;
      final above = oy < s;
      if (fromAbove ? !above : above) return null;
      return t;
    }
    var xB = dx > 0 ? ox.floorToDouble() + 1 : ox.ceilToDouble();
    if (dx * (xB - ox) <= 0) xB += dx > 0 ? 1 : -1;
    var t0 = (xB - ox) / dx;
    while (t0 < tMax) {
      final col = xB.toInt();
      if (col < 0 || col >= Constants.gridW) return null;
      var t1 = t0 + 1 / dx;
      if (t1 > tMax) t1 = tMax;
      final s = surfIn(col, ox + dx * (t0 + t1) / 2, tSec, w, water);
      if (s != null) {
        final f0 = oy + dy * t0 - s;
        final f1 = oy + dy * t1 - s;
        if (f0 * f1 < 0) {
          var lo = t0;
          var hi = t1;
          var fLo = f0;
          for (var i = 0; i < 30; i++) {
            final mid = (lo + hi) / 2;
            final sm = surfIn(col, ox + dx * mid, tSec, w, water)!;
            final fm = oy + dy * mid - sm;
            if (fLo * fm <= 0) {
              hi = mid;
            } else {
              lo = mid;
              fLo = fm;
            }
          }
          final t = (lo + hi) / 2;
          final above = f0 < 0;
          if (fromAbove ? above : !above) return t;
        }
      }
      xB += dx > 0 ? 1 : -1;
      t0 = t1;
    }
    return null;
  }
}

/// Two-medium interface optics (air/water), closed form in 2-D.
class Optics {
  /// Refractive index of water relative to air.
  static const double etaWater = 1.0 / 1.33;

  /// Snell refraction of unit direction [d] across a unit normal [n]
  /// (pointing from the new medium back at the incoming ray, i.e. up out
  /// of the water for air-to-water). [eta] is n_in / n_out. Returns null
  /// on total internal reflection.
  static (double, double)? refract(
    double dx,
    double dy,
    double nx,
    double ny,
    double eta,
  ) {
    final cosI = -(dx * nx + dy * ny);
    final sin2T = eta * eta * (1 - cosI * cosI);
    if (sin2T > 1) return null;
    final cosT = math.sqrt(1 - sin2T);
    final k = eta * cosI - cosT;
    return (eta * dx + k * nx, eta * dy + k * ny);
  }

  /// Unpolarized Fresnel reflectance (mean of the s and p polarizations)
  /// for incidence cosine [cosI] (> 0) and index ratio [eta].
  static double fresnel(double cosI, double eta) {
    final sin2T = eta * eta * (1 - cosI * cosI);
    if (sin2T > 1) return 1.0;
    final cosT = math.sqrt(1 - sin2T);
    final rs = (cosI - eta * cosT) / (cosI + eta * cosT);
    final rp = (eta * cosI - cosT) / (eta * cosI + cosT);
    return 0.5 * (rs * rs + rp * rp);
  }

  /// Henyey-Greenstein phase function (forward-scattering strength [g]).
  static double hg(double cosTheta, double g) {
    final g2 = g * g;
    final d2 = 1 + g2 - 2 * g * cosTheta;
    if (d2 <= 0) return 0;
    return (1 - g2) / (2 * math.pi * math.pow(d2, 1.5));
  }

  /// 16-bit Van der Corput low-discrepancy value in [0, 1) for index [k]:
  /// deterministic, needs no table or RNG state.
  static double vdc(int k) {
    var v = 0.0;
    var f = 0.5;
    k &= 0xFFFF;
    for (var i = 0; i < 16; i++) {
      if ((k & 1) != 0) v += f;
      f *= 0.5;
      k >>= 1;
    }
    return v;
  }

  /// Deterministic 16-bit hash of (x, y, seed).
  static int hash16(int x, int y, int seed) {
    var h = (x * 374761393 + y * 668265263 + seed * 1274126177) & 0xFFFF;
    h = (h ^ (h >> 8)) & 0xFFFF;
    h = (h * 0x9E3779) & 0xFFFF;
    h = (h ^ (h >> 4)) & 0xFFFF;
    return h;
  }
}
