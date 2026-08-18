# Changelog

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
