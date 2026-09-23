import 'constants.dart';
import 'materials.dart';
import 'world.dart';

/// One spurt column (a jet's held column, an overlay: its cells are out of
/// the grid). The spurt's position is derived from the column's current
/// surface so it always sits contiguous on top of the (dropping) pool.
class Spurt {
  /// The topmost spurt cell row (derived each tick: surface - height).
  int top = -1;

  /// The spurt's cell count (its height).
  int h = 0;

  bool get active => h > 0;
}

/// Falling-sand water (PLAN technique choice): each water cell steps one row
/// down or one column sideways per settle substep — the field never
/// overshoots, so it is unconditionally stable. A tick runs
/// [Constants.settleSubsteps] substeps of the falling/flow pass (stopping
/// early when a pass moves nothing), so a poured column sheds
/// [Constants.settleSubsteps] cells per tick and pancakes out instead of
/// standing as a pillar. A water cell falls when it can; otherwise it flows
/// sideways, so water levels out (finds its own level). On top of the cell
/// model:
///
/// * **Per-body hydrostatic head** — BFS flood fill finds connected water
///   bodies; the body's maximum head (its depth from its own surface) is
///   carried sideways to every cell of the body, so a thin sheet running off
///   a wall pushes with the deep body's full head. A wall erodes only when
///   the pressing head exceeds the material's tolerance; ground never
///   erodes.
/// * **Volumetric momentum** — a decaying lateral velocity per water cell
///   (the vorticity-confinement analog) so water on a floor keeps flowing
///   sideways instead of freezing into a brick. A settled, level pool rests
///   (its cells are blocked by their neighbours).
/// * **Jets** — a confined body (a surface column covered by a wall) whose
///   maximum head is >= [Constants.jetMinHead] spurts upward out of an open
///   crack: the spurt is a persistent column of cells above the body surface,
///   grown cell by cell (one cell per tick, up to height ~= head/2, capped
///   at [Constants.jetMaxHeight]); a spurt blocked by a wall stops growing
///   but stays held. The spurt is an overlay: the pumped surface cells move
///   out of the grid (the pool surface drops, since falling-sand water
///   cannot rise) and the spurt column is drawn from [Spurt] state, always
///   contiguous on top of the dropping surface.
///
/// * **Wash** — a sideways water move aimed at rubble or debris pushes the
///   grain into the open air beyond it and takes its cell (SPEC 4: deep
///   water washes rubble away); volume is conserved.
/// Water volume is conserved: movement never creates or destroys water;
/// water appears only via erosion (a wall cell crumbles into water), tools,
/// and rain (a spurt's cells fall back into the column when the jet stops).
class Water {
  /// Lateral push per water cell, 4-bit fixed point (16 = full push), signed
  /// (positive = right). Sets a fresh push when a cell starts flowing, decays
  /// while blocked, flips when it bounces off a wall; a resting cell (no air
  /// on either side) holds zero.
  final List<int> momentum;

  /// Cell moves made by the current settle pass (resets each substep).
  int _moves = 0;

  /// Head per water cell: depth in cells below its body's own surface row
  /// (for the tracer's depth tinting and the HUD pressure readout).
  final List<int> head;

  /// The pressing head per water cell: its body's maximum head (depth),
  /// carried sideways — the value compared against wall tolerances.
  final List<int> bodyHead;

  /// The spurt column per grid column (the jet's held column, an overlay).
  final List<Spurt> spurts;

  Water()
    : momentum = List.filled(Constants.gridW * Constants.gridH, 0),
      head = List.filled(Constants.gridW * Constants.gridH, 0),
      bodyHead = List.filled(Constants.gridW * Constants.gridH, 0),
      spurts = [for (var i = 0; i < Constants.gridW; i++) Spurt()];

  /// The total water volume: the grid's water plus the spurt overlay's cells
  /// (a spurt's cells are out of the grid; counting them keeps volume
  /// conserved).
  int countWater(World w) => w.countWater() + totalSpurtCells();

  int totalSpurtCells() {
    var n = 0;
    for (final s in spurts) {
      n += s.h;
    }
    return n;
  }

  /// True when (x, y) is a spurt cell (out of the grid, in the overlay).
  bool isSpurtCell(int x, int y) {
    final s = spurts[x];
    return s.active && y >= s.top && y < s.top + s.h;
  }

  /// The spurt cell's head (its height above the pool surface, 1 at the
  /// bottom to h at the top); 0 when (x, y) is not a spurt cell.
  int spurtCellHead(int x, int y) {
    final s = spurts[x];
    if (!s.active || y < s.top || y >= s.top + s.h) return 0;
    return s.top + s.h - y;
  }

  /// One physics tick; mutates [w] in place.
  void tick(World w) {
    _bodies(w); // head, bodyHead, erosion, the spurt pump + release
    _settle(w); // falling sand
  }

  // -- bodies: BFS flood fill + heads + erosion + the spurt pump ---------

  void _bodies(World w) {
    const W = Constants.gridW;
    final H = Constants.gridH;
    final colMaxHead = List.filled(W, 0);
    final seen = List.filled(w.cells.length, false);
    for (var i = 0; i < w.cells.length; i++) {
      if (seen[i] || w.cells[i] != Material.water) continue;
      // One connected body (the grid's water; spurt cells are out of the
      // grid, in the overlay). BFS flood fill over the 4-neighbour grid.
      final body = <int>[i];
      seen[i] = true;
      var top = H, bottom = 0;
      // The topmost cell per column (the body surface).
      final surf = <int, int>{};
      for (var b = 0; b < body.length; b++) {
        final idx = body[b];
        final y = idx ~/ W;
        final x = idx % W;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
        final s = surf[x];
        if (s == null || y < s) surf[x] = y;
        // Expand to 4-neighbour water cells.
        for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = x + d.$1, ny = y + d.$2;
          if (nx < 0 || nx >= W || ny < 0 || ny >= H) continue;
          final ni = ny * W + nx;
          if (seen[ni] || w.cells[ni] != Material.water) continue;
          seen[ni] = true;
          body.add(ni);
        }
      }
      if (top > bottom) continue; // empty (defensive)
      final maxHead = bottom - top; // the body's depth, carried sideways
      for (final idx in body) {
        final x = idx % W;
        final s = surf[x];
        head[idx] = s == null ? 0 : (idx ~/ W - s); // depth below the surface
        bodyHead[idx] = maxHead;
        if (maxHead > colMaxHead[x]) colMaxHead[x] = maxHead;
      }
      _erode(w, body, maxHead);
      // A jet needs a confined body: at least one surface column covered
      // by a real wall (furniture and rubble do not count — they move).
      var confined = false;
      for (final e in surf.entries) {
        final sx = e.key, sy = e.value;
        if (sy > 0 && Materials.blocksWater(w.at(sx, sy - 1))) {
          confined = true;
          break;
        }
      }
      if (maxHead >= Constants.jetMinHead && confined) {
        _jets(w, surf, maxHead);
      }
    }
    // Release any spurt whose column is no longer deep enough (its cells
    // fall back into the column), or reposition the others so the spurt
    // stays contiguous on top of the dropping surface.
    for (var x = 0; x < W; x++) {
      final s = spurts[x];
      if (!s.active) continue;
      if (colMaxHead[x] < Constants.jetMinHead) {
        _releaseSpurt(w, x);
      } else {
        var surfNow = -1;
        for (var y = 0; y < H; y++) {
          if (w.at(x, y) == Material.water) {
            surfNow = y;
            break;
          }
        }
        s.top = (surfNow < 0 ? H - 1 : surfNow) - s.h;
      }
    }
  }

  /// Erode adjacent walls when the body's head exceeds the wall's tolerance.
  /// A wall at full strength loses one strength per tick of exposure; at
  /// strength 1 it crumbles (becoming water: its mass joins the body, so
  /// volume is conserved by displacement, never by duplication).
  void _erode(World w, List<int> body, int maxHead) {
    for (final idx in body) {
      final x = idx % Constants.gridW, y = idx ~/ Constants.gridW;
      for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + d.$1, ny = y + d.$2;
        if (nx < 0 ||
            nx >= Constants.gridW ||
            ny < 0 ||
            ny >= Constants.gridH) {
          continue;
        }
        final n = ny * Constants.gridW + nx;
        final m = w.cells[n];
        if (!Materials.blocksWater(m) || m == Material.ground) continue;
        if (maxHead <= Materials.of(m).tolerance) continue;
        final hp = w.strength[n];
        if (hp <= 1) {
          w.strength[n] = 0;
          w.cells[n] = Material.water;
          w.destroyedCount++;
        } else {
          w.strength[n] = hp - 1;
        }
      }
    }
  }

  // -- jets: the held spurt column ---------------------------------------

  /// For each column of a confined, deep-enough body whose surface is
  /// uncovered (an open crack), grow the spurt (one cell per tick, up to
  /// height ~= head/2, capped). The pump moves the column's surface cell out
  /// of the grid into the spurt (volume-conserved); the pool surface drops
  /// (falling-sand water cannot rise). A spurt blocked by a wall stops
  /// growing but stays held; a spurt at the cap stays held.
  void _jets(World w, Map<int, int> surf, int maxHead) {
    final cap = maxHead ~/ 2;
    final capH = cap > Constants.jetMaxHeight ? Constants.jetMaxHeight : cap;
    final cols = surf.keys.toList()..sort();
    for (final x in cols) {
      final y0 = surf[x]!; // the body surface row in this column
      // The crack must be open above the surface (a wall blocks the jet).
      if (y0 > 0 && !_canEnter(w.at(x, y0 - 1))) continue;
      final s = spurts[x];
      if (s.h >= capH) continue; // the spurt column is at its cap
      // The pump: move the surface cell out of the grid into the spurt
      // (volume-conserving). The column's surface drops; the spurt grows.
      w.cells[y0 * Constants.gridW + x] = Material.air;
      w.strength[y0 * Constants.gridW + x] = 0;
      s.h += 1;
    }
  }

  /// Release column x's spurt: return its cells to the top of the column
  /// (they fall back into the pool) and clear the spurt. Volume-conserving.
  void _releaseSpurt(World w, int x) {
    final W = Constants.gridW;
    final H = Constants.gridH;
    final s = spurts[x];
    // The column's current surface.
    var surfNow = -1;
    for (var y = 0; y < H; y++) {
      if (w.at(x, y) == Material.water) {
        surfNow = y;
        break;
      }
    }
    // Return the spurt's cells stacked just above the surface (they settle
    // back into the pool on the falling-sand pass).
    for (var i = 0; i < s.h; i++) {
      final ty = (surfNow < 0 ? H - 1 : surfNow) - 1 - i;
      if (ty < 0 || ty >= H) continue;
      if (w.at(x, ty) == Material.air) {
        w.cells[ty * W + x] = Material.water;
        w.strength[ty * W + x] = 0;
      }
    }
    s.top = -1;
    s.h = 0;
  }

  // -- falling sand ------------------------------------------------------

  /// The falling/flow pass, run [Constants.settleSubsteps] times per tick:
  /// each pass lets one more cell per column flow out of a pile, so a poured
  /// column collapses substeps-per-tick faster than one pass would. A pass
  /// that moves nothing proves the field is settled (nothing to fall,
  /// nothing to flow), so the remaining substeps are skipped.
  void _settle(World w) {
    const W = Constants.gridW;
    final H = Constants.gridH;
    for (var sub = 0; sub < Constants.settleSubsteps; sub++) {
      _moves = 0;
      for (var y = H - 1; y >= 0; y--) {
        final ltr = y.isEven; // deterministic per-row scan order
        for (var c = 0; c < W; c++) {
          final x = ltr ? c : (W - 1 - c);
          final idx = y * W + x;
          if (w.cells[idx] != Material.water) continue;
          // Fall first: a cell over an empty cell drops (water never enters
          // rubble/debris — the granular cells sink/float out of the way by
          // swap, in the buoyancy pass).
          if (_move(w, idx, 0, 1)) continue;
          // The fall failed (below is water, a wall, or the bottom row):
          // flow sideways, so water levels out (finds its own level).
          _flowSideways(w, idx, x, y);
        }
      }
      if (_moves == 0) break; // settled
    }
  }

  void _flowSideways(World w, int idx, int x, int y) {
    // At rest: no open air and no washable grain on either side, so no
    // sideways move can carry. Rest the push to zero (a fresh hash
    // direction starts it again when air opens) and skip the bounce/flap
    // bookkeeping.
    final W = Constants.gridW;
    final left = x > 0 ? w.cells[idx - 1] : Material.ground;
    final right = x + 1 < W ? w.cells[idx + 1] : Material.ground;
    final flowable =
        left == Material.air ||
        right == Material.air ||
        left == Material.rubble ||
        left == Material.debris ||
        right == Material.rubble ||
        right == Material.debris;
    if (!flowable) {
      momentum[idx] = 0;
      return;
    }
    var mv = momentum[idx];
    if (mv == 0) {
      // A deterministic pseudo-random direction, sized with the body's
      // pressed head (a deep body's sheet pushes harder than a shallow one).
      final h = ((x * 73856093) ^ (y * 19349663)) & 0x7FFFFFFF;
      final mag = 8 + ((bodyHead[idx] >> 1) & 8); // 8..16 fixed point
      mv = (h & 1) == 0 ? -mag : mag;
      momentum[idx] = mv;
    }
    final dir = mv > 0 ? 1 : -1;
    if (_move(w, idx, dir, 0)) {
      return; // the push carried
    }
    if (wash(w, idx, x, y, dir)) {
      return; // the wash carried
    }
    if (_blocked(w, x + dir, y)) {
      // Pushing into a wall: the sheet bounces its push back, so a sheet
      // keeps running off the wall it came from (pour-off).
      momentum[idx] = -mv;
    } else {
      momentum[idx] = mv > 0 ? mv - 2 : mv + 2; // friction
    }
  }

  bool _blocked(World w, int x, int y) {
    if (x < 0 || x >= Constants.gridW || y < 0 || y >= Constants.gridH) {
      return true;
    }
    return !_canEnter(w.at(x, y));
  }

  /// Move the water cell at [src] to (x+dx, y+dy). Water never into rubble/
  /// debris (they settle by buoyancy; the lateral wash is [wash]) nor into a
  /// wall or another water cell; loose objects (furniture, lamps) block it —
  /// they move by buoyancy, and water levels out around them (displacement).
  /// Falling straight down resets the lateral push (a fresh start); a
  /// sideways move carries it.
  bool _move(World w, int src, int dx, int dy) {
    final W = Constants.gridW;
    final H = Constants.gridH;
    final x = src % W, y = src ~/ W;
    final nx = x + dx, ny = y + dy;
    if (nx < 0 || nx >= W || ny < 0 || ny >= H) return false;
    final t = ny * W + nx;
    if (!_canEnter(w.cells[t])) return false;
    w.cells[t] = Material.water;
    w.strength[t] = 0;
    w.cells[src] = Material.air;
    momentum[t] = (dy > 0 && dx == 0) ? 0 : momentum[src];
    head[t] = head[src];
    _moves++;
    return true;
  }

  /// Push the granular cell (rubble/debris) a sideways move is aimed at:
  /// the grain slides into the air cell beyond it and the water takes the
  /// grain's cell — the wash (SPEC 4 "deep water washes rubble away").
  /// No-op unless the grain's far side is open air.
  bool wash(World w, int src, int x, int y, int dir) {
    final W = Constants.gridW;
    final tx = x + dir, bx = x + 2 * dir;
    if (tx < 0 || tx >= W || bx < 0 || bx >= W) return false;
    final t = y * W + tx;
    final m = w.cells[t];
    if (m != Material.rubble && m != Material.debris) return false;
    if (!_canEnter(w.cells[y * W + bx])) return false;
    w.cells[y * W + bx] = m;
    w.cells[t] = Material.water;
    w.strength[t] = 0;
    w.cells[src] = Material.air;
    momentum[t] = momentum[src];
    head[t] = head[src];
    _moves++;
    return true;
  }

  /// True when a moving water cell may enter the cell: only empty air.
  /// Water never overwrites rubble/debris (they settle by buoyancy, SPEC 5)
  /// and never a wall or a loose object (furniture / lamp) — those move via
  /// buoyancy, and water levels out around them (displacement).
  static bool _canEnter(Material m) => m == Material.air;
}
