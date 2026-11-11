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

; Stable identity of a layout item: action label for items, "@Label" for
; submenus, "" for separators (no identity — never merged).
LayoutKey(it) {
    if it.kind = "sub"
        return "@" it.label
    if it.kind = "item"
        return it.action
    return ""
}

; [MenuKnown] Section~n = keys of the default items that existed when the
; section's layout was saved. A default missing from both the saved layout
; and this list is NEW since the save (app update, newly installed tool
; suite) and gets merged in; one in the list but absent from the layout was
; removed on purpose and stays hidden.
ReadKnownKeys(section) {
    global favoritesFile
    known := Map()
    loop 500 {
        v := IniRead(favoritesFile, "MenuKnown", section "~" A_Index, "#MISSING#")
        if v = "#MISSING#"
            break
        known[v] := true
    }
    return known
}

WriteKnownKeys(section) {
    global favoritesFile
    n := 0
    for it in GetDefaultItems(section) {
        k := LayoutKey(it)
        if k = ""
            continue
        n++
        IniWrite(k, favoritesFile, "MenuKnown", section "~" n)
    }
}

; Insert defaults that are new since the layout was saved, each right after
; the nearest preceding default that is present in the layout.
MergeNewDefaults(section, items, defaults) {
    known := ReadKnownKeys(section)
    if known.Count = 0 {
        ; layout saved before [MenuKnown] existed: we can't tell new from
        ; removed, so baseline today's defaults — later additions will merge.
        WriteKnownKeys(section)
        return items
    }
    present := Map()
    for it in items {
        k := LayoutKey(it)
        if k != ""
            present[k] := true
    }
    prevKey := ""
    for d in defaults {
        k := LayoutKey(d)
        if k = ""
            continue
        if !present.Has(k) && !known.Has(k) {
            insertAt := 1
            if prevKey != "" {
                for i, it in items {
                    if LayoutKey(it) = prevKey {
                        insertAt := i + 1
                        break
                    }
                }
            }
            items.InsertAt(insertAt, {kind: d.kind, label: d.label, action: d.action})
            present[k] := true
        }
        if present.Has(k)
            prevKey := k
    }
    return items
}

; User layout if saved in INI (plus any defaults added since), else defaults
GetLayoutItems(section) {
    global favoritesFile
    ; action labels renamed when the "\\" typos were fixed (AHK has no
    ; backslash escapes, so "\\" was two backslashes) — keep old layouts working
    static legacyActions := Map("AppData\\Roaming", "AppData\Roaming", "AppData\\Local", "AppData\Local")
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
        if legacyActions.Has(action) {
            action := legacyActions[action]
            label := StrReplace(label, "\\", "\")
        }
        items.Push({kind: (action = "@") ? "sub" : "item", label: label, action: action})
    }
    return MergeNewDefaults(section, items, defaults)
}

; Render all section menus from layout. Call after BuildMenus recorded specs.
BuildSectionMenus() {
    global sectionOrder, sectionMenus
    sectionMenus := Map()
    for section in sectionOrder {
        m := Menu()
        seen := Map()
        for it in GetLayoutItems(section) {
            if it.kind = "sep" {
                m.Add()
                continue
            }
            label := it.label
            ; Menu.Add throws on duplicate names — make unique
            if seen.Has(label) {
                i := 2
                while seen.Has(label " (" i ")")
                    i++
                label .= " (" i ")"
            }
            seen[label] := true
            if it.kind = "sub"
                AddSubIfPresent(m, section, label)
            else
                AddMenuAction(m, section, label, it.action)
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
    IniDelete(favoritesFile, "MenuKnown")
    for section, items in models {
        n := 0
        for it in items {
            n++
            IniWrite(LayoutValue(it), favoritesFile, "Menu", section "~" n)
        }
        WriteKnownKeys(section)  ; defaults seen at save time (see MergeNewDefaults)
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
