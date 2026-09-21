# Tooling notes

Hard-won, tooling-specific lessons. Keep terse.

## `dart test` hangs and zombies

- **`timeout N dart test` does not kill a hung test.** `timeout` sends SIGTERM;
  `dart test` installs a SIGINT/SIGTERM handler that prints
  `Waiting for current test(s) to finish. Press Control-C again to terminate
  immediately.` and **blocks**, so the VM outlives the timeout. Use
  `timeout -s KILL N dart test …` (or `pkill -9`) to get a definitive end state.
- **A hung test leaves a 100%-CPU zombie `dart` VM behind.** Several of these
  pile up and make every *subsequent* test run crawl (all tests pass in 1s
  alone, but the full suite "hangs" past 300s). Symptom: `ps` shows
  `dart:test` at ~100% CPU. Fix: `pkill -9 -f "dart test"` before re-running.
- **`tail` on `dart test` output mid-run is stale.** `dart test` buffers its
  output when piped; the log only flushes on exit. Judge by the `EXIT=` line
  plus the *final* log, never by a mid-run `tail`.

## Debugging a deterministic generator

- **`bool.fromEnvironment('FLAG')` + `dart run --define=FLAG=true`** to gate
  `print()` diagnostics without touching non-debug paths. (`dart test` does not
  accept `--define`; use `dart run`.)
- **When a "test bug" and a "generator bug" look alike, instrument the
  generator, not the test.** A `duplicate X in a room` failure can be (a) a
  real generator overlap, (b) a test that re-counts the same item, or (c) both.
  Add a `DBG`-gated `print` of the draw sequence + cell coordinates in the
  generator; the actual placed cells disambiguate.
- **A single slow "hang" at one setting is a real infinite loop.** If `timeout`
  fires at exactly one config (e.g. `width: 2`) and not the others, that config
  triggers an unbounded loop in the generator. The fix was `splits =
  min(rng.range(1, 3), bays)` (a floor with `b` bays has `b-1` partition slots
  → at most `b` rooms).
- **Unsorted `Set<int>` → overlapping room boundaries.** `parts` was a
  `Set<int>` of partition x-positions in hash order; room segments were built
  assuming `parts` was sorted ascending. Fix: `parts.sort()` before segmenting.
