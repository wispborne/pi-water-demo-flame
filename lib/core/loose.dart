import 'constants.dart';
import 'materials.dart';
import 'world.dart';

/// A loose object: a furniture piece, a lamp, or a broken cell (rubble/debris)
/// that is no longer attached to the structure. It moves one cell per tick
/// (floats up or sinks down) until it lands back on a solid surface.
class LooseObject {
  final Material material;
  /// Top-left cell; [h] is 1 for single cells and lamps.
  int x, y;
  final int w, h;
  /// The lamp object, when [material] is a lamp (kept lit/falls as a loose lamp).
  int lampIndex;

  LooseObject(this.material, this.x, this.y, this.w, this.h,
      {this.lampIndex = -1});

  bool get floats => Materials.floats(material);
  bool get shatterable => material == Material.rubble || material == Material.debris;

  /// The lamp object id; -1 = not a lamp. (Field kept for API symmetry;
  /// callers may use [lampIndex] directly.)
}

/// Buoyancy rules (SPEC 5 / PLAN decision 6): a loose object floats when the
/// cells under it are all pass-through (and there is water below it — a dry
/// hole does not float things), sinks when they are all pass-through, and
/// otherwise rests where it is.
class Buoyancy {
  static bool canFloat(Material m) => Materials.floats(m);
  static bool canSink(Material m) => !Materials.floats(m);

  /// Floats: every cell under the object is pass-through and some water is
  /// below it.
  static bool floatsAt(World w, LooseObject o) {
    for (var dx = 0; dx < o.w; dx++) {
      for (var dy = 0; dy < o.h; dy++) {
        if (!_passableBelow(w, o, dx, dy)) return false;
      }
    }
    var water = false;
    for (var dx = 0; dx < o.w; dx++) {
      for (var dy = 0; dy < o.h; dy++) {
        final m = _below(w, o, dx, dy);
        if (m == Material.water) water = true;
      }
    }
    return water;
  }

  /// Sinks: every cell under the object is pass-through (no water required,
  /// so things also drop through dry holes).
  static bool sinksAt(World w, LooseObject o) {
    for (var dx = 0; dx < o.w; dx++) {
      for (var dy = 0; dy < o.h; dy++) {
        if (!_passableBelow(w, o, dx, dy)) return false;
      }
    }
    return true;
  }

  static bool _passableBelow(World w, LooseObject o, int dx, int dy) {
    final m = _below(w, o, dx, dy);
    return m == Material.air ||
        m == Material.water ||
        m == Material.rubble ||
        m == Material.debris;
  }

  static Material? _below(World w, LooseObject o, int dx, int dy) {
    final x = o.x + dx;
    final y = o.y + o.h + dy;
    if (x < 0 || x >= Constants.gridW || y < 0 || y >= Constants.gridH) return null;
    return w.at(x, y);
  }
}
