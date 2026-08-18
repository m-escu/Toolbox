# Toolbox — Sysadmin/IT Power-User Launcher (AutoHotkey v2)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Windows launcher for everyday sysadmin/IT tasks: nested tray/hotkey menus, a type-to-filter command palette, network diagnostics, adapter config, clipboard utilities, and tool integrations (yt-dlp, handle64, WSCC).

## Hotkeys

| Hotkey | Action |
|---|---|
| `Ctrl+Shift+M` | Main menu (nested) |
| `Ctrl+Shift+P` | Command palette (fuzzy search + Enter to run) |
| `Ctrl+Shift+R` | Re-run last command |
| `Ctrl+Shift+E` | Open selected files in Notepad++ |
| `Ctrl+Alt+T` | Terminal at current folder |
| Tray right-click | Same menus + settings |

## Theming

Dark mode follows the Windows app theme by default; force it via `[Settings]` `Theme=dark` / `light` / `auto`. All GUIs (palette, updater, catalog browser, yt-dlp, input dialogs) are themed, including titlebars.

## Configuration

All hotkeys are remappable in INI `[Settings]` (`HotkeyMenu`, `HotkeyPalette`, `HotkeyRerun`, `HotkeyEditNpp`, `HotkeyTerminal`), as is `NppPath`.

## Features

- **Recently Used** — last 15 commands, persisted, keyboard-numbered
- **Files** — open selection in Notepad++, copy paths, terminal/Explorer here
- **Networking** — ping/tracert/nslookup, multi-target port check, browse/RDP/SSH to device, ARP/route tables, route add/delete/reset, flush DNS
  - Static IP with saved profiles (popup pick), DHCP, DNS presets (Cloudflare/Google/DHCP)
  - Wake-on-LAN, subnet calculator, /24 ping sweep + DNS resolve
- **Folders** — standard system folders + custom from INI
- **System** — Task Manager/Services/Event Viewer/Registry/Device Mgr, Wi-Fi toggle, restart/shutdown, kill process, empty recycle bin, uptime & disk space, recent event-log errors, copy host/IP/username
- **Clipboard** — dedupe, sort, URL/Base64 encode/decode, timestamps, strip HTML, trim, count stats
- **Tools** — yt-dlp GUI (multi-URL queue, presets, extra args, live command preview, self-update), handle64 lock finder (uses file copied in Explorer), external tools via INI, `Add tool...` dialog (browse for exe → named entry written to INI, no hand editing), `Update tools` (downloads latest from known suites — Sysinternals/NirSoft — into `Tools\`, keeps only the binaries)
- **Snippets** — auto-expanding hotstrings from INI
- **Settings** — elevation mode (`warn`/`auto`), confirmations, editor path

## Setup

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Optional: Notepad++ at `C:\Program Files\Notepad++\notepad++.exe` (edit `nppPath` otherwise).
3. Run `Toolbox.ahk` (or the shortcut). Autostart: place a shortcut in `shell:startup`.

> Tested on Windows 10. Windows 11 untested — core commands use standard `netsh` / PowerShell / MMC, so they should work, but no guarantees yet.

## Elevation

Commands needing admin rights are marked with `[admin]` in the menus **when Toolbox is not running elevated** (no badge when it already is). Tray tooltip shows `[ADMIN]` / `[non-admin]`.

- `ElevateMode=warn` (default) — asks before running a non-elevated admin command
- `ElevateMode=auto` — relaunches Toolbox elevated via UAC on first need

Admin-requiring: flush DNS, add/delete/reset routes, static IP / DHCP / DNS changes, Wi-Fi toggle, restart/shutdown, kill process, reduce working set.

## Configuration — `ToolboxFavorites.ini`

Created next to the script. Key sections:

```ini
[Settings]
WSCCRoot=C:\Path\To\WSCC        ; scanned for external tool exes
ElevateMode=warn                ; warn | auto (relaunch elevated when needed)
WarnNonAdmin=1                  ; 0 = silent
ConfirmRestart=1                ; 0 = skip confirmation

[AddressFavorites]              ; MRU addresses (ping/SSH/RDP/browse)
1=192.168.1.1

[PortFavorites]                 ; MRU ip:port targets
1=192.168.1.10:80

[IpProfiles]                    ; saved static-IP profiles
1_Adapter=Ethernet
1_IP=192.168.1.50
1_Mask=255.255.255.0
1_GW=192.168.1.1
1_DNS=1.1.1.1

[CustomFolders]                 ; LabelN/PathN pairs
Label1=Scripts
Path1=F:\Prog

[Tools]                         ; LabelN/ExeN (+ optional PathN)
Label1=Everything
Exe1=Everything.exe

[Snippets]                      ; trigger|expansion hotstrings
Snippet1=;mail|me@company.com

[YtdlpSettings]                 ; last-used yt-dlp GUI settings (managed)
```

Tool exe resolution order: `Tools\` subfolder next to the script → WSCC Apps cache → explicit INI path.

**Update tools**: Tools menu → `Update tools`. Shows each INI tool's local file version and checks the download source's `Last-Modified` against the timestamp from its last Toolbox download (`[ToolUpdates]` in the INI) — outdated entries are pre-checked. Updating pulls the official zip (or direct exe for yt-dlp), extracts, copies the binaries into `Tools\`, deletes the rest. Missing tools are pre-checked too, so the same dialog works as a first-run installer.

**Browse catalog**: full list of catalog tools (Sysinternals: Process Explorer/Monitor, Handle, TCPView, Autoruns, RAMMap, AD Explorer; NirSoft: CurrPorts, WifiInfoView, HashMyFiles, PingInfoView, LiveTcpUdpWatch, WNetWatcher, ProduKey, BatteryInfoView, USBDeview, DriverView, IPNetInfo, MACAddressView, NirCmd, OpenedFilesView, ShellExView; plus yt-dlp). Install checked → downloaded + auto-registered as a Tools menu entry. Caveats: Windows Defender may flag NirSoft zips as PUA; "unknown age" until the first Toolbox-side download baselines the timestamp.

## Project layout

- `Toolbox.ahk` — entry point (directives, module includes, startup)
- `lib/` — modules: `Config` (globals/INI), `Recent`, `Core` (shared utilities), `Updater` (catalog + downloader), `Files`, `Network`, `System`, `Clipboard`, `Tools` (yt-dlp/handle64), `Palette`, `Menu`
- `catalog.json` — tool download catalog for the updater (name, suite, URL, binaries to keep)
- `tests/Smoke.ahk` — smoke tests for pure functions (results in `tests/smoke-results.txt`)
- `.github/workflows/` — `lint` (syntax check + smoke tests on push), `release` (manual dispatch: tags `APP_VERSION` + creates a GitHub release)
- `ToolboxFavorites.ini` — favorites, profiles, settings, snippets (auto-created on first run; **not** tracked — copy `ToolboxFavorites.example.ini` to get started; every section is documented inline there)

## Development

Run tests locally: `AutoHotkey64.exe tests\Smoke.ahk` then check `tests/smoke-results.txt`.
CI runs the same on every push. To cut a release: bump `APP_VERSION` in `Toolbox.ahk`, update `CHANGELOG.md`, then run the `release` workflow.
