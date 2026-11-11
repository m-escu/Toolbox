; ============================================================
; FOLDER COMMANDS
; ============================================================

adapterCache := []
adapterCacheTick := 0

; Windows Terminal installs an app-execution alias here (the real exe under
; Program Files\WindowsApps is ACL-protected, so FileExist can't see it).
HasWindowsTerminal() {
    return FileExist(EnvGet("LOCALAPPDATA") "\Microsoft\WindowsApps\wt.exe") != ""
}

OpenFolder(path) {
    if DirExist(path) {
        Run('explorer.exe "' path '"')
    } else {
        Notify("Folder not found: " path, 2000)
    }
}

GetAdapters(force := false) {
    global adapterCache, adapterCacheTick
    if !force && adapterCache.Length > 0 && (A_TickCount - adapterCacheTick) < 60000
        return adapterCache.Clone()
    adapters := []
    try {
        svc := ComObjGet("winmgmts:root\cimv2")
        q := "SELECT NetConnectionID FROM Win32_NetworkAdapter WHERE NetConnectionID IS NOT NULL"
        for nic in svc.ExecQuery(q) {
            name := Trim(nic.NetConnectionID)
            if name != ""
                adapters.Push(name)
        }
    }
    if adapters.Length = 0 {
        raw := RunCapture("netsh interface show interface")
        for line in StrSplit(raw, "`n", "`r") {
            line := Trim(line)
            if line = "" || InStr(line, "Admin State") || InStr(line, "---")
                continue
            if RegExMatch(line, "\S+\s+\S+\s+\S+\s+(.+)$", &m)
                adapters.Push(Trim(m[1]))
        }
    }
    adapterCache := adapters
    adapterCacheTick := A_TickCount
    return adapters.Clone()
}

; Send Ctrl+C to the active window and return the selected files' paths
; (CF_HDROP). The previous clipboard content is always restored. Returns
; [] (with a tooltip) when nothing file-like was selected.
CopySelectedFiles() {
    savedClip := ClipboardAll()
    A_Clipboard := ""
    Sleep(30)
    Send("^c")
    filePaths := []
    loop 20 {  ; up to ~1 s for Explorer to publish the selection
        Sleep(50)
        if DllCall("IsClipboardFormatAvailable", "UInt", 15) {
            filePaths := GetFileListFromClipboard()
            if filePaths.Length = 0
                Notify("Could not read file paths.", 2000)
            break
        }
        if A_Index = 20
            Notify("No files selected.", 2000)
    }
    A_Clipboard := savedClip
    return filePaths
}

; Folder shown in the active Explorer window, or "" if Explorer isn't active
GetActiveExplorerPath() {
    try {
        for w in ComObject("Shell.Application").Windows {
            try {
                if WinActive("ahk_id " w.HWND)
                    return w.Document.Folder.Self.Path
            }
        }
    }
    return ""
}

OpenSelectedInNpp() {
    filePaths := CopySelectedFiles()
    if filePaths.Length = 0
        return

    cmdLine := '"' nppPath '"'
    for path in filePaths
        cmdLine .= ' "' path '"'

    try {
        Run(cmdLine)
        Notify("Opened " filePaths.Length " file(s) in Notepad++", 1500)
    } catch as err {
        MsgBox("Failed to launch Notepad++:`n" err.Message, "Error", 48)
    }
}

CopySelectedPaths() {
    filePaths := CopySelectedFiles()
    if filePaths.Length = 0
        return
    A_Clipboard := StrJoin(filePaths, "`n")
    Notify("Copied " filePaths.Length " path(s) to clipboard", 1500)
}

OpenTerminalHere() {
    currentPath := GetActiveExplorerPath()
    hasWt := HasWindowsTerminal()
    if currentPath = "" || !DirExist(currentPath) {
        Run(hasWt ? "wt.exe" : "cmd /k")
        return
    }
    ; "C:\" would end in \" — which wt's argument parser reads as an
    ; escaped quote — so pass "C:\." for drive roots
    dirArg := SubStr(currentPath, -1) = "\" ? currentPath "." : currentPath
    Run(hasWt ? 'wt.exe -d "' dirArg '"' : 'cmd /k cd /d "' currentPath '"', currentPath)
}

OpenInExplorer() {
    currentPath := GetActiveExplorerPath()
    if currentPath && DirExist(currentPath) {
        Run('explorer.exe "' currentPath '"')
    } else {
        Notify("Could not determine current folder.", 2000)
    }
}
