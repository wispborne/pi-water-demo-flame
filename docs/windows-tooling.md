# Windows tooling (agent reference)

What works for driving this Windows machine from the shell, verified by doing.
All of this was tested on this box (Windows 11 Pro, PowerShell 7.6.6) on 2026-09-25.

## The helper: `tool/windows/win.ps1`

One script, subcommands. Every coordinate is physical pixels (the script sets
itself per-monitor DPI aware, so window rects, cursor moves, and screenshots
all agree).

```
.\tool\windows\win.ps1 list [filter]                          visible top-level windows
.\tool\windows\win.ps1 active                                 the focused window
.\tool\windows\win.ps1 focus <title-substring> [index]        bring a window to front + focus
.\tool\windows\win.ps1 move <title-substring> <x> <y> [w h]   move, optionally resize
.\tool\windows\win.ps1 pid <title-substring>                  owning process id
.\tool\windows\win.ps1 mouse pos                              cursor position
.\tool\windows\win.ps1 mouse move <x> <y>                     absolute cursor move
.\tool\windows\win.ps1 mouse click [x y] [l|r]                click
.\tool\windows\win.ps1 mouse double [x y] [l|r]               double-click
.\tool\windows\win.ps1 mouse drag <x1> <y1> <x2> <y2> [l|r]   press, glide 20 steps, release
.\tool\windows\win.ps1 mouse wheel [delta]                    120 = one notch up
.\tool\windows\win.ps1 type <text>                            type into the focused control
.\tool\windows\win.ps1 key <combo>                            enter, tab, esc, up.., ctrl+c, alt+f4, ...
.\tool\windows\win.ps1 shot <file.png> [x y w h]              PNG; whole virtual desktop if no rect
.\tool\windows\win.ps1 clip [text]                            get or set the clipboard
```

All verified against live apps (Notepad): list, active, focus, move, resize,
pid, pos, move, left click, right click (context menu), double-click, drag
(text selection confirmed in a screenshot), wheel, type, key combos, both
screenshot modes, clipboard round-trip.

## GUI test recipe

The user may be at the keyboard at the same time. Keep focus-stealing to one
tight batch, and end every batch by restoring the previous foreground window
and parking the cursor at a neutral spot (e.g. `mouse move 1280 1400`).

```powershell
# remember who has focus, so you can give it back
.\tool\windows\win.ps1 active
Start-Process notepad; Start-Sleep -Milliseconds 1500
.\tool\windows\win.ps1 focus "Notepad"
.\tool\windows\win.ps1 move "Notepad" 0 0 400 300   # known position, known size
# ... act: type, key, mouse ...
.\tool\windows\win.ps1 shot out\check.png 0 0 400 300
.\tool\windows\win.ps1 pid "Notepad" | ForEach-Object { Stop-Process -Id $_ }
.\tool\windows\win.ps1 focus "<previous app>"
.\tool\windows\win.ps1 mouse move 1280 1400
```

Rules learned by hitting them:

- **Move the window to (0,0) at a known size before aiming.** Then window
  coordinates equal screen coordinates and the math is trivial.
- **Verify target pixels against a screenshot before clicking.** Menu bars
  and rows are taller than their visible text — my drag at y=63 hit "File",
  then "Edit", before y=90 was safely inside the text.
- **Sleep ~400 ms before a screenshot that should show a menu/dialog.** A
  shot taken immediately after a right-click missed the context menu.
- **Kill with `Stop-Process`, don't ask the app to close.** Alt+F4 on a
  Notepad with text opens a save dialog; killing the pid does not.

## Environment facts

- Shell is PowerShell 7 (`pwsh`), execution policy `RemoteSigned` — repo
  scripts run directly, no wrapper needed.
- `dart` and `flutter` are `.bat` shims at `F:\SDKs\flutter\bin\`. They work
  fine from the shell; `Start-Process dart` will not do what you expect —
  pass the full `.bat` path if you must.
- Native tools present and working: `git 2.45.1`, `curl 8.21.0`.
- Primary display 2560x1440, taskbar 48 px at the bottom.
- `out/` is gitignored — put throwaway screenshots there.
- ntfy works: `curl -d "msg" https://ntfy.sh/pi_alerts_wisp_notus`.

## Gotchas (all hit, all fixed in `win.ps1` — re-read before writing fresh interop)

PowerShell 7 + `Add-Type` C#:

1. Nested types are `[Win32+RECT]`, not `[Win32]::RECT` (the latter resolves
   to a null static-member access).
2. `::new()` on a nested type fails inside a scriptblock that is converted to
   a delegate. Construct structs in C# and return them.
3. `Add-Type -ReferencedAssemblies X` **replaces** the default assembly set
   instead of adding to it. Don't pass it; load extras with
   `Add-Type -AssemblyName`.
4. A public C# field of a struct type requires the struct to be public too
   (CS0052 Inconsistent accessibility).
5. **Pipelines unroll `ValueTuple`** — a `List<(int,int,int,int)>` piped into
   `ForEach-Object` hands you the fields, not the tuples. Return a small C#
   class from interop when the result gets piped.
6. .NET named tuples lose their names crossing into PowerShell: only
   `Item1..Item4` exist.
7. `GetCurrentThreadId` lives in `kernel32.dll`, not `user32.dll`.

Win32 behavior:

8. `SetForegroundWindow` silently fails from a console process. The working
   recipe: `AttachThreadInput` to the current foreground thread,
   `ShowWindow(SW_RESTORE)`, `SetForegroundWindow`, `BringWindowToTop`,
   detach. `win.ps1 focus` does this.
9. `SendInput` with `MOUSEEVENTF_MOVE` takes **relative** offsets. Use
   `SetCursorPos` for absolute positioning.
10. Minimized windows report rect `(-32000,-32000)`.
11. `System.Drawing.SystemInformation` does not exist in .NET's
    `System.Drawing.Common`. For the virtual desktop rect use
    `GetSystemMetrics(76..79)`.

Shell habits:

12. A failing script in a `;` chain does not stop the chain — the rest runs.
    `win.ps1`'s `Fail` exits the script only. Use `&&` when order matters.
13. `SendKeys` drops characters into a window that is still settling (right
    after a focus change or move). `win.ps1 type` sleeps 50 ms first.
