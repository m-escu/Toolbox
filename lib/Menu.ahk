; ============================================================
; HOTKEYS (INI-configurable in [Settings]; custom ones in [Hotkeys])
; Empty value in [Settings] disables that built-in hotkey.
; [Hotkeys] format:  Hotkey=Target  where Target is a registered
; command label or a raw command line.
; ============================================================
global registeredHotkeys := Map()

ApplyHotkeys() {
    global favoritesFile, registeredHotkeys
    ; unregister previous bindings so re-applying picks up changes
    for hk in registeredHotkeys.Clone()
        try Hotkey(hk, , "Off")
    registeredHotkeys := Map()

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
        if Trim(hk) = ""
            continue  ; disabled in INI
        RegisterHotkeySafe(hk, actions[name], name)
    }
    ; custom hotkeys: [Hotkeys] section, Hotkey=Target
    section := IniRead(favoritesFile, "Hotkeys", , "")
    for line in StrSplit(section, "`n") {
        p := InStr(line, "=")
        if !p
            continue
        hk := Trim(SubStr(line, 1, p - 1))
        target := Trim(SubStr(line, p + 1))
        if hk = "" || target = ""
            continue
        if registeredHotkeys.Has(hk)
            continue  ; conflict with built-in — already warned at registration
        RegisterHotkeySafe(hk, CreateCustomHotkeyAction(target), "Hotkey: " target)
    }
    SetTimer(() => ToolTip(), -4000)
}

RegisterHotkeySafe(hk, action, label) {
    global registeredHotkeys
    try {
        Hotkey(hk, action, "On")  ; "On": probe variants created during save are Off
        registeredHotkeys[hk] := true
    } catch as err
        ToolTip("Bad hotkey for " label " (`"" hk "`"): " err.Message)
}

; Custom hotkey target: registered command label if known, else raw command line
CreateCustomHotkeyAction(target) {
    global commandRegistry
    if commandRegistry.Has(target)
        return (*) => RunAndLog(target)
    return (*) => RunCustomHotkeyCommand(target)
}

RunCustomHotkeyCommand(target) {
    LogCommand("Hotkey: " target)
    try
        Run(target)
    catch as err
        MsgBox("Hotkey command failed:`n`n" target "`n`n" err.Message, "Toolbox", 48)
}


BuildMenus() {
    global settingsMenu
    SpecReset()
    SpecAdd("Files", "&1. Open selected in Notepad++", "Open selected in Notepad++", (*) => OpenSelectedInNpp())
    SpecAdd("Files", "&2. Copy paths of selected files", "Copy paths of selected files", (*) => CopySelectedPaths())
    SpecAdd("Files", "&3. Open terminal at current location", "Open terminal at current location", (*) => OpenTerminalHere())
    SpecAdd("Files", "&4. Open current folder in Explorer", "Open current folder in Explorer", (*) => OpenInExplorer())

    SpecAdd("Networking", "&1. Ping address...", "Ping address...", (*) => NetPing())
    SpecAdd("Networking", "&2. Traceroute...", "Traceroute...", (*) => NetTraceroute())
    SpecAdd("Networking", "&3. NS Lookup...", "NS Lookup...", (*) => NetNslookup())
    SpecAdd("Networking", "&4. Port check (IP:port)...", "Port check (IP:port)...", (*) => NetPortCheck())
    SpecAdd("Networking", "&5. Browse to device (open IP in browser)...", "Browse to device", (*) => NetBrowseToDevice())
    SpecSep("Networking")
    SpecAdd("Networking", "&6. Network Connections", "Network Connections", (*) => Run("ncpa.cpl"))
    SpecAdd("Networking", "&7. Flush DNS" Adm() , "Flush DNS", (*) => NetFlushDns())
    SpecAdd("Networking", "&8. Show IP config", "Show IP config", (*) => NetIpConfig())
    SpecAdd("Networking", "&9. Show ARP table", "Show ARP table", (*) => NetArpTable())
    SpecAdd("Networking", "1&0. Show route table", "Show route table", (*) => NetRoutePrint())
    SpecAdd("Networking", "1&1. Add route..." Adm() , "Add route...", (*) => NetRouteAdd())
    SpecAdd("Networking", "1&2. Delete route..." Adm() , "Delete route...", (*) => NetRouteDelete())
    SpecAdd("Networking", "1&3. Reset routes (flush & re-register DNS)" Adm() , "Reset routes", (*) => NetRouteReset())
    SpecSep("Networking")
    SpecAdd("Networking", "1&4. List network adapters", "List network adapters", (*) => NetListAdapters())
    SpecSep("Networking")
    SpecAdd("Networking", "1&5. Set static IP on adapter..." Adm() , "Set static IP on adapter...", (*) => NetSetStatic())
    SpecAdd("Networking", "1&6. Set adapter to DHCP..." Adm() , "Set adapter to DHCP...", (*) => NetSetDhcp())
    SpecAdd("Networking", "1&7. Set DNS on adapter..." Adm() , "Set DNS on adapter", (*) => NetDnsToggle())
    SpecSep("Networking")
    SpecAdd("Networking", "1&8. Wake-on-LAN...", "Wake-on-LAN...", (*) => NetWakeOnLan())
    SpecAdd("Networking", "1&9. SSH to device...", "SSH to device...", (*) => NetSsh())
    SpecAdd("Networking", "2&0. RDP to device...", "RDP to device", (*) => NetRdp())
    SpecSep("Networking")
    SpecAdd("Networking", "2&1. Scan subnet (ping sweep)...", "Scan subnet", (*) => NetIpScanner())
    SpecAdd("Networking", "2&2. Subnet calculator...", "Subnet calculator", (*) => NetSubnetCalc())
    SpecAdd("Networking", "2&3. Internet speed test...", "Internet speed test", (*) => NetSpeedTest())
    SpecSep("Networking")
    SpecAdd("Networking", "2&4. Show DNS cache", "Show DNS cache", (*) => NetDnsCache())
    SpecAdd("Networking", "2&5. Wi-Fi connection details", "Wi-Fi connection details", (*) => NetWifiDetails())
    SpecAdd("Networking", "2&6. Wi-Fi networks in range", "Wi-Fi networks in range", (*) => NetWifiNetworks())
    SpecAdd("Networking", "2&7. Wi-Fi profiles & passwords..." Adm() , "Wi-Fi profiles & passwords", (*) => NetWifiPasswords())
    SpecAdd("Networking", "2&8. Listening ports & process", "Listening ports & process", (*) => NetListeningPorts())
    SpecAdd("Networking", "2&9. Show shared folders (SMB)", "Show shared folders (SMB)", (*) => NetSmbShares())
    SpecSep("Networking")
    SpecAdd("Networking", "3&0. Show public IP & ISP (copy)", "Show public IP & ISP", (*) => NetPublicIp())
    SpecAdd("Networking", "3&1. Test website (HTTP status)...", "Test website (HTTP status)", (*) => NetTestWebsite())
    SpecAdd("Networking", "3&2. Show hosts file", "Show hosts file", (*) => NetHostsFile())

    SpecAdd("Folders", "&1. Temp folder (%TEMP%)", "Temp folder", (*) => OpenFolder(A_Temp))
    SpecAdd("Folders", "&2. AppData\\Roaming", "AppData\\Roaming", (*) => OpenFolder(A_AppData))
    SpecAdd("Folders", "&3. AppData\\Local", "AppData\\Local", (*) => OpenFolder(EnvGet("LOCALAPPDATA")))
    SpecAdd("Folders", "&4. User Profile", "User Profile", (*) => OpenFolder(userProfile))
    SpecAdd("Folders", "&5. Documents", "Documents", (*) => OpenFolder(A_MyDocuments))
    SpecAdd("Folders", "&6. Downloads", "Downloads", (*) => OpenFolder(userProfile "\\Downloads"))
    SpecAdd("Folders", "&7. Desktop", "Desktop", (*) => OpenFolder(A_Desktop))
    SpecSep("Folders")
    SpecAdd("Folders", "&8. Startup folder", "Startup folder", (*) => Run("shell:startup"))
    SpecAdd("Folders", "&9. Program Files", "Program Files", (*) => OpenFolder("C:\\Program Files"))
    SpecAdd("Folders", "1&0. Program Files (x86)", "Program Files (x86)", (*) => OpenFolder("C:\\Program Files (x86)"))
    SpecAdd("Folders", "1&1. System32", "System32", (*) => OpenFolder(A_WinDir "\\System32"))
    SpecAdd("Folders", "1&2. Windows", "Windows", (*) => OpenFolder(A_WinDir))
    SpecSep("Folders")
    SpecAdd("Folders", "1&3. This script's folder", "Script folder", (*) => OpenFolder(A_ScriptDir))

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
    if hasCustom
        SpecSub("Folders", "Custom", customFolders)

    SpecAdd("System", "&1. Task Manager", "Task Manager", (*) => Run("taskmgr.exe"))
    SpecAdd("System", "&2. Services", "Services", (*) => Run("services.msc"))
    SpecAdd("System", "&3. Event Viewer", "Event Viewer", (*) => Run("eventvwr.msc"))
    SpecAdd("System", "&4. Registry Editor", "Registry Editor", (*) => Run("regedit"))
    SpecSep("System")
    SpecAdd("System", "&5. Toggle Wi-Fi" Adm() , "Toggle Wi-Fi", (*) => ToggleWifi())
    SpecAdd("System", "&6. Device Manager", "Device Manager", (*) => Run("devmgmt.msc"))
    SpecAdd("System", "&7. Computer Management", "Computer Management", (*) => Run("compmgmt.msc"))
    SpecSep("System")
    SpecAdd("System", "&8. Restart..." Adm() , "Restart...", (*) => SysRestart())
    SpecAdd("System", "&9. Shutdown..." Adm() , "Shutdown...", (*) => SysShutdown())
    SpecAdd("System", "1&0. Empty Recycle Bin", "Empty Recycle Bin", (*) => FileRecycleEmpty())
    SpecAdd("System", "1&1. Kill process..." Adm() , "Kill process...", (*) => SysKillProcess())
    SpecSep("System")
    SpecAdd("System", "1&2. Copy computer name", "Copy computer name", (*) => CopyInfoItem("computername"))
    SpecAdd("System", "1&3. Copy local IP address(es)", "Copy local IP", (*) => CopyInfoItem("ip"))
    SpecAdd("System", "1&4. Copy username", "Copy username", (*) => CopyInfoItem("user"))
    SpecAdd("System", "1&5. Copy hostname & IP & user", "Copy host info", (*) => CopyInfoItem("all"))
    SpecSep("System")
    SpecAdd("System", "1&6. Uptime & disk space", "Uptime & disk space", (*) => SysUptimeDisk())
    SpecAdd("System", "1&7. Recent event log errors", "Event log errors", (*) => SysEventErrors())
    SpecAdd("System", "1&8. Reduce working set (free RAM)" Adm() , "Reduce working set", (*) => SysReduceWorkingSet())
    SpecAdd("System", "1&9. Clean temp folder...", "Clean temp folder", (*) => SysCleanTemp())
    SpecSep("System")
    SpecAdd("System", "2&0. System info summary", "System info summary", (*) => SysInfoSummary())
    SpecAdd("System", "2&1. Startup programs", "Startup programs", (*) => SysStartupItems())
    SpecAdd("System", "2&2. Top processes (CPU & RAM)", "Top processes (CPU & RAM)", (*) => SysTopProcesses())
    SpecAdd("System", "2&3. Running services", "Running services", (*) => SysRunningServices())
    SpecAdd("System", "2&4. Installed applications", "Installed applications", (*) => SysInstalledApps())
    SpecAdd("System", "2&5. Windows updates history", "Windows updates history", (*) => SysUpdateHistory())
    SpecAdd("System", "2&6. Disk health (SMART)", "Disk health (SMART)", (*) => SysDiskHealth())
    SpecAdd("System", "2&7. Battery status & report", "Battery status & report", (*) => SysBattery())
    SpecAdd("System", "2&8. Display & GPU info", "Display & GPU info", (*) => SysGpuInfo())
    SpecAdd("System", "2&9. Installed printers", "Installed printers", (*) => SysPrinters())
    SpecAdd("System", "3&0. Power plans (switch)...", "Power plans (switch)", (*) => SysPowerPlans())
    SpecAdd("System", "3&1. Windows activation status", "Windows activation status", (*) => SysActivation())
    SpecSep("System")
    SpecAdd("System", "3&2. Copy Windows product key (OEM)", "Copy Windows product key", (*) => SysCopyProductKey())
    SpecAdd("System", "3&3. Edit environment variables", "Edit environment variables", (*) => SysEditEnvVars())

    SpecAdd("Clipboard", "&1. Remove duplicate lines", "Remove duplicate lines", (*) => ClipRemoveDuplicates())
    SpecAdd("Clipboard", "&2. Sort lines (A-Z)", "Sort lines (A-Z)", (*) => ClipSortLines())
    SpecAdd("Clipboard", "&3. Sort lines (Z-A)", "Sort lines (Z-A)", (*) => ClipSortLines(true))
    SpecSep("Clipboard")
    SpecAdd("Clipboard", "&4. URL encode clipboard", "URL encode", (*) => ClipUrlEncode())
    SpecAdd("Clipboard", "&5. Base64 encode clipboard", "Base64 encode", (*) => ClipBase64Encode())
    SpecAdd("Clipboard", "&6. Base64 decode clipboard", "Base64 decode", (*) => ClipBase64Decode())
    SpecSep("Clipboard")
    SpecAdd("Clipboard", "&7. Insert timestamp (ISO 8601)", "Timestamp ISO", (*) => ClipInsertTimestamp("iso"))
    SpecAdd("Clipboard", "&8. Insert timestamp (Unix epoch)", "Timestamp Unix", (*) => ClipInsertTimestamp("unix"))
    SpecAdd("Clipboard", "&9. Insert timestamp (readable)", "Timestamp readable", (*) => ClipInsertTimestamp("readable"))
    SpecSep("Clipboard")
    SpecAdd("Clipboard", "1&0. Strip HTML formatting", "Strip HTML", (*) => ClipStripHtml())
    SpecAdd("Clipboard", "1&1. Trim each line", "Trim lines", (*) => ClipTrimLines())
    SpecAdd("Clipboard", "1&2. Count chars / words / lines", "Count stats", (*) => ClipCountStats())
    SpecSep("Clipboard")
    SpecAdd("Clipboard", "1&3. Hash clipboard text (SHA-256)", "Hash clipboard text (SHA-256)", (*) => ClipHashText())
    SpecAdd("Clipboard", "1&4. Generate GUID (copy)", "Generate GUID (copy)", (*) => ClipNewGuid())

    SpecAdd("Tools", "&1. yt-dlp downloader...", "yt-dlp downloader", (*) => ToolYtDlp())
    SpecAdd("Tools", "&2. handle64 — find file lock...", "handle64 find lock", (*) => ToolHandle64())
    SpecAdd("Tools", "&3. Hash file (SHA-256/SHA-1/MD5)...", "Hash file", (*) => ToolHashFile())
    SpecAdd("Tools", "&4. Password generator...", "Password generator", (*) => ToolPasswordGen())

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
            SpecSub("Tools", suiteName, suiteMenus[suiteName])
            suiteMenus.Delete(suiteName)
        }
    }
    for suiteName, sm in suiteMenus
        SpecSub("Tools", suiteName, sm)
    SpecSep("Tools")
    SpecAdd("Tools", "Add tool...", "Add tool", (*) => ToolAddTool())
    SpecAdd("Tools", "Manage tools...", "Manage tools", (*) => ToolManageGui())
    SpecAdd("Tools", "Update tools (versions + download)...", "Update tools", (*) => ToolUpdater())
    SpecAdd("Tools", "Browse tool catalog...", "Browse tool catalog", (*) => ToolBrowseCatalog())

    settingsMenu := Menu()
    settingsMenu.Add("&1. Hotkeys...", (*) => ShowHotkeyEditor())
    settingsMenu.Add("&2. Menu editor...", (*) => ShowMenuEditor())
    settingsMenu.Add("&3. Clear recently used...", (*) => ClearRecents())
    settingsMenu.Add()
    settingsMenu.Add("&4. Suspend hotkeys", (*) => Suspend(-1))
    settingsMenu.Add("&5. Pause script", (*) => Pause(-1))

    LoadSnippets()

    ; render section menus from spec + saved layout
    BuildSectionMenus()

    global recentMenu := Menu()
    RebuildRecentMenu()

    global mainMenu := Menu()
    mainMenu.Add("&S. Search...", (*) => ShowPalette())
    mainMenu.Add()
    mainMenu.Add("&1. Recently Used", recentMenu)
    mainMenu.Add()
    mainMenu.Add("&2. Files", sectionMenus["Files"])
    mainMenu.Add("&3. Networking", sectionMenus["Networking"])
    mainMenu.Add("&4. Folders", sectionMenus["Folders"])
    mainMenu.Add("&5. System", sectionMenus["System"])
    mainMenu.Add("&6. Clipboard", sectionMenus["Clipboard"])
    mainMenu.Add("&7. Tools", sectionMenus["Tools"])
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
    A_TrayMenu.Add("&2. Files", sectionMenus["Files"])
    A_TrayMenu.Add("&3. Networking", sectionMenus["Networking"])
    A_TrayMenu.Add("&4. Folders", sectionMenus["Folders"])
    A_TrayMenu.Add("&5. System", sectionMenus["System"])
    A_TrayMenu.Add("&6. Clipboard", sectionMenus["Clipboard"])
    A_TrayMenu.Add("&7. Tools", sectionMenus["Tools"])
    A_TrayMenu.Add()
    A_TrayMenu.Add("&8. Settings", settingsMenu)
    A_TrayMenu.Add("&9. Edit this script", (*) => Run('"' nppPath '" "' A_ScriptFullPath '"'))
    A_TrayMenu.Add("1&0. Edit favorites (INI)", (*) => EditFavorites())
    A_TrayMenu.Add()
    A_TrayMenu.Add("&R. Reload script", (*) => Reload())
    A_TrayMenu.Add("E&xit", (*) => ExitApp())
    A_TrayMenu.ClickCount := 1
}

ShowMainMenu() {
    global mainMenu, recentMenu
    RebuildRecentMenu()
    FlushMenuThemes()
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
