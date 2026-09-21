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
/// [Constants.slumpTicks], then breaks — structure -> rubble, wood -> debris
/// — and the broken cells fall as loose objects (see `loose.dart`).
class Structure {
  /// Slumping sections: deterministic section id (the component's minimum
  /// cell index) -> ticks remaining before release.
  final Map<int, int> slumping = {};

  /// One structural tick: detect newly severed sections (start their slump)
  /// and advance active slumps (release into rubble when the timer elapses).
  void tick(World w) {
    _detect(w);
    _advance(w);
  }

  /// Structural cells connected to the foundation.
  Set<int> _supported(World w) {
    const W = Constants.gridW;
    final H = Constants.gridH;
    final out = <int>{};
    final stack = <int>[];
    for (var y = 0; y < H; y++) {
      for (var x = 0; x < W; x++) {
        final i = y * W + x;
        if (!Materials.structure.contains(w.cells[i]) || out.contains(i)) {
          continue;
        }
        final below = y + 1 < H ? w.cells[i + W] : Material.air;
        if (below != Material.ground) continue;
        out.add(i);
        stack.add(i);
      }
    }
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % W, y = i ~/ W;
      // 4-neighbour structural cells.
      for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + d.$1, ny = y + d.$2;
        if (nx < 0 || nx >= W || ny < 0 || ny >= H) continue;
        final ni = ny * W + nx;
        if (out.contains(ni) || !Materials.structure.contains(w.cells[ni])) {
          continue;
        }
        out.add(ni);
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
            if (w.cells[(y + sign * g) * W + x] != Material.air) {
              gap = false;
              break;
            }
          }
          if (!gap) continue;
          final ni = ny * W + x;
          if (out.contains(ni) || !Materials.structure.contains(w.cells[ni])) {
            continue;
          }
          out.add(ni);
          stack.add(ni);
        }
      }
    }
    return out;
  }

  /// Severed (unsupported) sections start their slump timer.
  void _detect(World w) {
    final supported = _supported(w);
    final seen = List.filled(w.cells.length, false);
    for (var i = 0; i < w.cells.length; i++) {
      if (seen[i] ||
          !Materials.structure.contains(w.cells[i]) ||
          supported.contains(i)) {
        continue;
      }
      final comp = _component(w, i, supported);
      slumping.putIfAbsent(comp.first, () => Constants.slumpTicks);
    }
  }

  /// Active slumps decrement; at zero the section breaks into rubble/debris.
  /// A section that regains support (re-braced during the slump) is saved.
  void _advance(World w) {
    for (final id in slumping.keys.toList()) {
      final left = slumping[id]! - 1;
      if (left > 0) {
        slumping[id] = left;
        continue;
      }
      slumping.remove(id);
      final comp = _component(w, id, _supported(w));
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
  /// connectivity; gaps do not connect severed parts), identified by its
  /// minimum cell index. Empty when [i] is no longer an unsupported
  /// structural cell.
  List<int> _component(World w, int i, Set<int> supported) {
    const W = Constants.gridW;
    final H = Constants.gridH;
    if (!Materials.structure.contains(w.cells[i]) || supported.contains(i)) {
      return const [];
    }
    final seen = <int>{i};
    final comp = <int>[i];
    for (var b = 0; b < comp.length; b++) {
      final j = comp[b];
      final x = j % W, y = j ~/ W;
      for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + d.$1, ny = y + d.$2;
        if (nx < 0 || nx >= W || ny < 0 || ny >= H) continue;
        final ni = ny * W + nx;
        if (seen.contains(ni) ||
            !Materials.structure.contains(w.cells[ni]) ||
            supported.contains(ni)) {
          continue;
        }
        seen.add(ni);
        comp.add(ni);
      }
    }
    return comp;
  }
}
