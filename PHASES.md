# Phases — 30 Floors & a Pool

Each phase ends in a green `dart test` run and a commit. Dependencies flow
forward: later phases never re-open earlier ones. Phases 1–5 are pure Dart
and fully headless-testable on any box; Phase 6 is the GUI.

**User-verifiable artifact.** Each phase also ships a runnable, human-
inspectable artifact so the result is checkable before the next phase is
built on top (no coding to the end to find a mismatch):

|Phase|Artifact (run it, look at it)|
|---|---|
|1|`tool/phase1_dump.dart` → ASCII frame of the generated world (seed, floors, rooms, pool)|
|2|`tool/phase2_dump.dart` → ASCII frames: pool settling to depth, erosion of a weak wall, a jet|
|3|`tool/phase3_dump.dart` → ASCII frames: severance → rubble slump, lamp release, flooded room (sofa up, fridge/TV down)|
|4|`tool/phase4_dump.dart` → ASCII timeline: sun arc, hammer/bomb damage, rain counts, 0.5×/1×/2× speed|
|5|`tool/phase5_dump.dart` → ASCII light-field frames for the 4 standing checks|
|6|The running desktop app itself (`flutter run -d linux`)|

The test bar is behaviour and invariants only — no source-text, wiring, or
default-pinning assertions (see workflow: tests defend observable contracts).

## Phase 1 — Foundation: deterministic world generation
**Goal:** seed + settings → the exact t=0 world, verifiable twice and across
settings. Nothing animates yet; the world is a static, correct structure.

- Scaffold the root pure-Dart package (`pubspec.yaml`, `lib/`, `test/`).
- `core/rng.dart` — FNV-1a-64 seed hash → PCG32 (pure Dart, integer-only);
  forked sub-streams per world section (ADR 0001). No `math.random`.
- `core/constants.dart` — grid 220×240; floor 4 cells, bay 8 cells; ground
  surface 12–28; material table (tolerance/hp/buoyancy, decision 6); timings.
- `core/materials.dart` — material enum + properties.
- `core/world.dart` — grid container, cell access, water-body bookkeeping.
- `core/tower.dart` — generation: floors (1–50), rooms (1–3, contiguous, 1-cell
  partitions), furniture (non-overlapping, per §2 table), lamps (3 kinds),
  pool (size/position seeded, initial fill 8 cells clamped), ground.

**Testable contract:** same seed+settings → byte-identical world, run twice;
different settings (floors/width/material) → different but valid worlds.
Structural invariants: floor count = setting; every floor 1–3 rooms; no two
items share a cell, ≤1 of each type per room; pool present, fill = 8 clamped
to pool height; whole structure above the ground surface.

## Phase 2 — Water physics
**Goal:** water falls, flows, and exerts per-body pressure that erodes
material. The pool reaches equilibrium.

- `core/water.dart` — falling-sand fall/flow; per-body BFS flood-fill; head
  from each body's own surface, carried sideways; erode a wall only once head
  exceeds its tolerance; jets (head ≥ 8, spurt height); pour-off cascade.

**Testable contract:** spawned water falls and settles at the pool floor at
the configured depth; a thin sheet running off a wall pushes with the deep
body's full head; a wall with tolerance > head is untouched, one with
tolerance < head erodes; a head ≥ 8 body jets upward out of an open crack.

## Phase 3 — Structural failure and buoyancy
**Goal:** the structure fails cell by cell and loose items float or sink.

- `core/structure.dart` — load-path severance (support gap ≥ 3 cells; ≤ 2
  bridge) → slump into rubble over ~2 s (not vanish).
- `core/buoyancy.dart` — furniture floats/sinks per the §2 table; glass floats
  a little; heavy broken material → sinking rubble; light things → floating
  debris.

**Testable contract:** severing a support by ≥ 3 cells slumps that section
into rubble over ~2 s; a ≤ 2-cell gap holds. A flooded sofa rises to the
surface, a fridge and TV sink; broken concrete becomes sinking rubble,
broken furniture/wood floating debris.

## Phase 4 — Sun, tools, and the sim driver
**Goal:** the interactive, time-scaled world the user drives.

- `core/sun.dart` — 420 sim-second cycle (rise/arc/set/loop), freezes at
  scale 0.
- `core/tools.dart` — 8 tools (hammer, bomb, water, erase, build
  concrete/steel/glass/wood), brush 1–15 (default 5), initial tool Water.
- Rain (slider 0–40): water cells per second on the top row, uniform across
  the full 220 width.
- Speed cycle 0.5×/1×/2×, pause = scale 0.
- `sim.dart` — fixed-timestep accumulator (30 ticks/s at 1×) driving
  `tick(world)`, the single entry point.

**Testable contract:** sun position is a deterministic function of sim time and
is frozen when paused; a hammer/bomb reduces a cell's strength toward
destruction; rain at N spawns ≈ N water cells/s on the top row; 2× advances
sim state twice as fast as 1× per wall second.

## Phase 5 — Traced view (progressive light field)
**Goal:** genuinely transported light — the 4 standing checks pass headless.

- `trace/field.dart` — light-field state (per-pixel accumulation, convergence,
  dirty tiles).
- `trace/ray.dart` — per-column contiguous spans of occluder/water/glass
  cells; a ray's transmittance and first occluder come from the spans it
  crosses (a ray costs its width in columns, not its length in cells).
- `trace/shadows.dart` — the per-light angular shadow sweep: every
  light-blocking cell is a disc occluder around its centre, swept to the
  first-hit disc per angle; a visibility query is one angle lookup.
- `trace/surface.dart` + `trace/transport.dart` — one cell's light: direct
  next events to the sun and the lit lamps (Beer–Lambert through the water
  spans, red dies before green), forward-scattering shafts in water, the
  surface glint gathered toward the sun, the caustic on the pool floor from
  sun rays refracted at the surface.
- `trace/tracer.dart` — frame driver: world diff, dirty regions, budget.
- Temporal accumulation (~1 s settle, short lag); dirty-region tracking
  (re-converge only where water moved / a wall broke / a lamp changed).
- Fallback contract: sustained budget overrun → plain view, toggle off;
  recovery → re-enable.

**Testable contract (the 4 standing checks, headless):** (1) a lamp's light
never crosses a solid wall, including one-cell partitions; (2) light passes
through furniture; (3) a roofed pool's surface is static across the sun's arc;
(4) an open pool glitters brightest under the sun. Plus: the field settles to
a steady picture in ~1 s and re-converges only in dirty regions; an under-water
lamp reads warm amber.

## Phase 6 — GUI (Flutter/Flame, `app/`)
**Goal:** the visible, interactive desktop program.

- `app/` Flutter package depending on the root package by path.
- `lib/game/water_game.dart` — game loop (fixed-timestep accumulator over
  `update()`), camera (fit whole world at load / Reset / New seed; left-drag
  pan with tool, right-drag or space+drag pan, wheel zoom around cursor),
  input routing (mouse buttons → tools, keys 1–8).
- `lib/render/grid_painter.dart` — one `CustomPainter` per frame (batched
  fill-rects per material; the water-surface line, flat at rest and
  rippling where water lands).
- `lib/ui/hud.dart` — Flutter `Stack` overlay: counters (water cells, building
  damage %, destroyed cells, FPS), hover readout (material, strength bar,
  pressure, light swatch), controls (Pause, Speed, Reset, New seed, Glow,
  Path Trace), sliders (brush, rain, floors, width, structure), seed name
  field.

**Testable contract:** `flutter test` for the app package; the camera fits the
whole world at load and after Reset/New seed; speed/pause/scale propagate to
the sim driver; the traced view falls back to the plain view on sustained
overrun and the toggle re-enables on recovery. *(Note: the Flutter SDK is not
installed on this dev box, so this phase is authored and `flutter test`'d
where the SDK is present; the headless sim in Phases 1–5 is the verifiable
core.)*
