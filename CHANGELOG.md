# Changelog

## Unreleased
- Security: static IP / mask / gateway / DNS are validated (`ValidateStaticIp`) before they reach the elevated `netsh` command line — also for saved INI profiles; Kill process validates the image name; yt-dlp rejects URLs containing `"`; SSH `user@host` can't start with `-`
- Fix: multiple DNS servers in a static IP profile now work (`set dns` + `add dns index=N`; netsh rejects a comma list)
- Fix: Restart / Shutdown with a typo'd delay ("5s", blank) no longer means "immediately" — it asks again
- Reset routes asks for confirmation (it also resets Winsock + the TCP/IP stack) and defaults to Cancel
- Fix: `JsonParse` threw on every numeric value (match object overwritten by the position) and wasn't anchored; exponents supported
- Updater: the signing organisation must match exactly (`O=Microsoft` no longer accepts `O=Microsoft Corporation Ltd`)
- Fix: the `[admin]` badge is no longer frozen into a saved menu layout — stripped on save/load and re-added only while not elevated (auto-elevate relaunch used to leave stale badges)
- Subnet scanner rejects octets > 255; Dark menus no longer crash if the uxtheme ordinals are missing; small dead-code cleanups
- Smoke tests: 105 (static IP validation, delay parsing, process names, JSON numbers, signer match, badge handling)
- Info tools run in the background (`PsShowAsync` / `RunCaptureAsync`): hotkeys and menus stay responsive, a "Running: … (N s)" tooltip lists active tasks, a 120 s timeout kills the whole process tree
- Palette: prefix > word-start > substring > initials ranking, recent commands boosted (and listed first when the filter is empty), second column with section · hotkey · [admin]; only one palette at a time
- Updater integrity: Sysinternals binaries must carry a valid Microsoft Authenticode signature and yt-dlp must match the release's `SHA2-256SUMS` before anything is written to `Tools\` (catalog fields `signer` / `sha256sums`); direct downloads go to a temp file first, so a failed update keeps the working copy
- New: System → Abort pending shutdown / restart (`shutdown /a`)
- Browse to device: choose https:// or http:// (or type the scheme)
- Input validation: ping / traceroute / nslookup / SSH (`user@host`) / RDP (`host:port`) / browse / port check reject malformed addresses before running or saving them; routes validate destination, mask (dotted or `/N`, host bits checked), gateway and metric, and check admin before prompting
- Port check: 3 s connect timeout (was ~21 s per filtered port), reports OPEN / CLOSED / FILTERED / DNS failure
- DHCP switch also removes the static default route and resets DNS servers (IPv6 untouched)
- Static IP: failures are shown as such and not saved as a profile (netsh exit code); DNS-only warnings flagged separately
- Fix: Strip HTML always threw (AHK v2's `RegExReplace` takes no callback); `&amp;` now decoded last; hex entities supported
- Fix: URL encode garbled emoji (surrogate pairs); Wake-on-LAN no longer saves invalid MACs
- Clipboard hash, file hash, GUID and password generator use CNG / COM directly (no PowerShell window, no modulo bias); file hashing streams in 1 MB chunks
- yt-dlp batch starts with `chcp 65001` (non-ASCII URLs/paths on older cmd builds)
- Console: status timer can't hit a closed window; per-control color maps are pruned
- Internals: `Notify()` replaces ~30 ToolTip+SetTimer pairs, one `OnWmCtlColor` handler instead of four, `IsDarkMode()` cached (was INI + registry read per paint message), shared `PsWrite`/`PsQuote`/`AskAddress`/`CopySelectedFiles`/`GetActiveExplorerPath`, built-in `Sort()`, `StrJoin` no longer eats trailing separator chars
- Smoke tests: 86 (round trips for hotkeys and menu layout, palette ranking, address validation, async runner incl. timeout kill, signature/checksum checks); exceptions are reported as FAIL lines instead of blocking dialogs
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
