; ============================================================
; RECENT COMMANDS TRACKING
; ============================================================
maxRecent := 15
recentSection := "RecentCommands"
commandRegistry := Map()

; Register a command label → callback, return a wrapped callback that logs usage
MakeLogged(label, callback) {
    global commandRegistry
    commandRegistry[label] := callback
    return (*) => RunAndLog(label)
}

; Log a command label to recent history in INI (dedup, push to front, trim to maxRecent)
LogCommand(label) {
    global favoritesFile, recentSection, maxRecent
    if label = ""
        return
    recents := []
    if FileExist(favoritesFile) {
        loop maxRecent {
            val := IniRead(favoritesFile, recentSection, A_Index, "")
            if val != ""
                recents.Push(val)
        }
    }
    newRecents := []
    for r in recents {
        if r != label
            newRecents.Push(r)
    }
    newRecents.InsertAt(1, label)
    if newRecents.Length > maxRecent
        newRecents.Length := maxRecent
    IniDelete(favoritesFile, recentSection)
    for i, r in newRecents
        IniWrite(r, favoritesFile, recentSection, i)
}

; Execute a registered command by label and log it
RunAndLog(label) {
    global commandRegistry
    LogCommand(label)
    if commandRegistry.Has(label)
        commandRegistry[label].Call()
}

; Create a callback for a specific recent command (avoids loop capture bug)
CreateRecentCallback(label) {
    return (*) => RunAndLog(label)
}

; Rebuild the recently-used submenu from INI
RebuildRecentMenu() {
    global recentMenu, commandRegistry, favoritesFile, recentSection, maxRecent
    recentMenu.Delete()
    recents := []
    if FileExist(favoritesFile) {
        loop maxRecent {
            val := IniRead(favoritesFile, recentSection, A_Index, "")
            if val = ""
                break
            recents.Push(val)
        }
    }
    if recents.Length = 0 {
        recentMenu.Add("(no recent commands)", (*) => 0)
        return
    }
    for i, r in recents {
        num := Mod(i - 1, 9) + 1  ; cycle 1-9 for keyboard nav
        display := (i <= 9) ? "&" i ". " r : r  ; only prefix first 9 with number
        if commandRegistry.Has(r)
            recentMenu.Add(display, CreateRecentCallback(r))
        else
            recentMenu.Add(display " (unavailable)", (*) => 0)
    }
    recentMenu.Add()
    recentMenu.Add("Clear recently used...", (*) => ClearRecents())
}

; Wipe the recent-commands history (with confirmation)
ClearRecents() {
    global favoritesFile, recentSection, recentMenu
    result := MsgBox("Clear the recently-used command history?", "Clear Recents", 49)
    if result != "OK"
        return
    IniDelete(favoritesFile, recentSection)
    RebuildRecentMenu()
    ToolTip("Recent commands cleared")
    SetTimer(() => ToolTip(), -1500)
}

