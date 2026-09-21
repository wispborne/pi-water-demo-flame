import 'constants.dart';
import 'lamp.dart';
import 'materials.dart';
import 'world.dart';

/// A loose object: a furniture piece or a free lamp. It moves at most one
/// cell per tick: it falls through air, sinks through water (heavy material),
/// or rises to the water surface (light material), displacing the water it
/// passes, until it rests on a solid.
///
/// Broken material (rubble, debris) is NOT a loose object: it is granular
/// (SPEC 5 "fails cell by cell") — each cell falls like sand (see [Buoyancy]).
class LooseObject {
  final Material material;
  int x, y;
  final int w, h;

  /// Index into [World.lamps] when [material] is a lamp; -1 otherwise.
  final int lampIndex;

  LooseObject(
    this.material,
    this.x,
    this.y,
    this.w,
    this.h, {
    this.lampIndex = -1,
  });

  /// Floats to the water surface (material table); otherwise sinks.
  bool get floats => Materials.floats(material);

  /// The object's bottom row.
  int get bottom => y + h - 1;
}

/// Loose-object physics (SPEC 5). Loose items are discovered directly in the
/// grid — no separate registry:
///
/// * **Rigid**: each furniture piece (its 4-connected same-material cells)
///   and each free lamp moves as a unit, at most one cell per tick.
/// * **Granular**: rubble and debris cells fall one cell at a time (a broken
///   section crumbles, it does not slide as a slab); rubble sinks through
///   water, debris floats to the surface.
///
/// Water never overlaps an object: when an object moves vertically, the
/// water in the row it moves into is displaced into the row it vacates
/// (volume-conserving), so a flooded room's surface rises around floats.
class Buoyancy {
  /// The loose objects currently in the world (rebuilt by [resync]).
  final List<LooseObject> objects = [];

  /// Rebuild [objects] from the grid: each furniture piece (its 4-connected
  /// same-material cells) and each free lamp. A ceiling lamp is released
  /// (fixed -> free) when the slab above it has broken — i.e. the cell
  /// directly above it is no longer structure (SPEC 2).
  void resync(World w) {
    objects.clear();
    const W = Constants.gridW;
    final H = Constants.gridH;
    final seen = List.filled(w.cells.length, false);
    for (var i = 0; i < w.cells.length; i++) {
      if (seen[i]) continue;
      final m = w.cells[i];
      final x = i % W, y = i ~/ W;
      if (m == Material.lamp) {
        seen[i] = true;
        var lampIndex = -1;
        for (var k = 0; k < w.lamps.length; k++) {
          final l = w.lamps[k];
          if (l.state != LampState.broken && l.x == x && l.y == y) {
            lampIndex = k;
            break;
          }
        }
        if (lampIndex >= 0 && w.lamps[lampIndex].state == LampState.fixed) {
          final above = y > 0 ? w.cells[i - W] : Material.air;
          if (Materials.structure.contains(above)) continue; // still fixed
          w.lamps[lampIndex].state = LampState.free; // its ceiling broke
        }
        objects.add(LooseObject(m, x, y, 1, 1, lampIndex: lampIndex));
        continue;
      }
      if (!Materials.isFurniture(m)) continue;
      // 4-connected same-material mass (a furniture piece).
      var minx = x, maxx = x, miny = y, maxy = y;
      final comp = <int>[i];
      seen[i] = true;
      for (var b = 0; b < comp.length; b++) {
        final j = comp[b];
        final cx = j % W, cy = j ~/ W;
        if (cx < minx) minx = cx;
        if (cx > maxx) maxx = cx;
        if (cy < miny) miny = cy;
        if (cy > maxy) maxy = cy;
        for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = cx + d.$1, ny = cy + d.$2;
          if (nx < 0 || nx >= W || ny < 0 || ny >= H) continue;
          final ni = ny * W + nx;
          if (seen[ni] || w.cells[ni] != m) continue;
          seen[ni] = true;
          comp.add(ni);
        }
      }
      objects.add(LooseObject(m, minx, miny, maxx - minx + 1, maxy - miny + 1));
    }
  }

  /// One buoyancy tick: rigid objects move at most one cell; rubble and
  /// debris cells fall (or rise, for debris in water) at most one cell.
  void tick(World w) {
    for (final o in objects) {
      _moveOne(w, o);
    }
    _granular(w);
  }

  void _moveOne(World w, LooseObject o) {
    final H = Constants.gridH;
    var canFall = o.bottom + 1 < H;
    var allWaterBelow = canFall;
    for (var dx = 0; dx < o.w && canFall; dx++) {
      final m = w.at(o.x + dx, o.bottom + 1);
      if (!_passable(m)) canFall = false;
      if (m != Material.water) allWaterBelow = false;
    }
    if (canFall) {
      if (!o.floats) {
        _shift(w, o, 0, 1); // heavy: sinks through air and water
        return;
      }
      if (_submerged(w, o)) {
        _shift(w, o, 0, -1); // light: rises through fully submerged water
        return;
      }
      if (allWaterBelow) return; // at the surface (air above): rest
      _shift(w, o, 0, 1); // light: falls through dry air
      return;
    }
    // Blocked below (solid or grid bottom): a submerged float rises.
    if (o.floats && _submerged(w, o)) {
      _shift(w, o, 0, -1);
    }
  }

  /// Granular broken material: rubble sinks, debris floats (SPEC 5).
  void _granular(World w) {
    const W = Constants.gridW;
    final H = Constants.gridH;
    for (var y = H - 2; y >= 0; y--) {
      final ltr = y.isEven; // deterministic per-row scan order
      for (var c = 0; c < W; c++) {
        final x = ltr ? c : (W - 1 - c);
        final i = y * W + x;
        final m = w.cells[i];
        if (m != Material.rubble && m != Material.debris) continue;
        final below = w.cells[i + W];
        if (below == Material.air) {
          w.cells[i + W] = m;
          w.cells[i] = Material.air;
          continue;
        }
        if (below != Material.water) continue;
        if (m == Material.rubble) {
          // Sinks: swap with the water below.
          w.cells[i + W] = m;
          w.cells[i] = Material.water;
        } else {
          // Debris floats: rises only when fully submerged (water above too),
          // rests at the surface.
          final above = w.cells[i - W];
          if (above == Material.water) {
            w.cells[i - W] = m;
            w.cells[i] = Material.water;
          }
        }
      }
    }
  }

  /// Fully submerged: every cell above the object's top row is water.
  /// (A float at the surface has air/wall above and rests — no jitter.)
  bool _submerged(World w, LooseObject o) {
    if (o.y - 1 < 0) return false;
    for (var dx = 0; dx < o.w; dx++) {
      if (w.at(o.x + dx, o.y - 1) != Material.water) return false;
    }
    return true;
  }

  static bool _passable(Material m) => m == Material.air || m == Material.water;

  /// Move the object to (x+dx, y+dy) = (0, ±1). The water in the row the
  /// object moves into is displaced into the row the object vacates
  /// (volume-conserving; water never overlaps the object). No-op when the
  /// target row is not passable.
  void _shift(World w, LooseObject o, int dx, int dy) {
    final W = Constants.gridW, H = Constants.gridH;
    final nx = o.x + dx, ny = o.y + dy;
    if (nx < 0 || nx + o.w > W || ny < 0 || ny + o.h > H) return;
    // Only the row the object moves INTO is new; its other rows are its
    // own cells. No-op when that row is not passable.
    final entryRow = dy > 0 ? ny + o.h - 1 : ny;
    for (var c = nx; c < nx + o.w; c++) {
      if (!_passable(w.at(c, entryRow))) return;
    }
    // Displace the water in the entry row into the row the object vacates
    // (volume-conserving; water never overlaps the object), then clear the
    // vacated row (otherwise the object smears its material behind it when
    // moving through air).
    final vacatedRow = dy > 0 ? o.y : o.bottom;
    for (var c = nx; c < nx + o.w; c++) {
      if (w.at(c, entryRow) == Material.water) {
        w.set(c, vacatedRow, Material.water);
      } else {
        w.set(c, vacatedRow, Material.air);
      }
      w.set(c, entryRow, Material.air);
    }
    for (var yy = 0; yy < o.h; yy++) {
      for (var xx = 0; xx < o.w; xx++) {
        w.set(nx + xx, ny + yy, o.material);
      }
    }
    o.x = nx;
    o.y = ny;
    if (o.lampIndex >= 0) {
      w.lamps[o.lampIndex].x = o.x;
      w.lamps[o.lampIndex].y = o.y;
    }
  }
}
