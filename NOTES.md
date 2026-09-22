# Notes

## Standing instructions

- **Keep `README.md` updated as work progresses** (per user instruction,
  2026-09-21). After each phase lands, update its row in the README status
  table and the `## Status` note.

## Tooling
Hard-won, tooling-specific lessons. Keep terse.

## Screenshotting the running Windows app

- The repo's `out/shot*.png` screenshots come from a helper PowerShell
  script (kept in `out/`, which is gitignored). The method: enumerate
  visible windows with Win32 `EnumWindows`, pick the one titled
  `water_tower_app`, force it to the foreground, `CopyFromScreen` its
  rect.
- **`SetForegroundWindow` alone is silently ignored** when the calling
  process doesn't own the foreground. What works: a synthetic Alt
  keypress (`keybd_event 0x12 down/up`) to release the foreground lock,
  then `ShowWindow(SW_RESTORE)` + `SetForegroundWindow`, then a short
  sleep before the capture.
- `CopyFromScreen` grabs the *screen*, so the target must actually be
  in front: a terminal covering it will be captured instead. Verify the
  PNG shows the app window before trusting it.
- To launch: `powershell -NoProfile -Command "Start-Process 'F:\Code\pi-water-demo-flame\app\build\windows\x64\runner\Release\water_tower_app.exe'"` — the harness bash shell has no `start`/`timeout`/`copy` cmd builtins (use `cp`); wrap in PowerShell. Confirm with `tasklist | findstr /i water_tower_app` (two PIDs: the runner + child).
- Run: `powershell -NoProfile -ExecutionPolicy Bypass -File out/_shot.ps1` (saves `out/shot9.png`).
- **VM-service eval on the live app** (release builds have NO VM service; use a debug
  build): `cd app && flutter run -d windows`, read the `VM Service` URI/port from its
  output, then `python out/_vmeval.py '<dart expr>' ...` (edit the `HOST/PORT/PATH`
  constants at the top of the script first). It speaks raw WebSocket JSON-RPC and
  evaluates Dart in the app isolate — e.g. `state.sim.sun.timeSec`,
  `state.tracer.field.luminance(state.world.idx(200, 40))`, `cam.cellPx`.
  This is how you inspect the live app's actual state (field values, camera,
  budget) — don't guess from screenshots alone.

## Batch files (cmd)

- **CRLF line endings are required.** `write` emits LF; a multi-line
  `if (...)` block in an LF-only `.bat` mis-parses and the script dies
  silently at `pause`. Convert with `sed -i 's/$/\r/' run.bat` after
  writing.
- **No unbalanced parentheses in text inside `(...)` blocks.** An echo
  line containing `(` or `)` (even inside a word like `app\`) closes the
  block early. Keep block text paren-free.
- Test with `cmd /c path\to\run.bat`, and confirm the launched process
  with `tasklist | findstr`.


## `dart test` hangs and zombies

- **`timeout N dart test` does not kill a hung test.** `timeout` sends SIGTERM;
  `dart test` installs a SIGINT/SIGTERM handler that prints
  `Waiting for current test(s) to finish. Press Control-C again to terminate
  immediately.` and **blocks**, so the VM outlives the timeout. Use
  `timeout -s KILL N dart test …` to get a definitive end state.
- **A hung test leaves a 100%-CPU zombie `dart` VM behind.** Several of these
  pile up and make every *subsequent* test run crawl (all tests pass in 1s
  alone, but the full suite "hangs" past 300s). Symptom: a `dart` process
  at ~100% CPU after the run.

- **This Windows host: `pkill` does not exist.** Kill zombies with
  `taskkill /F /IM dart.exe` (kills every dart VM, including `dart test`
  zombies). Note `taskkill /F /IM water_tower_app.exe` exits "not found"
  when the app is not running — that is not an error.
- **Never run two `dart` compiles of the same package in parallel.** They
  fight over the incremental-kernel cache: one process starves past any
  `timeout` (observed: `dart run` hung 120 s while a parallel `dart test`
  compiled; same command ran in 3.7 s once serialized). One dart job at a
  time per package.

## Headless lighting repro (no GUI)

- `tool/_skycheck.dart` builds the app's boot world (seed-1, floors 30,
  width 3), settles the traced field, and dumps the 220×240 luminance
  field + top materials as ASCII. It runs the exact Tracer code path the
  GUI lighting bugs without the window: `dart run tool/_skycheck.dart`
  (~4 s). The `first column with a black sky cell` line reports the
  shadow's left edge (`-1` = no black sky).

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
