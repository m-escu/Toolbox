; ============================================================
; FOLDER COMMANDS
; ============================================================

adapterCache := []
adapterCacheTick := 0

OpenFolder(path) {
    if DirExist(path) {
        Run('explorer.exe "' path '"')
    } else {
        ToolTip("Folder not found: " path)
        SetTimer(() => ToolTip(), -2000)
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

OpenSelectedInNpp() {
    savedClip := ClipboardAll()
    A_Clipboard := ""
    Sleep(30)
    Send("^c")

    filesCopied := false
    loop 20 {
        Sleep(50)
        if DllCall("IsClipboardFormatAvailable", "UInt", 15) {
            filesCopied := true
            break
        }
    }

    if !filesCopied {
        A_Clipboard := savedClip
        ToolTip("No files selected.")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    filePaths := GetFileListFromClipboard()
    A_Clipboard := savedClip

    if filePaths.Length == 0 {
        ToolTip("Could not read file paths.")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    cmdLine := '"' nppPath '"'
    for path in filePaths
        cmdLine .= ' "' path '"'

    try {
        Run(cmdLine)
        ToolTip("Opened " filePaths.Length " file(s) in Notepad++")
        SetTimer(() => ToolTip(), -1500)
    } catch as err {
        MsgBox("Failed to launch Notepad++:`n" err.Message, "Error", 48)
    }
}

CopySelectedPaths() {
    savedClip := ClipboardAll()
    A_Clipboard := ""
    Sleep(30)
    Send("^c")

    filesCopied := false
    loop 20 {
        Sleep(50)
        if DllCall("IsClipboardFormatAvailable", "UInt", 15) {
            filesCopied := true
            break
        }
    }

    if !filesCopied {
        A_Clipboard := savedClip
        ToolTip("No files selected.")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    filePaths := GetFileListFromClipboard()

    if filePaths.Length == 0 {
        A_Clipboard := savedClip
        ToolTip("Could not read file paths.")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    textPaths := ""
    for path in filePaths
        textPaths .= path "`n"
    textPaths := RTrim(textPaths, "`n")

    A_Clipboard := textPaths
    ToolTip("Copied " filePaths.Length " path(s) to clipboard")
    SetTimer(() => ToolTip(), -1500)
}

OpenTerminalHere() {
    currentPath := ""

    try {
        shell := ComObject("Shell.Application")
        for w in shell.Windows {
            try {
                if WinActive("ahk_id " w.HWND) {
                    currentPath := w.Document.Folder.Self.Path
                    break
                }
            }
        }
    }

    termCmd := ""
    if FileExist("C:\Program Files\WindowsApps\Microsoft.WindowsTerminal_*\WindowsTerminal.exe") || FileExist(userProfile "\AppData\Local\Microsoft.WindowsApps\wt.exe")
        termCmd := 'wt.exe -d "' currentPath '"'
    else
        termCmd := 'cmd /k cd /d "' currentPath '"'

    if currentPath && DirExist(currentPath) {
        Run(termCmd, currentPath)
        return
    }

    if InStr(termCmd, "wt.exe")
        Run("wt.exe")
    else
        Run("cmd /k")
}

OpenInExplorer() {
    currentPath := ""

    try {
        shell := ComObject("Shell.Application")
        for w in shell.Windows {
            try {
                if WinActive("ahk_id " w.HWND) {
                    currentPath := w.Document.Folder.Self.Path
                    break
                }
            }
        }
    }

    if currentPath && DirExist(currentPath) {
        Run('explorer.exe "' currentPath '"')
    } else {
        ToolTip("Could not determine current folder.")
        SetTimer(() => ToolTip(), -2000)
    }
}
