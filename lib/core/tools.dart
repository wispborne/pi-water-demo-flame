import 'constants.dart';
import 'materials.dart';
import 'world.dart';

/// The eight user tools (SPEC 8), selectable by mouse or keys 1-8.
/// Initial tool is water (key 3).
enum Tool {
  hammer,
  bomb,
  water,
  erase,
  buildConcrete,
  buildSteel,
  buildGlass,
  buildWood,
}

const _buildMaterial = {
  Tool.buildConcrete: Material.concrete,
  Tool.buildSteel: Material.steel,
  Tool.buildGlass: Material.glass,
  Tool.buildWood: Material.wood,
};

/// User tools (SPEC 8/9): 8 tools, a brush of [brushSize] cells (1..15,
/// default 5), and rain ([rain], 0..40, default 0: water cells per sim-
/// second on the top row, uniform across the full grid width).
///
/// The tools are the only way the user damages or changes the world; ground
/// is not buildable (SPEC 1) and nothing erases it.
class Tools {
  Tool tool = Tool.water;

  /// Brush size in cells (1..15, default 5; SPEC 9).
  int brushSize = Constants.brushDefault;

  /// Rain rate in water cells per sim-second on the top row (0..40,
  /// default 0; SPEC 4).
  int rain = 0;

  /// Fraction of a sim-second of rain already applied (accumulation carry:
  /// 0.2 at 1x, 0.1 at 2x, 0.4 at 0.5x).
  double _carry = 0;

  /// Running drop counter: each spawned drop is the next one in a global
  /// left-to-right walk of the top row (wrapping), so the rain is uniform
  /// across the full width no matter how the drops split across ticks.
  int _drop = 0;

  /// Select a tool by key 1..8 (SPEC 8). Returns false (and selects
  /// nothing) for an out-of-range key.
  bool selectByKey(int key) {
    if (key < 0 || key >= Tool.values.length) return false;
    tool = Tool.values[key];
    return true;
  }

  /// Paint [tool] over a circular brush centred at (cx, cy) — the cells the
  /// user clicked. Returns the number of cells changed.
  int apply(World w, int cx, int cy) {
    switch (tool) {
      case Tool.water:
        return _circle(w, cx, cy, Material.water);
      case Tool.erase:
        return _circle(w, cx, cy, Material.air);
      case Tool.buildConcrete:
      case Tool.buildSteel:
      case Tool.buildGlass:
      case Tool.buildWood:
        return _circle(w, cx, cy, _buildMaterial[tool]!);
      case Tool.hammer:
        return _hammer(w, cx, cy);
      case Tool.bomb:
        return _bomb(w, cx, cy);
    }
  }

  /// One sim-tick of rain: spawn [rain] water cells/s on the top row,
  /// uniform across the full [Constants.gridW] width (SPEC 4). The rate is
  /// per sim-second, so a partial step (the 2x driver's 0.5-tick) applies
  /// exactly half as much — the spawn count is the deterministic function
  /// of time the contract requires.
  ///
  /// A column whose top cell is occupied (a tall tower) defers its drop to
  /// the next tick; its cells are not lost (volume: rain is the only
  /// creation besides erosion).
  void rainTick(World w, double stepSec) {
    if (rain <= 0) {
      _carry = 0;
      return;
    }
    _carry += rain * stepSec;
    var n = _carry.floor();
    if (n <= 0) return;
    _carry -= n;
    final W = Constants.gridW;
    for (var i = 0; i < n; i++) {
      // The next drop in the global left-to-right walk (wrapping) — the
      // uniform distribution across the full grid width (SPEC 4).
      final x = _drop % W;
      if (w.at(x, 0) != Material.air) {
        // Deferred: this tick's column is full at the top; the same drop
        // is retried next tick (its column is not consumed).
        _carry += 1;
        continue;
      }
      _drop++;
      w.set(x, 0, Material.water);
    }
  }

  /// Cells inside the brush circle (radius = brushSize/2, inclusive) that
  /// are not ground (ground is not buildable) and are changed to [m].
  int _circle(World w, int cx, int cy, Material m) {
    final r = brushSize ~/ 2;
    var changed = 0;
    for (var dy = -r; dy <= r; dy++) {
      final y = cy + dy;
      if (y < 0 || y >= Constants.gridH) continue;
      for (var dx = -r; dx <= r; dx++) {
        if (dx * dx + dy * dy > r * r + r) continue; // circular brush
        final x = cx + dx;
        if (x < 0 || x >= Constants.gridW) continue;
        final cur = w.at(x, y);
        if (cur == Material.ground || cur == m) continue;
        w.set(x, y, m);
        changed++;
      }
    }
    return changed;
  }

  /// Hammer (SPEC 8): one strength off every damaged-material cell under
  /// the brush. A cell at strength 1 is destroyed — structure becomes
  /// rubble, everything else becomes debris (the same break as a severed
  /// section, so a hammered slab crumbles, it does not vanish). Ground
  /// never takes damage.
  int _hammer(World w, int cx, int cy) {
    final r = brushSize ~/ 2;
    var hit = 0;
    for (var dy = -r; dy <= r; dy++) {
      final y = cy + dy;
      if (y < 0 || y >= Constants.gridH) continue;
      for (var dx = -r; dx <= r; dx++) {
        if (dx * dx + dy * dy > r * r + r) continue;
        final x = cx + dx;
        if (x < 0 || x >= Constants.gridW) continue;
        if (_hit(w, x, y, 1)) hit++;
      }
    }
    return hit;
  }

  /// Bomb (SPEC 8): a radius blast with a decaying damage falloff — the
  /// centre takes the most damage, the edge the least; every cell under
  /// blast loses at least one strength. A cell at strength 1 is destroyed
  /// into its broken form (structure -> rubble, else debris); ground never
  /// takes damage.
  int _bomb(World w, int cx, int cy) {
    final r = brushSize;
    var hit = 0;
    for (var dy = -r; dy <= r; dy++) {
      final y = cy + dy;
      if (y < 0 || y >= Constants.gridH) continue;
      for (var dx = -r; dx <= r; dx++) {
        if (dx * dx + dy * dy > r * r) continue;
        final x = cx + dx;
        if (x < 0 || x >= Constants.gridW) continue;
        final dist2 = dx * dx + dy * dy;
        // Falloff: r cells (edge) -> 1 damage, centre -> r+1 damage.
        final dmg = (r * r - dist2) ~/ r + 1;
        if (_hit(w, x, y, dmg)) hit++;
      }
    }
    return hit;
  }
  /// Apply [dmg] strength of damage to (x, y). Returns true when the cell
  /// was damaged (including a destruction). Ground is not buildable and
  /// air has nothing to damage; rubble and debris are already broken (no
  /// strength left) and stay broken.
  bool _hit(World w, int x, int y, int dmg) {
    final m = w.at(x, y);
    if (m == Material.air ||
        m == Material.ground ||
        m == Material.rubble ||
        m == Material.debris) {
      return false;
    }
    final hp = w.strength[w.idx(x, y)];
    final left = hp - dmg;
    if (left <= 0) {
      w.cells[w.idx(x, y)] = Materials.breaksInto(m);
      w.strength[w.idx(x, y)] = 0;
      w.destroyedCount++;
    } else {
      w.strength[w.idx(x, y)] = left;
    }
    return true;
  }
}
