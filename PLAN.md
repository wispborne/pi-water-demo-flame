# Implementation Plan — 30 Floors & a Pool (Flame, Flutter desktop)

**Target platform: desktop, not browser.** The spec's "interactive web page" is
retrofit: this is a Flutter **desktop** app (Windows primary, per the dev
machine). `flutter create --platform=windows,linux,macos`. Consequences:

- **Traced view**: no WebGL feature-detection story; on desktop we can assume a
  decent GPU is usually present, but the fallback contract still stands — if the
  tracer can't sustain its frame budget (or the device "gives up" mid-run,
  i.e. sustained frame overruns), fall back to plain view; toggle re-enables
  when it recovers.
- **URL seed**: becomes "seed in the title bar / startup arg". Seed stays
  shareable by name (a text field) — `dart run` argument or an in-app field.
  URL param support is not required on desktop.
- Mouse-only input is fine; no touch concerns.
- Everything else in SPEC.md / CONTEXT.md / ADR 0001 carries over unchanged.

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
- **One `CustomPainter` per frame**, not one component per cell. 30 floors × 5
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

## Layout (when starting)

```
lib/
  main.dart            # app shell, seed arg, HUD overlay (Stack)
  game/water_game.dart # FlameGame: loop, camera, input routing
  core/                # pure Dart, no Flutter imports
    rng.dart           # seeded PRNG — seed + settings → world (ADR 0001)
    world.dart         # grid, cells, water bodies
    tower.dart         # generation: floors/rooms/furniture/lamps/pool
    water.dart         # falling sand, pressure, jets, cascade
    structure.dart     # load-path severance (gap ≥ 3 cells) → rubble slump
    buoyancy.dart      # float/sink: furniture per table, rubble sinks, debris floats
    sun.dart           # ~7-min cycle, freezes on pause
    tools.dart         # 8 tools, brush 1–15 (default 5), initial tool = Water
  trace/tracer.dart    # progressive light field, dirty regions, fallback
  ui/hud.dart          # counters, hover readout, controls, sliders
test/standing_checks.dart # the 4 named scenarios, headless (no game loop)
```

**Key architectural rule**: `core/` and `trace/` are plain Dart with zero
Flutter imports. The 4 standing checks (lamp light blocked by solid walls
incl. 1-cell partitions; lamp light passes through furniture; roofed pool
surface static across the sun's arc; open pool glitters brightest under the
sun) run headless in a test. The Flame layer is thin: loop + camera + input +
paint.

## Standing checks (SPEC §11)
1. Lamp light must not cross a solid wall — including one-cell partitions.
2. Lamp light must pass through furniture.
3. A roofed pool's surface must not move as the sun crosses the sky.
4. An open pool must glitter brightest under the sun.

(The former flood-scenario check was removed with the flood tool; not in the
contract. There is no user-facing way to flood the world — no flood tool, no
single-key tower blast.)

## Open decisions (decide before coding)
1. Exact grid dimensions (fixed constants) — must fit 30 floors × 5 bays +
   pool + ground + margin, small enough for the tracer budget.
2. Tracer ray budget per frame and the light-field resolution.
3. Sun cycle: 7 minutes of *sim time* or wall clock (speed scales it — it's
   sim time, per SPEC §9 "scales physics, sun, and glow together").
4. Seed in URL: N/A on desktop — seed field + `--seed` startup arg.
