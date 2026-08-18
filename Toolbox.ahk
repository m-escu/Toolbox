#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All
APP_VERSION := "1.2.1"
; ============================================================
; Toolbox.ahk — Sysadmin/IT Power-User Command Launcher
;
; HOTKEYS:
;   Ctrl+Shift+M  — Show main command menu (nested)
;   Ctrl+Shift+P  — Command palette (type-to-filter over all commands)
;   Ctrl+Shift+R  — Re-run last used command
;   Ctrl+Shift+E  — Open selected files in Notepad++
;   Ctrl+Alt+T    — Open terminal at current folder
;   Right-click tray icon — Same menu
;
; MENU STRUCTURE:
;   Recently Used  (last 15 commands, persisted in INI, rebuilt on each open)
;   Files
;     Open selected in Notepad++
;     Copy paths of selected files (as text)
;     Open terminal at current location
;     Open current folder in Explorer
;   Networking
;     Ping / Traceroute / NS Lookup / Port check / Browse to device
;     Network Connections, Flush DNS, IP config, ARP, routes (add/del/reset)
;     Set static IP (saved profiles + popup pick), DHCP, DNS presets
;     RDP to device, SSH, Wake-on-LAN, Subnet calculator, Subnet scanner
;   Folders
;     Temp, AppData Roaming, AppData Local, Profile, Docs, Downloads, Desktop
;     Startup, Program Files, System32, Windows
;     Script folder
;     Custom (from INI [CustomFolders])
;   System
;     Task Manager, Services, Event Viewer, Registry
;     Toggle Wi-Fi, Device Manager, Computer Management
;     Restart..., Shutdown..., Empty Recycle Bin, Kill process...
;     Copy computer name / IP / user / all
;     Uptime & disk space, Recent event log errors
;     Reduce working set (free RAM)
;     Clean temp folder
;   Clipboard
;     Remove duplicates, Sort A-Z/Z-A
;     URL encode, Base64 encode/decode
;     Timestamps (ISO, Unix epoch, readable)
;     Strip HTML, Trim lines, Count stats
;   Tools
;     yt-dlp downloader (multi-URL queue, formats, update, GUI)...
;     handle64 — find file lock (uses selected file if copied)...
;     External tools from INI [Tools] (WSCC / local Tools folder)
;   Settings (submenu + tray)
;     Edit script, Edit INI, Reload, Suspend, Pause
;   Snippets (INI [Snippets]) — auto-expanding hotstrings
;
; REQUIREMENTS:
;   - AutoHotkey v2
;   - Notepad++ (for file opening command)
; ============================================================

; --- CONFIGURATION ---

; --- ADMIN DETECTION ---
; Modules (single namespace — include order matters)
#Include lib\Config.ahk
#Include lib\Recent.ahk
#Include lib\Core.ahk
#Include lib\Updater.ahk
#Include lib\Files.ahk
#Include lib\Network.ahk
#Include lib\System.ahk
#Include lib\Clipboard.ahk
#Include lib\Tools.ahk
#Include lib\Palette.ahk
#Include lib\Menu.ahk

; ============================================================
; STARTUP
; ============================================================
CleanupOldTemp()
BuildMenus()
ApplyHotkeys()

; After an auto-elevate relaunch, resume the command that triggered it
pendingCmd := EnvGet("TOOLBOX_PENDING")
if pendingCmd != "" {
    EnvSet("TOOLBOX_PENDING", "")
    SetTimer(() => RunAndLog(pendingCmd), -1000)
}
