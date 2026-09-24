import 'constants.dart';
import 'materials.dart';
import 'world.dart';

/// Structural failure (SPEC 5 / PLAN decision): a section that loses its load
/// path to the foundation — severed by a support gap of >= [Constants.severGap]
/// cells; gaps of <= 2 air cells still bridge — slumps into rubble over
/// [Constants.slumpTicks] (~2 sim-seconds), rather than vanishing.
///
/// Support model: a structural cell is supported when it is 4-connected to a
/// structural cell resting directly on ground, through structural cells,
/// where a vertical gap of up to `severGap - 1` (2) air cells bridges. A
/// disconnected component is a severed section: it slumps for
/// [Constants.slumpTicks], then breaks — structure -> rubble, wood -> debris —
/// and the broken cells fall as loose objects (see `loose.dart`).
///
/// Cost: one full-grid support BFS per tick, with per-cell work as a flat
/// array lookup — a severed section of S cells costs O(S), not O(S^2).
class Structure {
  /// Slumping sections: deterministic section id (the component's minimum
  /// cell index) -> ticks remaining before release.
  final Map<int, int> slumping = {};

  /// "Supported this tick" stamp per cell (a flat array beats a fresh
  /// Set<int> per tick: no hashing, no allocation).
  final List<int> _sup = List.filled(Constants.gridW * Constants.gridH, 0);
  int _supGen = 0;

  /// "Already in a detected component" stamp per cell, so a severed section
  /// is found once per tick, not once per cell.
  final List<int> _seen = List.filled(Constants.gridW * Constants.gridH, 0);
  int _seenGen = 0;

  /// Reusable BFS worklists.
  final List<int> _stack = [];
  final List<int> _comp = [];

  void _nextSupGen() {
    _supGen++;
    if (_supGen == 0) {
      _sup.fillRange(0, _sup.length, 0);
      _supGen = 1;
    }
  }

  int _nextSeenGen() {
    _seenGen++;
    if (_seenGen == 0) {
      _seen.fillRange(0, _seen.length, 0);
      _seenGen = 1;
    }
    return _seenGen;
  }

  /// One structural tick: the support BFS runs once, then newly severed
  /// sections start their slump and active slumps advance (release into
  /// rubble when the timer elapses).
  void tick(World w) {
    _nextSupGen();
    final supGen = _supGen;
    _supported(w, supGen);
    _detect(w, supGen);
    _advance(w, supGen);
  }

  /// Structural cells connected to the foundation, stamped into [_sup] with
  /// [supGen].
  void _supported(World w, int supGen) {
    const W = Constants.gridW;
    final H = Constants.gridH;
    final cells = w.cells;
    final sup = _sup;
    final stack = _stack..clear();
    for (var i = 0; i < cells.length; i++) {
      if (!Materials.structureByIndex[cells[i].index] || sup[i] == supGen) {
        continue;
      }
      final below = i + W < cells.length ? cells[i + W] : Material.air;
      if (below != Material.ground) continue;
      sup[i] = supGen;
      stack.add(i);
    }
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % W, y = i ~/ W;
      // 4-neighbour structural cells.
      for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + d.$1, ny = y + d.$2;
        if (nx < 0 || nx >= W || ny < 0 || ny >= H) continue;
        final ni = ny * W + nx;
        if (sup[ni] == supGen ||
            !Materials.structureByIndex[cells[ni].index]) {
          continue;
        }
        sup[ni] = supGen;
        stack.add(ni);
      }
      // Vertical gap bridge (both directions): up to severGap-1 (2) air
      // cells, then a structural cell — a slab above, or a column below,
      // spans a small support gap.
      for (final sign in const [-1, 1]) {
        for (var k = 1; k <= Constants.severGap; k++) {
          final ny = y + sign * k;
          if (ny < 0 || ny >= H) break;
          var gap = true;
          for (var g = 1; g < k; g++) {
            if (cells[(y + sign * g) * W + x] != Material.air) {
              gap = false;
              break;
            }
          }
          if (!gap) continue;
          final ni = ny * W + x;
          if (sup[ni] == supGen ||
              !Materials.structureByIndex[cells[ni].index]) {
            continue;
          }
          sup[ni] = supGen;
          stack.add(ni);
        }
      }
    }
  }

  /// Severed (unsupported) sections start their slump timer. Each severed
  /// cell is visited once per tick: a found component is stamped, so a
  /// section of S cells costs one BFS of O(S), not S BFS of O(S).
  void _detect(World w, int supGen) {
    final seenGen = _nextSeenGen();
    final cells = w.cells;
    final seen = _seen;
    final sup = _sup;
    for (var i = 0; i < cells.length; i++) {
      if (seen[i] == seenGen ||
          !Materials.structureByIndex[cells[i].index] ||
          sup[i] == supGen) {
        continue;
      }
      final comp = _component(w, i, supGen, seenGen);
      slumping.putIfAbsent(comp.first, () => Constants.slumpTicks);
      for (final j in comp) {
        seen[j] = seenGen;
      }
    }
  }

  /// Active slumps decrement; at zero the section breaks into rubble/debris.
  /// A section that regains support (re-braced during the slump) is saved.
  void _advance(World w, int supGen) {
    for (final id in slumping.keys.toList()) {
      final left = slumping[id]! - 1;
      if (left > 0) {
        slumping[id] = left;
        continue;
      }
      slumping.remove(id);
      final comp = _component(w, id, supGen, _nextSeenGen());
      if (comp.isEmpty) continue; // released or saved
      for (final i in comp) {
        final m = w.cells[i];
        w.cells[i] = Materials.breaksInto(m);
        w.strength[i] = 0;
        w.destroyedCount++;
      }
    }
  }

  /// The unsupported structural component containing [i] (4-neighbour
  /// connectivity; gaps do not connect severed parts), in the reused
  /// [_comp] list, led by [i] (the minimum cell, since callers scan
  /// row-major). Empty when [i] is no longer an unsupported structural cell.
  List<int> _component(World w, int i, int supGen, int seenGen) {
    const W = Constants.gridW;
    final H = Constants.gridH;
    final cells = w.cells;
    final sup = _sup;
    final seen = _seen;
    final comp = _comp..clear();
    if (!Materials.structureByIndex[cells[i].index] || sup[i] == supGen) {
      return comp;
    }
    comp.add(i);
    seen[i] = seenGen;
    for (var b = 0; b < comp.length; b++) {
      final j = comp[b];
      final x = j % W, y = j ~/ W;
      for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + d.$1, ny = y + d.$2;
        if (nx < 0 || nx >= W || ny < 0 || ny >= H) continue;
        final ni = ny * W + nx;
        if (seen[ni] == seenGen ||
            sup[ni] == supGen ||
            !Materials.structureByIndex[cells[ni].index]) {
          continue;
        }
        seen[ni] = seenGen;
        comp.add(ni);
      }
    }
    return comp;
  }
}
