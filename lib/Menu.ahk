; ============================================================
; HOTKEYS (INI-configurable in [Settings])
; ============================================================
ApplyHotkeys() {
    global favoritesFile
    defaults := Map(
        "HotkeyMenu", "^+m",
        "HotkeyPalette", "^+p",
        "HotkeyRerun", "^+r",
        "HotkeyEditNpp", "^+e",
        "HotkeyTerminal", "^!t"
    )
    actions := Map(
        "HotkeyMenu", (*) => ShowMainMenu(),
        "HotkeyPalette", (*) => ShowPalette(),
        "HotkeyRerun", (*) => RunLastCommand(),
        "HotkeyEditNpp", (*) => OpenSelectedInNpp(),
        "HotkeyTerminal", (*) => OpenTerminalHere()
    )
    for name, def in defaults {
        hk := IniRead(favoritesFile, "Settings", name, def)
        try Hotkey(hk, actions[name])
        catch as err
            ToolTip("Bad hotkey for " name " (`"" hk "`"): " err.Message)
    }
    SetTimer(() => ToolTip(), -4000)
}

BuildMenus() {
    fileMenu := Menu()
    fileMenu.Add("&1. Open selected in Notepad++", MakeLogged("Open selected in Notepad++", (*) => OpenSelectedInNpp()))
    fileMenu.Add("&2. Copy paths of selected files", MakeLogged("Copy paths of selected files", (*) => CopySelectedPaths()))
    fileMenu.Add("&3. Open terminal at current location", MakeLogged("Open terminal at current location", (*) => OpenTerminalHere()))
    fileMenu.Add("&4. Open current folder in Explorer", MakeLogged("Open current folder in Explorer", (*) => OpenInExplorer()))

    netMenu := Menu()
    netMenu.Add("&1. Ping address...", MakeLogged("Ping address...", (*) => NetPing()))
    netMenu.Add("&2. Traceroute...", MakeLogged("Traceroute...", (*) => NetTraceroute()))
    netMenu.Add("&3. NS Lookup...", MakeLogged("NS Lookup...", (*) => NetNslookup()))
    netMenu.Add("&4. Port check (IP:port)...", MakeLogged("Port check (IP:port)...", (*) => NetPortCheck()))
    netMenu.Add("&5. Browse to device (open IP in browser)...", MakeLogged("Browse to device", (*) => NetBrowseToDevice()))
    netMenu.Add()
    netMenu.Add("&6. Network Connections", MakeLogged("Network Connections", (*) => Run("ncpa.cpl")))
    netMenu.Add("&7. Flush DNS" Adm() , MakeLogged("Flush DNS", (*) => NetFlushDns()))
    netMenu.Add("&8. Show IP config", MakeLogged("Show IP config", (*) => NetIpConfig()))
    netMenu.Add("&9. Show ARP table", MakeLogged("Show ARP table", (*) => NetArpTable()))
    netMenu.Add("1&0. Show route table", MakeLogged("Show route table", (*) => NetRoutePrint()))
    netMenu.Add("1&1. Add route..." Adm() , MakeLogged("Add route...", (*) => NetRouteAdd()))
    netMenu.Add("1&2. Delete route..." Adm() , MakeLogged("Delete route...", (*) => NetRouteDelete()))
    netMenu.Add("1&3. Reset routes (flush & re-register DNS)" Adm() , MakeLogged("Reset routes", (*) => NetRouteReset()))
    netMenu.Add()
    netMenu.Add("1&4. List network adapters", MakeLogged("List network adapters", (*) => NetListAdapters()))
    netMenu.Add()
    netMenu.Add("1&5. Set static IP on adapter..." Adm() , MakeLogged("Set static IP on adapter...", (*) => NetSetStatic()))
    netMenu.Add("1&6. Set adapter to DHCP..." Adm() , MakeLogged("Set adapter to DHCP...", (*) => NetSetDhcp()))
    netMenu.Add("1&7. Set DNS on adapter..." Adm() , MakeLogged("Set DNS on adapter", (*) => NetDnsToggle()))
    netMenu.Add()
    netMenu.Add("1&8. Wake-on-LAN...", MakeLogged("Wake-on-LAN...", (*) => NetWakeOnLan()))
    netMenu.Add("1&9. SSH to device...", MakeLogged("SSH to device...", (*) => NetSsh()))
    netMenu.Add("2&0. RDP to device...", MakeLogged("RDP to device", (*) => NetRdp()))
    netMenu.Add()
    netMenu.Add("2&1. Scan subnet (ping sweep)...", MakeLogged("Scan subnet", (*) => NetIpScanner()))
    netMenu.Add("2&2. Subnet calculator...", MakeLogged("Subnet calculator", (*) => NetSubnetCalc()))
    netMenu.Add("2&3. Internet speed test...", MakeLogged("Internet speed test", (*) => NetSpeedTest()))

    folderMenu := Menu()
    folderMenu.Add("&1. Temp folder (%TEMP%)", MakeLogged("Temp folder", (*) => OpenFolder(A_Temp)))
    folderMenu.Add("&2. AppData\\Roaming", MakeLogged("AppData\\Roaming", (*) => OpenFolder(A_AppData)))
    folderMenu.Add("&3. AppData\\Local", MakeLogged("AppData\\Local", (*) => OpenFolder(EnvGet("LOCALAPPDATA"))))
    folderMenu.Add("&4. User Profile", MakeLogged("User Profile", (*) => OpenFolder(userProfile)))
    folderMenu.Add("&5. Documents", MakeLogged("Documents", (*) => OpenFolder(A_MyDocuments)))
    folderMenu.Add("&6. Downloads", MakeLogged("Downloads", (*) => OpenFolder(userProfile "\\Downloads")))
    folderMenu.Add("&7. Desktop", MakeLogged("Desktop", (*) => OpenFolder(A_Desktop)))
    folderMenu.Add()
    folderMenu.Add("&8. Startup folder", MakeLogged("Startup folder", (*) => Run("shell:startup")))
    folderMenu.Add("&9. Program Files", MakeLogged("Program Files", (*) => OpenFolder("C:\\Program Files")))
    folderMenu.Add("1&0. Program Files (x86)", MakeLogged("Program Files (x86)", (*) => OpenFolder("C:\\Program Files (x86)")))
    folderMenu.Add("1&1. System32", MakeLogged("System32", (*) => OpenFolder(A_WinDir "\\System32")))
    folderMenu.Add("1&2. Windows", MakeLogged("Windows", (*) => OpenFolder(A_WinDir)))
    folderMenu.Add()
    folderMenu.Add("1&3. This script's folder", MakeLogged("Script folder", (*) => OpenFolder(A_ScriptDir)))

    customFolders := Menu()
    hasCustom := false
    if FileExist(favoritesFile) {
        loop 20 {
            label := IniRead(favoritesFile, "CustomFolders", "Label" A_Index, "")
            path := IniRead(favoritesFile, "CustomFolders", "Path" A_Index, "")
            if label = "" || path = ""
                continue
            fullLabel := "Folder: " label
            commandRegistry[fullLabel] := CreateFolderOpener(path)
            cNum := Mod(A_Index - 1, 9) + 1
            cPrefix := (A_Index <= 9) ? "&" cNum ". " : ""
            customFolders.Add(cPrefix label, CreateRecentCallback(fullLabel))
            hasCustom := true
        }
    }
    if hasCustom {
        folderMenu.Add()
        folderMenu.Add("Custom", customFolders)
    }

    sysMenu := Menu()
    sysMenu.Add("&1. Task Manager", MakeLogged("Task Manager", (*) => Run("taskmgr.exe")))
    sysMenu.Add("&2. Services", MakeLogged("Services", (*) => Run("services.msc")))
    sysMenu.Add("&3. Event Viewer", MakeLogged("Event Viewer", (*) => Run("eventvwr.msc")))
    sysMenu.Add("&4. Registry Editor", MakeLogged("Registry Editor", (*) => Run("regedit")))
    sysMenu.Add()
    sysMenu.Add("&5. Toggle Wi-Fi" Adm() , MakeLogged("Toggle Wi-Fi", (*) => ToggleWifi()))
    sysMenu.Add("&6. Device Manager", MakeLogged("Device Manager", (*) => Run("devmgmt.msc")))
    sysMenu.Add("&7. Computer Management", MakeLogged("Computer Management", (*) => Run("compmgmt.msc")))
    sysMenu.Add()
    sysMenu.Add("&8. Restart..." Adm() , MakeLogged("Restart...", (*) => SysRestart()))
    sysMenu.Add("&9. Shutdown..." Adm() , MakeLogged("Shutdown...", (*) => SysShutdown()))
    sysMenu.Add("1&0. Empty Recycle Bin", MakeLogged("Empty Recycle Bin", (*) => FileRecycleEmpty()))
    sysMenu.Add("1&1. Kill process..." Adm() , MakeLogged("Kill process...", (*) => SysKillProcess()))
    sysMenu.Add()
    sysMenu.Add("1&2. Copy computer name", MakeLogged("Copy computer name", (*) => CopyInfoItem("computername")))
    sysMenu.Add("1&3. Copy local IP address(es)", MakeLogged("Copy local IP", (*) => CopyInfoItem("ip")))
    sysMenu.Add("1&4. Copy username", MakeLogged("Copy username", (*) => CopyInfoItem("user")))
    sysMenu.Add("1&5. Copy hostname & IP & user", MakeLogged("Copy host info", (*) => CopyInfoItem("all")))
    sysMenu.Add()
    sysMenu.Add("1&6. Uptime & disk space", MakeLogged("Uptime & disk space", (*) => SysUptimeDisk()))
    sysMenu.Add("1&7. Recent event log errors", MakeLogged("Event log errors", (*) => SysEventErrors()))
    sysMenu.Add("1&8. Reduce working set (free RAM)" Adm() , MakeLogged("Reduce working set", (*) => SysReduceWorkingSet()))
    sysMenu.Add("1&9. Clean temp folder...", MakeLogged("Clean temp folder", (*) => SysCleanTemp()))

    clipMenu := Menu()
    clipMenu.Add("&1. Remove duplicate lines", MakeLogged("Remove duplicate lines", (*) => ClipRemoveDuplicates()))
    clipMenu.Add("&2. Sort lines (A-Z)", MakeLogged("Sort lines (A-Z)", (*) => ClipSortLines()))
    clipMenu.Add("&3. Sort lines (Z-A)", MakeLogged("Sort lines (Z-A)", (*) => ClipSortLines(true)))
    clipMenu.Add()
    clipMenu.Add("&4. URL encode clipboard", MakeLogged("URL encode", (*) => ClipUrlEncode()))
    clipMenu.Add("&5. Base64 encode clipboard", MakeLogged("Base64 encode", (*) => ClipBase64Encode()))
    clipMenu.Add("&6. Base64 decode clipboard", MakeLogged("Base64 decode", (*) => ClipBase64Decode()))
    clipMenu.Add()
    clipMenu.Add("&7. Insert timestamp (ISO 8601)", MakeLogged("Timestamp ISO", (*) => ClipInsertTimestamp("iso")))
    clipMenu.Add("&8. Insert timestamp (Unix epoch)", MakeLogged("Timestamp Unix", (*) => ClipInsertTimestamp("unix")))
    clipMenu.Add("&9. Insert timestamp (readable)", MakeLogged("Timestamp readable", (*) => ClipInsertTimestamp("readable")))
    clipMenu.Add()
    clipMenu.Add("1&0. Strip HTML formatting", MakeLogged("Strip HTML", (*) => ClipStripHtml()))
    clipMenu.Add("1&1. Trim each line", MakeLogged("Trim lines", (*) => ClipTrimLines()))
    clipMenu.Add("1&2. Count chars / words / lines", MakeLogged("Count stats", (*) => ClipCountStats()))

    toolsMenu := Menu()
    toolsMenu.Add("&1. yt-dlp downloader...", MakeLogged("yt-dlp downloader", (*) => ToolYtDlp()))
    toolsMenu.Add("&2. handle64 — find file lock...", MakeLogged("handle64 find lock", (*) => ToolHandle64()))

    ScanWsccApps()
    GetAdapters(true)
    suiteMenus := Map()
    suiteHas := Map()
    loop 200 {
        tLabel := IniRead(favoritesFile, "Tools", "Label" A_Index, "")
        tExe := IniRead(favoritesFile, "Tools", "Exe" A_Index, "")
        if tLabel = "" || tExe = ""
            continue
        if (tExe = "handle64.exe")
            continue
        tCustomPath := IniRead(favoritesFile, "Tools", "Path" A_Index, "")
        tFull := ResolveToolPath(tExe, tCustomPath)
        suite := "Other"
        if toolCatalog.Has(StrLower(tExe))
            suite := toolCatalog[StrLower(tExe)].suite
        if !suiteMenus.Has(suite) {
            suiteMenus[suite] := Menu()
            suiteHas[suite] := 0
        }
        suiteHas[suite] += 1
        n := suiteHas[suite]
        displayLabel := (n <= 9) ? "&" n ". " tLabel : tLabel
        if tFull != "" {
            fullLabel := "Tool: " tLabel
            commandRegistry[fullLabel] := CreateRunner(tFull)
            suiteMenus[suite].Add(displayLabel, CreateRecentCallback(fullLabel))
        } else {
            suiteMenus[suite].Add(displayLabel " (not found)", (*) => 0)
        }
    }
    for , suiteName in ["Sysinternals", "NirSoft", "GitHub", "Other"] {
        if suiteMenus.Has(suiteName) {
            toolsMenu.Add(suiteName, suiteMenus[suiteName])
            suiteMenus.Delete(suiteName)
        }
    }
    for suiteName, sm in suiteMenus
        toolsMenu.Add(suiteName, sm)
    toolsMenu.Add()
    toolsMenu.Add("Add tool...", MakeLogged("Add tool", (*) => ToolAddTool()))
    toolsMenu.Add("Update tools (versions + download)...", MakeLogged("Update tools", (*) => ToolUpdater()))
    toolsMenu.Add("Browse tool catalog...", MakeLogged("Browse tool catalog", (*) => ToolBrowseCatalog()))

    settingsMenu := Menu()
    settingsMenu.Add("&1. Edit this script", (*) => Run('"' nppPath '" "' A_ScriptFullPath '"'))
    settingsMenu.Add("&2. Edit favorites (INI)", (*) => EditFavorites())
    settingsMenu.Add()
    settingsMenu.Add("&3. Clear recently used...", (*) => ClearRecents())
    settingsMenu.Add("&4. Reload script", (*) => Reload())
    settingsMenu.Add("&5. Suspend hotkeys", (*) => Suspend(-1))
    settingsMenu.Add("&6. Pause script", (*) => Pause(-1))

    LoadSnippets()

    global recentMenu := Menu()
    RebuildRecentMenu()

    global mainMenu := Menu()
    mainMenu.Add("&S. Search...", (*) => ShowPalette())
    mainMenu.Add()
    mainMenu.Add("&1. Recently Used", recentMenu)
    mainMenu.Add()
    mainMenu.Add("&2. Files", fileMenu)
    mainMenu.Add("&3. Networking", netMenu)
    mainMenu.Add("&4. Folders", folderMenu)
    mainMenu.Add("&5. System", sysMenu)
    mainMenu.Add("&6. Clipboard", clipMenu)
    mainMenu.Add("&7. Tools", toolsMenu)
    mainMenu.Add("&8. Settings", settingsMenu)

    adminBadge := isAdmin ? " [ADMIN]" : " [non-admin]"
    A_IconTip := "Toolbox — Sysadmin Launcher" adminBadge
    iconDir := A_ScriptDir "\icons"
    if isAdmin && FileExist(iconDir "\toolbox_admin.ico")
        TraySetIcon(iconDir "\toolbox_admin.ico")
    else if FileExist(iconDir "\toolbox.ico")
        TraySetIcon(iconDir "\toolbox.ico")
    A_TrayMenu.Delete()
    A_TrayMenu.Add("&S. Search...", (*) => ShowPalette())
    A_TrayMenu.Add()
    A_TrayMenu.Add("&1. Recently Used", recentMenu)
    A_TrayMenu.Add()
    A_TrayMenu.Add("&2. Files", fileMenu)
    A_TrayMenu.Add("&3. Networking", netMenu)
    A_TrayMenu.Add("&4. Folders", folderMenu)
    A_TrayMenu.Add("&5. System", sysMenu)
    A_TrayMenu.Add("&6. Clipboard", clipMenu)
    A_TrayMenu.Add("&7. Tools", toolsMenu)
    A_TrayMenu.Add()
    A_TrayMenu.Add("&8. Edit this script", (*) => Run('"' nppPath '" "' A_ScriptFullPath '"'))
    A_TrayMenu.Add("&9. Edit favorites (INI)", (*) => EditFavorites())
    A_TrayMenu.Add()
    A_TrayMenu.Add("&0. Reload script", (*) => Reload())
    A_TrayMenu.Add("E&xit", (*) => ExitApp())
    A_TrayMenu.ClickCount := 1
}

ShowMainMenu() {
    global mainMenu, recentMenu
    RebuildRecentMenu()
    mainMenu.Show()
}

EditFavorites() {
    global favoritesFile, nppPath
    if !FileExist(favoritesFile)
        FileAppend("; Toolbox Favorites`n; Edit freely, sections: AddressFavorites, PortFavorites, IpProfiles`n", favoritesFile, "UTF-8")
    if FileExist(nppPath)
        Run('"' nppPath '" "' favoritesFile '"')
    else
        Run('notepad.exe "' favoritesFile '"')
}
