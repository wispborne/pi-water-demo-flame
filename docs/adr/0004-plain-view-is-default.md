# The plain view is the default; path tracing is no longer under consideration

The traced view starts off. A new `SimState` loads in the plain day-sky view, and the T key / HUD button turn the traced view on or off as before.

**Why:** the traced view is the most expensive part of the app (the per-frame ray budget, the span/sweep precompute, the settle-and-re-converge loop) and it is a demo feature, not the point of the project. The plain view already shows the whole scene with the sun and glow. The decision is final: no further investment in the traced view — no new lighting features, no performance work on the tracer, no plans to make it the default again. It stays in the code as a working optional toggle (the Phase 5 contract tests and the budget-fallback contract keep covering it), but it is frozen.

**Consequences:** the default is the plain view at load, after Reset, and after New seed. The traced view remains selectable via T or the HUD button, behaves exactly as before when on, and still falls back on sustained budget overrun. SPEC 7 is "default off, toggleable".
