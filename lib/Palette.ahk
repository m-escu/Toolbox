; ============================================================
; COMMAND PALETTE (Ctrl+Shift+P) — fuzzy search over commandRegistry
; ============================================================
global palKeyFn := ""
global palGui := ""   ; the open palette (one at a time — its key hook is global)

ShowPalette() {
    global commandRegistry, palKeyFn, palGui
    ; Already open: bring it forward instead of stacking a second window
    ; (a second one would overwrite palKeyFn and leak the first key hook).
    if palGui != "" {
        try {
            WinActivate("ahk_id " palGui.Hwnd)
            return
        }
        palGui := ""  ; stale (destroyed) — fall through and build a new one
    }
    recentRank := LoadRecentRanks()
    info := GetPaletteInfo()
    palEntries := []
    for label in GetRegisteredCommandNames()  ; alphabetical
        palEntries.Push({label: label, lower: StrLower(label), recent: recentRank.Has(label) ? recentRank[label] : 0
            , info: info.Has(label) ? info[label] : ""})

    pal := Gui("", "Toolbox — Command Palette")
    palGui := pal
    pal.SetFont("s10", "Segoe UI")
    pal.OnEvent("Escape", PalClose)
    pal.OnEvent("Close", PalClose)
    searchEdit := pal.AddEdit("xm w600 h26")
    lv := pal.AddListView("xm y+8 w600 h400 -Multi -LV0x10", ["Command", "Where"])
    lv.OnEvent("DoubleClick", (g, row) => RunPalettePick(pal, lv))
    pal.AddText("xm y+4 cGray", "Type to filter · ↑↓ = move · Enter = run · Esc = close · recent first")

    RefreshPalList() {
        lv.Delete()
        needle := StrLower(Trim(searchEdit.Value))
        matches := []
        for , e in palEntries {
            if needle = "" {
                ; no filter: recents (most recent first), then A-Z
                score := e.recent ? e.recent : 1000
            } else {
                score := PaletteScore(needle, e.lower, e.recent)
                if score < 0
                    continue
            }
            matches.Push({e: e, score: score})
        }
        ; stable insertion sort by score (equal scores keep A-Z order)
        Loop matches.Length - 1 {
            i := A_Index + 1
            m := matches[i]
            j := i - 1
            while j >= 1 && matches[j].score > m.score {
                matches[j + 1] := matches[j]
                j--
            }
            matches[j + 1] := m
        }
        for , m in matches
            lv.Add(, m.e.label, m.e.info)
    }

    PalNav(dir) {
        count := lv.GetCount()
        if count = 0
            return
        row := lv.GetNext(0)
        if row = 0
            row := (dir > 0) ? 1 : count
        else {
            row += dir
            if row < 1
                row := count
            else if row > count
                row := 1
        }
        lv.Modify(0, "-Select")
        lv.Modify(row, "Select Focus Vis")
    }

    PalOnKey(wParam, lParam, msg, hwnd) {
        if hwnd != searchEdit.Hwnd
            return
        switch wParam {
            case 13:
                RunPalettePick(pal, lv)
                return 0
            case 38:
                PalNav(-1)
                return 0
            case 40:
                PalNav(1)
                return 0
        }
    }

    PalClose(*) {
        if palKeyFn != "" {
            OnMessage(0x0100, palKeyFn, 0)
            palKeyFn := ""
        }
        palGui := ""
        pal.Destroy()
    }

    lv.ModifyCol(1, 360), lv.ModifyCol(2, 230)

    DoRefresh(*) {
        RefreshPalList()
        if lv.GetCount() > 0
            lv.Modify(1, "Select Vis")
    }
    searchEdit.OnEvent("Change", DoRefresh)

    RefreshPalList()
    if lv.GetCount() > 0
        lv.Modify(1, "Select Vis")
    ApplyDarkTheme(pal)
    palKeyFn := PalOnKey
    OnMessage(0x0100, palKeyFn)
    pal.Show()
    searchEdit.Focus()
}

RunPalettePick(pal, lv) {
    global commandRegistry, palKeyFn, palGui
    if lv.GetCount() = 0
        return  ; nothing matches the filter — keep the palette open
    row := lv.GetNext(0)
    if row = 0
        row := 1
    label := lv.GetText(row, 1)
    if palKeyFn != "" {
        OnMessage(0x0100, palKeyFn, 0)
        palKeyFn := ""
    }
    palGui := ""
    pal.Destroy()
    if commandRegistry.Has(label)
        RunAndLog(label)
}

; Ranking for one palette entry (needle + hay already lowercase).
; Lower = better, -1 = no match. Base: FuzzyScore gap sum (every needle
; char in order). Bonuses, strongest first: label starts with the needle,
; a word starts with it, it's a contiguous substring, or it matches the
; words' initials ("tw" -> Toggle Wi-Fi). Recent commands (rank 1 = most
; recent of 15) get an extra boost.
PaletteScore(needle, hay, recentRank := 0) {
    base := FuzzyScore(needle, hay)
    if base < 0
        return -1
    score := 1000 + base * 10
    p := InStr(hay, needle)
    if p = 1
        score -= 400
    else if p && RegExMatch(SubStr(hay, p - 1, 1), "[^a-z0-9]")
        score -= 300
    else if p
        score -= 150
    else if InStr(WordInitials(hay), needle) = 1
        score -= 250
    if recentRank
        score -= (16 - recentRank) * 15
    return Max(score, 0)
}

; "Toggle Wi-Fi" -> "twf" (first letter/digit of every word)
WordInitials(s) {
    out := ""
    pos := 1
    while pos := RegExMatch(s, "[a-z0-9]+", &m, pos) {
        out .= SubStr(m[0], 1, 1)
        pos += m.Len
    }
    return out
}

; Recent command label -> rank (1 = most recent)
LoadRecentRanks() {
    global favoritesFile, recentSection, maxRecent
    ranks := Map()
    loop maxRecent {
        v := IniRead(favoritesFile, recentSection, A_Index, "")
        if v != "" && !ranks.Has(v)
            ranks[v] := A_Index
    }
    return ranks
}

; Command label -> "Section · Hotkey · [admin]" for the palette's 2nd column.
; Section and the admin badge come from the menu spec (the display label
; carries "[admin]" only when Toolbox is NOT elevated); hotkeys from the
; built-in [Settings] keys and custom [Hotkeys] targets.
GetPaletteInfo() {
    global sectionSpecs, commandRegistry, favoritesFile
    parts := Map()
    for section, items in sectionSpecs
        for it in items
            if it.kind = "item"
                parts[it.action] := {section: section, hotkey: "", admin: InStr(it.label, "[admin]") > 0}
    for label in commandRegistry {
        if parts.Has(label)
            continue
        sec := SubStr(label, 1, 8) = "Folder: " ? "Folders" : SubStr(label, 1, 6) = "Tool: " ? "Tools" : ""
        parts[label] := {section: sec, hotkey: "", admin: false}
    }
    ; built-in hotkeys that map to a registered command
    for name, target in Map("HotkeyEditNpp", "Open selected in Notepad++", "HotkeyTerminal", "Open terminal at current location") {
        hk := IniRead(favoritesFile, "Settings", name, name = "HotkeyEditNpp" ? "^+e" : "^!t")
        if Trim(hk) != "" && parts.Has(target)
            parts[target].hotkey := HkToFriendly(hk)
    }
    for line in StrSplit(IniRead(favoritesFile, "Hotkeys", , ""), "`n") {
        p := InStr(line, "=")
        if !p
            continue
        target := Trim(SubStr(line, p + 1))
        if parts.Has(target)
            parts[target].hotkey := HkToFriendly(Trim(SubStr(line, 1, p - 1)))
    }
    info := Map()
    for label, x in parts {
        s := x.section
        if x.hotkey != ""
            s .= (s = "" ? "" : "  ·  ") x.hotkey
        if x.admin
            s .= (s = "" ? "" : "  ·  ") "[admin]"
        info[label] := s
    }
    return info
}

RunLastCommand() {
    global favoritesFile, recentSection
    last := IniRead(favoritesFile, recentSection, 1, "")
    if last = "" {
        Notify("No recent commands yet.", 2000)
        return
    }
    RunAndLog(last)
}
