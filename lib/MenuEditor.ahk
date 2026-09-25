; ============================================================
; MENU EDITOR GUI — reorder/remove/rename/add items in any menu
; section. Edits the layout saved in INI [Menu] (see MenuLayout.ahk).
; "Reset section" clears the section's saved layout (back to the
; app defaults). Save & Rebuild rewrites the INI and rebuilds the
; tray + main menus live.
; ============================================================

ShowMenuEditor() {
    global sectionOrder, gSubMenus, commandRegistry, THEME_BG

    ; working model: section -> array of {kind, label, action}
    allModels := Map()
    for sec in sectionOrder {
        copy := []
        for it in GetLayoutItems(sec)
            copy.Push({kind: it.kind, label: it.label, action: it.action})
        allModels[sec] := copy
    }

    g := Gui(, "Toolbox — Menu Editor")
    g.MarginX := 12, g.MarginY := 12
    g.SetFont("s9", "Segoe UI")
    if FileExist(A_ScriptDir "\icons\toolbox.ico")
        SetWindowIcon(g, A_ScriptDir "\icons\toolbox.ico")
    g.AddText("x12 y16", "Section:")
    ddlSection := g.AddDDL("x72 y12 w200 Choose1", sectionOrder)
    g.AddText("x12 y48", "Items (select a row to edit):")
    lv := g.AddListView("x12 y66 w430 h250 NoSortHdr", ["Label", "Action"])
    lv.ModifyCol(1, 200), lv.ModifyCol(2, 210)

    ; right column: target search — edit + always-visible filtered list
    g.AddText("x452 y48", "Target (type to filter):")
    allTargets := GetRegisteredCommandNames()
    edTarget := g.AddEdit("x452 y66 w230")
    lbTargets := g.AddListBox("x452 y+4 w230 h210")
    edTarget.OnEvent("Change", (*) => FilterTargets())
    lbTargets.OnEvent("DoubleClick", (ctl, row) => PickTarget(row))
    g.AddButton("x690 y65 w80", "Browse...").OnEvent("Click", (*) => BrowseMenuTarget(edTarget))

    g.AddText("x12 y330", "Label:")
    edLabel := g.AddEdit("x60 y326 w610")
    g.AddText("x12 y364 w640", "Target = menu command (list above, double-click), file/exe (Browse), or raw command line. Blank label + target = new item.")

    btnUp := g.AddButton("x12 y396 w80", "Up")
    btnDown := g.AddButton("x98 y396 w80", "Down")
    btnDel := g.AddButton("x184 y396 w80", "Remove")
    btnAdd := g.AddButton("x270 y396 w80", "Add")
    btnUpd := g.AddButton("x356 y396 w80", "Update")
    btnSep := g.AddButton("x442 y396 w80", "Add sep")
    btnReset := g.AddButton("x528 y396 w95", "Reset section")
    btnSave := g.AddButton("x630 y396 w115 Default", "Save && Rebuild")
    g.AddButton("x755 y396 w80", "Close").OnEvent("Click", (*) => g.Destroy())

    btnUp.OnEvent("Click", (*) => MoveItem(-1))
    btnDown.OnEvent("Click", (*) => MoveItem(1))
    btnDel.OnEvent("Click", (*) => RemoveItem())
    btnAdd.OnEvent("Click", (*) => AddItem())
    btnUpd.OnEvent("Click", (*) => UpdateItem())
    btnSep.OnEvent("Click", (*) => AddSeparator())
    btnReset.OnEvent("Click", (*) => ResetSection())
    btnSave.OnEvent("Click", (*) => SaveAndRebuild())
    ddlSection.OnEvent("Change", (*) => SwitchSection())
    lv.OnEvent("Click", (ctl, row) => LoadRow(row))
    lv.OnEvent("DoubleClick", (ctl, row) => LoadRow(row))
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

    LoadSection(sec) {
        lv.Delete()
        for it in allModels[sec] {
            if it.kind = "sep"
                lv.Add("", "— separator —", "")
            else if it.kind = "sub"
                lv.Add("", it.label, "@ submenu")
            else if (SubStr(it.action, 1, 4) = "run:")
                lv.Add("", it.label, it.action)
            else
                lv.Add("", it.label, it.action)
        }
    }

    SwitchSection() {
        sec := ddlSection.Text
        if !allModels.Has(sec)
            return
        LoadSection(sec)
    }

    LoadRow(row) {
        if !row || row > allModels[ddlSection.Text].Length
            return
        it := allModels[ddlSection.Text][row]
        if it.kind = "sep"
            return
        edLabel.Value := it.label
        edTarget.Value := (SubStr(it.action, 1, 4) = "run:") ? SubStr(it.action, 5) : it.action
        FilterTargets()
    }

    ; parse fields into an item ("" target invalid)
    ItemFromFields() {
        label := Trim(edLabel.Value), target := Trim(edTarget.Value)
        if target = ""
            return ""
        if label = ""
            label := target
        if commandRegistry.Has(target)
            action := target
        else if SubStr(target, 1, 4) = "run:"
            action := target
        else
            action := "run:" target
        return {kind: "item", label: label, action: action}
    }

    AddItem() {
        it := ItemFromFields()
        if !it {
            ToolTip("Target is required.")
            SetTimer(() => ToolTip(), -3000)
            return
        }
        sec := ddlSection.Text
        row := lv.GetNext()
        pos := row ? row + 1 : allModels[sec].Length + 1
        allModels[sec].InsertAt(pos, it)
        LoadSection(sec)
        lv.Modify(pos, "Select")
    }

    AddSeparator() {
        sec := ddlSection.Text
        row := lv.GetNext()
        pos := row ? row + 1 : allModels[sec].Length + 1
        allModels[sec].InsertAt(pos, {kind: "sep", label: "", action: ""})
        LoadSection(sec)
        lv.Modify(pos, "Select")
    }

    UpdateItem() {
        row := lv.GetNext()
        it := ItemFromFields()
        if !row || !it {
            ToolTip("Select a row and fill in the fields.")
            SetTimer(() => ToolTip(), -3000)
            return
        }
        allModels[ddlSection.Text][row] := it
        LoadSection(ddlSection.Text)
        lv.Modify(row, "Select")
    }

    RemoveItem() {
        row := lv.GetNext()
        sec := ddlSection.Text
        if !row || row > allModels[sec].Length
            return
        if allModels[sec][row].kind = "sep" || MsgBox("Remove '" allModels[sec][row].label "'?", "Menu Editor", 33) = "OK"
            allModels[sec].RemoveAt(row)
        LoadSection(sec)
    }

    MoveItem(dir) {
        sec := ddlSection.Text
        row := lv.GetNext()
        n := allModels[sec].Length
        if !row || row > n
            return
        tgt := row + dir
        if tgt < 1 || tgt > n
            return
        items := allModels[sec]
        tmp := items[row], items[row] := items[tgt], items[tgt] := tmp
        LoadSection(sec)
        lv.Modify(tgt, "Select")
    }

    ResetSection() {
        sec := ddlSection.Text
        allModels[sec] := []
        for it in GetDefaultItems(sec)
            allModels[sec].Push({kind: it.kind, label: it.label, action: it.action})
        LoadSection(sec)
        ToolTip("Section reset to app defaults (save to apply).")
        SetTimer(() => ToolTip(), -3000)
    }

    SaveAndRebuild() {
        global favoritesFile
        SaveMenuLayout(allModels)
        g.Destroy()
        BuildMenus()
        FlushMenuThemes()
        ToolTip("Menu layout saved & rebuilt.")
        SetTimer(() => ToolTip(), -3000)
    }

    LoadSection(sectionOrder[1])
    FilterTargets()
    g.Show()
}

BrowseMenuTarget(edTarget) {
    f := FileSelect(1, , "Pick program or file to launch", "Programs and files (*.exe; *.bat; *.cmd; *.ps1; *.lnk; *.msc; *.cpl)|*.exe;*.bat;*.cmd;*.ps1;*.lnk;*.msc;*.cpl|All files (*.*)|*.*")
    if f != ""
        edTarget.Value := '"' f '"'
}
