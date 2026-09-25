# win.ps1 - Windows GUI automation helper: windows, mouse, keyboard, screenshots, clipboard.
# Usage: .\tool\windows\win.ps1 <command> [args...]
# Commands:
#   list [filter]                          list visible top-level windows (hwnd, pid, rect, title)
#   active                                 foreground window (hwnd, rect, title)
#   focus <title-substring> [index]        bring matching window to front and focus it
#   move <title-substring> <x> <y> [w] [h] move (and optionally resize) a window
#   pid <title-substring>                  print the pid owning the first matching window
#   mouse pos                              print cursor position
#   mouse move <x> <y>                     move cursor
#   mouse click [x y] [l|r]                click (position = cursor if omitted, button = left)
#   mouse double [x y] [l|r]               double-click
#   mouse drag <x1> <y1> <x2> <y2> [l|r]   press, glide, release (20 steps, 10 ms apart)
#   mouse wheel [delta]                    scroll; 120 = one notch up, -120 = one notch down
#   type <text>                            type text into the focused control (SendKeys)
#   key <combo>                            press a key/combo: enter, tab, esc, space, up, down,
#                                          left, right, home, end, pgup, pgdn, del, f1..f12, ctrl+c,
#                                          ctrl+a, ctrl+v, ctrl+z, ctrl+s, alt+f4, shift+tab, ...
#   shot <file.png> [x y w h]              screenshot; whole virtual desktop if rect omitted
#   clip [text]                            print clipboard, or set it
# All coordinates are physical pixels (the script is per-monitor DPI aware).
# See docs/windows-tooling.md.

param(
    [Parameter(Position = 0)][string]$Cmd,
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][object[]]$Rest
)

$ErrorActionPreference = 'Stop'

function Fail([string]$msg) {
    Write-Error $msg
    exit 1
}

$code = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class Win32 {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool redraw);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);

    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct HARDWAREINPUT { public uint uMsg; public ushort wParamL, wParamH; }
    [StructLayout(LayoutKind.Explicit)] public struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public InputUnion U; }

    public const uint INPUT_MOUSE = 0, INPUT_KEYBOARD = 1;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x2, MOUSEEVENTF_LEFTUP = 0x4,
        MOUSEEVENTF_RIGHTDOWN = 0x8, MOUSEEVENTF_RIGHTUP = 0x10, MOUSEEVENTF_WHEEL = 0x800;
    public const uint KEYEVENTF_KEYUP = 0x2;

    [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int cbSize);

    static void Send(INPUT[] inputs) {
        uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
        if (sent != (uint)inputs.Length)
            throw new Exception("SendInput: sent " + sent + " of " + inputs.Length + " (error " + Marshal.GetLastWin32Error() + ")");
    }

    static INPUT Mouse(uint flags, int dx, int dy, uint data) {
        var i = new INPUT { type = INPUT_MOUSE };
        i.U.mi.dx = dx; i.U.mi.dy = dy; i.U.mi.mouseData = data; i.U.mi.dwFlags = flags;
        return i;
    }
    static INPUT Key(ushort vk, bool up) {
        var i = new INPUT { type = INPUT_KEYBOARD };
        i.U.ki.wVk = vk; i.U.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
        return i;
    }

    public static void MouseMove(int x, int y) { SetCursorPos(x, y); }
    public static void MouseDown(uint flags) { Send(new[] { Mouse(flags, 0, 0, 0) }); }
    public static void MouseUp(uint flags) { Send(new[] { Mouse(flags, 0, 0, 0) }); }
    public static void Wheel(short delta) { Send(new[] { Mouse(MOUSEEVENTF_WHEEL, 0, 0, (uint)(short)delta) }); }
    public static void KeyDown(ushort vk) { Send(new[] { Key(vk, false) }); }
    public static void KeyUp(ushort vk) { Send(new[] { Key(vk, true) }); }

    public static bool ForceForeground(IntPtr h) {
        IntPtr fg = GetForegroundWindow();
        uint cur = GetCurrentThreadId();
        uint fgThread = fg != IntPtr.Zero ? GetWindowThreadProcessId(fg, out uint _) : 0;
        bool attached = fgThread != 0 && AttachThreadInput(cur, fgThread, true);
        ShowWindow(h, 9); // SW_RESTORE
        SetForegroundWindow(h);
        BringWindowToTop(h);
        if (attached) AttachThreadInput(cur, fgThread, false);
        return h == GetForegroundWindow();
    }

    public static uint Pid(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return p; }

    public class WinInfo { public IntPtr H; public string Title; public uint Pid; }
    public static System.Collections.Generic.List<WinInfo> EnumAll() {
        var list = new System.Collections.Generic.List<WinInfo>();
        EnumWindows((h, l) => {
            if (IsWindowVisible(h)) list.Add(new WinInfo { H = h, Title = Title(h), Pid = Pid(h) });
            return true;
        }, IntPtr.Zero);
        return list;
    }

    public static string Title(IntPtr h) {
        var sb = new StringBuilder(512);
        GetWindowTextW(h, sb, sb.Capacity);
        return sb.ToString();
    }
    public static (int L, int T, int R, int B) RectT(IntPtr h) { RECT r; GetWindowRect(h, out r); return (r.Left, r.Top, r.Right, r.Bottom); }
    public static (int X, int Y) CursorPosT() { POINT p; GetCursorPos(out p); return (p.X, p.Y); }

    [DllImport("user32.dll")] static extern int GetSystemMetrics(int idx);
    public static (int X, int Y, int W, int H) VirtualScreen() {
        return (GetSystemMetrics(76), GetSystemMetrics(77), GetSystemMetrics(78), GetSystemMetrics(79));
    }
}
'@
Add-Type -TypeDefinition $code
[void][Win32]::SetProcessDpiAwarenessContext([IntPtr]::new(-4)) # PER_MONITOR_AWARE_V2

function Get-Win([string]$needle, [int]$Index = 0) {
    $filtered = [Win32]::EnumAll() | Where-Object { $_.Title -like "*$needle*" }
    if (-not $filtered) { Fail "no visible window matching '$needle'" }
    if ($Index -ge @($filtered).Count) { Fail "'$needle' matched $(@($filtered).Count) windows, index $Index out of range" }
    return @($filtered)[$Index]
}

function Format-Rect($r) { "({0},{1} {2}x{3})" -f $r.Item1, $r.Item2, ($r.Item3 - $r.Item1), ($r.Item4 - $r.Item2) }

if (-not $Cmd) { Fail "no command. See the header comment for usage." }

switch -regex ($Cmd) {
    '^list$' {
        $needle = if ($Rest.Count) { $Rest[0] } else { '' }
        [Win32]::EnumAll() | Where-Object { $_.Title -like "*$needle*" } | ForEach-Object {
            $r = [Win32]::RectT($_.H)
            Write-Output ("{0,-10} {1,6} {2,-16} {3}" -f $_.H, $_.Pid, (Format-Rect $r), $_.Title)
        }
    }
    '^active$' {
        $h = [Win32]::GetForegroundWindow()
        $r = [Win32]::RectT($h)
        Write-Output ("{0,-10} {1,-16} {2}" -f $h, (Format-Rect $r), [Win32]::Title($h))
    }
    '^focus$' {
        if (-not $Rest.Count) { Fail "focus needs a title substring" }
        $idx = if ($Rest.Count -gt 1) { [int]$Rest[1] } else { 0 }
        $w = Get-Win $Rest[0] $idx
        $ok = [Win32]::ForceForeground($w.H)
        if (-not $ok) { Fail "could not focus '$($w.Title)' (handle $($w.H)); try again" }
        Write-Output ("focused: {0} (hwnd {1})" -f $w.Title, $w.H)
    }
    '^move$' {
        if ($Rest.Count -lt 3) { Fail "move needs: title x y [w h]" }
        $w = Get-Win $Rest[0] 0
        $x = [int]$Rest[1]; $y = [int]$Rest[2]
        $r = [Win32]::RectT($w.H)
        if ($Rest.Count -eq 4) { Fail "move needs both width and height, or neither" }
        $cw = if ($Rest.Count -ge 5) { [int]$Rest[3] } else { $r.Item3 - $r.Item1 }
        $ch = if ($Rest.Count -ge 5) { [int]$Rest[4] } else { $r.Item4 - $r.Item2 }
        [void][Win32]::MoveWindow($w.H, $x, $y, $cw, $ch, $true)
        $r2 = [Win32]::RectT($w.H)
        Write-Output ("moved '{0}' to {1}" -f $w.Title, (Format-Rect $r2))
    }
    '^pid$' {
        if (-not $Rest.Count) { Fail "pid needs a title substring" }
        Write-Output ([Win32]::Pid((Get-Win $Rest[0] 0).H))
    }
    '^mouse$' {
        $sub = $Rest[0]
        switch ($sub) {
            'pos' {
                $p = [Win32]::CursorPosT()
                Write-Output ("{0} {1}" -f $p.Item1, $p.Item2)
            }
            'move' {
                [Win32]::MouseMove([int]$Rest[1], [int]$Rest[2])
                Write-Output "ok"
            }
            'click' {
                $hasPos = $Rest.Count -ge 3 -and $Rest[1] -match '^-?\d+$'
                if ($hasPos) { [Win32]::MouseMove([int]$Rest[1], [int]$Rest[2]); $btn = if ($Rest.Count -ge 4) { $Rest[3] } else { 'l' } }
                else { $btn = if ($Rest.Count -ge 2) { $Rest[1] } else { 'l' } }
                $down = if ($btn -eq 'r') { [Win32]::MOUSEEVENTF_RIGHTDOWN } else { [Win32]::MOUSEEVENTF_LEFTDOWN }
                $up = if ($btn -eq 'r') { [Win32]::MOUSEEVENTF_RIGHTUP } else { [Win32]::MOUSEEVENTF_LEFTUP }
                [Win32]::MouseDown($down); Start-Sleep -Milliseconds 30; [Win32]::MouseUp($up)
                Write-Output "ok"
            }
            'double' {
                $hasPos = $Rest.Count -ge 3 -and $Rest[1] -match '^-?\d+$'
                if ($hasPos) { [Win32]::MouseMove([int]$Rest[1], [int]$Rest[2]); $btn = if ($Rest.Count -ge 4) { $Rest[3] } else { 'l' } }
                else { $btn = if ($Rest.Count -ge 2) { $Rest[1] } else { 'l' } }
                $down = if ($btn -eq 'r') { [Win32]::MOUSEEVENTF_RIGHTDOWN } else { [Win32]::MOUSEEVENTF_LEFTDOWN }
                $up = if ($btn -eq 'r') { [Win32]::MOUSEEVENTF_RIGHTUP } else { [Win32]::MOUSEEVENTF_LEFTUP }
                [Win32]::MouseDown($down); Start-Sleep -Milliseconds 30; [Win32]::MouseUp($up)
                Start-Sleep -Milliseconds 60
                [Win32]::MouseDown($down); Start-Sleep -Milliseconds 30; [Win32]::MouseUp($up)
                Write-Output "ok"
            }
            'drag' {
                if ($Rest.Count -lt 5) { Fail "drag needs: x1 y1 x2 y2 [l|r]" }
                $x1 = [int]$Rest[1]; $y1 = [int]$Rest[2]; $x2 = [int]$Rest[3]; $y2 = [int]$Rest[4]
                $btn = if ($Rest.Count -ge 6) { $Rest[5] } else { 'l' }
                $down = if ($btn -eq 'r') { [Win32]::MOUSEEVENTF_RIGHTDOWN } else { [Win32]::MOUSEEVENTF_LEFTDOWN }
                $up = if ($btn -eq 'r') { [Win32]::MOUSEEVENTF_RIGHTUP } else { [Win32]::MOUSEEVENTF_LEFTUP }
                [Win32]::MouseMove($x1, $y1)
                Start-Sleep -Milliseconds 50
                [Win32]::MouseDown($down)
                $steps = 20
                for ($i = 1; $i -le $steps; $i++) {
                    $t = [double]$i / $steps
                    [Win32]::MouseMove([int]($x1 + ($x2 - $x1) * $t), [int]($y1 + ($y2 - $y1) * $t))
                    Start-Sleep -Milliseconds 10
                }
                [Win32]::MouseUp($up)
                Write-Output "ok"
            }
            'wheel' {
                $delta = if ($Rest.Count -ge 2) { [int]$Rest[1] } else { -120 }
                [Win32]::Wheel([short]$delta)
                Write-Output "ok"
            }
            default { Fail "unknown mouse subcommand '$sub'" }
        }
    }
    '^type$' {
        if (-not $Rest.Count) { Fail "type needs text" }
        $text = $Rest -join ' '
        Add-Type -AssemblyName System.Windows.Forms
        # SendKeys special chars: { } + ^ % ~ ( ) must be escaped
        $escaped = $text -replace "([\{\}\+\^%~\(\)'])", '+$1'
        Start-Sleep -Milliseconds 50 # let the target settle; SendKeys drops chars into busy windows
        [System.Windows.Forms.SendKeys]::SendWait($escaped)
        Write-Output "ok"
    }
    '^key$' {
        if (-not $Rest.Count) { Fail "key needs a combo" }
        $combo = ($Rest -join ' ')
        $vkMap = @{
            'enter' = 0x0D; 'tab' = 0x09; 'esc' = 0x1B; 'escape' = 0x1B; 'space' = 0x20
            'backspace' = 0x08; 'del' = 0x2E; 'delete' = 0x2E
            'up' = 0x26; 'down' = 0x28; 'left' = 0x25; 'right' = 0x27
            'home' = 0x24; 'end' = 0x23; 'pgup' = 0x21; 'pgdn' = 0x22
            'shift' = 0x10; 'ctrl' = 0x11; 'alt' = 0x12; 'win' = 0x5B
        }
        $parts = $combo -split '\+' | ForEach-Object { $_.Trim().ToLower() }
        $vks = [System.Collections.Generic.List[int]]::new()
        foreach ($p in $parts) {
            if ($vkMap.ContainsKey($p)) { $vks.Add($vkMap[$p]); continue }
            if ($p -match '^f([1-9]|1[0-2])$') { $vks.Add(0x6F + [int]$Matches[1]); continue }
            if ($p -match '^[a-z0-9]$') { $vks.Add([int][char][char]::ToUpper($p[0])); continue }
            Fail "unknown key '$p' in combo '$combo'"
        }
        for ($i = 0; $i -lt $vks.Count; $i++) { [Win32]::KeyDown([ushort]$vks[$i]) }
        Start-Sleep -Milliseconds 30
        for ($i = $vks.Count - 1; $i -ge 0; $i--) { [Win32]::KeyUp([ushort]$vks[$i]) }
        Write-Output "ok"
    }
    '^shot$' {
        if (-not $Rest.Count) { Fail "shot needs an output file" }
        $path = [System.IO.Path]::GetFullPath($Rest[0])
        Add-Type -AssemblyName System.Drawing
        if ($Rest.Count -ge 5) {
            $x = [int]$Rest[1]; $y = [int]$Rest[2]; $w = [int]$Rest[3]; $h = [int]$Rest[4]
        } else {
            $b = [Win32]::VirtualScreen()
            $x = $b.Item1; $y = $b.Item2; $w = $b.Item3; $h = $b.Item4
        }
        $bmp = New-Object System.Drawing.Bitmap $w, $h
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($x, $y, 0, 0, $bmp.Size)
        $g.Dispose()
        $dir = [System.IO.Path]::GetDirectoryName($path)
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Write-Output "saved $path ($w x $h)"
    }
    '^clip$' {
        if ($Rest.Count) { Set-Clipboard (($Rest -join ' ')); Write-Output "ok" }
        else { Get-Clipboard }
    }
    default { Fail "unknown command '$Cmd'. See the header comment for usage." }
}
