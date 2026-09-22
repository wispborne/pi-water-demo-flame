# Implementation Plan — 30 Floors & a Pool (Flame, Flutter desktop)

**Target platform: desktop.** Flutter **desktop** app (Windows primary, per
the dev machine). `flutter create --platform=windows,linux,macos`.

- **Traced view**: no WebGL feature-detection story; on desktop we can
  assume a decent GPU is usually present, but the fallback contract still
  stands — if the tracer can't sustain its frame budget (or the device
  "gives up" mid-run, i.e. sustained frame overruns), fall back to plain
  view; toggle re-enables when it recovers.
- **Seed**: shareable by name (a text field in the UI) and passable as a
  `--seed` startup argument.
- Mouse-only input is fine; no touch concerns.
- SPEC.md, CONTEXT.md, and ADR 0001 are written for this target.

## Overall shape

This is a cell-grid simulation, not a sprite game. Flame is used for what it's
good at; the world itself is one canvas, not a component forest.

### Flame's job (the 20%)
- **Game loop**: fixed-timestep accumulator over `update()`; speed cycle
  0.5×/1×/2× = physics ticks per second × scale; pause = 0. Physics is pure
  Dart, decoupled from render rate.
- **CameraComponent**: fit whole world (tower + pool + margin) at load, after
  Reset / New seed; left-drag pan with selected tool, right-drag or
  space+drag pan, wheel zoom around cursor.
- **Input routing**: mouse buttons → tools, keys 1–8 → tool select.
- **HUD**: a Flutter `Stack` overlay (not in-game components): counters,
  hover readout, controls, sliders.

### The grid (the core)
- **One `CustomPainter` per frame**, not one component per cell. 30 floors × 10
  bays is at most a few thousand visible cells; 10k Flame components would be a
  perf disaster. The painter iterates the grid and batches fill-rects per
  material; water surface is a wavy line (slow swell + two faster short waves).
- **Fixed grid dimensions are constants**, independent of seed/floors/width
  (SPEC §1).
- Grid resolution: pick a cell size so the default 30-floor tower fits the
  camera at load. Grid constants are a fixed size (e.g. ~180×100 cells) so the
  falling-sand sim and the tracer stay in the same coordinate space.

### The hard part: traced view (default on)
Spec wants *settled* light — clean steady picture in ~1s, re-convergence only
in changed regions. That is a **progressive ray tracer in pure Dart** at low
resolution:

- Light field at low res (~4–8 px per cell); rays from the sun + every lamp
  step through the grid; water/glass bend and tint by depth (red dies before
  green); walls cast soft shadows; forward-scattering shafts inside water.
- Accumulate per-pixel over frames (temporal accumulation with a short lag
  following slow changes like the drifting sun).
- **Dirty-region tracking**: a cell (or light-field tile) is dirty when water
  moves into/out of it, a wall breaks, or a lamp state changes; converged
  undirty pixels keep their value — this is what gives "re-converges only in
  the places that changed".
- Blit the light field as a `ui.Image`/texture; no GPU compute needed.
- Water surface glitters only where the sun actually reaches; caustic drifts
  across the pool floor — both derived from the same traced field, no extra
  mechanism.
- **Fallback contract**: tracer must sustain its per-frame ray budget; if it
  can't (measured over a window), switch to plain view, disable the toggle;
  recover (budget met again) → re-enable.

### Things the spec makes easy
- Furniture is pass-through to **both** water and light: water and rays treat
  furniture cells as empty. No per-item interaction.
- "No seep mechanism": water blocking is binary. No permeability table.
- Pressure is **per water body**: BFS flood-fill finds connected bodies; each
  body gets one head (from its own surface, carried sideways); erodes an
  adjacent wall only once head exceeds that material's tolerance. The
  physically interesting bit, but it's an algorithm.

### Performance risk
7-minute sun cycle + jets + cascade + 2s rubble slump, all in Dart on a
desktop app. Falling-sand on a ~180×100 grid is cheap; the tracer is the
budget consumer and is low-res by design. Smoke-test the full loop early (a
30-floor world mid-flood, traced view on) rather than at the end.

## Technique choices (evaluated 2025)

Chosen and rejected options, so the tradeoffs are on the record. Both domains were
checked against current practice (semi-Lagrangian / "Stable Fluids" grid fluids;
progressive Monte Carlo path tracing with NEE/MIS).

### Water — keep the falling-sand cellular model, add cheap realism
**Rejected: a per-tick Eulerian velocity field + sparse-Poisson pressure
projection (Stam's "Stable Fluids" advection→diffusion→projection loop, or the
MAC/staggered-grid + conjugate-gradient Poisson solve).** It is the classic
*continuous* grid-fluid method, but it is not more efficient or more realistic
here: (a) the world is a 220×240 **cell** grid, not a continuous field, so a
velocity field on edges + a divergence-free projection would be a second,
heavier model bolted over the cell sim; (b) it would replace per-body pressure
with a global pressure solve, breaking the contract (one head per connected
body, erosion when head > material tolerance, jets, buoyancy) that the 4 standing
checks and Phases 2–3 are written against; (c) it buys nothing the cell model
doesn't already give, at higher cost per tick.

**Chosen: falling-sand cellular water (the cell-discretized form of the
semi-Lagrangian "Stable Fluids" method — unconditionally stable because a whole
cell moves rather than a velocity being interpolated), refined with the cheap
realism terms grid fluids use:**
- **Backward (semi-Lagrangian) advection** is the stability choice and is
  implicit in the cell model: each water cell steps one row down or one column
  sideways per tick, so the field never overshoots (unconditionally stable) —
  the cellular analog of Stam's semi-Lagrangian advection.
- **Per-body hydrostatic head** (BFS flood-fill → one head per connected body,
  carried sideways) is the discrete pressure-integral; erode a wall only when
  head > material tolerance. This is the physically meaningful part and stays.
- **Volumetric momentum (vorticity-confinement analog)**: a water cell carries a
  small decaying lateral velocity, so thin sheets, pour-off, and jets have
  persistent sideways motion instead of freezing into a brick. This is the
  cheap, standard anti-numerical-damping term (vorticity confinement / momentum
  advection) ported to the cell model — the one realism term worth adding.
- **Water volume is conserved**: no water is created or destroyed except by
  erosion (wall → rubble) and tools; asserted in Phase 2 tests so the sim can't
  silently leak mass.

### Traced view — NEE + MIS, not BDPT / photon maps / neural sampling
**Chosen: progressive per-cell Monte Carlo with Next Event Estimation +
Multiple Importance Sampling**, which is the standard, robust modern setup for a
scene with a **small set of known, bright, finite lights** (1 sun + a few dozen
lamps) plus a participating medium (water):
- **NEE**: from each sampled point, directly ray to each known light (sun +
  lamps) instead of relying on random path hits. This is the dominant
  variance-reduction / efficiency win for exactly this scene — a handful of
  known, finite, bright sources. Without it a diffuse point would almost never
  hit a lamp by random bounce.
- **MIS**: balance the NEE estimator against the BSDF (path) estimator so the
  two combine with low variance and no double-counting. This is the modern way
  to use NEE; it keeps the caustic/focus paths (which NEE alone under-samples)
  from going black while the diffuse/soft-shadow paths stay clean.
- **Cosine-weighted hemisphere sampling** for the diffuse bounces (cheap and
  unbiased).
- **Temporal accumulation + dirty-region re-convergence** (already the plan):
  per-pixel accumulation with a short lag following slow changes (the drifting
  sun); converged undirty pixels keep their value. (ReSTIR-style spatiotemporal
  resampling is the current frontier and is the natural future upgrade, but
  classic per-pixel accumulation is the pragmatic choice for a low-res
  progressive field and keeps the budget predictable.)
- **Participating medium (water)**: per-ray Beer–Lambert / depth-attenuation
  stepping with **wavelength-dependent absorption (red dies before green)** and
  forward-scattering shafts. This is the standard efficient+realistic treatment
  for a 2D cutaway; exact multiple-scattering photon Monte Carlo is the
  realistic extreme but is far too costly per frame for a low-res field.

**Rejected (with reasons):**
- **Bidirectional path tracing (BDPT)** — needs a camera *and* a light path plus
  connection/weighting machinery, designed for 3D scenes with many bounces.
  This is a 2D cutaway rendered as a per-cell *light field*, not per-pixel
  camera rays, with a small known light set — BDPT's machinery adds cost with
  no benefit here.
- **Photon mapping / photon tracing** — a precomputed, static photon map does not
  fit a dynamic, dirty-region, per-cell field that re-converges as water moves
  and walls break.
- **Neural / learned importance sampling (learned light selection, learned BRDF
  sampling)** — the scene has a fixed, small set of materials (air / water /
  glass / structure / furniture) and a small known light set. Analytic NEE +
  MIS + cosine sampling already capture the variance reduction; a learned sampler
  adds training + inference cost for a fixed, known scene.

## Layout

Two packages (decision 5): a root pure-Dart package that owns all simulation
and light physics, and `app/` — a Flutter/Flame package that depends on it by
path. Everything in the root package runs headless; `dart test` covers it
without a display.

```
pubspec.yaml           # root package: name, dart sdk constraint
lib/
  main.dart            # CLI entry: --seed arg, runs the sim headless (debug)
  core/                # pure Dart, zero Flutter imports
    constants.dart     # grid dims, floor/bay geometry, material table, timings
    rng.dart           # seeded PRNG — seed + settings → world (ADR 0001)
    materials.dart     # material enum, properties (tolerance, hp, buoyancy)
    world.dart         # grid container, cell access, water bodies, dirty tracking
    tower.dart         # generation: floors/rooms/furniture/lamps/pool/ground
    water.dart         # falling sand, per-body pressure, jets, cascade
    structure.dart     # load-path severance (gap ≥ 3 cells) → rubble slump
    buoyancy.dart      # float/sink: furniture per table, rubble sinks, debris floats
    sun.dart           # ~7-min cycle (sim time), freezes on pause
    tools.dart         # 8 tools, brush 1–15 (default 5), initial tool = Water
  trace/               # pure Dart, zero Flutter imports
    tracer.dart        # progressive light field, dirty regions, fallback contract
    field.dart         # light-field state: accumulation, convergence, dirty tiles
  sim.dart             # fixed-timestep driver: tick(world) — the one entry point
test/                  # dart test, headless
  determinism_test.dart# same seed+settings → identical world, twice; across settings
  structure_test.dart  # severance → slump; gaps ≤ 2 bridge
  pressure_test.dart   # per-body head; sheet carries deep head
  standing_checks.dart # the 4 named scenarios (SPEC §11)
app/                   # Flutter/Flame package (created when Flutter SDK available)
  pubspec.yaml         # depends on root package by path
  lib/main.dart        # app shell, seed arg, HUD overlay (Stack)
  lib/game/water_game.dart # FlameGame: loop, camera, input routing
  lib/ui/hud.dart      # counters, hover readout, controls, sliders
  lib/render/grid_painter.dart # one CustomPainter per frame; water wavy line
```

**Key architectural rule**: `core/` and `trace/` are plain Dart with zero
Flutter imports. The 4 standing checks (lamp light blocked by solid walls
incl. 1-cell partitions; lamp light passes through furniture; roofed pool
surface static across the sun's arc; open pool glitters brightest under the
sun) run headless in the root package's tests. The Flame layer is thin:
loop + camera + input + paint.

## Standing checks (SPEC §11)
1. Lamp light must not cross a solid wall — including one-cell partitions.
2. Lamp light must pass through furniture.
3. A roofed pool's surface must not move as the sun crosses the sky.
4. An open pool must glitter brightest under the sun.

(The former flood-scenario check was removed with the flood tool; not in the
contract. There is no user-facing way to flood the world — no flood tool, no
single-key tower blast.)

## Decisions (resolved)
1. **Grid: 220 × 240 cells (W × H).** Floor height 4 cells (1 slab + 3 interior),
   bay 8 cells wide. Ground surface level seeded
   12–28 cells above the bottom; sky margin ≥ 12 cells. Rain distributes
   uniformly across the full 220 width. (The earlier ~180×100 estimate cannot
   fit a 50-floor tower at 4 cells/floor.)
2. **Tracer**: light field 1:1 with the grid (220 × 240 px). Budget:
   1,500–2,500 pixel-light shadow rays per frame at 1× (30 t/s), measured over a
   2 s window; sustained overrun → fall back to plain view. Convergence window
   ~1 s; dirty regions re-converge, undirty pixels keep their value.
3. **Sun: sim time.** Full cycle = 420 sim-seconds at 1×; speed scales it,
   pause (scale 0) freezes it.
4. **Physics: fixed-timestep accumulator, 30 ticks/s at 1×** (0.5× → 15,
   2× → 60). Slump duration 2 sim-seconds.
5. **Package shape**: one root pure-Dart package (zero Flutter imports in
   `lib/core` and `lib/trace`, testable with `dart test`); `app/` is a separate
   Flutter/Flame package (created with the Flutter SDK in the GUI phase)
   depending on the root package by path. The 4 standing checks run headless in
   the root package's tests.
6. **Material properties** (tolerance = water-head in cells that erodes it;
   hp = tool-damage to destroy):

   | Material | Tolerance | hp | Note |
   |---|---|---|---|
   | glass | 2 | 2 | very weak, floats a little |
   | wood | 6 | 3 | |
   | concrete | 12 | 8 | |
   | reinforced concrete | 20 | 12 | default structure |
   | steel | 30 | 20 | |
   | titanium | 40 | 30 | |
   | ground | ∞ | ∞ | very hard |

   Rubble: broken heavy, pass-through, sinks. Debris: broken light,
   pass-through, floats.
7. **PRNG**: FNV-1a 64-bit hash of (seed string + settings) → PCG32 (pure-Dart,
   integer-only, stable across platforms); forked sub-streams per world section.
   No `math.random`.
8. **Jets**: head ≥ 8 cells → spurt upward from open cracks; spurt height
   ≈ head / 2, capped at 12 cells.
