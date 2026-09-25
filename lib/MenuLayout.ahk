; ============================================================
; DYNAMIC MENU LAYOUT — menu sections are data-driven.
; BuildMenus() records default items into sectionSpecs (via
; SpecAdd/SpecSep/SpecSub), then BuildSectionMenus() renders
; real Menu objects from the user's saved layout (INI [Menu]).
; INI [Menu] keys:  Section~n = value
;   value:  "-"                separator
;           "Label"            item (action = same label in commandRegistry)
;           "Label|Action"     item with different registry action label
;           "Label|run:cmd"    item running a raw command line
;           "Label|@"          dynamic submenu (tool suites, custom folders)
; A section absent from [Menu] uses the default order.
; ============================================================

global sectionOrder := ["Files", "Networking", "Folders", "System", "Clipboard", "Tools"]
global sectionSpecs := Map()   ; section -> array of {kind, label, action}
global sectionMenus := Map()   ; section -> rendered Menu (runtime)
global gSubMenus := Map()      ; "Section|Label" -> Menu object (rebuilt each build)

SpecReset() {
    global sectionSpecs, gSubMenus
    sectionSpecs := Map()
    gSubMenus := Map()
}

SpecAdd(section, displayLabel, actionLabel, cb) {
    global sectionSpecs, commandRegistry
    commandRegistry[actionLabel] := cb  ; keep registry for palette/recents/hotkeys
    if !sectionSpecs.Has(section)
        sectionSpecs[section] := []
    sectionSpecs[section].Push({kind: "item", label: displayLabel, action: actionLabel})
}

SpecSep(section) {
    global sectionSpecs
    if !sectionSpecs.Has(section)
        sectionSpecs[section] := []
    sectionSpecs[section].Push({kind: "sep", label: "", action: ""})
}

SpecSub(section, label, menuObj) {
    global sectionSpecs, gSubMenus
    if !sectionSpecs.Has(section)
        sectionSpecs[section] := []
    sectionSpecs[section].Push({kind: "sub", label: label, action: "@"})
    gSubMenus[section "|" label] := menuObj
}

; Default items for a section (recorded by BuildMenus at startup)
GetDefaultItems(section) {
    global sectionSpecs
    return sectionSpecs.Has(section) ? sectionSpecs[section] : []
}

; User layout if saved in INI, else defaults
GetLayoutItems(section) {
    global favoritesFile
    defaults := GetDefaultItems(section)
    if !FileExist(favoritesFile)
        return defaults
    vals := []
    loop 500 {
        v := IniRead(favoritesFile, "Menu", section "~" A_Index, "#MISSING#")
        if v = "#MISSING#"
            break
        vals.Push(v)
    }
    if vals.Length = 0
        return defaults
    items := []
    for v in vals {
        v := Trim(v)
        if v = ""
            continue
        if v = "-" {
            items.Push({kind: "sep", label: "", action: ""})
            continue
        }
        p := InStr(v, "|")
        label := p ? Trim(SubStr(v, 1, p - 1)) : v
        action := p ? Trim(SubStr(v, p + 1)) : label
        if label = ""
            continue
        items.Push({kind: (action = "@") ? "sub" : "item", label: label, action: action})
    }
    return items
}

; Render all section menus from layout. Call after BuildMenus recorded specs.
BuildSectionMenus() {
    global sectionOrder, sectionMenus
    sectionMenus := Map()
    for section in sectionOrder {
        m := Menu()
        for it in GetLayoutItems(section) {
            if it.kind = "sep"
                m.Add()
            else if it.kind = "sub"
                AddSubIfPresent(m, section, it.label)
            else
                AddMenuAction(m, section, it.label, it.action)
        }
        sectionMenus[section] := m
    }
}

AddSubIfPresent(m, section, label) {
    global gSubMenus
    key := section "|" label
    if gSubMenus.Has(key)
        m.Add(label, gSubMenus[key])
}

; Resolve one item's action: registry label or "run:" raw command
AddMenuAction(m, section, label, action) {
    global commandRegistry
    if SubStr(action, 1, 4) = "run:" {
        m.Add(label, CreateRawRunner(label, SubStr(action, 5)))
        return
    }
    if commandRegistry.Has(action)
        m.Add(label, CreateRecentCallback(action))
}

; Closure-safe runner for raw command lines (used by layout + editor)
CreateRawRunner(label, cmd) {
    return (*) => MenuRunRaw(label, cmd)
}

MenuRunRaw(label, cmd) {
    LogCommand(label)
    try
        Run(cmd)
    catch as err
        MsgBox("Command failed:`n`n" cmd "`n`n" err.Message, "Toolbox", 48)
}

; Save full layout: models = Map(section -> items array). Sections absent
; from models are left unwritten (fall back to defaults next build).
SaveMenuLayout(models) {
    global favoritesFile
    if !FileExist(favoritesFile)
        return
    IniDelete(favoritesFile, "Menu")
    for section, items in models {
        n := 0
        for it in items {
            n++
            IniWrite(LayoutValue(it), favoritesFile, "Menu", section "~" n)
        }
    }
}

; Serialize items to INI values
LayoutValue(it) {
    if it.kind = "sep"
        return "-"
    if it.kind = "sub"
        return it.label "|@"
    return (it.action = it.label) ? it.label : it.label "|" it.action
}
