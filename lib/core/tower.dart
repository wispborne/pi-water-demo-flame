import 'dart:math' show min;

import 'constants.dart';
import 'lamp.dart';
import 'materials.dart';
import 'rng.dart';
import 'settings.dart';
import 'world.dart';

/// Deterministically builds the whole t=0 world from seed + settings (ADR 0001).
/// Every world section draws from its own sub-stream (a re-hash of
/// seed + section name), so the layout is independent of draw order.
class WorldBuilder {
  final String seed;
  final Settings settings;

  WorldBuilder(this.seed, this.settings);

  Rng _stream(String section) => Rng.fromString(seed, section);

  World build() {
    final w = World(settings, seed);
    _ground(w);
    _tower(w);
    _pool(w);
    w.originalStructuralCount = w.countStructural();
    return w;
  }

  /// The very hard earth; its surface is seeded 12..28 cells above the bottom.
  void _ground(World w) {
    final rng = _stream('ground');
    final level = rng.range(Constants.groundLevelMin, Constants.groundLevelMax);
    final topY = Constants.gridH - 1 - level;
    w.groundTopY = topY;
    w.fillRect(0, topY, Constants.gridW - 1, Constants.gridH - 1, Material.ground);
  }

  void _tower(World w) {
    final f = settings.floors;
    final bays = settings.width;
    final mat = _structureMaterial();

    final towerW = bays * Constants.bayWidth + 2;
    final cx = Constants.gridW ~/ 2;
    final left = cx - towerW ~/ 2;
    final baseY = w.groundTopY - 1; // base slab sits on the ground surface
    w.towerLeft = left;
    w.towerRight = left + towerW - 1;
    w.towerBottomY = baseY;
    w.towerTopY = baseY - f * Constants.floorHeight; // roof slab

    // Slabs: one per floor (at the bottom of each floor band), plus a roof.
    for (var i = 0; i <= f; i++) {
      final slabY = baseY - i * Constants.floorHeight;
      w.fillRect(left, slabY, w.towerRight, slabY, mat);
    }

    // Outer walls: full-height columns on both edges.
    w.fillRect(left, w.towerTopY, left, baseY, mat);
    w.fillRect(w.towerRight, w.towerTopY, w.towerRight, baseY, mat);

    for (var fi = 0; fi < f; fi++) {
      final floorSlabY = baseY - fi * Constants.floorHeight;
      final ceilingSlabY = floorSlabY - Constants.floorHeight;
      final rng = _stream('floor $fi');
      _floor(w, fi, left, bays, floorSlabY, ceilingSlabY, mat, rng);
    }
  }

  void _floor(
    World w,
    int floorIndex,
    int left,
    int bays,
    int floorSlabY,
    int ceilingSlabY,
    Material mat,
    Rng rng,
  ) {
    // The 3 interior rows sit above the floor slab (y grows downward, so
    // "above" = smaller y). floorSlabY-3 is topmost, floorSlabY-1 just above slab.
    final interiorRows = <int>[
      floorSlabY - 3,
      floorSlabY - 2,
      floorSlabY - 1,
    ];
    final floorBase = floorSlabY - 1; // item base: sits on the slab
    final ceilingRow = interiorRows.first; // just below the ceiling slab

    final slotXs = List.generate(
        bays - 1, (k) => left + 1 + (k + 1) * Constants.bayWidth);

    // Splits: 1..3 rooms, capped at the bay count (a floor with b bays has
    // b-1 partition slots -> at most b rooms). bays==1 collapses to 1 room.
    final splits = min(rng.range(1, 3), bays);
    final parts = <int>[];
    if (splits > 1) {
      final chosen = <int>{};
      while (chosen.length < splits - 1) {
        chosen.add(slotXs[rng.range(0, slotXs.length - 1)]);
      }
      parts.addAll(chosen);
      parts.sort(); // ascending x, so room segments below are ordered
      for (final px in parts) {
        for (final y in interiorRows) {
          w.set(px, y, mat); // 1-cell partition walls
        }
      }
    }

    // Room segments (contiguous bay runs).
    final lastEnd = left + 1 + bays * Constants.bayWidth - 1;
    final roomCount = parts.length + 1;
    for (var r = 0; r < roomCount; r++) {
      final s = r == 0 ? left + 1 : parts[r - 1] + 1;
      final e = r == roomCount - 1 ? lastEnd : parts[r] - 1;
      _placeRoom(w, s, e, interiorRows, floorBase, ceilingRow, rng);
    }
  }

  void _placeRoom(
    World w,
    int s,
    int e,
    List<int> rows,
    int floorBase,
    int ceilingRow,
    Rng rng,
  ) {
    final x0 = s;
    final x1 = e;

    // ---- Furniture: a random non-overlapping mix of 2..5 items.
    final types = _fisherYates(Materials.furnitureTypes.toList(), rng);
    final n = rng.range(2, 5);
    final chosen = types.sublist(0, n); // no replacement -> at most one of each
    bool tryPlace(Material m) {
      final (fw, fh) = Materials.furnitureSize[m]!;
      if (fw > (x1 - x0 + 1) || fh > 3) return false; // 3 interior rows tall
      for (var attempt = 0; attempt < 8; attempt++) {
        final px = rng.range(x0, x1 - fw + 1);
        // Items sit on the floor slab: base at floorBase, rising (smaller y).
        final py = floorBase;
        if (_fits(w, px, py, fw, fh)) {
          for (var dy = 0; dy < fh; dy++) {
            for (var dx = 0; dx < fw; dx++) {
              w.set(px + dx, py - dy, m);
            }
          }
          return true;
        }
      }
      return false;
    }
    // A draw that does not fit is redrawn once, then skipped (SPEC 2).
    // A redraw picks a type NOT in `chosen` (so it can never equal an
    // original draw) and NOT already placed, so a room never gets two of
    // the same type.
    final chosenSet = chosen.toSet();
    final used = <Material>{};
    for (final m in chosen) {
      if (tryPlace(m)) {
        used.add(m);
      } else {
        final pool = <Material>[];
        for (final t in Materials.furnitureTypes) {
          if (!chosenSet.contains(t) && !used.contains(t)) pool.add(t);
        }
        if (pool.isNotEmpty) {
          final redrawn = pool[rng.range(0, pool.length - 1)];
          if (tryPlace(redrawn)) used.add(redrawn);
        }
      }
    }

    // ---- Lamps: 1..3 kinds, no duplicates.
    final kinds =
        _fisherYates([LampKind.floor, LampKind.ceiling, LampKind.table], rng);
    final nL = rng.range(1, 3);
    final lampKinds = kinds.sublist(0, nL);

    // Table cells (a table lamp sits on top of a table cell).
    final tableCells = <List<int>>[];
    for (final y in rows) {
      for (var x = x0; x <= x1; x++) {
        if (w.at(x, y) == Material.table) tableCells.add([x, y]);
      }
    }

    for (final kind in lampKinds) {
      final (lx, ly) = _lampSpot(w, kind, s, e, floorBase, ceilingRow, tableCells);
      if (lx < 0) continue; // no free spot -> skip this lamp
      w.set(lx, ly, Material.lamp);
      w.lamps.add(Lamp(
        kind,
        lx,
        ly,
        state: kind == LampKind.ceiling ? LampState.fixed : LampState.free,
      ));
    }
  }

  /// Find a free column at [row], scanning outward from the room centre.
  /// Returns the column, or -1 if the whole room row is occupied.
  int _freeCol(World w, int s, int e, int row) {
    final cx = s + (e - s) ~/ 2;
    for (var d = 0; d <= (e - s) ~/ 2 + 1; d++) {
      for (final x in [cx + d, cx - d]) {
        if (x < s || x > e) continue;
        if (w.at(x, row) == Material.air) return x;
      }
    }
    return -1;
  }

  /// (x, y) for a lamp, or (-1, -1) when no free spot exists.
  (int, int) _lampSpot(
    World w,
    LampKind kind,
    int s,
    int e,
    int floorBase,
    int ceilingRow,
    List<List<int>> tableCells,
  ) {
    switch (kind) {
      case LampKind.floor:
        // On the room floor, on the slab (same base as furniture).
        final x = _freeCol(w, s, e, floorBase);
        return x < 0 ? (-1, -1) : (x, floorBase);
      case LampKind.ceiling:
        // Fixed to the ceiling (just below the ceiling slab).
        final x = _freeCol(w, s, e, ceilingRow);
        return x < 0 ? (-1, -1) : (x, ceilingRow);
      case LampKind.table:
        // On top of a table (the highest table cell); else the floor (SPEC 2).
        if (tableCells.isNotEmpty) {
          var top = tableCells.first;
          for (final c in tableCells) {
            if (c[1] < top[1]) top = c;
          }
          final tx = top[0];
          final ty = top[1] - 1;
          if (w.at(tx, ty) == Material.air) return (tx, ty);
        }
        final x = _freeCol(w, s, e, floorBase);
        return x < 0 ? (-1, -1) : (x, floorBase);
    }
  }

  /// True if the footprint fits in the room and every cell is free (air or
  /// a pass-through material) so placed items never share a cell.
  bool _fits(World w, int x, int y, int fw, int fh) {
    if (x < 0 || x + fw > Constants.gridW || y - fh + 1 < 0) return false;
    for (var dy = 0; dy < fh; dy++) {
      for (var dx = 0; dx < fw; dx++) {
        final m = w.at(x + dx, y - dy);
        if (m != Material.air && !Materials.passThroughWater(m)) return false;
        if (Materials.isFurniture(m) || m == Material.lamp) return false;
      }
    }
    return true;
  }

  void _pool(World w) {
    final rng = _stream('pool');
    var poolW = rng.range(Constants.poolWMin, Constants.poolWMax);
    final poolDepth = rng.range(Constants.poolDepthMin, Constants.poolDepthMax);
    final gap = rng.range(Constants.poolGapMin, Constants.poolGapMax);

    // Prefer the left side of the tower; mirror right if it does not fit.
    var left = w.towerLeft - gap - poolW;
    if (left < 1) {
      left = w.towerRight + gap + 1;
    }
    // Shrink to fit the grid (the gap keeps it clear of the tower).
    if (left + poolW - 1 >= Constants.gridW) {
      poolW = Constants.gridW - 1 - left;
    }
    if (poolW < 4) return; // degenerate: skip the pool
    final right = left + poolW - 1;

    // Dug-in basin: from the ground surface down poolDepth rows.
    final top = w.groundTopY;
    final bottom = min(w.groundTopY + poolDepth - 1, Constants.gridH - 1);
    final depth = bottom - top + 1;

    // Clear the ground, then fill with water (8 cells, clamped to depth).
    w.fillRect(left, top, right, bottom, Material.air);
    final fill = Materials.clampPoolFill(depth);
    for (var y = bottom - fill + 1; y <= bottom; y++) {
      w.fillRect(left, y, right, y, Material.water);
    }

    w.poolLeft = left;
    w.poolRight = right;
    w.poolTopY = bottom - fill + 1;
    w.poolBottomY = bottom;
    w.poolDepth = fill;
  }

  /// Deterministic shuffle over our [Rng] (Fisher-Yates).
  List<T> _fisherYates<T>(List<T> xs, Rng rng) {
    final out = List<T>.of(xs);
    for (var i = out.length - 1; i > 0; i--) {
      final j = rng.range(0, i);
      final t = out[i];
      out[i] = out[j];
      out[j] = t;
    }
    return out;
  }

  Material _structureMaterial() {
    switch (settings.material) {
      case 'concrete':
        return Material.concrete;
      case 'rebar':
        return Material.rebar;
      case 'steel':
        return Material.steel;
      case 'titanium':
        return Material.titanium;
    }
    throw ArgumentError('bad material ${settings.material}');
  }
}
