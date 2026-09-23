# Notes

## Standing instructions

- **Keep `README.md` updated as work progresses** (per user instruction,
  2026-09-21). After each phase lands, update its row in the README status
  table and the `## Status` note.

## UI Pass — Findings (2026-09-22, approved-for-future-sessions)

Live review of the running app (captures in `out/shot9.png`,
`out/shot_hover.png`) + code read. Ordered by importance.

1. **Contrast bug: black text on the dark panels (bottom bar + hover
   readout).** `app/lib/main.dart:75` — `MaterialApp` has no `theme`, so
   `Text` defaults follow the *light* theme (`Colors.black87`) while the
   scaffold is dark `0xFF0B0E14` and the HUD panels are dark `0xCC101828`
   (`app/lib/ui/hud.dart:91,128`). The counter row (`water … damage …
   FPS … seed … tool`) and the hover readout are nearly invisible in
   every capture. Fix: give `MaterialApp` a dark theme
   (`ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor:
   Color(0xFF0B0E14))`); slider tracks, the seed `TextField`, and the
   `DropdownButton` menu inherit it. Optionally theme the accent to cyan
   to match the water. Verify: screenshot with `out/_shot.ps1`, all
   HUD text legible.
2. **Hover readout missing the SPEC 10 colour-coded strength bar.**
    *(Fixed 2026-09-22: the bar is in `_hoverPanel`, gated to damageable
    cells, with a GUI contract test.)*
    SPEC.md §10: the hover readout must show remaining strength *with a
    colour-coded bar*. `app/lib/ui/hud.dart:97-106` (`_hoverPanel`)
    renders `HP $hp/$maxHp head $head` as text only (the traced-mode
    light swatch at 107-118 is present). Fix: add a ~60×6 bar filled
    `hp/maxHp`, colour lerping green→amber→red as it drops. Verify:
    hammer a structural cell, hover it, bar shrinks and recolors.
3. **Hover crosshair is sub-pixel at the default fit zoom.**
   `app/lib/render/grid_painter.dart:272-282` — stroke `0.08` *world*
   units; at fit zoom (cellPx ≈ 3) that is ~0.24 px on screen, so no
   outline is visible in the captures. Fix: screen-constant stroke,
   e.g. pass `cam.cellPx` into `_drawHover` and use
   `strokeWidth: 1.5 / cellPx`. Verify: crisp 1–2 px outline at fit
   zoom and at 8× zoom.
4. **Key-hint line omits the P/S/G/T/R/N shortcuts.**
   `app/lib/ui/hud.dart:238-241` shows only
   `keys 1-8 tools · LMB apply · RMB/MMB pan · wheel zoom`, but the app
   also has P pause, S speed, G glow, T path trace, R reset, N new seed
   (`app/lib/main.dart:42-62`; README documents them). Fix: extend the
   hint string (the row is horizontally scrollable, length is fine).
5. **Dead `IgnorePointer(ignoring: false)` wrapper in the HUD build.**
   `app/lib/ui/hud.dart:66-74` — `ignoring: false` is the identity
   transform; return the `Stack` directly. Verify: `flutter analyze` +
   the 13 GUI contract tests in `app/test/`.
6. **(Cosmetic) Window title is `water_tower_app`** — `app/windows/runner/main.cpp:30`;
   `MaterialApp(title: '30 Floors & a Pool')` in main.dart:77 does not
   affect the OS title bar.

Notes on what was verified live: traced light field, sun, lamps,
glow, water, bottom-bar layout, buttons, sliders, dropdown, seed field
all render. The hover readout *contents* were confirmed via a
pressed-drag capture (see the Tooling note below on why plain
synthetic hover cannot be captured).
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

## Synthetic mouse input on the app

- `SetCursorPos` alone emits NO `WM_MOUSEMOVE` — the app's hover readout
  never updates for a teleported cursor. What works: press LMB first
  (`mouse_event 0x0002`), then `SetCursorPos` in small steps (pressed
  moves route to the down target), release (`0x0004`). Use a **debug**
  build (`flutter build windows --debug`) when VM-service inspection is
  needed: the release exe has no VM service.
- **Flutter splits mouse moves by button state (2026-09-23):** a move with
  no button down is a `PointerHoverEvent`, not a `PointerMoveEvent` — a
  `Listener` must wire `onPointerHover` to track plain hover. This was the
  "readout needs a click" bug; the app's `Listener` (main.dart) now wires
  both. Real-mouse hover works; the `SetCursorPos` caveat above stands
  (the OS sends no event at all for a teleported cursor).


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
