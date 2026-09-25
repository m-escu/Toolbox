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

; Show command output. Reads [Settings] OutputMode:
;   console (default) — themed OLED window (lib\Console.ahk)
;   file              — legacy: temp .txt opened in N++/Notepad
; The signature never changed, so every existing ShowText call site
; (ARP table, route table, event log errors, adapters, ...) upgrades free.
ShowText(title, text) {
    global favoritesFile
    mode := IniRead(favoritesFile, "Settings", "OutputMode", "console")
    if (mode = "file") {
        ShowTextInEditor(title, text)
        return
    }
    ConsoleShow(title, text)
}

; Legacy output path: write a temp file, open it in N++ (or Notepad).
; Kept for the "Open in editor" button inside the console + OutputMode=file.
ShowTextInEditor(title, text) {
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

; The standard pattern for all the new "show me info" tools:
;   1. build an array of PowerShell lines   psLines := [] / psLines.Push('...')
;   2. run it hidden and capture stdout     output := PsCapture(psLines, "name")
;   3. display it                           ShowText("Title", output)  -> themed console
; Steps 1-2 used to be copy-pasted 6 lines per tool; this helper does the
; join + write + run + capture + cleanup in one call. The static runCount
; makes every temp file unique, so two tools can run at the same time
; without overwriting each other's .ps1 (CleanupOldTemp removes leftovers
; on the next Toolbox start).
PsCapture(psLines, name := "ps") {
    static runCount := 0
    runCount += 1
    psScript := ""
    for , line in psLines
        psScript .= line "`n"
    tmpPs := WriteTempPs("toolbox_" name runCount ".ps1", psScript)
    output := RunCapture('powershell -NoProfile -ExecutionPolicy Bypass -File "' tmpPs '"')
    Try FileDelete(tmpPs)
    return output
}

; Remove leftover toolbox_* temp files from previous runs
CleanupOldTemp() {
    Loop Files A_Temp "\toolbox_*.*"
        Try FileDelete(A_LoopFilePath)
}

; Run a temp PS script in a visible window (cleanup happens on next Toolbox start).
; noExit=true keeps the window open even if the script crashes (errors stay readable).
; title: when set, the spawned console gets themed (window title, bigger
; character grid, dark palette in dark mode) — see PsConsoleTheme(). The
; theme lines must run INSIDE PowerShell, so we switch from -File to a
; -Command wrapper that sets the theme then dot-runs the temp script.
RunTempPsVisible(tmpPs, workDir := "", noExit := false, title := "") {
    flag := noExit ? " -NoExit" : ""
    if (title != "") {
        ; We need quote marks as DATA here (the -Command argument is wrapped
        ; in ", the script path in '). Rather than fighting AHK's ''-escape
        ; rules with ''' clusters, the quote characters live in variables
        ; and the command is assembled by plain concatenation. Readable and
        ; lexer-proof.
        dq := '"'    ; double quote, as data
        sq := "'"    ; single quote, as data
        psPath := StrReplace(tmpPs, sq, sq sq)   ; PS escapes ' by doubling it
        theme := PsConsoleTheme(title, IsDarkMode())
        ; Final shape: powershell ... -Command "<theme>;& 'C:\...\script.ps1'"
        cmd := "powershell -NoProfile -ExecutionPolicy Bypass" flag
             . " -Command " dq theme "& " sq psPath sq dq
        Run(cmd, workDir, , &pid)
        ; Style + center the window without blocking the menu thread
        SetTimer(() => StyleSpawnedConsole(title), -50)
    } else {
        Run('powershell -NoProfile -ExecutionPolicy Bypass' flag ' -File "' tmpPs '"', workDir)
    }
}

; One line of PowerShell that themes the console FROM INSIDE the spawned
; process: window title, larger character grid (110x38, scrollback 3000),
; and in dark mode a black background + gray text so the whole buffer reads
; like our OLED console. Both resizes are wrapped in try/catch because
; conhost rejects sizes bigger than the monitor or current buffer.
PsConsoleTheme(title, dark) {
    t := StrReplace(title, "'", "")
    out := "$Host.UI.RawUI.WindowTitle='Toolbox — " t "';"
         . "$u=$Host.UI.RawUI;"
         . "try{$u.WindowSize=New-Object System.Management.Automation.Host.Size(110,38)}catch{};"
         . "try{$u.BufferSize=New-Object System.Management.Automation.Host.Size(110,3000)}catch{};"
    if dark
        out .= "$u.ForegroundColor='Gray';$u.BackgroundColor='Black';Clear-Host;"
    return out
}

; Find the console window we just spawned and give it the DWM dark caption
; + center it. The window only carries our title AFTER the preamble ran, so
; poll briefly (typically 1-2 tries). Windows Terminal owns its windows
; under a different window class (and is already dark) — skipped on purpose.
StyleSpawnedConsole(title) {
    hwnd := 0
    loop 10 {
        hwnd := WinExist("Toolbox — " title " ahk_class ConsoleWindowClass")
        if hwnd
            break
        Sleep(120)
    }
    if !hwnd
        return
    if IsDarkMode()
        DwmDarkFrame(hwnd, THEME_BG)
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
    MonitorGetWorkArea(, &al, &at, &ar, &ab)
    WinMove(al + (ar - al - ww) // 2, at + (ab - at - wh) // 2, ww, wh, "ahk_id " hwnd)
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

; ============================================================
; THEME CONSTANTS — OLED look, one identity for all Toolbox GUIs
; (mirrors ShellExView Modern: #0D0D0D bg, #60CDFF Win11-blue accent)
; AHK option strings are RGB ("60CDFF"); Win32 COLORREF is 0x00BBGGRR
; — convert with BgrOf() before handing values to DllCall.
; ============================================================
THEME_BG        := "0D0D0D"   ; window background (OLED black)
THEME_CTL_BG    := "141416"   ; input controls
THEME_TEXT      := "E8E8EA"   ; primary text
THEME_TEXT_DIM  := "9A9AA0"   ; secondary text
THEME_TEXT_MUTE := "5E5E64"   ; hints / status bar
THEME_ACCENT    := "60CDFF"   ; Win11 blue accent

; ---- per-control color overrides (used by WM_CTLCOLOR* hooks above) ----
; Map: control hwnd -> {fg, bk} COLORREFs (BGR). Register via SetCtlColors.
global gCtlColors := Map()
; Brush cache: COLORREF -> HBRUSH. Brushes returned from WM_CTLCOLOR* must
; outlive the message, so they are created once and never deleted.
global gBrushCache := Map()

; RGB hex string ("60CDFF") -> Win32 COLORREF 0x00BBGGRR (0xFFCD60).
BgrOf(rgb) {
    r := Integer("0x" SubStr(rgb, 1, 2))
    g := Integer("0x" SubStr(rgb, 3, 2))
    b := Integer("0x" SubStr(rgb, 5, 2))
    return (b << 16) | (g << 8) | r
}

; Cached GDI brush for a COLORREF (BGR).
ThemeBrush(colorref) {
    global gBrushCache
    if !gBrushCache.Has(colorref)
        gBrushCache[colorref] := DllCall("gdi32\CreateSolidBrush", "UInt", colorref, "Ptr")
    return gBrushCache[colorref]
}

; Give one control exact fg/bg colors at paint time (BGR COLORREFs).
; Works for Text, read-only Edit (WM_CTLCOLORSTATIC) and Edit (WM_CTLCOLOREDIT).
SetCtlColors(hwnd, fg, bk) {
    global gCtlColors
    gCtlColors[hwnd] := {fg: fg, bk: bk}
}

; Register the WM_CTLCOLOR* message hooks exactly once per process.
EnsureCtlColorHooks() {
    static done := false
    if done
        return
    OnMessage(0x0138, OnWmCtlColorStatic)  ; WM_CTLCOLORSTATIC
    OnMessage(0x0133, OnWmCtlColorEdit)    ; WM_CTLCOLOREDIT
    OnMessage(0x0135, OnWmCtlColorBtn)     ; WM_CTLCOLORBTN
    OnMessage(0x0134, OnWmCtlColorListbox) ; WM_CTLCOLORLISTBOX (combo dropdowns)
    done := true
}

; Dark paint for listboxes incl. ComboBox dropped lists — the dropdown
; popup is a separate top-level window, so SetWindowTheme alone is not
; enough; this hook supplies its background/text brushes.
OnWmCtlColorListbox(wParam, lParam, msg, hwnd) {
    global gCtlColors, darkCtlBrush
    if gCtlColors.Has(lParam) {
        c := gCtlColors[lParam]
        DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", c.fg)
        DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", c.bk)
        return ThemeBrush(c.bk)
    }
    if !IsDarkMode()
        return
    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", 0x00FFFFFF)
    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", 0x002B2B2B)
    return darkCtlBrush
}

OnWmCtlColorStatic(wParam, lParam, msg, hwnd) {
    global darkBgBrush, gCtlColors
    ; per-control exact colors win first (registered via SetCtlColors)
    if gCtlColors.Has(lParam) {
        c := gCtlColors[lParam]
        DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", c.fg)
        DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", c.bk)
        return ThemeBrush(c.bk)
    }
    if !IsDarkMode()
        return
    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", 0x00E0E0E0)
    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", 0x001F1F1F)
    return darkBgBrush
}

OnWmCtlColorEdit(wParam, lParam, msg, hwnd) {
    global darkCtlBrush, gCtlColors
    if gCtlColors.Has(lParam) {
        c := gCtlColors[lParam]
        DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", c.fg)
        DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", c.bk)
        return ThemeBrush(c.bk)
    }
    if !IsDarkMode()
        return
    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", 0x00FFFFFF)
    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", 0x002B2B2B)
    return darkCtlBrush
}

OnWmCtlColorBtn(wParam, lParam, msg, hwnd) {
    global darkBgBrush, gCtlColors
    if gCtlColors.Has(lParam) {
        c := gCtlColors[lParam]
        DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", c.fg)
        DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", c.bk)
        return ThemeBrush(c.bk)
    }
    if !IsDarkMode()
        return
    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", 0x00FFFFFF)
    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", 0x001F1F1F)
    return darkBgBrush
}

; DWM dark title bar + caption color for ANY top-level window — our Gui
; windows AND spawned console windows (conhost) alike. bgHex: RGB string.
; Attrs: 20/19 = immersive dark mode (Win11+/older Win10), 35 = caption
; color, 36 = caption text color. Final SetWindowPos forces a frame redraw.
DwmDarkFrame(hwnd, bgHex := "1F1F1F") {
    isDark := Buffer(4, 0)
    NumPut("Int", 1, isDark)
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 20, "Ptr", isDark.Ptr, "UInt", 4)
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 19, "Ptr", isDark.Ptr, "UInt", 4)
    captionColor := Buffer(4, 0)
    NumPut("UInt", BgrOf(bgHex), captionColor)
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 35, "Ptr", captionColor.Ptr, "UInt", 4)
    textColor := Buffer(4, 0)
    NumPut("UInt", 0x00FFFFFF, textColor)
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 36, "Ptr", textColor.Ptr, "UInt", 4)
    DllCall("user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x0027) ; SWP_NOMOVE|SWP_NOSIZE|SWP_NOZORDER|SWP_FRAMECHANGED
}

; bgColor: optional RGB string ("0D0D0D") to override the default #1F1F1F
; window + caption color — used by the OLED console and future themed GUIs.
ApplyDarkTheme(guiObj, bgColor := "") {
    if !IsDarkMode()
        return
    InitDarkBrushes()
    if (bgColor = "")
        bgColor := "1F1F1F"
    guiObj.BackColor := bgColor
    if guiObj.Hwnd
        DwmDarkFrame(guiObj.Hwnd, bgColor)
    EnsureCtlColorHooks()
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
