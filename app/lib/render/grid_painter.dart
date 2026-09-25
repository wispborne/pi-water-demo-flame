import 'dart:math' as math;
import 'dart:ui';

import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/sun.dart';
import 'package:water_tower/core/water.dart';
import 'package:water_tower/core/world.dart';
import 'package:water_tower/trace/field.dart';
import 'package:water_tower_app/camera.dart';
import 'package:water_tower_app/sim_state.dart';

/// The painter: one pass over the visible grid per frame (PLAN: one
/// CustomPainter-equivalent per frame, not one component per cell).
///
/// Plain mode: day-sky gradient, cells batched per material, per-cell
/// water depth tint, the wavy surface line, the glow band, lamps, sun.
/// Traced mode: the settled light field (blitted image), then the lamp
/// bulbs, sun disc, surface line, and glow band on top — the scene is lit
/// only by the traced light (SPEC 7).
class GridPainter {
  static const Color _bg = Color(0xFF0B0E14);

  static const Map<Material, Color> _mat = {
    Material.ground: Color(0xFF3B322A),
    Material.concrete: Color(0xFFA8A8A8),
    Material.rebar: Color(0xFFB5AC9C),
    Material.steel: Color(0xFF8FA6B2),
    Material.titanium: Color(0xFFC7C9CE),
    Material.glass: Color(0x66BFE5EF),
    Material.wood: Color(0xFF8A6B4C),
    Material.rubble: Color(0xFF6E655A),
    Material.debris: Color(0xFFD9D2BE),
    Material.water: Color(0x997FD4FF),
    Material.chair: Color(0xFFA0522D),
    Material.plant: Color(0xFF3E8B3E),
    Material.tv: Color(0xFF20242B),
    Material.fridge: Color(0xFFC9CDD3),
    Material.desk: Color(0xFF8B5E34),
    Material.table: Color(0xFFA26A3A),
    Material.counter: Color(0xFFD8CBA8),
    Material.bed: Color(0xFF7C8FB0),
    Material.tub: Color(0xFFE9EBF2),
    Material.sofa: Color(0xFF5C705C),
    Material.lamp: Color(0xFFFFD27F),
  };

  // Slight per-cell shade variation for the granular/earthy materials.
  static const List<Color> _groundShades = [
    Color(0xFF3B322A),
    Color(0xFF423830),
    Color(0xFF352D26),
  ];
  static const List<Color> _rubbleShades = [
    Color(0xFF6E655A),
    Color(0xFF7A7065),
    Color(0xFF645B50),
  ];
  static const List<Color> _debrisShades = [
    Color(0xFFD9D2BE),
    Color(0xFFE3DCC9),
    Color(0xFFCFC8B2),
  ];

  static void draw(
    Canvas c,
    Size size,
    SimState state,
    Camera cam,
    Image? fieldImage,
    bool traced,
    (int, int) hover,
  ) {
    final world = state.world;
    final water = state.sim.water;
    final (sx, sy) = Sun.position(state.sim.sun.timeSec);

    c.drawRect(Offset.zero & size, Paint()..color = _bg);
    if (!traced) {
      _drawSky(c, size, sx, sy);
    }

    c.save();
    c.translate(cam.offX, cam.offY);
    c.scale(cam.cellPx);

    final (x0, y0, x1, y1) = cam.visible(size.width, size.height);

    if (!traced && sx < Constants.gridW) {
      _drawSunGlow(c, sx, sy);
    }

    if (traced && fieldImage != null) {
      c.drawImage(
        fieldImage,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.none,
      );
    } else {
      // Plain mode — and traced mode for the first frames after a world
      // rebuild, before the blitted field image is ready.
      _drawCells(c, world, water, x0, y0, x1, y1, cam.cellPx);
    }

    _drawLamps(c, world);
    _drawSun(c, state.sim.sun, small: traced);
    _drawSurface(c, world, water, state.sim.sun.timeSec, state.glow,
        cam.cellPx);
    _drawHover(c, hover, cam.cellPx);

    c.restore();
  }

  /// The day sky: a vertical gradient whose warmth follows the sun's
  /// altitude — peach at the horizon (rise/set), bright blue at noon.
  static void _drawSky(Canvas c, Size size, double sx, double sy) {
    final altitude =
        (1.0 - (sy - Constants.sunTopY) / Constants.sunArcDepth).clamp(0.0, 1.0);
    c.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = Gradient.linear(Offset.zero, Offset(0, size.height), [
          Color.lerp(const Color(0xFF6E7CA6), const Color(0xFF5B9BD5),
              altitude)!,
          Color.lerp(
              const Color(0xFFF2CDA4), const Color(0xFFD8EDFB), altitude)!,
        ]),
    );
  }

  /// A soft radial glow around the sun, strongest and warmest at low
  /// altitude (drawn behind the cells, so the tower silhouettes against it).
  static void _drawSunGlow(Canvas c, double sx, double sy) {
    final altitude =
        (1.0 - (sy - Constants.sunTopY) / Constants.sunArcDepth).clamp(0.0, 1.0);
    const r = 46.0;
    final alpha = (0x3D + (0x66 - 0x3D) * (1.0 - altitude)).round();
    c.drawRect(
      Rect.fromLTWH(sx + 0.5 - r, sy + 0.5 - r, r * 2, r * 2),
      Paint()
        ..shader = Gradient.radial(Offset(sx + 0.5, sy + 0.5), r, [
          Color.fromARGB(alpha, 255, 214, 130),
          Color.fromARGB(0, 255, 214, 130),
        ]),
    );
  }

  /// Plain-mode cells: batched per-material paths, per-cell water depth
  /// tint, per-cell shade for granular materials, per-cell detail for
  /// furniture when zoomed in, structure grid lines and damage cracks when
  /// zoomed in, damaged-structure darkening, and the spurt overlay.
  static void _drawCells(
    Canvas c,
    World w,
    Water water,
    int x0,
    int y0,
    int x1,
    int y1,
    double cellPx,
  ) {
    final paint = Paint();
    final paths = <Material, Path>{};
    final detail = cellPx >= 4;
    const W = Constants.gridW;

    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final m = w.at(x, y);
        if (m == Material.air) continue;
        final rect = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1);
        switch (m) {
          case Material.water:
            paint.color = _waterColor(water.head[w.idx(x, y)]);
            c.drawRect(rect, paint);
          case Material.ground:
            paint.color = _groundShades[(x * 7 + y * 13) % 3];
            c.drawRect(rect, paint);
          case Material.rubble:
            paint.color = _rubbleShades[(x * 7 + y * 13) % 3];
            c.drawRect(rect, paint);
          case Material.debris:
            paint.color = _debrisShades[(x * 7 + y * 13) % 3];
            c.drawRect(rect, paint);
          default:
            if (detail && Materials.furnitureByIndex[m.index]) {
              paint.color = _mat[m]!;
              c.drawRect(rect, paint);
              _drawFurnitureDetail(c, w, m, x, y, paint);
            } else {
              paths.putIfAbsent(m, () => Path()).addRect(rect);
            }
        }
      }
    }

    paths.forEach((m, p) {
      paint.color = _mat[m]!;
      c.drawPath(p, paint);
    });

    if (cellPx >= 6) {
      final p = Path();
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          final m = w.at(x, y);
          if (!Materials.structureByIndex[m.index]) continue;
          p.addRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1));
        }
      }
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 / cellPx
        ..color = const Color(0x26000000);
      c.drawPath(p, paint);
    }

    // Damaged structure: a darkening overlay scaled by the missing hp, plus
    // crack strokes when zoomed in (first crack below 70% hp, a second
    // below 35%).
    for (var i = 0; i < w.cells.length; i++) {
      final m = w.cells[i];
      if (!Materials.structureByIndex[m.index]) continue;
      final maxHp = Materials.hpByIndex[m.index];
      final hp = w.strength[i];
      if (hp >= maxHp) continue;
      final x = i % W;
      final y = i ~/ W;
      if (x < x0 || x >= x1 || y < y0 || y >= y1) continue;
      paint.color = Color.fromARGB(
        ((1 - hp / maxHp) * 120).round().clamp(0, 160),
        0,
        0,
        0,
      );
      c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), paint);
      final frac = hp / maxHp;
      if (cellPx >= 5 && frac < 0.7) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 / cellPx
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x80000000);
        final p = Path()
          ..moveTo(x + 0.15, y + 0.25)
          ..lineTo(x + 0.55, y + 0.62);
        if (frac < 0.35) {
          p
            ..moveTo(x + 0.78, y + 0.12)
            ..lineTo(x + 0.42, y + 0.85);
        }
        c.drawPath(p, paint);
      }
    }

    // Spurt overlay (the held jet columns; out of the grid).
    for (var x = x0; x < x1; x++) {
      final s = water.spurts[x];
      if (!s.active) continue;
      for (var y = s.top; y < s.top + s.h; y++) {
        if (y < 0 || y >= Constants.gridH) continue;
        paint.color = _waterColor(water.spurtCellHead(x, y));
        c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), paint);
      }
    }
  }

  /// The plain-view colour of a material (the HUD's hover swatch).
  static Color materialColor(Material m) =>
      _mat[m] ?? const Color(0xFF888888);

  /// Sub-rect detail that makes a furniture cell read as its item when
  /// zoomed in: a chair back, a plant pot, a TV screen, a fridge door seam,
  /// a tabletop, a bed pillow, a tub rim, sofa arms. Multi-cell footprints
  /// check their neighbours so a sofa's arms land only on its end cells and
  /// the pillow only at the bed's head.
  static void _drawFurnitureDetail(
    Canvas c,
    World w,
    Material m,
    int x,
    int y,
    Paint paint,
  ) {
    const W = Constants.gridW;
    final left = x > 0 ? w.at(x - 1, y) : Material.air;
    final right = x + 1 < W ? w.at(x + 1, y) : Material.air;
    switch (m) {
      case Material.chair:
        paint.color = const Color(0xFF7A3A20);
        c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 0.38, 1), paint);
      case Material.plant:
        paint.color = const Color(0xFF8A5A33);
        c.drawRect(Rect.fromLTWH(x.toDouble(), y + 0.62, 1, 0.38), paint);
        paint.color = const Color(0xFF2F6E30);
        c.drawRect(Rect.fromLTWH(x + 0.2, y + 0.3, 0.6, 0.32), paint);
      case Material.tv:
        paint.color = const Color(0xFF2E4A5E);
        c.drawRect(Rect.fromLTWH(x + 0.16, y + 0.2, 0.68, 0.6), paint);
      case Material.fridge:
        paint.color = const Color(0xFFDDE0E5);
        c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 0.36), paint);
        paint.color = const Color(0xFF9AA0A8);
        c.drawRect(Rect.fromLTWH(x.toDouble(), y + 0.36, 1, 0.05), paint);
      case Material.desk:
        paint.color = const Color(0xFFA97B4B);
        c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 0.3), paint);
      case Material.table:
        paint.color = const Color(0xFFBC8550);
        c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 0.34), paint);
      case Material.counter:
        paint.color = const Color(0xFFEDE4CD);
        c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 0.3), paint);
      case Material.bed:
        if (left != Material.bed) {
          paint.color = const Color(0xFFE8ECF2);
          c.drawRect(Rect.fromLTWH(x + 0.08, y + 0.26, 0.3, 0.48), paint);
        }
      case Material.tub:
        paint.color = const Color(0xFFD3D7E0);
        c.drawRect(Rect.fromLTWH(x + 0.14, y + 0.14, 0.72, 0.72), paint);
      case Material.sofa:
        paint.color = const Color(0xFF4A5B4A);
        if (left != Material.sofa) {
          c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 0.24, 1), paint);
        }
        if (right != Material.sofa) {
          c.drawRect(Rect.fromLTWH(x + 0.76, y.toDouble(), 0.24, 1), paint);
        }
      default:
        break;
    }
  }

  /// The wavy water-surface line (SPEC 7) and the decorative glow band
  /// (SPEC 9). The wave is the core's [Waves.surface], so the drawn line
  /// moves with the traced glint and caustic. Only at-rest water gets a
  /// surface: a water run counts as at rest when its bottom cell has
  /// water or a permanent wall under it (open air under it = falling
  /// rain, pour, pour-off sheet; a mobile grain under it sinks or
  /// floats out on the next buoyancy pass), so a falling drop above the
  /// pool keeps the pool's own surface point. A real surface changes
  /// level by at most a cell between neighbouring columns (water levels
  /// out sideways), so a jump bigger than that — a jet spurt above its
  /// pool, a cliff between two levels — starts a new subpath instead of
  /// drawing a chord across the gap.
  static void _drawSurface(
    Canvas c,
    World w,
    Water water,
    double t,
    bool glow,
    double cellPx,
  ) {
    final paint = Paint();
    final line = Path();
    var prevAtRest = false;
    var prevWy = -1e9;
    var anyPoint = false;
    const twoPi = 6.283185307179586;

    for (var x = 0; x < Constants.gridW; x++) {
      final s = water.spurts[x];
      int surf;
      if (s.active) {
        surf = s.top;
      } else {
        // Scan the column's water runs top-down and take the top of the
        // first at-rest run. A run is at rest when its bottom cell has
        // water or a permanent wall under it: open air under the bottom
        // = falling (rain, pour, pour-off sheet), and a mobile grain
        // (rubble, debris, furniture, lamp) under it sinks or floats out
        // on the next buoyancy pass. A falling drop above the pool must
        // not take the column's point, or the pool's surface line gaps
        // out under every passing drop.
        surf = -1;
        var y = 0;
        while (surf < 0 && y < Constants.gridH) {
          if (w.at(x, y) != Material.water) {
            y++;
            continue;
          }
          var bottom = y;
          while (bottom + 1 < Constants.gridH &&
              w.at(x, bottom + 1) == Material.water) {
            bottom++;
          }
          final below = bottom + 1 < Constants.gridH
              ? w.at(x, bottom + 1)
              : Material.ground;
          if (below == Material.water ||
              Materials.blocksWaterByIndex[below.index]) {
            surf = y;
          }
          y = bottom + 1;
        }
      }
      if (surf < 0) {
        prevAtRest = false;
        continue;
      }

      final off = Waves.surface(x.toDouble(), t) * 0.35;
      final wy = surf - 0.12 + off;

      // Connect only across small level changes: a real surface moves at
      // most a cell or two between neighbours. A bigger jump (a mid-sky
      // point beside a pool, a spurt above its pool, a cliff) is a gap,
      // not a slope — start a new subpath instead of a long chord.
      if (prevAtRest && (wy - prevWy).abs() <= 2.0) {
        line.lineTo(x + 0.5, wy + 0.05);
      } else {
        line.moveTo(x + 0.5, wy + 0.05);
      }
      prevAtRest = true;
      prevWy = wy;
      anyPoint = true;

      if (glow) {
        final a = 0.10 +
            0.08 * math.sin(0.5 * x + twoPi * t / 7) +
            0.25 * math.pow(math.max(0.0, math.sin(1.3 * x + 2.1 * t)), 16);
        paint.color = Color.fromARGB(a.round().clamp(0, 90), 255, 255, 230);
        c.drawRect(Rect.fromLTWH(x.toDouble(), wy - 0.75, 1, 0.75), paint);
      }
    }

    if (anyPoint) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 / cellPx
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xB8E8FFFF);
      c.drawPath(line, paint);
    }
  }

  static void _drawLamps(Canvas c, World w) {
    final paint = Paint();
    for (final lamp in w.lamps) {
      final cx = lamp.x + 0.5;
      final cy = lamp.y + 0.5;
      if (lamp.isLit) {
        c.drawCircle(Offset(cx, cy), 2.2, paint..color = const Color(0x33FFC85A));
        c.drawCircle(Offset(cx, cy), 0.35, paint..color = const Color(0xFFFFD27F));
      } else {
        c.drawCircle(Offset(cx, cy), 0.35, paint..color = const Color(0xFF8A8F98));
      }
    }
  }

  static void _drawSun(Canvas c, Sun sun, {required bool small}) {
    final (sx, sy) = Sun.position(sun.timeSec);
    if (sx >= Constants.gridW) return; // below the horizon in the wrap gap
    final paint = Paint();
    c.drawCircle(
      Offset(sx + 0.5, sy + 0.5),
      4.0,
      paint..color = const Color(0x40FFC85A),
    );
    c.drawCircle(
      Offset(sx + 0.5, sy + 0.5),
      2.0,
      paint..color = small ? const Color(0xB8FFD87A) : const Color(0xFFFFD87A),
    );
  }

  /// The hover crosshair (the hovered cell, for the HUD readout). The stroke
  /// is screen-constant (1.5 px) so it stays crisp at fit zoom, where a
  /// fixed world-unit stroke would be sub-pixel.
  static void _drawHover(Canvas c, (int, int) hover, double cellPx) {
    if (hover.$1 < 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / cellPx
      ..color = const Color(0xCCFFFFFF);
    c.drawRect(
      Rect.fromLTWH(hover.$1.toDouble(), hover.$2.toDouble(), 1, 1),
      paint,
    );
  }

  /// Water colour by head (depth in cells): light cyan at the surface to
  /// deep blue-green (SPEC 7: water darkens quickly with depth).
  static Color _waterColor(int h) {
    final t = (h / 12).clamp(0.0, 1.0);
    return Color.fromARGB(
      (153 + 51 * t).round(),
      (127 - 116 * t).round(),
      (212 - 153 * t).round(),
      (255 - 163 * t).round(),
    );
  }
}
