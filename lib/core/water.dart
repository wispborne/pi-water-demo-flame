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
/// * **Jets** — a confined body (a wall — a roof — above it) whose maximum
///   head is >= [Constants.jetMinHead] spurts upward out of an open crack: the
///   spurt is a persistent column of cells above the body surface, grown cell
///   by cell (one cell per tick, up to height ~= head/2, capped at
///   [Constants.jetMaxHeight]); a spurt blocked by a wall stops growing but
///   stays held. When the body opens to the sky (its roof is gone), the spurt
///   releases and its cells fall back into the pool. The spurt is an overlay:
///   the pumped surface cells move out of the grid (the pool surface drops,
///   since falling-sand water cannot rise) and the spurt column is drawn from
///   [Spurt] state, always contiguous on top of the dropping surface.
///
/// * **Wash** — a sideways water move aimed at rubble or debris pushes the
///   grain into the open air beyond it and takes its cell (SPEC 4: deep
///   water washes rubble away); volume is conserved.
/// * **Surface motion** — each column's at-rest surface carries a damped
///   displacement: water arriving vertically kicks it (a landed drop, a
///   poured column, a released spurt), the kick spreads sideways as
///   travelling ripples (a 1-D damped wave), and a settled field decays to
///   exactly zero, so a calm pool's surface is flat and the surface only
///   moves with the water's own impacts, pours, and flows (SPEC 4/7). A
///   slow level rise is sideways spread and leaves the surface alone. The
///   motion is an overlay on the grid: it never moves a cell, so it costs
///   nothing against volume conservation.
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

  /// The surface displacement per column (fixed-point, 1/16 of a cell,
  /// signed): the damped motion the water's own impacts, pours, and flows
  /// stir into the surface. A settled field decays to zero, so a calm pool
  /// draws a flat line.
  final List<int> elev;

  /// The displacement's velocity per column (fixed-point, 1/16 of a cell
  /// per tick).
  final List<int> _vel;

  /// The previous tick's surface rows (the impulse compares against them).
  final List<int> _prevSurfRow;

  /// The reusable next-step displacement buffer (the wave update reads the
  /// old field symmetrically, so it writes to a side buffer first).
  final List<int> _elevNext;

  /// The at-rest surface row per column: the top of the column's first
  /// at-rest water run (or the spurt's top while its jet is held), -1 when
  /// the column has no at-rest surface. The drawn surface line, the traced
  /// surface, and the motion model all read this one scan.
  final List<int> surfRow;

  /// Landing weight per column for the current settle pass: the mass (cell
  /// count) of the water run that just touched down. The surface motion
  /// kicks off this, not off surface-row changes: a level rise is a
  /// sideways spread, not an impact. A landing is a down move whose cell
  /// below is water that did not itself move down this pass (the bottom of
  /// the falling run, not the run's interior), so a falling column counts
  /// once, weighted by its height.
  final List<int> _landing;

  /// Pass stamp of the cell's last down move (a landing needs the water
  /// below to carry an older stamp).
  final List<int> _downStamp;
  int _downGen = 0;

  /// Until the first surface scan, a column's surface is "new" — but water
  /// that was already at rest when the world was built must not count as an
  /// arrival (a fresh pool would otherwise slosh once at t=0).
  bool _surfInit = true;

  /// "Seen this body pass" stamp per cell (a flat array beats a fresh
  /// boolean list per tick: no allocation, no boxing).
  final List<int> _seen;
  int _seenGen = 0;

  /// Reusable body worklist and per-column surface rows (-1 = none).
  final List<int> _body = [];
  final List<int> _surf;

  /// Surface motion tuning (fixed-point, 1/16 of a cell): the velocity
  /// impulse per cell of landed water mass, the wave coefficient (c^2 =
  /// 4/16, below the 1/2 stability limit of the explicit update), the
  /// restoring spring to the rest level (removes the uniform mode), the
  /// per-tick damping (240/256: a ripple dies in ~1-2 s at 30 ticks/s),
  /// and the amplitude caps (velocity, displacement).
  static const int _impulse = 4;
  static const int _c2 = 4;
  static const int _spring = 4;
  static const int _dampNum = 240;
  static const int _dampDen = 256;
  static const int _velCap = 64;
  static const int _elevCap = 48;
  static const int _restSnap = 4;

  Water()
    : momentum = List.filled(Constants.gridW * Constants.gridH, 0),
      head = List.filled(Constants.gridW * Constants.gridH, 0),
      bodyHead = List.filled(Constants.gridW * Constants.gridH, 0),
      spurts = [for (var i = 0; i < Constants.gridW; i++) Spurt()],
      _seen = List.filled(Constants.gridW * Constants.gridH, 0),
      _surf = List.filled(Constants.gridW, -1),
      elev = List.filled(Constants.gridW, 0),
      _vel = List.filled(Constants.gridW, 0),
      _prevSurfRow = List.filled(Constants.gridW, -1),
      _elevNext = List.filled(Constants.gridW, 0),
      _landing = List.filled(Constants.gridW, 0),
      _downStamp = List.filled(Constants.gridW * Constants.gridH, 0),
      surfRow = List.filled(Constants.gridW, -1);

  int _nextSeenGen() {
    _seenGen++;
    if (_seenGen == 0) {
      _seen.fillRange(0, _seen.length, 0);
      _seenGen = 1;
    }
    return _seenGen;
  }

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
    _surfaceMotion(w); // damped ripples on the at-rest surface
  }

  // -- surface motion: damped ripples on the at-rest surface -------------

  /// The surface displacement a renderer adds to the column's surface row,
  /// in cells (the state is fixed-point 1/16).
  double surfaceOffset(int x) => elev[x] / 16.0;

  /// One step of the surface motion. The grid is read only: water arriving
  /// in a column vertically (a landed drop, a poured column, a released
  /// spurt — the settle pass's down moves) kicks that column's surface,
  /// the displacement spreads to the neighbours as a damped 1-D wave, and
  /// a settled field decays to zero (a calm pool's surface is flat).
  void _surfaceMotion(World w) {
    const W = Constants.gridW;
    final H = Constants.gridH;
    final cells = w.cells;
    // 1. The at-rest surface row per column (the same rule the drawn line
    //    uses: a spurt's top while its jet is held, else the top of the
    //    first at-rest run — a run whose bottom cell sits on water or a
    //    permanent wall).
    for (var x = 0; x < W; x++) {
      final s = spurts[x];
      if (s.active) {
        surfRow[x] = s.top;
        continue;
      }
      var surf = -1;
      var y = 0;
      while (surf < 0 && y < H) {
        if (cells[y * W + x] != Material.water) {
          y++;
          continue;
        }
        var bottom = y;
        while (bottom + 1 < H &&
            cells[(bottom + 1) * W + x] == Material.water) {
          bottom++;
        }
        final below = bottom + 1 < H
            ? cells[(bottom + 1) * W + x]
            : Material.ground;
        if (below == Material.water ||
            Materials.blocksWaterByIndex[below.index]) {
          surf = y;
        }
        y = bottom + 1;
      }
      surfRow[x] = surf;
    }
    if (_surfInit) {
      // The first scan only establishes the baseline: what is already at
      // rest at t=0 arrived before the simulation started.
      _prevSurfRow.setRange(0, W, surfRow);
      _surfInit = false;
      return;
    }
    // 2. Impulses: the kick is the water that just landed in the column
    //    (the settle pass's landing weight: a falling run touches down),
    //    plus one cell when a surface newly forms. A level rise or drain
    //    is sideways spread, not an impact, and leaves the surface alone.
    for (var x = 0; x < W; x++) {
      if (surfRow[x] < 0) continue;
      var kick = _landing[x];
      if (_prevSurfRow[x] < 0) kick += 1;
      if (kick > 0) {
        _vel[x] = (_vel[x] + kick * _impulse).clamp(-_velCap, _velCap);
      }
    }
    _prevSurfRow.setRange(0, W, surfRow);
    // 3. The damped wave: the displacement spreads to the at-rest
    //    neighbours and decays; a column without an at-rest surface just
    //    decays (a vanished surface leaves no frozen bump).
    for (var x = 0; x < W; x++) {
      if (surfRow[x] < 0) {
        _vel[x] = (_vel[x] * _dampNum) ~/ _dampDen;
        _elevNext[x] = (elev[x] * _dampNum) ~/ _dampDen;
      } else {
        final el = x > 0 && surfRow[x - 1] >= 0 ? elev[x - 1] : 0;
        final er = x + 1 < W && surfRow[x + 1] >= 0 ? elev[x + 1] : 0;
        // The neighbour coupling spreads the bump sideways; the spring
        // pulls it back to the rest level — without it the uniform
        // (whole-surface) mode has no restoring force and never decays.
        final acc = _c2 * (el - 2 * elev[x] + er) ~/ 16 -
            elev[x] * _spring ~/ 16;
        var v = (_vel[x] * _dampNum) ~/ _dampDen + acc;
        v = v.clamp(-_velCap, _velCap);
        _vel[x] = v;
        _elevNext[x] = (elev[x] + v).clamp(-_elevCap, _elevCap);
      }
      // Integer leapfrog locks into 1-unit cycles the damping can't kill
      // (damping only bites at |v| * 240 >= 256): snap sub-quarter-cell
      // motion to zero so a settled surface is exactly flat.
      if (_vel[x].abs() <= _restSnap && _elevNext[x].abs() <= _restSnap) {
        _vel[x] = 0;
        _elevNext[x] = 0;
      }
    }
    elev.setRange(0, W, _elevNext);
  }

  // -- bodies: BFS flood fill + heads + erosion + the spurt pump ---------

  void _bodies(World w) {
    const W = Constants.gridW;
    final H = Constants.gridH;
    final colMaxHead = List.filled(W, 0);
    final colConfined = List.filled(W, false);
    final cells = w.cells;
    final seen = _seen;
    final seenGen = _nextSeenGen();
    final surf = _surf..fillRange(0, W, -1);
    for (var i = 0; i < cells.length; i++) {
      if (seen[i] == seenGen || cells[i] != Material.water) continue;
      // One connected body (the grid's water; spurt cells are out of the
      // grid, in the overlay). BFS flood fill over the 4-neighbour grid.
      final body = _body..clear();
      body.add(i);
      seen[i] = seenGen;
      var top = H, bottom = 0;
      for (var b = 0; b < body.length; b++) {
        final idx = body[b];
        final y = idx ~/ W;
        final x = idx % W;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
        final s = surf[x];
        if (s == -1 || y < s) surf[x] = y;
        // Expand to 4-neighbour water cells.
        for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = x + d.$1, ny = y + d.$2;
          if (nx < 0 || nx >= W || ny < 0 || ny >= H) continue;
          final ni = ny * W + nx;
          if (seen[ni] == seenGen || cells[ni] != Material.water) continue;
          seen[ni] = seenGen;
          body.add(ni);
        }
      }
      if (top > bottom) continue; // empty (defensive)
      final maxHead = bottom - top; // the body's depth, carried sideways
      for (final idx in body) {
        final x = idx % W;
        final s = surf[x];
        head[idx] = s == -1 ? 0 : (idx ~/ W - s); // depth below the surface
        bodyHead[idx] = maxHead;
        if (maxHead > colMaxHead[x]) colMaxHead[x] = maxHead;
      }
      _erode(w, body, maxHead);
      // A jet needs a confined body: at least one surface column with a real
      // wall somewhere above it — a roof (furniture and rubble do not count,
      // they move). Scan up to the top of the grid, not a fixed distance: the
      // pump and the ripple sink the surface several rows below the roof, and
      // a roof is a roof no matter how far the surface falls. Once the roof is
      // gone the column is open to the sky and the body stops being confined.
      var confined = false;
      for (var x = 0; x < W; x++) {
        final sy = surf[x];
        if (sy <= 0) continue;
        for (var y = sy - 1; y >= 0; y--) {
          if (Materials.blocksWaterByIndex[cells[y * W + x].index]) {
            confined = true;
            break;
          }
        }
        if (confined) break;
      }
      if (maxHead >= Constants.jetMinHead && confined) {
        _jets(w, surf, maxHead);
        for (var x = 0; x < W; x++) {
          if (surf[x] != -1) colConfined[x] = true;
        }
      }
      for (var x = 0; x < W; x++) {
        if (surf[x] != -1) surf[x] = -1;
      }
    }
    // Release any spurt whose column is no longer deep enough, or whose
    // body is no longer confined (its roof is gone — a spurt must not
    // outlive the body that pumped it); its cells fall back into the
    // column. The others are repositioned so the spurt stays contiguous on
    // top of the dropping surface.
    for (var x = 0; x < W; x++) {
      final s = spurts[x];
      if (!s.active) continue;
      final supported = colMaxHead[x] >= Constants.jetMinHead && colConfined[x];
      if (supported) {
        _repositionSpurt(w, x, H);
      } else {
        _releaseSpurt(w, x);
      }
    }
  }

  /// Move the spurt so it sits contiguous on top of the column's current
  /// grid surface (the pool drops as the pump feeds the spurt).
  void _repositionSpurt(World w, int x, int H) {
    final s = spurts[x];
    var surfNow = -1;
    for (var y = 0; y < H; y++) {
      if (w.at(x, y) == Material.water) {
        surfNow = y;
        break;
      }
    }
    s.top = (surfNow < 0 ? H - 1 : surfNow) - s.h;
  }

  /// Erode adjacent walls when the body's head exceeds the wall's tolerance.
  /// A wall at full strength loses one strength per tick of exposure; at
  /// strength 1 it crumbles (becoming water: its mass joins the body, so
  /// volume is conserved by displacement, never by duplication).
  void _erode(World w, List<int> body, int maxHead) {
    const W = Constants.gridW;
    final H = Constants.gridH;
    final cells = w.cells;
    final strength = w.strength;
    for (final idx in body) {
      final x = idx % W, y = idx ~/ W;
      for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + d.$1, ny = y + d.$2;
        if (nx < 0 || nx >= W || ny < 0 || ny >= H) continue;
        final n = ny * W + nx;
        final m = cells[n];
        final mi = m.index;
        if (!Materials.blocksWaterByIndex[mi] ||
            m == Material.ground) {
          continue;
        }
        if (maxHead <= Materials.toleranceByIndex[mi]) continue;
        final hp = strength[n];
        if (hp <= 1) {
          strength[n] = 0;
          cells[n] = Material.water;
          w.destroyedCount++;
        } else {
          strength[n] = hp - 1;
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
  void _jets(World w, List<int> surf, int maxHead) {
    final cap = maxHead ~/ 2;
    final capH = cap > Constants.jetMaxHeight ? Constants.jetMaxHeight : cap;
    for (var x = 0; x < surf.length; x++) {
      final y0 = surf[x];
      if (y0 == -1) continue; // no body surface in this column
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
    _landing.fillRange(0, W, 0);
    _downGen++;
    if (_downGen == 0) {
      _downStamp.fillRange(0, W * H, 0);
      _downGen = 1;
    }
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
    if (dy > 0 && dx == 0) {
      // A down move: stamp the destination, and — when the cell below is
      // water that did not move down this pass — the bottom of the falling
      // run has landed: record it weighted by the run's mass (the cells
      // still standing above the source, which move later in the scan).
      _downStamp[t] = _downGen;
      if (ny + 1 < H &&
          w.cells[(ny + 1) * W + nx] == Material.water &&
          _downStamp[(ny + 1) * W + nx] != _downGen) {
        var mass = 1;
        var yy = ny - 2; // above the source (ny - 1)
        while (yy >= 0 &&
            w.cells[yy * W + nx] == Material.water &&
            mass < 64) {
          yy--;
          mass++;
        }
        _landing[nx] = (_landing[nx] + mass).clamp(0, 64);
      }
    }
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
