# Changelog

## Unreleased
- Fix: subnet calculator always reported "Invalid IP or mask" (input was split per character); now accepts `IP MASK`, `IP /N` and `IP/N`, rejects non-contiguous masks — logic moved to pure `SubnetCalc()`
- Fix: Windows activation status always said "Could not query" (the licensing query line was missing)
- Fix: Toggle Wi-Fi never found the adapter (`Get-NetAdapter -InterfaceType` doesn't exist); now detects the 802.11 adapter, and a disconnected-but-enabled adapter is no longer treated as "on"
- Fix: auto-elevate resume — the command is passed as `--pending "<label>"` (UAC-elevated processes don't inherit env vars), `RequireAdmin` labels now match registry labels, and compiled builds relaunch the exe correctly
- Fix: an invalid hotkey in the Hotkey editor no longer leaves other live hotkeys disabled
- Fix: Kill process shows taskkill's error text instead of an empty box
- Fix: Windows Terminal detection (path typo) for "Open terminal here" / SSH
- Fix: a saved menu layout no longer hides commands and tool-suite submenus added later — new defaults are merged in (tracked in INI `[MenuKnown]`), deliberately removed ones stay hidden
- Fix: folder menu labels/paths showed `\\` (AHK has no backslash escapes); old saved layouts are migrated
- Fix: `catalog.json` parser handles `\"`, `\\`, `\uXXXX` and throws on malformed input instead of hanging at startup
- Fix: updater prefers binaries in an `x64\` folder (the old check matched any path with a folder ending in "d")
- `RunCapture` runs hidden through a temp-file redirect: no console flash, stderr merged, no deadlock on large stderr output; remaining `WScript.Shell.Exec` call sites switched to it
- CI: lint now really parses `Toolbox.ahk` (`/Validate`; the old step checked an empty file); release zip includes `icons/`
- Smoke tests: subnet calc, JSON escapes/errors, RunCapture stderr flood, RequireAdmin-label ↔ registry check, layout merge + legacy migration
- Output console: `ShowText` now opens a themed OLED window (`lib/Console.ahk`) — Consolas body, accent-bar header with timestamp + line count, Copy / Open in editor / Close buttons, live status line, resizable; dark caption + per-control colors via new WM_CTLCOLOR override map
- New INI key `[Settings] OutputMode` — `console` (default) or `file` to restore the temp-text-file behavior
- Core: `ApplyDarkTheme(gui, bgColor)` accepts a background override; theme constants (`THEME_BG`, `THEME_ACCENT`, ...) shared for future restyling
- Fix: console Size callback signature — the Size event passes 4 parameters (Gui, MinMax, Width, Height); the previous 3-parameter callback threw "Invalid callback function." on resize and prevented the layout reflow
- Console opens at ~85% of the work-area height (was fixed 520 px) and no longer select-all's its content on open
- Spawned PowerShell consoles (Port check, Wake-on-LAN, Subnet scanner, Speed test) now get the themed treatment: Toolbox window title, 110×38 grid with 3000-line scrollback, black bg + gray text in dark mode, DWM dark caption and centered on the work area (classic conhost only — Windows Terminal manages its own look)

## v1.2.1
- Custom toolbox tray icons (square handle, UAC shield badge when elevated)
- Networking: internet speed test — Cloudflare primary, OVH/httpbin fallbacks, dynamic payload sizing via probes, crash-safe window

## v1.2.0
- Palette: Up/Down keys move ListView while search Edit stays focused
- Adapters: WMI query + 60s cache; warm cache at menu build
- Tools menu: group by catalog `suite` (Sysinternals / NirSoft / GitHub / Other); 200 INI slots
- `RunCapture` uses temp `.bat` redirect instead of `WScript.Shell.Exec`
- Release workflow: Ahk2Exe compile + zip asset on windows-latest
- Fix `compmgmt.msc` typo

## v1.1.0
- Split single-file script into `lib/` modules (`#Include`); `Toolbox.ahk` is now a thin entry point
- Updater catalog moved to `catalog.json` (external JSON config, minimal built-in parser)
- Update detection prefers HTTP `ETag` over `Last-Modified` (falls back automatically)
- Base64 via Crypt32 DllCalls (certutil removed); pure `B64EncodeText`/`B64DecodeText` helpers
- Smoke tests (`tests/Smoke.ahk`) + GitHub Actions lint workflow; manual-dispatch release workflow
- README: hotkey remapping, INI keys, catalog docs
- Dark mode helpers, tray elevate icon, async updater HEAD checks

## v1.0.0
- Menu system: nested tray/hotkey menus, Recently Used tracking, command palette (fuzzy search)
- Networking: ping/tracert/nslookup, port check, routes, static IP profiles, DHCP, DNS presets, RDP/SSH/Wake-on-LAN, subnet calculator, ping sweep
- System: Wi-Fi toggle, kill process, uptime/disk, event log errors, reduce working set, clean temp folder, copy host info
- Clipboard: dedupe/sort/trim, URL & Base64, timestamps, strip HTML
- Tools: yt-dlp GUI (multi-URL queue, update), handle64 lock finder, external tools from INI/WSCC, Add tool dialog, Update tools + Browse catalog with auto-registration
- Snippet hotstrings from INI, admin badges, auto-elevation option, MIT license
