import 'constants.dart';
import 'materials.dart';
import 'rng.dart';
import 'settings.dart';
import 'lamp.dart';

/// The world grid: the single coordinate space for physics and the tracer.
/// Cell (x, y): x 0..gridW-1, y 0..gridH-1 (y grows downward).
class World {
  final Settings settings;
  final String seed;

  /// Row-major material grid.
  final List<Material> cells;
  /// Current strength (hp) per cell.
  final List<int> strength;
  /// Ground surface: the y of the first ground row (rows >= are ground).
  int groundTopY = 0;

  /// Pool extent (the dug-in water basin in the ground).
  int poolLeft = 0;
  int poolRight = 0;
  int poolTopY = 0; // y of the pool water surface
  int poolBottomY = 0; // y of the pool floor (a ground row)
  int poolDepth = 0;

  /// Tower extent (inclusive columns, inclusive rows).
  int towerLeft = 0;
  int towerRight = 0;
  int towerTopY = 0; // y of the roof slab
  int towerBottomY = 0; // y of the lowest slab row
  /// Structural cells at the end of the last generation pass (the denominator
  /// base for damage: cells that exist at t=0).
  int originalStructuralCount = 0;

  /// Cells destroyed by any cause (tools, erosion, severance) — HUD counter.
  int destroyedCount = 0;
  /// Lamp objects in the world (kind + state tracked separately).
  List<Lamp> lamps = [];

  World(this.settings, this.seed)
      : cells = List.filled(Constants.gridW * Constants.gridH, Material.air),
        strength = List.filled(Constants.gridW * Constants.gridH, 0);

  int idx(int x, int y) => y * Constants.gridW + x;

  Material at(int x, int y) => cells[idx(x, y)];

  void set(int x, int y, Material m) {
    if (x < 0 || x >= Constants.gridW || y < 0 || y >= Constants.gridH) {
      throw RangeError('cell $x,$y out of bounds');
    }
    cells[idx(x, y)] = m;
    strength[idx(x, y)] = Materials.of(m).hp;
  }

  void fillRect(int x0, int y0, int x1, int y1, Material m) {
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        set(x, y, m);
      }
    }
  }

  int countWater() {
    var n = 0;
    for (final m in cells) {
      if (m == Material.water) n++;
    }
    return n;
  }

  int countStructural() {
    var n = 0;
    for (final m in cells) {
      if (Materials.structure.contains(m)) n++;
    }
    return n;
  }

  /// FNV-1a over the whole grid + lamps + settings (determinism tests).
  String fingerprint() {
    final sb = StringBuffer('$seed\0${settings.fingerprint}\0$groundTopY\0');
    for (var i = 0; i < cells.length; i++) {
      sb.write(cells[i].index);
    }
    for (final l in lamps) {
      sb.write('${l.kind.index},$l.x,$l.y,${l.state.index},');
    }
    return Rng.fnv1a64(sb.toString()).toRadixString(16);
  }

  /// Deterministic snapshot (for equality tests; avoids depending on
  /// material names).
  List<int> snapshot() {
    final out = List<int>.filled(cells.length, 0);
    for (var i = 0; i < cells.length; i++) {
      out[i] = cells[i].index;
    }
    return out;
  }
}
