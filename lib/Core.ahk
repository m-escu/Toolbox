; ============================================================
; SHARED UTILITIES: run & capture, show output, pick menus, temp PS
; ============================================================

; Run a console command, capture stdout. Blocks until the command finishes
; (no timeout — a blocking read is the only deadlock-safe option here).
; StdOut is read FIRST: StdErr.ReadAll() blocks until process exit, so draining
; it while the process is alive deadlocks both sides once the stdout pipe fills.
RunCapture(cmd) {
    output := ""
    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec(cmd)
        output := exec.StdOut.ReadAll()   ; blocks until stdout EOF (process exit)
        errOut := ""
        try errOut := exec.StdErr.ReadAll()
        if Trim(output) = "" && Trim(errOut) != ""
            output := errOut
    } catch as err {
        output := "Error: " err.Message
    }
    return output
}

; Show text output in a temp file opened in N++ (or notepad)
ShowText(title, text) {
    safeName := RegExReplace(title, "[^A-Za-z0-9_-]", "_")
    tmpFile := A_Temp "\toolbox_" safeName ".txt"
    header := title " — " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n`n"
    Try FileDelete(tmpFile)
    FileAppend(header text, tmpFile, "UTF-8")
    if FileExist(nppPath)
        Run('"' nppPath '" "' tmpFile '"')
    else
        Run('notepad.exe "' tmpFile '"')
}

; Write a PS script to a temp file (no BOM — PS chokes on BOM) and return its path
WriteTempPs(name, content) {
    tmpPs := A_Temp "\" name
    Try FileDelete(tmpPs)
    FileAppend(content, tmpPs, "UTF-8-RAW")
    return tmpPs
}

; Remove leftover toolbox_* temp files from previous runs
CleanupOldTemp() {
    Loop Files A_Temp "\toolbox_*.*"
        Try FileDelete(A_LoopFilePath)
}

; Run a temp PS script in a visible window (cleanup happens on next Toolbox start).
; noExit=true keeps the window open even if the script crashes (errors stay readable).
RunTempPsVisible(tmpPs, workDir := "", noExit := false) {
    flag := noExit ? " -NoExit" : ""
    Run('powershell -NoProfile -ExecutionPolicy Bypass' flag ' -File "' tmpPs '"', workDir)
}

; Show a popup menu of items; calls onPick(item) with the chosen string.
; Returns nothing (async) — caller logic goes in the onPick closure.
ShowPickMenu(items, onPick) {
    if items.Length = 0
        return
    m := Menu()
    for , item in items
        m.Add(StrReplace(item, "&", "&&"), CreatePickCallback(item, onPick))  ; escape & for display only
    m.Show()
}

; Closure-safe callback for ShowPickMenu
CreatePickCallback(item, onPick) {
    return (*) => onPick(item)
}

; --- IPv4 helpers (subnet calculator) ---
IpToInt(ip) {
    parts := StrSplit(ip, ".")
    if parts.Length != 4
        return -1
    n := 0
    for , p in parts {
        if !RegExMatch(p, "^\d+$") || Integer(p) > 255
            return -1
        n := n * 256 + Integer(p)
    }
    return n
}

IntToIp(n) {
    return (n >> 24 & 255) "." (n >> 16 & 255) "." (n >> 8 & 255) "." (n & 255)
}

; Mask from CIDR (/24 → 255.255.255.0). Accepts dotted mask or /N. Returns -1 on bad input.
ParseMask(maskStr) {
    maskStr := Trim(maskStr)
    if RegExMatch(maskStr, "^/(\d{1,2})$", &m)
        maskStr := m[1]
    if RegExMatch(maskStr, "^\d{1,2}$") {
        bits := Integer(maskStr)
        if bits < 0 || bits > 32
            return -1
        if bits = 0
            return 0
        return (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF
    }
    return IpToInt(maskStr)
}

; ============================================================
; SNIPPET EXPANSION (INI [Snippets], format: SnippetN=trigger|expansion)
; ============================================================
LoadSnippets() {
    if !FileExist(favoritesFile)
        return
    loop 100 {
        val := IniRead(favoritesFile, "Snippets", "Snippet" A_Index, "")
        if val = ""
            continue
        parts := StrSplit(val, "|", , 2)
        if parts.Length = 2 && parts[1] != ""
            Hotstring(":*:" parts[1], parts[2])
    }
}

; ============================================================
; UTILITY: Read file paths from CF_HDROP clipboard format
; ============================================================
GetFileListFromClipboard() {
    files := []

    if !DllCall("IsClipboardFormatAvailable", "UInt", 15)
        return files

    if !DllCall("OpenClipboard", "Ptr", 0)
        return files

    hDrop := DllCall("GetClipboardData", "UInt", 15, "Ptr")
    if !hDrop {
        DllCall("CloseClipboard")
        return files
    }

    fileCount := DllCall("shell32\DragQueryFileW", "Ptr", hDrop, "Int", -1, "Ptr", 0, "UInt", 0)

    if fileCount > 0 {
        loop fileCount {
            bufSize := DllCall("shell32\DragQueryFileW", "Ptr", hDrop, "Int", A_Index - 1, "Ptr", 0, "UInt", 0)
            bufSize += 1
            buf := Buffer(bufSize * 2)
            charsWritten := DllCall("shell32\DragQueryFileW", "Ptr", hDrop, "Int", A_Index - 1, "Ptr", buf.Ptr, "UInt", bufSize)
            if charsWritten > 0 {
                filePath := StrGet(buf, charsWritten, "UTF-16")
                files.Push(filePath)
            }
        }
    }

    DllCall("CloseClipboard")
    return files
}

; ============================================================
; THEME HELPERS: Windows Dark Mode detection, WM_CTLCOLOR hooks & Dark InputBox
; ============================================================
global darkBgBrush := 0
global darkCtlBrush := 0

IsDarkMode() {
    global favoritesFile
    themeOpt := IniRead(favoritesFile, "Settings", "Theme", "auto")
    if (themeOpt = "dark")
        return true
    if (themeOpt = "light")
        return false
    try {
        val := RegRead("HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme")
        return (val = 0)
    } catch {
        return false
    }
}

InitDarkBrushes() {
    global darkBgBrush, darkCtlBrush
    if !darkBgBrush
        darkBgBrush := DllCall("gdi32\CreateSolidBrush", "UInt", 0x1F1F1F, "Ptr")
    if !darkCtlBrush
        darkCtlBrush := DllCall("gdi32\CreateSolidBrush", "UInt", 0x2B2B2B, "Ptr")
}

OnWmCtlColorStatic(wParam, lParam, msg, hwnd) {
    global darkBgBrush
    if !IsDarkMode()
        return
    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", 0x00E0E0E0)
    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", 0x001F1F1F)
    return darkBgBrush
}

OnWmCtlColorEdit(wParam, lParam, msg, hwnd) {
    global darkCtlBrush
    if !IsDarkMode()
        return
    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", 0x00FFFFFF)
    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", 0x002B2B2B)
    return darkCtlBrush
}

OnWmCtlColorBtn(wParam, lParam, msg, hwnd) {
    global darkBgBrush
    if !IsDarkMode()
        return
    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", 0x00FFFFFF)
    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", 0x001F1F1F)
    return darkBgBrush
}

ApplyDarkTheme(guiObj) {
    if !IsDarkMode()
        return
    InitDarkBrushes()
    guiObj.BackColor := "1F1F1F"
    if guiObj.Hwnd {
        isDark := Buffer(4, 0)
        NumPut("Int", 1, isDark)
        ; DWMWA_USE_IMMERSIVE_DARK_MODE (Win11 / Win10 20H1+ = 20, Win10 1809-1909 = 19)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 20, "Ptr", isDark.Ptr, "UInt", 4)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 19, "Ptr", isDark.Ptr, "UInt", 4)
        ; DWMWA_CAPTION_COLOR (35) -> #1F1F1F, DWMWA_TEXT_COLOR (36) -> #FFFFFF (BGR format: 0x001F1F1F / 0x00FFFFFF)
        captionColor := Buffer(4, 0)
        NumPut("UInt", 0x001F1F1F, captionColor)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 35, "Ptr", captionColor.Ptr, "UInt", 4)
        textColor := Buffer(4, 0)
        NumPut("UInt", 0x00FFFFFF, textColor)
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", guiObj.Hwnd, "UInt", 36, "Ptr", textColor.Ptr, "UInt", 4)
        ; Force frame redraw
        DllCall("user32\SetWindowPos", "Ptr", guiObj.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x0027) ; SWP_NOMOVE|SWP_NOSIZE|SWP_NOZORDER|SWP_FRAMECHANGED
    }
    static msgsHooked := false
    if !msgsHooked {
        OnMessage(0x0138, OnWmCtlColorStatic)  ; WM_CTLCOLORSTATIC
        OnMessage(0x0133, OnWmCtlColorEdit)    ; WM_CTLCOLOREDIT
        OnMessage(0x0135, OnWmCtlColorBtn)     ; WM_CTLCOLORBTN
        msgsHooked := true
    }
    for , ctrl in guiObj {
        try {
            cType := ctrl.Type
            if (cType = "ListView") {
                DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "WStr", "DarkMode_Explorer", "Ptr", 0)
                ; LVM_SETTEXTCOLOR (0x1024), LVM_SETBKCOLOR (0x1001), LVM_SETTEXTBKCOLOR (0x1026)
                SendMessage(0x1024, 0, 0x00FFFFFF, ctrl.Hwnd)
                SendMessage(0x1001, 0, 0x00202020, ctrl.Hwnd)
                SendMessage(0x1026, 0, 0x00202020, ctrl.Hwnd)
                ; Theme header control
                hdrHwnd := SendMessage(0x101F, 0, 0, ctrl.Hwnd)
                if hdrHwnd
                    DllCall("uxtheme\SetWindowTheme", "Ptr", hdrHwnd, "WStr", "DarkMode_ItemsView", "Ptr", 0)
            } else if (cType = "Edit") {
                ctrl.Opt("Background2B2B2B cFFFFFF")
                DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "WStr", "DarkMode_Explorer", "Ptr", 0)
            } else if (cType = "Text") {
                ctrl.Opt("cE0E0E0")
            } else if (cType = "Button") {
                DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "WStr", "DarkMode_Explorer", "Ptr", 0)
            } else if (cType = "DDL" || cType = "DropDownList" || cType = "ComboBox") {
                ctrl.Opt("Background2B2B2B cFFFFFF")
                DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "WStr", "DarkMode_CFD", "Ptr", 0)
            }
        }
    }
}

; Theme-aware InputBox replacement supporting Dark Mode
TbInputBox(prompt, title := "", options := "", defaultVal := "") {
    if !IsDarkMode()
        return InputBox(prompt, title, options, defaultVal)

    w := 450, h := 220
    if RegExMatch(options, "i)w(\d+)", &mW)
        w := Integer(mW[1])
    if RegExMatch(options, "i)h(\d+)", &mH)
        h := Integer(mH[1])

    res := {Result: "Cancel", Value: ""}
    ibGui := Gui("+AlwaysOnTop -MinimizeBox", title)
    ibGui.SetFont("s10", "Segoe UI")
    ibGui.OnEvent("Escape", (*) => ibGui.Destroy())
    ibGui.OnEvent("Close", (*) => ibGui.Destroy())

    promptW := w - 30
    promptH := h - 95
    if promptH < 40
        promptH := 40
    ibGui.AddText("xm ym w" promptW " h" promptH, prompt)

    editCtrl := ibGui.AddEdit("xm y+" 8 " w" promptW " h26 Background2B2B2B cFFFFFF", defaultVal)
    DllCall("uxtheme\SetWindowTheme", "Ptr", editCtrl.Hwnd, "WStr", "DarkMode_Explorer", "Ptr", 0)

    btnY := "y+" 12
    okBtn := ibGui.AddButton("xm " btnY " w100 h30 Default", "OK")
    cancelBtn := ibGui.AddButton("x+10 yp w100 h30", "Cancel")

    DoOk(*) {
        res.Result := "OK"
        res.Value := editCtrl.Value
        ibGui.Destroy()
    }
    okBtn.OnEvent("Click", DoOk)
    cancelBtn.OnEvent("Click", (*) => ibGui.Destroy())

    ApplyDarkTheme(ibGui)  ; before Show: DWM paints the caption at show-time
    ibGui.Show("w" w " Center")
    editCtrl.Focus()
    WinWaitClose(ibGui.Hwnd)
    return res
}
