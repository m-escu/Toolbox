; ============================================================
; HOTKEY EDITOR GUI — view/edit/disable hotkeys, add custom ones
; Custom hotkeys live in INI [Hotkeys] as  Hotkey=Target  where
; Target is either a registered command label or a raw command line.
; Built-in hotkeys stay in [Settings] (HotkeyMenu etc.); an empty
; value disables that hotkey.
; Hotkeys are shown in friendly form (Ctrl+Alt+T); INI keeps the
; AHK syntax (^!t). Both forms are accepted as input.
; ============================================================

ShowHotkeyEditor() {
    global favoritesFile, commandRegistry, THEME_BG
    builtinDefs := [
        ["HotkeyMenu", "^+m", "Main command menu"],
        ["HotkeyPalette", "^+p", "Command palette"],
        ["HotkeyRerun", "^+r", "Re-run last command"],
        ["HotkeyEditNpp", "^+e", "Open selected in Notepad++"],
        ["HotkeyTerminal", "^!t", "Open terminal here"]
    ]
    rows := []  ; {name, hk (raw), target, builtin}
    for def in builtinDefs
        rows.Push({name: def[1], hk: IniRead(favoritesFile, "Settings", def[1], def[2]), target: def[3], builtin: true})
    section := IniRead(favoritesFile, "Hotkeys", , "")
    for line in StrSplit(section, "`n") {
        p := InStr(line, "=")
        if !p
            continue
        hk := Trim(SubStr(line, 1, p - 1))
        target := Trim(SubStr(line, p + 1))
        if hk != "" && target != ""
            rows.Push({name: "", hk: hk, target: target, builtin: false})
    }

    g := Gui(, "Toolbox — Hotkey Editor")
    g.MarginX := 12, g.MarginY := 12
    g.SetFont("s9", "Segoe UI")
    SetWindowIcon(g, A_ScriptDir "\icons\toolbox.ico")
    lv := g.AddListView("w560 h280 NoSortHdr", ["Hotkey", "Target"])
    for r in rows
        lv.Add("", HkToFriendly(r.hk), r.target)
    lv.ModifyCol(1, 150), lv.ModifyCol(2, 390)
    g.AddText("ym x590 Section", "Hotkey (e.g. Ctrl+Alt+G):")
    edHK := g.AddEdit("ys w190")
    g.AddText("xs Section", "Target (type to filter):")
    allTargets := GetRegisteredCommandNames()
    edTarget := g.AddEdit("xp y+4 w270")
    lbTargets := g.AddListBox("xp y+4 w270 r8")
    edTarget.OnEvent("Change", (*) => FilterTargets())
    lbTargets.OnEvent("DoubleClick", (ctl, row) => PickTarget(row))
    g.AddButton("xp+280 yp w60", "Browse...").OnEvent("Click", (*) => BrowseTarget())
    g.AddText("xs w480", "Target = a command from the list (double-click), a file/exe picked via Browse, or any raw command line.")
    btnAdd := g.AddButton("xm ym+300 w110", "Add / Update")
    btnDel := g.AddButton("xp+120 wp", "Delete")
    btnDel.OnEvent("Click", (*) => DeleteSelected())
    btnAdd.OnEvent("Click", (*) => AddOrUpdate())
    btnSave := g.AddButton("xp+130 w130 Default", "Save && Apply")
    btnSave.OnEvent("Click", (*) => SaveAndApply())
    g.AddButton("xp+140 w80", "Cancel").OnEvent("Click", (*) => g.Destroy())
    lv.OnEvent("DoubleClick", (ctl, row) => LoadRow(row))
    lv.OnEvent("Click", (ctl, row) => LoadRow(row))
    g.OnEvent("Escape", (*) => g.Destroy())
    ApplyDarkTheme(g, THEME_BG)

    ; type-to-filter over registered commands; free text stays free
    FilterTargets() {
        q := edTarget.Value
        lbTargets.Delete()
        for name in allTargets
            if (q = "" || InStr(name, q))  ; case-insensitive substring match
                lbTargets.Add([name])
    }

    PickTarget(row) {
        if row
            edTarget.Value := lbTargets.Text
    }

    LoadRow(row) {
        if !row
            return
        edHK.Value := lv.GetText(row, 1)
        edTarget.Value := lv.GetText(row, 2)
        FilterTargets()
    }

    BrowseTarget() {
        f := FileSelect(1, , "Pick program or file to launch", "Programs and files (*.exe; *.bat; *.cmd; *.ps1; *.lnk; *.msc; *.cpl)|*.exe;*.bat;*.cmd;*.ps1;*.lnk;*.msc;*.cpl|All files (*.*)|*.*")
        if f = ""
            return
        edTarget.Value := '"' f '"'
    }

    AddOrUpdate() {
        hk := Trim(edHK.Value), target := Trim(edTarget.Value)
        if hk = "" || target = "" {
            ToolTip("Both hotkey and target are required.")
            SetTimer(() => ToolTip(), -3000)
            return
        }
        if FriendlyToHk(hk) = "" {
            ToolTip("Cannot parse hotkey: " hk)
            SetTimer(() => ToolTip(), -4000)
            return
        }
        ; update in place if this hotkey already listed
        loop lv.GetCount() {
            if HkToFriendly(FriendlyToHk(lv.GetText(A_Index, 1))) = HkToFriendly(FriendlyToHk(hk)) {
                lv.Modify(A_Index, "", HkToFriendly(FriendlyToHk(hk)), target)
                return
            }
        }
        lv.Add("", HkToFriendly(FriendlyToHk(hk)), target)
    }

    DeleteSelected() {
        row := lv.GetNext()
        if row
            lv.Delete(row)
    }

    SaveAndApply() {
        global favoritesFile
        ; collect rows back into arrays
        newBuiltins := Map(), customs := []
        for name in ["HotkeyMenu", "HotkeyPalette", "HotkeyRerun", "HotkeyEditNpp", "HotkeyTerminal"]
            newBuiltins[name] := ""
        loop lv.GetCount() {
            hk := FriendlyToHk(Trim(lv.GetText(A_Index, 1))), target := lv.GetText(A_Index, 2)
            if hk = ""
                continue
            matched := false
            for name, label in { HotkeyMenu: "Main command menu", HotkeyPalette: "Command palette"
                , HotkeyRerun: "Re-run last command", HotkeyEditNpp: "Open selected in Notepad++"
                , HotkeyTerminal: "Open terminal here" } {
                if target = label {
                    newBuiltins[name] := hk, matched := true
                    break
                }
            }
            if !matched
                customs.Push({hk: hk, target: target})
        }
        ; duplicate check
        seen := Map()
        for name, hk in newBuiltins {
            if hk = ""
                continue
            if seen.Has(hk)
                return MsgBox("Hotkey '" HkToFriendly(hk) "' is assigned more than once.", "Hotkey Editor", 48)
            seen[hk] := true
        }
        for c in customs {
            if seen.Has(c.hk)
                return MsgBox("Hotkey '" HkToFriendly(c.hk) "' is assigned more than once.", "Hotkey Editor", 48)
            seen[c.hk] := true
        }
        for name, hk in newBuiltins
            IniWrite(hk, favoritesFile, "Settings", name)
        IniDelete(favoritesFile, "Hotkeys")
        for c in customs
            IniWrite(c.target, favoritesFile, "Hotkeys", c.hk)
        g.Destroy()
        ApplyHotkeys()
        ToolTip("Hotkeys saved & applied.")
        SetTimer(() => ToolTip(), -3000)
    }

    g.Show()
}

; Sorted list of registered command labels for the target dropdown
GetRegisteredCommandNames() {
    global commandRegistry
    names := []
    for label in commandRegistry  ; Map iteration yields keys (command labels)
        names.Push(label)
    ; insertion sort (Array has no built-in Sort)
    i := 1
    while i < names.Length {
        j := i
        while j > 0 && StrCompare(names[j], names[j + 1]) > 0 {
            tmp := names[j], names[j] := names[j + 1], names[j + 1] := tmp
            j--
        }
        i++
    }
    return names
}

; Dark-theme the dropdown list + edit part of a ComboBox (ApplyDarkTheme
; only styles the closed control; the dropped list stays light otherwise).
; AHK hotkey syntax (^!t) -> friendly display (Ctrl+Alt+T)
HkToFriendly(hk) {
    hk := Trim(hk)
    if hk = ""
        return ""
    mods := ""
    key := hk
    while key != "" {
        c := SubStr(key, 1, 1)
        if c = "^"
            mods .= "Ctrl+", key := SubStr(key, 2)
        else if c = "!"
            mods .= "Alt+", key := SubStr(key, 2)
        else if c = "+"
            mods .= "Shift+", key := SubStr(key, 2)
        else if c = "#"
            mods .= "Win+", key := SubStr(key, 2)
        else if (c = "<" || c = ">") && InStr("^!+#", SubStr(key, 2, 1)) && SubStr(key, 2, 1) != "" {
            nx := SubStr(key, 2, 1)
            mods .= (c = "<" ? "Left" : "Right") (nx = "^" ? "Ctrl+" : nx = "!" ? "Alt+" : nx = "+" ? "Shift+" : "Win+")
            key := SubStr(key, 3)
        } else
            break
    }
    if key = ""
        return mods . "?"  ; malformed — show what we have
    ; pretty-print key name: single letters/digits upper, known names capitalized
    static named := Map("enter", "Enter", "esc", "Esc", "tab", "Tab", "space", "Space"
        , "backspace", "Backspace", "delete", "Delete", "insert", "Insert", "home", "Home"
        , "end", "End", "pgup", "PgUp", "pgdn", "PgDn", "up", "Up", "down", "Down"
        , "left", "Left", "right", "Right", "capslock", "CapsLock", "numpad0", "Numpad0")
    lk := StrLower(key)
    if named.Has(lk)
        keyName := named[lk]
    else if StrLen(key) = 1
        keyName := StrUpper(key)
    else
        keyName := SubStr(key, 1, 1) SubStr(key, 2)  ; F5, NumpadAdd keep as typed
    return mods keyName
}

; Friendly (Ctrl+Alt+T) or raw (^!t) -> raw AHK syntax. "" if unparsable.
FriendlyToHk(s) {
    s := Trim(s)
    if s = ""
        return ""
    if !InStr(s, "+") || StrLen(s) <= 1  ; raw AHK syntax passed through
        return s
    mods := ""
    key := ""
    for part in StrSplit(s, "+") {
        part := Trim(part)
        if part = ""
            return ""
        p := StrLower(part)
        if p = "ctrl" || p = "control"
            mods .= "^"
        else if p = "alt"
            mods .= "!"
        else if p = "shift"
            mods .= "+"
        else if p = "win" || p = "windows"
            mods .= "#"
        else
            key := part
    }
    if key = ""
        return ""
    return mods key
}
