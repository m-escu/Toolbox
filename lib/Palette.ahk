; ============================================================
; COMMAND PALETTE (Ctrl+Shift+P) — fuzzy search over commandRegistry
; ============================================================
global palKeyFn := ""

ShowPalette() {
    global commandRegistry, palKeyFn
    palEntries := []
    for label, cb in commandRegistry
        palEntries.Push({label: label, cb: cb})

    pal := Gui("", "Toolbox — Command Palette")
    pal.SetFont("s10", "Segoe UI")
    pal.OnEvent("Escape", PalClose)
    pal.OnEvent("Close", PalClose)
    searchEdit := pal.AddEdit("xm w500 h26")
    lv := pal.AddListView("xm y+8 w500 h400 -Multi -LV0x10", ["Command"])
    lv.OnEvent("DoubleClick", (g, row) => RunPalettePick(pal, lv))
    pal.AddText("xm y+4 cGray", "Type to filter · ↑↓ = move · Enter = run · Esc = close")

    RefreshPalList() {
        lv.Delete()
        needle := StrLower(Trim(searchEdit.Value))
        if needle = "" {
            for , e in palEntries
                lv.Add(, e.label)
            return
        }
        matches := []
        for , e in palEntries {
            score := FuzzyScore(needle, StrLower(e.label))
            if score >= 0
                matches.Push({label: e.label, score: score})
        }
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
            lv.Add(, m.label)
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
        pal.Destroy()
    }

    lv.ModifyCol(1, 490)

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
    global commandRegistry, palKeyFn
    row := lv.GetNext(0)
    if row = 0
        row := 1
    label := lv.GetText(row, 1)
    if palKeyFn != "" {
        OnMessage(0x0100, palKeyFn, 0)
        palKeyFn := ""
    }
    pal.Destroy()
    if commandRegistry.Has(label)
        RunAndLog(label)
}

RunLastCommand() {
    global favoritesFile, recentSection
    last := IniRead(favoritesFile, recentSection, 1, "")
    if last = "" {
        ToolTip("No recent commands yet.")
        SetTimer(() => ToolTip(), -2000)
        return
    }
    RunAndLog(last)
}
