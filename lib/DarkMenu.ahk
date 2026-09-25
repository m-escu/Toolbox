; ============================================================
; DARK MENUS — theme tray/popup menus to match system dark mode
; Uses undocumented uxtheme.dll ordinals (SetPreferredAppMode=135,
; FlushMenuThemes=136). Windows 10 1809+ / Windows 11.
; Original technique by DepthTrawler (reddit).
; ============================================================

EnableDarkMenus(mode := "AllowDark") {
    SetPreferredAppMode(mode)
}

SetPreferredAppMode(option := "AllowDark") {
    static modes := Map(
        "DEFAULT", 0,     ; standard light
        "ALLOWDARK", 1,   ; dark when system app mode is dark
        "FORCEDARK", 2,
        "FORCELIGHT", 3,
        "MAX", 4
    )
    option := StrUpper(option)
    if !modes.Has(option)
        option := "ALLOWDARK"
    hModule := DllCall("kernel32.dll\GetModuleHandle", "str", "uxtheme.dll", "ptr")
    fn := DllCall("kernel32.dll\GetProcAddress", "ptr", hModule, "ptr", 135, "ptr")
    DllCall(fn, "int", modes[option])
}

FlushMenuThemes() {
    hModule := DllCall("kernel32.dll\GetModuleHandle", "str", "uxtheme.dll", "ptr")
    fn := DllCall("kernel32.dll\GetProcAddress", "ptr", hModule, "ptr", 136, "ptr")
    DllCall(fn)
}
