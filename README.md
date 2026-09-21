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
    column), volume conserved.
  - `structure.dart` — structural failure: a section severed from the
    foundation (support gap ≥ 3 air cells; gaps ≤ 2 bridge) slumps for
    ~2 sim-seconds, then breaks into rubble (heavy materials) or debris.
  - `buoyancy.dart` — loose objects: rigid furniture masses and free lamps
    plus granular rubble/debris; water displacement, floats rising,
    heavies sinking; ceiling lamps release and fall lit.
- `test/phase1_test.dart` — determinism + structural invariants.
- `test/phase2_test.dart` — water contract: settle/level, per-body head
  erosion, tolerance boundaries, jets, volume conservation.
- `test/phase3_test.dart` — structure + buoyancy contract: severance at a
  3-cell gap, 2-cell gap bridges, slump → rubble, floats rest at the
  surface, heavies sink, water displacement conserves volume, ceiling lamp
  releases.
- `tool/phaseN_dump.dart` — per-phase headless artifacts: pure-Dart ASCII
  dumps of the sim into `out/phaseN/` (e.g. `dart run tool/phase3_dump.dart`).
- `app/` — the Flutter/Flame GUI (Phase 6). Not present yet.

## Run

```sh
dart pub get
dart test          # headless sim tests (Phases 1–5)
dart analyze lib test
dart run tool/phase3_dump.dart   # Phase 3 artifact: collapse frames in out/phase3/
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
| 4 | Sun, tools, sim driver | not started |
| 5 | Traced view (progressive light field) | not started |
| 6 | GUI (Flutter/Flame) | not started |

**Phase 3 is complete and committed.** A section that loses its load path to
the foundation (severed by a support gap of ≥ 3 air cells; gaps of ≤ 2 still
bridge) slumps for ~2 sim-seconds and then breaks into rubble (heavy
materials) or debris; a re-braced section is saved. Loose objects obey
buoyancy: a rigid float rises through water and rests exactly at the surface
(fully submerged to rise; water displaced, never overlapped), heavy objects
sink to the floor, granular rubble/debris move cell by cell, and water volume
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
