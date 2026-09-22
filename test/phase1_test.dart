import 'package:test/test.dart';
import 'package:water_tower/core/constants.dart';
import 'package:water_tower/core/lamp.dart';
import 'package:water_tower/core/materials.dart';
import 'package:water_tower/core/settings.dart';
import 'package:water_tower/core/tower.dart';
import 'package:water_tower/core/world.dart';

World build(String seed, Settings s) => WorldBuilder(seed, s).build();

void main() {
  group('determinism (ADR 0001)', () {
    test('same seed + settings -> byte-identical world, built twice', () {
      final s = const Settings(floors: 30, width: 3, material: 'rebar');
      final a = build('pi-water', s);
      final b = build('pi-water', s);
      expect(a.snapshot(), equals(b.snapshot()));
      expect(a.fingerprint(), equals(b.fingerprint()));
    });

    test('different seed -> different world', () {
      final s = const Settings(floors: 12, width: 3, material: 'rebar');
      expect(build('alpha', s).fingerprint(),
          isNot(equals(build('beta', s).fingerprint())));
    });

    test('different settings -> different but valid worlds', () {
      const base = Settings(floors: 8, width: 3, material: 'rebar');
      const otherFloors = Settings(floors: 9, width: 3, material: 'rebar');
      const otherWidth = Settings(floors: 8, width: 4, material: 'rebar');
      const otherMat = Settings(floors: 8, width: 3, material: 'steel');
      final worlds = [
        build('seed', base),
        build('seed', otherFloors),
        build('seed', otherWidth),
        build('seed', otherMat),
      ];
      final f0 = worlds[0].fingerprint();
      for (final w in worlds.skip(1)) {
        expect(w.fingerprint(), isNot(equals(f0)));
        expect(w.countStructural(), greaterThan(0));
      }
    });

    test('settings validation rejects out-of-range inputs', () {
      expect(() => Settings.validate(floors: 0), throwsArgumentError);
      expect(() => Settings.validate(floors: 51), throwsArgumentError);
      expect(() => Settings.validate(width: 0), throwsArgumentError);
      expect(() => Settings.validate(width: 11), throwsArgumentError);
      expect(() => Settings.validate(material: 'brick'), throwsArgumentError);
    });
  });

  group('structural invariants', () {
    test('ground surface in range; no structure inside the ground', () {
      final w = build('pi-water', const Settings(floors: 30, width: 3));
      final level = Constants.gridH - 1 - w.groundTopY;
      expect(
          level,
          inInclusiveRange(
              Constants.groundLevelMin, Constants.groundLevelMax));
      // No structural cell strictly below the ground surface.
      for (var y = w.groundTopY; y < Constants.gridH; y++) {
        for (var x = 0; x < Constants.gridW; x++) {
          final m = w.at(x, y);
          if (!Materials.structure.contains(m)) continue;
          expect(y < w.groundTopY, isTrue,
              reason: 'structure $m at $x,$y is inside the ground');
        }
      }
    });

    test('floor count, slabs and full-height outer walls match the setting',
        () {
      const s = Settings(floors: 7, width: 2, material: 'concrete');
      final w = build('pi-water', s);
      final mat = Material.concrete;
      for (var i = 0; i <= s.floors; i++) {
        final slabY = w.towerBottomY - i * Constants.floorHeight;
        expect(slabY, greaterThanOrEqualTo(0), reason: 'slab $i out of grid');
        for (var x = w.towerLeft; x <= w.towerRight; x++) {
          expect(w.at(x, slabY), equals(mat),
              reason: 'slab $i incomplete at $x');
        }
      }
      for (var y = w.towerTopY; y <= w.towerBottomY; y++) {
        expect(w.at(w.towerLeft, y), equals(mat),
            reason: 'left wall missing at $y');
        expect(w.at(w.towerRight, y), equals(mat),
            reason: 'right wall missing at $y');
      }
    });

    test('every floor has 1-3 contiguous rooms with 1-cell partitions', () {
      final s = Settings(floors: 15, width: 5, material: 'rebar');
      final w = build('pi-water', s);
      final mat = Material.rebar;
      for (var fi = 0; fi < s.floors; fi++) {
        final slabY = w.towerBottomY - fi * Constants.floorHeight;
        final rows = [slabY - 3, slabY - 2, slabY - 1];
        final parts = <int>[];
        for (var x = w.towerLeft + 1; x < w.towerRight; x++) {
          if (rows.every((y) => w.at(x, y) == mat)) parts.add(x);
        }
        expect(parts.length + 1, inInclusiveRange(1, 3),
            reason: 'floor $fi has ${parts.length + 1} rooms');
        var prev = w.towerLeft;
        final bounds = [...parts, w.towerRight];
        for (final e in bounds) {
          // Interior is prev+1 .. e-1 (e is the partition or right wall).
          _checkRoomInterior(w, prev + 1, e - 1, rows);
          prev = e;
        }
      }
    });

    test('no two items share a cell; <=1 of each type per room', () {
      final s = Settings(floors: 20, width: 4, material: 'steel');
      final w = build('pi-water', s);
      final mat = Material.steel;
      // Per room: (a) every furniture component is exactly one item — its area
      // equals that type's footprint, so two items never share a cell; and
      // (b) at most one of each type per room.
      for (var fi = 0; fi < s.floors; fi++) {
        final slabY = w.towerBottomY - fi * Constants.floorHeight;
        final rows = [slabY - 3, slabY - 2, slabY - 1];
        final parts = <int>[];
        for (var x = w.towerLeft + 1; x < w.towerRight; x++) {
          if (rows.every((yy) => w.at(x, yy) == mat)) parts.add(x);
        }
        var prev = w.towerLeft;
        final bounds = [...parts, w.towerRight];
        for (final e in bounds) {
          final seenFlood = <int>{};
          final seenType = <Material>{};
          for (final yy in rows) {
            for (var xx = prev + 1; xx < e; xx++) {
              final m = w.at(xx, yy);
              if (!Materials.isFurniture(m)) continue;
              if (seenFlood.contains(w.idx(xx, yy))) continue;
              final comp = _floodBounded(
                  w, xx, yy, (mm) => mm == m, seenFlood, prev + 1, e - 1);
              seenFlood.addAll(comp); // mark counted cells so we skip them
              final (fw, fh) = Materials.furnitureSize[m]!;
              expect(comp.length, equals(fw * fh),
                  reason: '${m.name} component of ${comp.length} cells != '
                      '${fw * fh} at $xx,$yy (overlap)');
              expect(seenType.add(m), isTrue,
                  reason: 'duplicate ${m.name} in a room (fi=$fi)');
            }
          }
          prev = e;
        }
      }
    });

    test('lamps: no two share a cell; ceiling fixed, floor/table free', () {
      final w = build('pi-water', const Settings(floors: 10, width: 3));
      expect(w.lamps, isNotEmpty);
      final seen = <int>{};
      for (final l in w.lamps) {
        final idx = w.idx(l.x, l.y);
        expect(seen.add(idx), isTrue,
            reason: 'lamp overlap at ${l.x},${l.y}');
        expect(w.at(l.x, l.y), equals(Material.lamp),
            reason: 'lamp cell is not a lamp cell');
        if (l.kind == LampKind.ceiling) {
          expect(l.state, equals(LampState.fixed));
        } else {
          expect(l.state, equals(LampState.free));
        }
      }
    });

    test(
        'pool present, fill = 8 clamped to pool height, water full, in the ground',
        () {
      final w = build('pi-water', const Settings(floors: 30, width: 3));
      expect(w.poolRight, greaterThan(w.poolLeft), reason: 'no pool');
      expect(w.poolBottomY, greaterThan(w.poolTopY));
      final fill = w.poolBottomY - w.poolTopY + 1;
      final basin = w.poolBottomY - w.groundTopY + 1;
      expect(fill,
          equals(Constants.poolFill < basin
              ? Constants.poolFill
              : basin));
      for (var x = w.poolLeft; x <= w.poolRight; x++) {
        for (var y = w.poolTopY; y <= w.poolBottomY; y++) {
          expect(w.at(x, y), equals(Material.water),
              reason: 'pool not filled at $x,$y');
        }
      }
      if (w.poolBottomY + 1 < Constants.gridH) {
        expect(w.at(w.poolLeft, w.poolBottomY + 1), equals(Material.ground),
            reason: 'pool floor is not in the ground');
      }
      expect(
          w.poolRight < w.towerLeft || w.poolLeft > w.towerRight, isTrue,
          reason: 'pool overlaps the tower');
    });
  });
}

void _checkRoomInterior(World w, int s, int e, List<int> rows) {
  expect(e, greaterThanOrEqualTo(s), reason: 'empty room $s..$e');
  for (final y in rows) {
    for (var x = s; x <= e; x++) {
      expect(Materials.structure.contains(w.at(x, y)), isFalse,
          reason: 'structure in room interior at $x,$y');
    }
  }
}

/// Bounded 4-connected flood fill of cells matching [pred], within
/// columns [x0, x1] on the grid, deduplicated against [visited].
/// Returns the set of cell indices in the connected component.
Set<int> _floodBounded(
  World w,
  int x,
  int y,
  bool Function(Material) pred,
  Set<int> visited,
  int x0,
  int x1,
) {
  final out = <int>{};
  final stack = <int>[w.idx(x, y)];
  while (stack.isNotEmpty) {
    final idx = stack.removeLast();
    if (visited.contains(idx) || out.contains(idx)) continue;
    final cx = idx % Constants.gridW;
    final cy = idx ~/ Constants.gridW;
    if (cx < x0 || cx > x1 || !pred(w.at(cx, cy))) continue;
    out.add(idx);
    for (final d in const [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1]
    ]) {
      final nx = cx + d[0];
      final ny = cy + d[1];
      if (nx < x0 || nx > x1) continue;
      if (ny < 0 || ny >= Constants.gridH) continue;
      final nidx = w.idx(nx, ny);
      if (visited.contains(nidx) || out.contains(nidx)) continue;
      stack.add(nidx);
    }
  }
  return out;
}
