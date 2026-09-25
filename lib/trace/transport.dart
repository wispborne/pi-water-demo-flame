import 'dart:math' as math;

import '../core/constants.dart';
import '../core/materials.dart';
import '../core/water.dart';
import '../core/world.dart';
import 'field.dart';
import 'ray.dart';
import 'shadows.dart';
import 'surface.dart';

/// One light sample at a grid cell: direct next-event estimation to the sun
/// and the lit lamps (visibility from an angular sweep, Beer-Lambert along
/// the geometric path), the true caustic gathered from sun rays refracted
/// at the water surface, and single-scatter shafts in the water.
///
/// The sample is an exact pure function of (world, water, lamps, sim time)
/// — no RNG state, no per-sample epoch — so a re-sample of an unchanged
/// scene returns the bit-identical value, the same stability contract as
/// the old march-based tracer.
class Transport {
  final SceneSpans spans;
  final ShadowSweep sunSweep;
  final List<ShadowSweep> lampSweeps;
  final List<int> lampX, lampY;
  final World w;
  final Water water;
  final double sx, sy, tSec;

  // Sun colour: warm white, slightly over 1 so a clear-sky cell reads bright
  // (the GUI tone-maps with Reinhard).
  static const double sunR = 1.40, sunG = 1.33, sunB = 1.19;
  // Lamp colour: warm tungsten, dimmed so a lamp-lit room reads ~40-70% of
  // the sunlit sky (SPEC 7: a lamp lights its room and only its room).
  static const double lampR = 0.24, lampG = 0.15, lampB = 0.072;

  /// A lamp's light is sampled for cells within this many cells of it.
  static const int lampRadius2 = 48 * 48;

  // Single-scatter shafts (Jensen & Hestnes 2005 form): phase-weighted
  // in-scatter of the sun beam between the surface and the point.
  static const double _shaftRatio = 1.5; // sigma_s / sigma_t
  static const double _hgG = 0.7;

  // Surface glint: a narrow lobe centred on the sun's x, wobbled by the
  // wave slope (a strict top-down 2-D view cannot show a mirror glint; the
  // lobe is the standing-check-4 glitter, width set by the wave).
  static const double _glintK = 0.90;
  static const double _glintWidth = 7.0;
  static const double _glintSlope = 2.5;

  // Caustic gather: sun rays refracted at the surface land where Snell's
  // law puts them; a narrow kernel deposits the focus.
  static const double _causticK = 0.40;
  static const int _causticSpread = 8;
  static const double _causticSigma = 0.5;

  Transport(
    this.spans,
    this.sunSweep,
    this.lampSweeps,
    this.lampX,
    this.lampY,
    this.w,
    this.water,
    this.sx,
    this.sy,
    this.tSec,
  );

  /// The light arriving at cell (x, y).
  (double, double, double) sample(int x, int y) {
    final px = x + 0.5;
    final py = y + 0.5;
    final m = w.at(x, y);
    final inWater = m == Material.water || water.isSpurtCell(x, y);
    final exclude = x * 256 + y;

    var r = 0.0, g = 0.0, b = 0.0;

    // --- Sun (next event) ---
    if (sunSweep.isVisible(px, py, excludeCell: exclude)) {
      final ddx = sx - px;
      final ddy = sy - py;
      final dLen = math.sqrt(ddx * ddx + ddy * ddy);
      final tClip = dLen > 1.0 ? 1 - 0.5 / dLen : 1.0;
      final ray = Ray(px, py, ddx, ddy);
      final (tr, tg, tb) = spans.transmittance(ray, tMax: tClip);
      r += sunR * tr;
      g += sunG * tg;
      b += sunB * tb;
      if (inWater) {
        // Single-scatter in-scatter of the sun beam above the point:
        // (1 - T_w) is the fraction of the beam scattered on the way.
        final (twR, twG, twB) =
            spans.transmittance(ray, tMax: tClip, waterOnly: true);
        final upCos = (-ddy / dLen).clamp(-1.0, 1.0);
        final ph = Optics.hg(upCos, _hgG);
        r += sunR * _shaftRatio * ph * (1 - twR);
        g += sunG * _shaftRatio * ph * (1 - twG);
        b += sunB * _shaftRatio * ph * (1 - twB);
      }
      if (_isWaterSurface(x, y)) {
        final lobe = _glintLobe(x);
        if (lobe > 0) {
          final elev = ((Constants.sunTopY +
                      Constants.sunArcDepth -
                      sy) /
                  Constants.sunArcDepth)
              .clamp(0.0, 1.0);
          final gl = _glintK * lobe * elev;
          r += sunR * gl * tr;
          g += sunG * gl * tg;
          b += sunB * gl * tb;
        }
      }
    }

    // --- Caustic: sun rays refracted at the surface above this cell ---
    if (!inWater) {
      final top = Surface.topY(x, tSec, w, water);
      if (top >= 0 && py > top) {
        for (var sxx = x - _causticSpread; sxx <= x + _causticSpread; sxx++) {
          if (sxx < 0 || sxx >= Constants.gridW) continue;
          final qy = Surface.surfIn(sxx, sxx + 0.5, tSec, w, water);
          if (qy == null) continue;
          final qx = sxx + 0.5;
          if (!sunSweep.isVisible(qx, qy)) continue;
          final dsx = sx - qx;
          final dsy = sy - qy;
          if (dsy >= 0) continue; // the sun must sit above the surface
          final dLen = math.sqrt(dsx * dsx + dsy * dsy);
          final dxn = dsx / dLen;
          final dyn = dsy / dLen;
          final (nx, ny) = Surface.normal(qx, tSec);
          final cosI = -(dxn * nx + dyn * ny);
          if (cosI <= 0) continue;
          final refr = Optics.refract(dxn, dyn, nx, ny, Optics.etaWater);
          if (refr == null) continue; // TIR: the light stays in the air
          final tExit = spans.waterExit(Ray(qx, qy, refr.$1, refr.$2));
          if (tExit == null) continue;
          final lx = qx + refr.$1 * tExit;
          final ly = qy + refr.$2 * tExit;
          final ox = px - lx;
          final oy = py - ly;
          final off2 = ox * ox + oy * oy;
          if (off2 > 6.0) continue;
          final wgt = math.exp(-off2 / (2 * _causticSigma * _causticSigma));
          r += sunR * _causticK * wgt * math.exp(-waterSigma.r * tExit);
          g += sunG * _causticK * wgt * math.exp(-waterSigma.g * tExit);
          b += sunB * _causticK * wgt * math.exp(-waterSigma.b * tExit);
        }
      }
    }

    // --- Lamps (next events) ---
    for (var li = 0; li < lampSweeps.length; li++) {
      final ddx = lampX[li].toDouble() + 0.5 - px;
      final ddy = lampY[li].toDouble() + 0.5 - py;
      final d2 = ddx * ddx + ddy * ddy;
      if (d2 > lampRadius2) continue;
      if (!lampSweeps[li].isVisible(px, py, excludeCell: exclude)) continue;
      final dLen = math.sqrt(d2);
      final tClip = dLen > 1.0 ? 1 - 0.5 / dLen : 1.0;
      final (tr, tg, tb) =
          spans.transmittance(Ray(px, py, ddx, ddy), tMax: tClip);
      // Half intensity at 8 cells, ~2% at the 48-cell radius: a lamp's
      // light stays mostly in its own room.
      final fall = 1 / (1 + d2 / 64);
      r += lampR * fall * tr;
      g += lampG * fall * tg;
      b += lampB * fall * tb;
    }

    // A solid cell reflects only a fraction of the arriving light (its
    // albedo), so walls and slabs read darker than the lit air around
    // them; air, water, glass, and furniture pass the light through.
    if (Materials.blocksLightByIndex[m.index]) {
      final (ar, ag, ab) = Materials.albedoByIndex[m.index];
      r *= ar;
      g *= ag;
      b *= ab;
    }

    return (r, g, b);
  }

  /// True when the cell is a water surface cell: water (or spurt) with air
  /// (or the top edge) above it.
  bool _isWaterSurface(int x, int y) {
    final m = w.at(x, y);
    if (m != Material.water) return false;
    return y == 0 || w.at(x, y - 1) == Material.air;
  }

  /// The glint lobe in (0, 1] at surface column [x].
  double _glintLobe(int x) {
    final center =
        (x - sx) + _slope(x.toDouble()) * _glintSlope;
    final v = 1.0 - center * center / (_glintWidth * _glintWidth);
    return v <= 0 ? 0.0 : v * v;
  }

  double _slope(double x) =>
      Waves.surface(x + 0.5, tSec) - Waves.surface(x - 0.5, tSec);
}
