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

    g := Gui("+Resize", "Toolbox — Menu Editor")
    g.MarginX := 12, g.MarginY := 12
    g.SetFont("s9", "Segoe UI")
    g.AddText("Section:")
    ddlSection := g.AddDDL("xp+70 yp w180 Choose1", sectionOrder)
    g.AddText("xm y+8", "Items (select a row to edit):")
    lv := g.AddListView("xm y+4 w620 h260 NoSortHdr", ["Label", "Action"])
    lv.ModifyCol(1, 300), lv.ModifyCol(2, 300)

    g.AddText("xm y+10 Section", "Label:")
    edLabel := g.AddEdit("yp x+8 w300")
    g.AddText("x330 ys Section", "Target:")
    cbTarget := g.AddComboBox("xp+70 yp w220", GetRegisteredCommandNames())
    g.AddButton("xp+230 yp w70", "Browse...").OnEvent("Click", (*) => BrowseMenuTarget(cbTarget))
    g.AddText("xm y+6 w620", "Target = menu command (dropdown), file/exe (Browse), or raw command line. Blank label + target = new item.")

    btnUp := g.AddButton("xm y+10 w70", "Up")
    btnDown := g.AddButton("xp+80 wp", "Down")
    btnDel := g.AddButton("xp+80 wp", "Remove")
    btnAdd := g.AddButton("xp+80 wp", "Add")
    btnUpd := g.AddButton("xp+80 wp", "Update")
    btnReset := g.AddButton("xp+80 wp", "Reset section")
    btnSave := g.AddButton("xp+90 w120 Default", "Save && Rebuild")
    g.AddButton("xp+130 w80", "Close").OnEvent("Click", (*) => g.Destroy())

    btnUp.OnEvent("Click", (*) => MoveItem(-1))
    btnDown.OnEvent("Click", (*) => MoveItem(1))
    btnDel.OnEvent("Click", (*) => RemoveItem())
    btnAdd.OnEvent("Click", (*) => AddItem())
    btnUpd.OnEvent("Click", (*) => UpdateItem())
    btnReset.OnEvent("Click", (*) => ResetSection())
    btnSave.OnEvent("Click", (*) => SaveAndRebuild())
    ddlSection.OnEvent("Change", (*) => SwitchSection())
    lv.OnEvent("Click", (ctl, row) => LoadRow(row))
    lv.OnEvent("DoubleClick", (ctl, row) => LoadRow(row))
    g.OnEvent("Escape", (*) => g.Destroy())
    ApplyDarkTheme(g, THEME_BG)
    DarkComboBox(cbTarget)

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
        cbTarget.Text := (SubStr(it.action, 1, 4) = "run:") ? SubStr(it.action, 5) : it.action
    }

    ; parse fields into an item ("" target invalid)
    ItemFromFields() {
        label := Trim(edLabel.Value), target := Trim(cbTarget.Text)
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
    g.Show()
}

BrowseMenuTarget(cbTarget) {
    f := FileSelect(1, , "Pick program or file to launch", "Programs and files (*.exe; *.bat; *.cmd; *.ps1; *.lnk; *.msc; *.cpl)|*.exe;*.bat;*.cmd;*.ps1;*.lnk;*.msc;*.cpl|All files (*.*)|*.*")
    if f != ""
        cbTarget.Text := '"' f '"'
}
