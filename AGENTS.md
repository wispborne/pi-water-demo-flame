# AGENTS.md

## Workflow

- Commit and push regularly. When a piece of work is complete and verified, commit it with a plain message saying what changed, and push to both remotes (`origin` and `gitea`). Don't let working changes pile up uncommitted across sessions.

## Remotes

- Push to both `origin` (GitHub) and `gitea` at the same time.
- Pull from `gitea` only.
- Keep `README.md` updated as work progresses: after each phase lands, update its row in the status table and the `## Status` note.
- Each phase ends in a green `dart test` run and a commit (see `PHASES.md`).
- `out/` is gitignored (ASCII dumps from `tool/`, screenshots).

## Layout

Two packages:

- **Root (`water_tower`)** — pure-Dart simulation core, no Flutter imports. `lib/core/` (world gen, water, structure, buoyancy, sun, tools), `lib/trace/` (traced light field), `lib/sim.dart` (fixed-timestep driver). Headless-testable.
- **`app/` (`water_tower_app`)** — Flutter/Flame desktop GUI (Windows + macOS), depends on the root by path. All GUI work happens here.

## Commands

```sh
# root package
dart pub get
dart test                # Phases 1–5 contract tests
dart analyze lib test
dart run tool/phase4_dump.dart   # ASCII artifacts into out/

# app package
cd app
flutter pub get
flutter test             # 16 GUI contract tests
flutter run -d macos     # or -d windows
flutter analyze
```

`./run.sh` (macOS) builds the release app and launches it.

## Invariants — do not break

- **Determinism (ADR 0001, `docs/adr/`):** seed + settings → the exact t=0 world, run twice and across settings. All randomness goes through `lib/core/rng.dart` (FNV-1a-64 → PCG32, forked sub-streams). Never `dart:math.Random`; integer-only math in the core.
- **Water volume is conserved** through every move (grid + spurt overlay).
- **Tests defend observable behaviour and invariants only** — no source-text, wiring, or default-pinning assertions.
- SPEC is in `SPEC.md`; terminology in `CONTEXT.md`; decisions of record in `docs/adr/`.

## Gotchas (details in `NOTES.md`)

- **`timeout N dart test` does not kill a hung test** (it catches the signal and blocks). Use `timeout -s KILL`.
- **A hung test leaves a ~100%-CPU zombie `dart` VM** that makes every later run crawl. Kill stray dart processes when runs are abnormally slow.
- **Never run two dart compiles of the same package in parallel** — they fight over the incremental-kernel cache and one starves past any timeout. One dart job at a time per package.
- **Flutter pointer events are split by button state:** a button-less mouse move is a `PointerHoverEvent`, not a `PointerMoveEvent`; a macOS trackpad pinch arrives as a `PointerScaleEvent` with a multiplicative `scale`, not a scroll delta. The app's `Listener` wires both — keep it that way.
- **`.bat` files need CRLF line endings** and no unbalanced parentheses inside `(...)` blocks, or they die silently.
- Gate `print()` diagnostics with `bool.fromEnvironment('FLAG')` + `dart run --define=FLAG=true` (`dart test` does not accept `--define`).
- To inspect the live GUI without a window, use the `tool/` headless repros (e.g. `dart run tool/_skycheck.dart`), not screenshots.

## Rabbit Holes

Every time you start thinking, first pose this question to yourself: am I going down a rabbit hole? If so, STOP.

## Screenshots

Never use webp; this will cause the entire conversation to break. Only use PNG or JPEG images.

## ntfy Notifications

Use ntfy to notify me. The topic is `pi_alerts_wisp_notus`.

Send a notification when:
- You need me to answer a question or make a decision.
- You encounter an error, blocker, or unexpected issue that requires my input.
- A task finishes or reaches a meaningful milestone.
- A small task is done - the user loves updates!

Send notifications with:

```bash
curl -d "<message>" https://ntfy.sh/pi_alerts_wisp_notus
```

Keep notifications short but specific. Include enough context to identify the task and what you need from me.
Continue working autonomously whenever possible instead of waiting for a response.
