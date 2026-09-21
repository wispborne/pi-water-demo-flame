# 30 Floors & a Pool

> **Built end-to-end by a local LLM** — no cloud LLM and no human editing.
> A for-fun proof-of-concept side project: the model drives the entire build
> (design, code, tests, debugging) on the developer's own machine, and every
> line of code in this repo is locally generated.

A seeded 2D side-view water simulation with physically traced light. A tower
is built beside a pool; the structure fails cell by cell under water,
pressure, and user attack, and light is genuinely transported.

Built in Flutter/Flame (desktop) on a pure-Dart core. The simulation itself
is a pure-Dart package — headless-testable on any box; the GUI is the
`app/` package.


## Layout

- `lib/core/` — the pure-Dart simulation core (no Flutter import):
  - `constants.dart` — grid 220×240; floor 4 cells, bay 4 cells; timings.
  - `rng.dart` — FNV-1a-64 seed hash → PCG32; forked sub-streams per world
    section. Deterministic; integer-only; no `dart:math.Random` (ADR 0001).
  - `settings.dart` — world settings (floors 1–50, width 1–5, structure
    material) with validation.
  - `materials.dart` — material enum + property table (tolerance/hp/buoyancy).
  - `world.dart` — the cell-grid container (cell access, water/structural
    bookkeeping, destroyed-cell counter, snapshot + fingerprint).
  - `tower.dart` — `WorldBuilder`: ground, tower, floors/rooms, furniture,
    lamps, pool.
  - `lamp.dart` — the three lamp kinds (floor / ceiling / table) and states.
  - `water.dart` — falling-sand water: per-body BFS head (carried sideways),
    erosion at head > material tolerance, lateral momentum, jets (a
    head ≥ 8 confined body spurts out of an open crack as a held spurt
    column), wash (flowing water scours rubble/debris sideways), volume
    conserved.
  - `structure.dart` — structural failure: a section severed from the
    foundation (support gap ≥ 3 air cells; gaps ≤ 2 bridge) slumps for
    ~2 sim-seconds, then breaks into rubble (heavy materials) or debris.
  - `buoyancy.dart` — loose objects: rigid furniture masses and free lamps
    plus granular rubble/debris; water displacement, floats rising,
    heavies sinking; ceiling lamps release and fall lit.
  - `sun.dart` — the sun disc: a deterministic function of sim time (420 s
    cycle, left-right arc, freezes when the world is paused).
  - `tools.dart` — the eight user tools (hammer, bomb, water, erase, four
    build materials) with a 1–15 cell brush, plus rain (0–40 water cells
    per sim-second on the top row, uniform left to right).
- `sim.dart` — the fixed-timestep driver: wall-clock time × speed scale
  (0.5/1/2, paused at 0) → physics ticks at 30/s; owns the sim clock, the
  sun, and the tools; water volume is conserved through it.
- `test/phase1_test.dart` — determinism + structural invariants.
- `test/phase2_test.dart` — water contract: settle/level, per-body head
  erosion, tolerance boundaries, jets, volume conservation.
- `test/phase3_test.dart` — structure + buoyancy contract: severance at a
  3-cell gap, 2-cell gap bridges, slump → rubble, deep water washes rubble
  out of a vertical column, floats rest at the surface, heavies sink,
  water displacement conserves volume, ceiling lamp releases.
- `test/phase4_test.dart` — sun determinism, the eight tools (hammer to
  rubble, bomb falloff, build/erase, rain at 3 rates, keys 1–8), and the
  fixed-timestep driver (pause, 0.5x/1x/2x, speed cycle).
- `tool/phaseN_dump.dart` — per-phase headless artifacts: pure-Dart ASCII
  dumps of the sim into `out/phaseN/` (e.g. `dart run tool/phase4_dump.dart`).
- `app/` — the Flutter/Flame GUI (Phase 6). Not present yet.

## Run

```sh
dart pub get
dart test          # headless sim tests (Phases 1–5)
dart analyze lib test
dart run tool/phase4_dump.dart   # Phase 4 artifact: sun arc, tools, driver in out/phase4/
```

The GUI (Phase 6) is a separate `app/` Flutter package and is not yet
authored.

## Status

Phases are defined in `PHASES.md`; each ends in a green `dart test` run and a
commit. Decisions are in `PLAN.md`; the design context in `CONTEXT.md`.

| Phase | Description | Status |
|---|---|---|
| 1 | Foundation: deterministic world generation | ✅ done |
| 2 | Water physics (fall/flow, per-body head, erosion, jets) | ✅ done |
| 3 | Structural failure and buoyancy | ✅ done |
| 4 | Sun, tools, sim driver | ✅ done |
| 5 | Traced view (progressive light field) | not started |
| 6 | GUI (Flutter/Flame) | not started |

**Phase 4 is complete and committed.** The sun disc is a deterministic
function of sim time: a 420 s cycle, rising from the left, crossing the top
at mid-cycle, setting at the right, and looping — frozen when the world is
paused. The eight user tools work on a 1–15 cell brush: the hammer removes
one strength per hit (structure breaks to rubble at 0, other materials to
debris; ground is untouchable), the bomb deals decaying falloff damage
(centre worst, radius edge one), water/erase paint, and the four build
materials place their cell (ground never overwritable). Rain spawns
0–40 water cells per sim-second on the top row, uniform left to right, and
scales exactly with the speed scale. The sim driver is a fixed-timestep
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
runs (grid + spurt overlay).

## Notes

- `NOTES.md` — tooling lessons learned while building (hung `dart test`,
  generator debugging).
- `docs/adr/0001-seeded-world.md` — the seeded-world determinism decision.
