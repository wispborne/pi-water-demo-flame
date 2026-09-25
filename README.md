# 30 Floors & a Pool

> **Built end-to-end by a local LLM** — no cloud LLM and no human editing.
> A for-fun proof-of-concept side project: the model drives the entire build
> (design, code, tests, debugging) on the developer's own machine, and every
> line of code in this repo is locally generated.

A seeded 2D side-view water simulation with an optional physically traced
light view (off by default, ADR 0004). A tower is built beside a pool; the
structure fails cell by cell under water, pressure, and user attack, and in
the traced view light is genuinely transported.

Built in Flutter/Flame (desktop) on a pure-Dart core. The simulation itself
is a pure-Dart package — headless-testable on any box; the GUI is the
`app/` package.


## Layout

- `lib/core/` — the pure-Dart simulation core (no Flutter import):
  - `constants.dart` — grid 220×240; floor 4 cells, bay 8 cells; timings.
  - `rng.dart` — FNV-1a-64 seed hash → PCG32; forked sub-streams per world
    section. Deterministic; integer-only; no `dart:math.Random` (ADR 0001).
  - `settings.dart` — world settings (floors 1–50, width 1–10, structure
    material) with validation.
  - `materials.dart` — material enum + property table (tolerance/hp/buoyancy).
  - `world.dart` — the cell-grid container (cell access, water/structural
    bookkeeping, destroyed-cell counter, snapshot + fingerprint).
  - `tower.dart` — `WorldBuilder`: ground, tower, floors/rooms, furniture,
    lamps, pool.
  - `lamp.dart` — the three lamp kinds (floor / ceiling / table) and states.
  - `water.dart` — falling-sand water: the falling/flow pass runs as
    substeps per tick (early-exiting when settled) so a poured column
    pancakes out instead of standing as a pillar; per-body BFS head
    (carried sideways), erosion at head > material tolerance, lateral
    momentum, jets (a head ≥ 8 confined body spurts out of an open crack as
    a held spurt column), wash (flowing water scours rubble/debris
    sideways), volume conserved; surface motion (a per-column damped
    elevation that dips where water lands — a pour, a falling column, rain,
    a jet, a dumped wall — and decays back to a flat line, so a calm pool is
    exactly flat).
  - `structure.dart` — structural failure: a section severed from the
    foundation (support gap ≥ 3 air cells; gaps ≤ 2 bridge) slumps for
    ~2 sim-seconds, then breaks into rubble (heavy materials) or debris.
  - `buoyancy.dart` — loose objects: rigid furniture masses and free lamps
    plus granular rubble/debris (which fall at the water's settling rate —
    one gravity for everything granular); water displacement, floats
    rising, heavies sinking; ceiling lamps release and fall lit.
  - `sun.dart` — the sun disc: a deterministic function of sim time (420 s
    cycle, left-right arc, freezes when the world is paused).
  - `tools.dart` — the eight user tools (hammer, bomb, water, erase, four
    build materials) with a 1–15 cell brush, plus rain (0–40 water cells
    per sim-second on the top row, in random columns across the full width).
- `sim.dart` — the fixed-timestep driver: wall-clock time × speed scale
  (0.5/1/2, paused at 0) → physics ticks at 30/s; owns the sim clock, the
  sun, and the tools; water volume is conserved through it.
- `test/phase1_test.dart` — determinism + structural invariants.
- `test/phase2_test.dart` — water contract: settle/level, a poured column
  spreads out instead of piling up, per-body head erosion, tolerance
  boundaries, jets, volume conservation.
- `test/phase3_test.dart` — structure + buoyancy contract: severance at a
  3-cell gap, 2-cell gap bridges, slump → rubble, deep water washes rubble
  out of a vertical column, rubble falls at the settling rate, floats rest
  at the surface, heavies sink,
  water displacement conserves volume, ceiling lamp releases.
- `test/phase4_test.dart` — sun determinism, the eight tools (hammer to
  rubble, bomb falloff, build/erase, rain at 3 rates, keys 1–8), and the
  fixed-timestep driver (pause, 0.5x/1x/2x, speed cycle).
- `tool/phaseN_dump.dart` — per-phase headless artifacts: pure-Dart ASCII
  dumps of the sim into `out/phaseN/` (e.g. `dart run tool/phase4_dump.dart`).
- `lib/trace/` — the traced view (Phase 5), pure Dart: `field.dart` (the
  per-cell light field), `ray.dart` (per-column scene spans, transmittance,
  occluder queries), `shadows.dart` (the per-light angular shadow sweep),
  `surface.dart` (the surface step + per-column displacement and refraction),
  `transport.dart` (one cell's light: sun/lamp next events, shafts, glint,
  caustic), and `tracer.dart` (dirty-region re-convergence, ray budget).
- `test/phase5_test.dart` — the standing checks: light blocked by a
  one-cell partition, light through furniture, roofed-pool surface static
  across the arc, open-pool glint under the sun, settle + local
  re-convergence, warm submerged lamp, budget fallback/recovery.
- `app/` — the Flutter/Flame GUI (Phase 6), a separate package depending on
  the root by path:
  - `main.dart` — app shell, the `--seed` argument, the keyboard
    shortcuts (1–8 tools, P pause, S speed, G glow, T path trace, R reset,
    N new seed), pointer routing to the game.
  - `sim_state.dart` — the app's sim state (pure Dart): the seeded world,
    tracer, tools, view switches, speed/pause; Reset / New seed rebuild the
    exact t=0 world.
  - `camera.dart` — fit the whole world, pan, wheel zoom around the cursor
    (pure Dart).
  - `game/water_game.dart` — the Flame layer: game loop, pointer routing
    (left = tool, right/middle = pan, wheel = zoom), the `FieldBlitter`
    (light field → `ui.Image` via a pure-Dart PNG encode, decoded on a
    codec thread).
  - `render/grid_painter.dart` — one painter per frame: plain mode (sky,
    cells batched per material, depth tint, the surface line (flat at rest,
    rippling where water lands), glow band, sun) and traced mode (the
    blitted field, then bulbs, sun disc, surface line and glow band on top;
    the scene is lit only by the traced light).
  - `ui/hud.dart` — the 10 Hz overlay: counters, hover readout, controls,
    sliders.
  - `test/widget_test.dart` — the 16 GUI contract tests.

## Run

```sh
dart pub get
dart test          # headless sim tests (Phases 1–5)
dart analyze lib test
dart run tool/phase4_dump.dart   # Phase 4 artifact: sun arc, tools, driver in out/phase4/
dart run tool/phase5_dump.dart     # Phase 5 artifact: the four standing-check
                                   # scenes as ASCII light fields in out/phase5/
```

The GUI (Phase 6) is the `app/` Flutter package, run separately:

```sh
cd app
flutter pub get
flutter run -d windows
flutter run -d macos
flutter test       # the 15 GUI contract tests
```

Or, on Windows, just double-click `run.bat` (it builds the release on the
first run, then launches the app), or on macOS run `./run.sh` (same: release
build if needed, then launch).

## Status

Phases are defined in `PHASES.md`; each ends in a green `dart test` run and a
commit. Decisions are in `PLAN.md`; the design context in `CONTEXT.md`.

| Phase | Description | Status |
|---|---|---|
| 1 | Foundation: deterministic world generation | ✅ done |
| 2 | Water physics (fall/flow, per-body head, erosion, jets, surface ripples) | ✅ done |
| 3 | Structural failure and buoyancy | ✅ done |
| 4 | Sun, tools, sim driver | ✅ done |
| 5 | Traced view (progressive light field) | ✅ done |
| 6 | GUI (Flutter/Flame) | ✅ done |

**Phase 6 is complete and committed.** Water settling now runs as substeps
per tick (early-exiting when nothing moves): a poured column pancakes out
in well under a second instead of standing as a pillar, and granular
rubble/debris falls at the same rate as water. Settled fields cost no more
than a single pass. The GUI is a Flutter/Flame desktop
app (`app/`) over the pure-Dart core. The camera fits the whole world at
load and after Reset / New seed; left-drag applies the selected tool,
right- or middle-drag pans, and the wheel and trackpad pinch zoom around
the cursor. The
traced view is off by default (ADR 0004): when on, the 220×240 light field
is blitted each frame and the scene is lit only by that field; a sustained ray-budget
overrun drops to the plain view and re-enables on recovery. The HUD (10
Hz) shows the counters
(water cells, damage %, destroyed cells, FPS), the hover readout
(material, strength, pressure, light swatch), the controls (Pause, Speed,
Reset, New seed, Glow, Path trace), and the sliders (brush, rain, floors,
width, structure) with a seed-name field; tapping a control returns
keyboard focus to the game. The 16 `flutter test` contract tests cover the
camera fit, wheel and pinch zoom and middle/right-button pan, seed/reset rebuilds,
speed propagation, the traced-view fallback, the tool keys, and the
hover readout's SPEC 10 strength bar. Verified
in the running app on Windows: `cd app && flutter run -d windows`.
macOS desktop support was added on 2026-09-23 (`app/macos/` via
`flutter create --platforms=macos`, org `com.water_tower`); the app builds
 and runs there with the same 15/15 `flutter test` pass. On 2026-09-25 the
 plain view gained a sun-altitude-tinted sky gradient with a radial sun glow,
 structural grid lines and damage cracks that appear above a zoom threshold,
 furniture detail sub-rectangles on larger cells, a crisp stroked
 water-surface line, and a bomb burst with a screen flash (SPEC 8); the
 traced view now shows plain cells as a placeholder before the first
 light-field blit, and the HUD buttons are filled with the hover readout
 showing a material swatch.

**Change (2026-09-25).** The water surface now moves. The old ambient swell
(a slow sine plus two faster short waves, a fixed function of sim time) is
gone; the surface is flat exactly where the water is at rest. Instead the
core carries a per-column damped elevation: water that lands — a pour, a
falling column, rain, a jet, a wall dumping in — kicks a dip where it
touches down, weighted by how much water arrived, the ripples spread
sideways and decay back to a flat line in a couple of seconds. The dip comes
from vertical arrivals only, so a slow level rise (water spreading sideways)
does not stir the surface. It is deterministic (integer-only, no clock),
volume is untouched, and the traced view reads the same per-column
displacement for glint slope and refraction. `tool/_sloshcheck.dart` writes
the settled/pour/rain surface lines to `out/_sloshcheck/` and asserts the
calm pool is exactly flat, the pour stirs then decays, and rain stirs;
`test/phase2_test.dart` adds the standing contract (flat at rest, stirs on a
pour, decays to flat, volume conserved).

**Fix (2026-09-25).** The pool's surface line gapped out under every
falling drop in its column: the column scan stopped at the first water
cell, so a drop above the pool took the column's only surface point and
the pool lost its line where the drop passed. The scan now walks the
column's water runs top-down and takes the top of the first at-rest run,
so a drop above the pool keeps the pool's point and a drop in open sky
gets no point at all. `tool/_raincheck.dart` checks the scan against all
four column shapes (drop + pool, open-sky drop, plain pool, pool split
by a sinking grain); `out/rain_pools.png` shows the pool line continuous
under the falling drops.

**Fix (2026-09-25).** The rain lines came back on damaged towers: the
surface line connected a point in one column to the point in the
neighbouring column no matter the vertical distance, so any flagged
mid-sky point (a drop passing falling rubble, a jet spurt above its
pool) drew a near-vertical line down to the pool surface beside it. A
column now only counts as at-rest when water or a permanent wall sits
under its top cell (a mobile grain under a drop is not support), and the
line starts a new subpath when the level jumps more than two cells
between neighbouring columns, since a real surface moves at most that
far. `app/test/_rainrender.dart` renders the damaged-tower frame headless
to `out/rain_damaged.png`; the drops stay dots and the pool and roof
surface lines are unchanged.

**Fix (2026-09-25).** Rain read as long bright vertical lines: the
water-surface line took a point at the top of every water column — a
falling rain drop included — and connected that point to the next water
column across empty space, so each falling drop drew a near-vertical line
down to the ground pool (the bright dot at the top of each line was the
drop's own point). Only at-rest water gets a surface now: a falling
column's top cell has open air under it, so it drops out of the line and
the glow band, and the path restarts at every non-contiguous run.
`app/test/_rainrender.dart` renders the frame headless to
`out/rain_before.png` / `out/rain_after.png`; the lines are gone and the
pool's wavy surface line is unchanged.

**Fix (2026-09-24).** The traced view ran at ~2 fps on the default
30-floor world: the per-frame world diff invalidated the lamps' angular
shadow sweeps on *any* cell change, and the pool's water cells change every
frame, so all 120 lamp sweeps (each sorting the angle events of ~7,600
occluder cells) were rebuilt every frame. A CPU profile of the running app
put ~89 % of the frame in those rebuilds, ~47 % of it the sort. Only
light-blocking cells feed the occluder list, so only a light-blocking cell
change now invalidates the sweeps. A steady frame is back to ~24 ms
headless (JIT) and the app holds 30 fps in the window;
`tool/_fpsprobe.dart` reproduces the scene and times it.

**Fix (2026-09-24).** The traced tower read as a blown-out blob: the lamps
were ~5× too strong, the falloff was shallow enough that a lamp lit the
whole tower, and solid cells rendered the light arriving at them with no
material reflectance, so walls read as bright as the lit air. Lamps are now
dimmed and the falloff is steeper (half intensity at 8 cells, not 12), and
solid cells multiply the arriving light by their material albedo
(`Materials.albedoByIndex`, following the plain-view palette). A lamp-lit
room now reads ~67 % of the sky in the default world (measured from a
screenshot) and walls read darker than the air around them. The standing
checks' brightness thresholds are re-set to the new magnitudes;
`tool/_lampdim.dart` prints the settled values.

**Traced-view engine rewrite (2026-09-24).** The tracer no longer marches
each sun/lamp ray through the grid cell by cell. Per frame it precomputes
per-column contiguous spans of occluder/water/glass cells and, per light,
an angular shadow sweep (each light-blocking cell as a disc occluder,
swept to the first-hit disc per angle), so a sample is one angle lookup
plus the geometric length inside the spans (ADR 0003). The traced picture
is unchanged: all eight standing checks pass unmodified, and a steady
frame drops to ~7 ms of the 33 ms budget on a 30-floor world with four
lamps (`tool/trace_bench.dart`).

**Fix (2026-09-24).** A falling lamp's light no longer dies with the
traced view. The dirty-cell re-convergence pass had no ray-budget cap:
each one-cell lamp move dirtied ~20,000 cells around its old and new
position, costing ~27,000 rays/frame — 10× the 2,500 cap — so any ceiling
lamp falling for more than 2 s pushed the budget past its fallback, and
the fallback was permanent (`record()` only runs inside `trace()`, so with
the traced view off the 2 s recovery window never drained and the Path
trace toggle stayed dead until the world was rebuilt). Dirty cells now
re-converge within the frame's ray budget, nearest the moved lamp first
(its light follows radially and settles in ~1 s, the same window as the
sun drift), and the first frame after `field.clear()` still re-samples the
whole field in one go (the one-off spike the budget tolerates). The app
records 0 rays while the plain view is up, so a fallen-back view
re-enables on its own. The standing checks are green plus a new one —
a falling lamp stays inside the ray budget and its light follows
(`tool/_lampfall.dart` reproduces the scenario headless).

**Fix (2026-09-24).** Breaking the foundation of a large tower froze the
app: `Structure._detect` ran a component BFS from *every* severed cell
(its `seen` list was never marked), so a severed section of S cells cost
O(S²) per tick for the whole 60-tick slump — ~3 s/tick, and a 2–3 minute
hard freeze, on a 50-floor tower. A section is now stamped as it is found
(one BFS per section), the support BFS runs once per tick and is shared by
detection and release, and the per-cell bookkeeping moved from `Set<int>`/
`Set<Material>`/`Map` lookups to flat index tables (`Materials.*ByIndex`)
and reusable stamp arrays in `Structure`, `Water`, and `Buoyancy`. The
collapse now costs ~3 ms/tick at worst (bit-identical world state to the
old code across a 121-tick A/B run of the same collapse; `tool/
_collapsebench.dart` reproduces the scenario and times it).

**Fix (2026-09-23).** Trackpad pinch zoom and two-finger pan did nothing
on macOS: the macOS embedder delivers *both* as `panZoomStart/Update/End`
pointer changes (with a cumulative `scale` and a per-event `panDelta`),
not as scroll/scale signal events — only the physical mouse wheel arrives
as a `PointerScrollEvent`. The app's `Listener` wired neither the panZoom
callbacks nor anything that matches them, so trackpad input was silently
dropped while wheel zoom kept working. The `Listener` now forwards
`onPointerPanZoomStart/Update/End`, and `WaterGame.panZoomUpdate` applies
the scale ratio (cumulative → per-event) through `cam.zoomAt` at the
gesture position and the pan delta through `cam.pan`. A 16th GUI contract
test drives a panZoom start/update/end sequence through the widget tree
and fails without the fix.

**Fix (2026-09-23).** The hover readout only followed the cursor while a
button was held: in Flutter a button-less mouse move is delivered as a
`PointerHoverEvent`, not a `PointerMoveEvent`, and the app's `Listener`
wired only `onPointerMove` — so the readout (and the crosshair) tracked a
pressed drag, i.e. a "selected" tile, on every platform. The `Listener`
now also forwards `onPointerHover`, so the readout shows the hovered tile
with no click, on Windows and macOS alike. A 15th GUI contract test drives
a real button-less mouse gesture through the widget tree and fails without
the fix.

**Fix (2026-09-22).** The hover readout was missing the SPEC 10
colour-coded strength bar: `_hoverPanel` showed `HP x/y` as text only. It
now draws a 60×6 bar between the material name and the counters, filled
`hp/maxHp`, colour lerping green→amber→red as it drops — shown only for
damageable cells (air/water and the 999-hp sentinels would read as a full
green bar). A 14th GUI contract test verifies it: hovering an intact
structural cell shows a full-width bar, hammering the cell to 1 hp shrinks
the fill in proportion.

**Fix (2026-09-22).** The tracer's ray march was a one-cell-diagonal
staircase, not the straight ray to the light: on shallow rays it ran a row
above the true line, so a sky cell whose line to a low sun slips past
under the roof was blocked, and the whole open sky beside the tower
rendered black in the GUI. The march is now a proper grid DDA (Amanatides
& Woo) over the exact line; the shadow of the tower under a low sun is a
clean diagonal from its top corner, matching the screenshot.

**Fix (2026-09-22).** The HUD text was nearly invisible: the app had no
dark theme, so `Text` defaulted to near-black on the dark panels. The
`MaterialApp` now carries a dark theme (scaffold background `0xFF0B0E14`,
cyan accent for the sliders and dropdown), and the counters, hover readout,
buttons, seed field, and key hints are legible in the running app.

**Change (2026-09-22).** The tower was too narrow. A bay is now 8 cells
wide, not 4, so the default tower (6 bays, not 3) is 50 columns wide, not
14, and the width setting and its slider run 1–10, not 1–5. The pool and
everything else keep their seeded layout rules.


**Phase 5 is complete and committed.** The traced view is a progressive
light field, 1:1 with the 220×240 grid, in pure Dart (`lib/trace/`, zero
Flutter imports). Every cell carries a running mean of its exact
next-event-estimated light: direct rays to the known lights — the sun (with
wavelength-dependent Beer–Lambert through water, so deep water reads dark
blue-green, a forward-scatter shaft, and a specular glint band that follows
the drawn wave slope) and every lit lamp (warm tungsten, 1/d² falloff) —
computed from precomputed scene geometry (ADR 0003): per-column contiguous
spans of occluder/water/glass cells price the ray at the columns it crosses,
and a per-light angular shadow sweep (each light-blocking cell as a disc
occluder, swept to a min-heap lower envelope) answers visibility with one
angle lookup; structure/ground/wood block, glass tints, furniture passes.
A sample is deterministic, so one is the settled value; a changing cell's
value is a running mean that re-converges, so a change never flashes black.
Per frame the tracer diffs the world (grid, spurt overlay, lamp
positions/states), marks the changed cells dirty plus a margin, and spends
a fixed 2,500-sample budget: dirty cells re-converge within it, the cells
nearest a moved lamp first (a fresh field settles in ~0.7 s, a local edit
re-converges only its box, a falling lamp's light follows with a
sub-second lag, every other cell bit-identical), and the remainder
re-means a rotating stripe of undirty cells so the whole field follows the
drifting sun with a sub-second lag. A steady frame costs ~7 ms of the
33 ms budget on a 30-floor world with four lamps (`tool/trace_bench.dart`).
`TraceBudget` falls back to the plain view only on a sustained overrun (a
full 2 s window over the cap) and recovers on a full window back under it.
The standing checks are green: lamp light never crosses a solid wall
(incl. one-cell partitions), light passes through furniture, a roofed
pool's surface is static across the sun's arc, an open pool glitters
brightest under the sun, and a submerged lamp reads warm amber. See the
artifact: `dart run tool/phase5_dump.dart` writes the four standing-check
scenes as ASCII light-field frames (materials + a luminance ramp) to
`out/phase5/`.

**Phase 4 is complete and committed.** The sun disc is a deterministic
function of sim time: a 420 s cycle, rising from the left, crossing the top
at mid-cycle, setting at the right, and looping — frozen when the world is
paused. The eight user tools work on a 1–15 cell brush: the hammer removes
one strength per hit (structure breaks to rubble at 0, other materials to
debris; ground is untouchable), the bomb deals decaying falloff damage
(centre worst, radius edge one), water/erase paint, and the four build
materials place their cell (ground never overwritable). Rain spawns
0–40 water cells per sim-second on the top row, in random columns across
the full width, and scales exactly with the speed scale. The sim driver is a
fixed-timestep
accumulator: wall-clock time × speed scale (0.5/1/2, paused at 0) →
30 physics ticks per sim-second, so 2x advances the sim state (sun, water,
structure, tools) exactly twice as fast per wall second. See the artifact:
`dart run tool/phase4_dump.dart` writes the sun arc, the hammer sequence,
the bomb blasts, and 3 sim-seconds of rain at 0.5x/1x/2x (all reaching the
same sim time and spawning the same 90 drops) to `out/phase4/`.

**Phase 3 is complete and committed.** A section that loses its load path to
the foundation (severed by a support gap of ≥ 3 air cells; gaps of ≤ 2 still
bridge) slumps for ~2 sim-seconds and then breaks into rubble (heavy
materials) or debris; a re-braced section is saved. Loose objects obey
buoyancy: a rigid float rises through water and rests exactly at the surface
(fully submerged to rise; water displaced, never overlapped), heavy objects
sink to the floor, granular rubble/debris move cell by cell, and flowing
water washes them sideways out of a vertical column (SPEC 4); water volume
is conserved through every move. A ceiling lamp fixed to a slab is released
when the slab breaks and falls lit, then floats at the surface. See the
artifact: `dart run tool/phase3_dump.dart` writes ASCII frames of a full
collapse (intact → mid-slump → broken → settled) to `out/phase3/`.

**Phase 2 is complete and committed.** Spawned water falls and settles at the
basin floor; a contained pool levels out and rests at exactly its depth; a
thin sheet running off a wall pushes with the deep body's full head (erodes a
low-tolerance partition); walls with tolerance > head are untouched, with
tolerance < head erode; a confined body with head ≥ 8 jets upward out of an
open crack (sustained, contiguous spurt); water volume is conserved over long
runs (grid + spurt overlay). The surface is flat where the water is at rest:
water that lands (a pour, a falling column, rain) dips the line where it
touches down, the ripples spread sideways, and they decay back to a flat
line in a couple of seconds.

## Notes

- `NOTES.md` — tooling lessons learned while building (hung `dart test`,
  generator debugging).
- `docs/adr/0001-seeded-world.md` — the seeded-world determinism decision.
