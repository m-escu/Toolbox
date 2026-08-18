global userProfile  ; super-global: used across modules
userProfile := EnvGet("USERPROFILE")

; Check once at startup whether we're running elevated
isAdmin := DllCall("shell32\IsUserAnAdmin")  ; returns 1 (true) or 0 (false)

; Helper: warn if not admin. Returns true to proceed, false to abort.
; Settings.WarnNonAdmin in INI: 1 = warn (default), 0 = silent
; Settings.ElevateMode in INI: "auto" = relaunch elevated (default), "warn" = old behavior
RequireAdmin(commandLabel) {
    global isAdmin, favoritesFile
    if isAdmin
        return true
    elevate := IniRead(favoritesFile, "Settings", "ElevateMode", "warn")
    if (elevate = "auto") {
        ToolTip("Relaunching Toolbox as admin...")
        SetTimer(() => ToolTip(), -2000)
        try {
            EnvSet("TOOLBOX_PENDING", commandLabel)  ; resume this command after relaunch
            Run("*RunAs `"" A_AhkPath "`" `"" A_ScriptFullPath "`"")
            ExitApp()
        } catch {
            return false  ; UAC declined
        }
    }
    ; Check INI setting
    warn := IniRead(favoritesFile, "Settings", "WarnNonAdmin", "1")
    if warn != "1"
        return true  ; warnings disabled, proceed silently
    result := MsgBox("The following command requires admin privileges:`n`n  " commandLabel "`n`nContinue anyway? (will likely fail without elevation)", "Not Running as Admin", 49)  ; OK+Cancel with ! icon
    return (result = "OK")
}

; --- FAVORITES FILE (IP:port, addresses you use often) ---
; Stored in ToolboxFavorites.ini next to this script
; Format: [Favorites] \n 1=192.168.0.2:102 \n 2=192.168.1.1 \n ...
; Max 20 entries, most-recently-used pushed to top
favoritesFile := A_ScriptDir "\ToolboxFavorites.ini"
nppPath := IniRead(favoritesFile, "Settings", "NppPath", "C:\Program Files\Notepad++\notepad++.exe")
maxFavorites := 20

; Helper: load favorites from INI into an array
LoadFavorites(section := "Favorites") {
    global favoritesFile, maxFavorites
    favs := []
    if !FileExist(favoritesFile)
        return favs
    loop maxFavorites {
        val := IniRead(favoritesFile, section, A_Index, "")
        if val != ""
            favs.Push(val)
    }
    return favs
}

; Helper: save favorites array to INI (most recent first)
SaveFavorites(favs, section := "Favorites") {
    global favoritesFile
    ; Delete existing section keys first
    IniDelete(favoritesFile, section)
    for i, val in favs
        IniWrite(val, favoritesFile, section, i)
}

; Helper: add a value to favorites (push to front, dedup, trim to max)
AddFavorite(val, section := "Favorites") {
    global maxFavorites
    if val = ""
        return
    val := Trim(val)
    favs := LoadFavorites(section)
    ; Remove duplicate if exists
    newFavs := []
    for f in favs {
        if f != val
            newFavs.Push(f)
    }
    ; Insert at front
    newFavs.InsertAt(1, val)
    ; Trim to max
    if newFavs.Length > maxFavorites
        newFavs.Length := maxFavorites
    SaveFavorites(newFavs, section)
}

; Helper: build a display string of favorites for InputBox prompt
FormatFavoritesPrompt(favs, prefix := "Recent targets: ") {
    if favs.Length == 0
        return ""
    text := prefix "(type number to quick-pick)`n"
    for i, f in favs
        text .= "  " i ". " f "`n"
    return text "`n"
}

; Helper: resolve user input — if they typed a number matching a favorite, return that value
ResolveInput(input, favs) {
    input := Trim(input)
    if input = ""
        return ""
    ; Check if pure number and within range
    if RegExMatch(input, "^(\d+)$") {
        idx := Integer(input)
        if idx >= 1 && idx <= favs.Length
            return favs[idx]
    }
    return input
}

; ============================================================
; IP PROFILE FAVORITES (multi-field: adapter, IP, mask, GW, DNS)
; ============================================================

ipProfileMax := 10
ipProfileSection := "IpProfiles"

; Load all saved IP profiles as an array of objects
LoadIpProfiles() {
    global favoritesFile, ipProfileMax, ipProfileSection
    profiles := []
    if !FileExist(favoritesFile)
        return profiles
    loop ipProfileMax {
        adapter := IniRead(favoritesFile, ipProfileSection, A_Index "_Adapter", "")
        if adapter = ""
            continue
        ip     := IniRead(favoritesFile, ipProfileSection, A_Index "_IP", "")
        mask   := IniRead(favoritesFile, ipProfileSection, A_Index "_Mask", "")
        gw     := IniRead(favoritesFile, ipProfileSection, A_Index "_GW", "")
        dns    := IniRead(favoritesFile, ipProfileSection, A_Index "_DNS", "")
        profiles.Push({adapter: adapter, ip: ip, mask: mask, gw: gw, dns: dns})
    }
    return profiles
}

; Save IP profiles array back to INI
SaveIpProfiles(profiles) {
    global favoritesFile, ipProfileSection
    IniDelete(favoritesFile, ipProfileSection)
    for i, p in profiles {
        IniWrite(p.adapter, favoritesFile, ipProfileSection, i "_Adapter")
        IniWrite(p.ip, favoritesFile, ipProfileSection, i "_IP")
        IniWrite(p.mask, favoritesFile, ipProfileSection, i "_Mask")
        IniWrite(p.gw, favoritesFile, ipProfileSection, i "_GW")
        IniWrite(p.dns, favoritesFile, ipProfileSection, i "_DNS")
    }
}

; Add an IP profile to front, dedup by adapter+firstIP, trim to max
AddIpProfile(adapter, ip, mask, gw, dns) {
    global ipProfileMax
    profiles := LoadIpProfiles()
    ; Get first IP for dedup comparison
    firstIp := ParseIpList(ip)[1]  ; ip can be comma-separated
    newProfiles := []
    for p in profiles {
        pFirstIp := ParseIpList(p.ip)[1]
        if !(p.adapter = adapter && pFirstIp = firstIp)
            newProfiles.Push(p)
    }
    newProfiles.InsertAt(1, {adapter: adapter, ip: ip, mask: mask, gw: gw, dns: dns})
    if newProfiles.Length > ipProfileMax
        newProfiles.Length := ipProfileMax
    SaveIpProfiles(newProfiles)
}

; Build display text for IP profiles
FormatIpProfilesPrompt(profiles) {
    if profiles.Length == 0
        return ""
    text := "Saved profiles (type number to quick-apply):`n"
    for i, p in profiles {
        gwPart := p.gw != "" ? " GW:" p.gw : ""
        dnsPart := p.dns != "" ? " DNS:" p.dns : ""
        text .= "  " i ". " p.adapter "`n     " p.ip "/" p.mask gwPart dnsPart "`n"
    }
    return text "`n"
}

; Parse a comma-separated IP string into an array
ParseIpList(ipStr) {
    ips := []
    for part in StrSplit(ipStr, ",") {
        ip := Trim(part)
        if ip != ""
            ips.Push(ip)
    }
    return ips
}

; Helper: badge shown after commands that need elevation (only when NOT elevated)
Adm() {
    global isAdmin
    return isAdmin ? "" : "  [admin]"
}

; Helper: create a callback that opens a specific folder (for custom folder menu items)
CreateFolderOpener(folderPath) {
    return (*) => OpenFolder(folderPath)
}

; Helper: create a callback that launches a specific executable (avoids closure capture bug)
CreateRunner(executablePath) {
    return (*) => Run('"' executablePath '"')
}

; ============================================================
; EXTERNAL TOOLS RESOLVER (WSCC + local Tools folder)
; ============================================================

; Cache: exe filename → full path (populated by WSCC scan)
wsccCache := Map()

; Catalog: known-suite tool downloads (for the updater)
toolCatalog := BuildToolCatalog()

; Scan WSCC Apps folder recursively once at startup, build lookup cache
ScanWsccApps() {
    global favoritesFile, wsccCache
    wsccRoot := IniRead(favoritesFile, "Settings", "WSCCRoot", "")
    if wsccRoot = "" || !DirExist(wsccRoot)
        return
    appsPath := wsccRoot "\Apps"
    if !DirExist(appsPath)
        return
    wsccCache := Map()
    try {
        Loop Files appsPath "\*.exe", "R"
            wsccCache[StrLower(A_LoopFileName)] := A_LoopFilePath  ; lowercase keys — Map lookups are case-sensitive
    }
}

; Resolve a tool exe by searching: 1) explicit path from INI  2) Script\Tools  3) WSCC cache
ResolveToolPath(exeName, customPath := "") {
    global wsccCache
    ; 1) Explicit custom path from INI (user-picked — highest priority)
    if customPath != "" && FileExist(customPath)
        return customPath
    ; 2) Packed in script's Tools subfolder
    localPath := A_ScriptDir "\Tools\" exeName
    if FileExist(localPath)
        return localPath
    ; 3) Found in WSCC Apps (cache keys are lowercase)
    if wsccCache.Has(StrLower(exeName))
        return wsccCache[StrLower(exeName)]
    return ""
}

