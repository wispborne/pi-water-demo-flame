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

    // Background + day sky (the sky is part of the traced field itself in
    // traced mode, so it is not drawn there).
    c.drawRect(Offset.zero & size, Paint()..color = _bg);
    if (!traced) {
      c.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = Gradient.linear(Offset.zero, Offset(0, size.height), [
            const Color(0xFF8FBFE8),
            const Color(0xFFD8EDFB),
          ]),
      );
    }

    c.save();
    c.translate(cam.offX, cam.offY);
    c.scale(cam.cellPx);

    final (x0, y0, x1, y1) = cam.visible(size.width, size.height);

    if (traced && fieldImage != null) {
      c.drawImage(
        fieldImage,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.none,
      );
    } else if (!traced) {
      _drawCells(c, world, water, x0, y0, x1, y1);
    }
    // Traced with the image not ready yet: the field's settled values are
    // not drawn (the first 1-2 frames after a world rebuild).

    _drawLamps(c, world);
    _drawSun(c, state.sim.sun, small: traced);
    _drawSurface(c, world, water, state.sim.sun.timeSec, state.glow);
    _drawHover(c, hover);

    c.restore();
  }

  /// Plain-mode cells: batched per-material paths, per-cell water depth
  /// tint, per-cell shade for granular materials, damaged-structure
  /// darkening, and the spurt overlay.
  static void _drawCells(
    Canvas c,
    World w,
    Water water,
    int x0,
    int y0,
    int x1,
    int y1,
  ) {
    final paint = Paint();
    final paths = <Material, Path>{};
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
            paths.putIfAbsent(m, () => Path()).addRect(rect);
        }
      }
    }

    paths.forEach((m, p) {
      paint.color = _mat[m]!;
      c.drawPath(p, paint);
    });

    // Damaged structure: a darkening overlay scaled by the missing hp.
    for (var i = 0; i < w.cells.length; i++) {
      final m = w.cells[i];
      if (!Materials.structure.contains(m)) continue;
      final maxHp = Materials.of(m).hp;
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

  /// The wavy water-surface line (SPEC 7) and the decorative glow band
  /// (SPEC 9). The wave is the core's [Waves.surface], so the drawn line
  /// moves with the traced glint and caustic.
  static void _drawSurface(
    Canvas c,
    World w,
    Water water,
    double t,
    bool glow,
  ) {
    final paint = Paint();
    const twoPi = 6.283185307179586;

    for (var x = 0; x < Constants.gridW; x++) {
      final s = water.spurts[x];
      int surf;
      if (s.active) {
        surf = s.top;
      } else {
        surf = -1;
        for (var y = 0; y < Constants.gridH; y++) {
          if (w.at(x, y) == Material.water) {
            final above = y > 0 ? w.at(x, y - 1) : Material.air;
            if (above != Material.water) {
              surf = y;
              break;
            }
          }
        }
      }
      if (surf < 0) continue;

      final off = Waves.surface(x.toDouble(), t) * 0.35;
      final wy = surf - 0.12 + off;

      paint.color = const Color(0xAAE8FFFF);
      c.drawRect(Rect.fromLTWH(x.toDouble(), wy, 1, 0.10), paint);

      if (glow) {
        final a = 0.10 +
            0.08 * math.sin(0.5 * x + twoPi * t / 7) +
            0.25 * math.pow(math.max(0.0, math.sin(1.3 * x + 2.1 * t)), 16);
        paint.color = Color.fromARGB(a.round().clamp(0, 90), 255, 255, 230);
        c.drawRect(Rect.fromLTWH(x.toDouble(), wy - 0.75, 1, 0.75), paint);
      }
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

  /// The hover crosshair (the hovered cell, for the HUD readout).
  static void _drawHover(Canvas c, (int, int) hover) {
    if (hover.$1 < 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.08
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
