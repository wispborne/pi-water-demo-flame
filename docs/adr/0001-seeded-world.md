# The whole world is seeded, not just the tower

The spec originally said only the tower is rebuilt from the seed, leaving the stage (grid, pool, sky) unspecified. We decided the seed deterministically determines the entire world — stage layout and tower — not just the tower.

**Why:** a seed is shareable by name and passable as a startup argument; a shared name must reproduce the exact scene, not just the tower, or two people opening the same name would see two different pools beside the same tower. Extending determinism from "same seed + settings → same tower" to "same world" makes the whole contract verifiable by a standing check, and keeps Reset ("rebuilds the current seed") well-defined without a separate rule for the stage.

**Consequences:** every world property must be classified as seeded or constant; the camera, pool, and tower must all be reproducible from seed + settings; anything user-modified (hammered, built, damaged) is cleared by Reset and New seed.
