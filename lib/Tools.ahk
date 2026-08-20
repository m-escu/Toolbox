; ============================================================
; TOOLS COMMANDS
; ============================================================

; --- yt-dlp: update to latest version ---
DoYtdlpUpdate() {
    ytdlpExe := ResolveToolPath("yt-dlp.exe")
    if ytdlpExe != ""
        Run('cmd /k "' ytdlpExe '" -U')
    else
        Run('cmd /k yt-dlp -U')
}

; --- yt-dlp downloader with GUI ---
; Parameters persisted in INI [YtdlpSettings]:
;   Format, Concurrency, ExtraArgs, Folder, WindowX, WindowY
ToolYtDlp() {
    global favoritesFile

    ; Locate yt-dlp via the same resolver (Tools\ folder, WSCC, PATH)
    ytdlpExe := ResolveToolPath("yt-dlp.exe")
    ytdlpCmd := ""
    if ytdlpExe != "" {
        ytdlpCmd := '"' ytdlpExe '"'
    } else {
        try {
            shell := ComObject("WScript.Shell")
            exec := shell.Exec('where yt-dlp 2>nul')
            whereOut := Trim(exec.StdOut.ReadAll())
            if whereOut != ""
                ytdlpCmd := "yt-dlp"
        }
    }

    if ytdlpCmd = "" {
        result := MsgBox(
            "yt-dlp not found.`n`n"
            "Options:`n"
            "  1. Place yt-dlp.exe in the Tools subfolder`n     (next to this script).`n"
            "  2. Or install via: pip install yt-dlp`n`n"
            "Open the releases page?",
            "yt-dlp not found", 51)
        if result = "Yes"
            Run("https://github.com/yt-dlp/yt-dlp/releases")
        return
    }

    ; ------------------------------------------------------------------
    ; Restore last-used settings from INI
    ; ------------------------------------------------------------------
    savedFmt := IniRead(favoritesFile, "YtdlpSettings", "Format", "best video (bv*+ba/b)")
    savedConc := IniRead(favoritesFile, "YtdlpSettings", "Concurrency", "7")
    savedExtra := IniRead(favoritesFile, "YtdlpSettings", "ExtraArgs", "")
    savedFolder := IniRead(favoritesFile, "YtdlpSettings", "Folder", "")
    savedWinX := IniRead(favoritesFile, "YtdlpSettings", "WindowX", "")
    savedWinY := IniRead(favoritesFile, "YtdlpSettings", "WindowY", "")
    if savedFolder = ""
        savedFolder := userProfile "\Downloads"

    ; Try pasting URL from clipboard as default
    clipText := A_Clipboard != "" ? Trim(A_Clipboard) : ""
    defaultUrl := RegExMatch(clipText, "i)^https?://") ? clipText : ""

    ; ------------------------------------------------------------------
    ; Helper: map dropdown label to yt-dlp format flags
    ; (Must be a named function since switch/case is a statement, not an expression,
    ;  so it cannot appear inside a fat-arrow lambda in AHK v2.)
    ; ------------------------------------------------------------------
    YtdlpFormatFlags(fmt) {
        if fmt = "m4a audio (139)"
            return "-f 139"
        if fmt = "mp3 audio (bestaudio+audio quality 0)"
            return "-x --audio-format mp3 --audio-quality 0"
        if fmt = "best video (bv*+ba/b)"
            return '-f "bv*+ba/b"'
        if fmt = "best video only (bv*+ba/b --merge-output-format mp4)"
            return '-f "bv*+ba/b" --merge-output-format mp4'
        if fmt = "worst video (small file)"
            return '-f "worstvideo[ext=mp4]+worstaudio/worst"'
        if fmt = "720p video (bv*[height<=720]+ba/b)"
            return '-f "bv*[height<=720]+ba/b"'
        if fmt = "1080p video (bv*[height<=1080]+ba/b)"
            return '-f "bv*[height<=1080]+ba/b"'
        if fmt = "4K video (bv*[height<=2160]+ba/b)"
            return '-f "bv*[height<=2160]+ba/b"'
        if fmt = "thumbnail only"
            return "--write-thumbnail --skip-download"
        if fmt = "Custom (-f)"
            return ""
        return "-f 139"
    }

    ; ------------------------------------------------------------------
    ; Build GUI
    ; ------------------------------------------------------------------
    ytg := Gui("", "yt-dlp Downloader")
    ytg.SetFont("s10", "Segoe UI")
    ytg.OnEvent("Escape", (*) => ytg.Destroy())
    ytg.OnEvent("Close", (*) => ytg.Destroy())

    ; --- URL row (multi-line: one URL per line = download queue) ---
    ytg.AddText("xm y+10", "URL(s):")
    urlEdit := ytg.AddEdit("xm+50 yp-3 w420 h56 WantReturn -Wrap", defaultUrl)
    urlEdit.SetFont("s9", "Consolas")
    ytg.AddButton("xm+50 y+2 w60", "Paste").OnEvent("Click", (*) => (urlEdit.Value := A_Clipboard, urlEdit.Focus()))
    ytg.AddButton("x+5 yp w140", "&Update yt-dlp").OnEvent("Click", (*) => DoYtdlpUpdate())

    ; --- Format dropdown ---
    ytg.AddText("xm y+12", "Format:")
    fmtList := ['m4a audio (139)'
        , 'mp3 audio (bestaudio+audio quality 0)'
        , 'best video (bv*+ba/b)'
        , 'best video only (bv*+ba/b --merge-output-format mp4)'
        , 'worst video (small file)'
        , '720p video (bv*[height<=720]+ba/b)'
        , '1080p video (bv*[height<=1080]+ba/b)'
        , '4K video (bv*[height<=2160]+ba/b)'
        , 'thumbnail only'
        , 'Custom (-f)']
    fmtDD := ytg.AddDDL('xm+50 yp-3 w280', fmtList)
    ; Choose accepts a string to match — try it, fall back to index 3 (best video)
    try fmtDD.Choose(savedFmt)
    catch
        fmtDD.Choose(3)

    ; --- Concurrency row ---
    ytg.AddText("xm y+12", "Concurrent (-N):")
    concEdit := ytg.AddEdit("xm+120 yp-3 w60 h26", savedConc)

    ; --- Extra args row ---
    ytg.AddText("xm y+12", "Extra args:")
    extraEdit := ytg.AddEdit("xm+90 yp-3 w340 h26", savedExtra)
    ; Show tooltip on focus, hide on blur; (?) label also shows it on click
    extraHint := "Examples:`n"
        . "--cookies-from-browser firefox`n"
        . "--write-subs --sub-langs en.*`n"
        . "--embed-subs --embed-metadata`n"
        . "--sponsorblock-remove all`n"
        . "--no-playlist`n"
        . "--playlist-items 1-5`n"
        . "-o `"%(title)s.%(ext)s`"`n"
        . "--proxy socks5://127.0.0.1:1080`n"
        . "--concurrent-fragments N`n"
        . "--max-filesize 500M"
    extraEdit.OnEvent("Focus", (*) => ToolTip(extraHint))
    extraEdit.OnEvent("LoseFocus", (*) => ToolTip())
    DismissExtraTip(*) {
        ToolTip()
    }
    tipLabel := ytg.AddText("x+5 yp+4 cBlue", "(?)")
    tipLabel.OnEvent("Click", (*) => (ToolTip(extraHint), SetTimer(DismissExtraTip, -6000)))

    ; --- Folder row ---
    ytg.AddText("xm y+12", "Save to:")
    folderEdit := ytg.AddEdit("xm+60 yp-3 w330 h26", savedFolder)
    DoBrowse() {
        picked := DirSelect(folderEdit.Value, 1, "Select download folder")
        if picked != ""
            folderEdit.Value := picked
    }
    ytg.AddButton("x+5 yp w80", "Browse...").OnEvent("Click", (*) => DoBrowse())

    ; --- Command preview ---
    ytg.AddText("xm y+14", "Command:")
    previewEdit := ytg.AddEdit("xm+70 yp-3 w420 h24 ReadOnly -Wrap")
    previewEdit.SetFont("s9", "Consolas")

    ; --- Live preview updater (nested named function — safe in AHK v2) ---
    UpdatePreview() {
        urls := []
        for , line in StrSplit(urlEdit.Value, "`n", "`r ") {
            line := Trim(line)
            if line != ""
                urls.Push(line)
        }
        fmt := fmtDD.Text
        conc := Trim(concEdit.Value)
        extra := Trim(extraEdit.Value)
        folder := Trim(folderEdit.Value)

        if urls.Length = 0
            cmdPreview := "(enter URL(s) above)"
        else {
            fmtFlags := YtdlpFormatFlags(fmt)
            cmdPreview := "yt-dlp "
            if fmtFlags != ""
                cmdPreview .= fmtFlags " "
            if RegExMatch(conc, "^\d+$")
                cmdPreview .= "-N " conc " "
            if extra != ""
                cmdPreview .= extra " "
            for , u in urls
                cmdPreview .= '"' u '" '
            cmdPreview := RTrim(cmdPreview)
            if urls.Length > 1
                cmdPreview .= "  (" urls.Length " URLs queued)"
            if folder != ""
                cmdPreview .= "`n  (dir: " folder ")"
        }
        previewEdit.Value := cmdPreview
    }

    urlEdit.OnEvent("Change", (*) => UpdatePreview())
    fmtDD.OnEvent("Change", (*) => UpdatePreview())
    concEdit.OnEvent("Change", (*) => UpdatePreview())
    extraEdit.OnEvent("Change", (*) => UpdatePreview())
    folderEdit.OnEvent("Change", (*) => UpdatePreview())

    ; --- Buttons ---
    dlBtn := ytg.AddButton("xm y+16 w120 h32", "&Download")
    dlBtn.SetFont("s10 Bold")
    ytg.AddButton("x+15 yp w100 h32", "Cancel").OnEvent("Click", (*) => ytg.Destroy())

    ; --- Download handler (named function — avoids switch/case in lambda) ---
    DoDownload(g) {
        urls := []
        for , line in StrSplit(urlEdit.Value, "`n", "`r ") {
            line := Trim(line)
            if line != ""
                urls.Push(line)
        }
        if urls.Length = 0 {
            MsgBox("Please enter at least one URL.", "yt-dlp", 48)
            urlEdit.Focus()
            return
        }
        folder := Trim(folderEdit.Value)
        if folder = ""
            folder := userProfile "\Downloads"

        if !DirExist(folder) {
            result := MsgBox("Folder does not exist:`n" folder "`n`nCreate it?", "yt-dlp", 52)
            if result = "Yes" {
                try {
                    DirCreate(folder)
                } catch as err {
                    MsgBox("Could not create folder:`n" err.Message, "yt-dlp", 48)
                    return
                }
            } else
                return
        }

        ; Remember window position (must be BEFORE Destroy)
        wx := 0, wy := 0
        g.GetPos(&wx, &wy)

        ; Build the yt-dlp command line (all queued URLs in one call)
        fmtFlags := YtdlpFormatFlags(fmtDD.Text)
        conc := Trim(concEdit.Value)
        extra := Trim(extraEdit.Value)
        cmd := ""
        if fmtFlags != ""
            cmd .= fmtFlags " "
        if RegExMatch(conc, "^\d+$")
            cmd .= "-N " conc " "
        if extra != ""
            cmd .= extra " "
        for , u in urls
            cmd .= '"' u '" '

        ; Write command to a temp .bat file — this completely avoids
        ; AHK v2 Run() re-parsing quotes and truncating URLs with ? & = etc.
        tmpBat := A_Temp "\toolbox_ytdlp.bat"
        try FileDelete(tmpBat)
        ; Escape % for batch file context (URLs may contain %XX encoding)
        safeCmd := StrReplace(cmd, "%", "%%")
        batchLine := ytdlpCmd ' ' safeCmd
        FileAppend(batchLine, tmpBat, "UTF-8-RAW")  ; no BOM — cmd.exe chokes on it

        ; Persist all settings to INI
        IniWrite(fmtDD.Text, favoritesFile, "YtdlpSettings", "Format")
        IniWrite(Trim(concEdit.Value), favoritesFile, "YtdlpSettings", "Concurrency")
        IniWrite(Trim(extraEdit.Value), favoritesFile, "YtdlpSettings", "ExtraArgs")
        IniWrite(folder, favoritesFile, "YtdlpSettings", "Folder")
        IniWrite(wx, favoritesFile, "YtdlpSettings", "WindowX")
        IniWrite(wy, favoritesFile, "YtdlpSettings", "WindowY")

        g.Destroy()
        ; cmd /k runs the batch file and keeps the window open afterward
        Run(A_ComSpec ' /k "' tmpBat '"', folder)
    }
    dlBtn.OnEvent("Click", (*) => DoDownload(ytg))

    ; --- Show GUI (theme first: DWM paints the caption at show-time) ---
    ApplyDarkTheme(ytg)
    if savedWinX != "" && savedWinY != "" {
        wx := Integer(savedWinX)
        wy := Integer(savedWinY)
        ytg.Show("x" wx " y" wy)
    } else {
        ytg.Show("Center")
    }
    UpdatePreview()
}

; --- Add tool: browse for exe, name it, persist to INI [Tools], reload ---
ToolAddTool() {
    global favoritesFile
    exePath := FileSelect("S1", , "Select tool executable", "Programs (*.exe;*.bat;*.cmd;*.lnk)")
    if exePath = ""
        return
    fileName := StrSplit(exePath, "\")[-1]
    defaultName := StrSplit(fileName, ".")[1]

    nameInput := TbInputBox("Menu name for this tool:", "Add Tool", "w400 h160", defaultName)
    if nameInput.Result != "OK" || Trim(nameInput.Value) = ""
        return
    label := Trim(nameInput.Value)

    ; Refuse duplicates (same path already registered)
    loop 50 {
        existingPath := IniRead(favoritesFile, "Tools", "Path" A_Index, "")
        if existingPath = exePath {
            MsgBox("This tool is already registered as:`n  " IniRead(favoritesFile, "Tools", "Label" A_Index, "?"), "Add Tool", 48)
            return
        }
    }

    ; Find next free slot
    slot := 0
    loop 50 {
        if IniRead(favoritesFile, "Tools", "Label" A_Index, "") = "" {
            slot := A_Index
            break
        }
    }
    if slot = 0 {
        MsgBox("Tools list is full (50 entries). Remove some from the INI.", "Add Tool", 48)
        return
    }

    IniWrite(label, favoritesFile, "Tools", "Label" slot)
    IniWrite(fileName, favoritesFile, "Tools", "Exe" slot)
    IniWrite(exePath, favoritesFile, "Tools", "Path" slot)

    result := MsgBox("Added: " label "`n" exePath "`n`nReload Toolbox now to show it in the menu?", "Add Tool", 52)
    if result = "Yes"
        Reload()
}

; --- handle64: find which process has a file locked ---
ToolHandle64() {
    exePath := ResolveToolPath("handle64.exe")
    if !exePath {
        MsgBox("handle64.exe not found.`n`nExpected in WSCC Apps\SysInternals Suite\`nor place next to this script.", "handle64", 48)
        return
    }

    ; Try the selected file (Ctrl+C in Explorer) first, else file picker
    selectedFile := ""
    try {
        clipFiles := GetFileListFromClipboard()
        if clipFiles.Length > 0
            selectedFile := clipFiles[1]
    }
    if selectedFile = "" || !FileExist(selectedFile) {
        selectedFile := FileSelect("S1", , "Select file to check for locks")
        if !selectedFile
            return
    }

    ; handle64 needs admin rights to see most handles;
    ; extract just the filename for the filter (handle64 matches on name, not path)
    fileName := StrSplit(selectedFile, "\")[-1]
    try {
        shell := ComObject("WScript.Shell")
        ; -nobanner suppresses the copyright line; -accepteula skips the EULA popup
        exec := shell.Exec('"' exePath '" -accepteula -nobanner "' fileName '"')
        ; Read stdout first — reading stderr before exit deadlocks (pipe fill)
        output := Trim(exec.StdOut.ReadAll())
        errOut := Trim(exec.StdErr.ReadAll())
        ; Combine outputs for completeness
        if output = "" && errOut != ""
            output := errOut
        ; handle64 outputs nothing when no matches — provide a helpful message
        if output = ""
            output := "No matching handles found.`n`n"
                . "Possible reasons:`n"
                . "  - No process is locking this file.`n"
                . "  - Script is not running as Administrator.`n"
                . "  - handle64 needs elevated rights to enumerate handles.`n`n"
                . "Try right-clicking the script > 'Run as administrator'."
        MsgBox(output, "handle64: " fileName, 64)
    }
}

; ============================================================
; MANAGE TOOLS — rename / delete / run / reveal INI tool entries
; ============================================================

; Read all [Tools] entries as {label, exe, path} (compact, gaps removed)
LoadToolsIni() {
    global favoritesFile
    entries := []
    loop 50 {
        label := IniRead(favoritesFile, "Tools", "Label" A_Index, "")
        exe := IniRead(favoritesFile, "Tools", "Exe" A_Index, "")
        if label = "" || exe = ""
            continue
        path := IniRead(favoritesFile, "Tools", "Path" A_Index, "")
        entries.Push({label: label, exe: exe, path: path})
    }
    return entries
}

; Rewrite [Tools] compactly from an entries array
SaveToolsIni(entries) {
    global favoritesFile
    IniDelete(favoritesFile, "Tools")
    for i, e in entries {
        IniWrite(e.label, favoritesFile, "Tools", "Label" i)
        IniWrite(e.exe, favoritesFile, "Tools", "Exe" i)
        if e.path != ""
            IniWrite(e.path, favoritesFile, "Tools", "Path" i)
    }
}

; Where an entry resolves + display path
ToolResolveInfo(exe, customPath) {
    if customPath != "" && FileExist(customPath)
        return {src: "custom", path: customPath}
    localPath := A_ScriptDir "\Tools\" exe
    if FileExist(localPath)
        return {src: "Tools\", path: localPath}
    global wsccCache
    if wsccCache.Has(StrLower(exe))
        return {src: "WSCC", path: wsccCache[StrLower(exe)]}
    return {src: "not found", path: ""}
}

ToolManageGui() {
    global favoritesFile
    entries := LoadToolsIni()
    dirty := false

    mg := Gui("", "Toolbox — Manage Tools")
    mg.SetFont("s10", "Segoe UI")
    mg.OnEvent("Escape", (*) => mg.Destroy())
    mg.OnEvent("Close", (*) => CloseManage())
    lv := mg.AddListView("xm w700 h340 -Multi", ["Tool", "Exe", "Source", "Resolved path"])
    lv.ModifyCol(1, 160), lv.ModifyCol(2, 140), lv.ModifyCol(3, 80), lv.ModifyCol(4, 300)

    RefreshList() {
        lv.Delete()
        for , e in entries {
            ri := ToolResolveInfo(e.exe, e.path)
            lv.Add(, e.label, e.exe, ri.src, ri.path != "" ? ri.path : "-")
        }
    }
    RefreshList()

    SelectedEntry() {
        row := lv.GetNext(0)
        return row = 0 ? "" : entries[row]
    }

    DoRun(*) {
        e := SelectedEntry()
        if e = ""
            return
        ri := ToolResolveInfo(e.exe, e.path)
        if ri.path != ""
            Run('"' ri.path '"')
    }
    DoRename(*) {
        e := SelectedEntry()
        if e = ""
            return
        nb := TbInputBox("New menu name:", "Rename Tool", "w400 h160", e.label)
        if nb.Result != "OK" || Trim(nb.Value) = "" || Trim(nb.Value) = e.label
            return
        e.label := Trim(nb.Value)
        dirty := true
        SaveToolsIni(entries)
        RefreshList()
    }
    DoDelete(*) {
        e := SelectedEntry()
        if e = ""
            return
        if MsgBox('Delete tool "' e.label '" from the menu?', "Delete Tool", 49) != "OK"
            return
        for i, x in entries {
            if x.label = e.label && x.exe = e.exe {
                entries.RemoveAt(i)
                break
            }
        }
        dirty := true
        SaveToolsIni(entries)
        RefreshList()
    }
    DoReveal(*) {
        e := SelectedEntry()
        if e = ""
            return
        ri := ToolResolveInfo(e.exe, e.path)
        if ri.path != ""
            Run('explorer.exe /select,"' ri.path '"')
    }
    DoAdd(*) {
        mg.Destroy()
        ToolAddTool()
    }

    CloseManage(*) {
        mg.Destroy()
        if dirty {
            if MsgBox("Reload Toolbox now to apply the Tools menu changes?", "Manage Tools", 52) = "Yes"
                Reload()
        }
    }

    mg.AddButton("xm y+10 w90 h32", "&Run").OnEvent("Click", DoRun)
    mg.AddButton("x+8 yp w100 h32", "&Rename...").OnEvent("Click", DoRename)
    mg.AddButton("x+8 yp w100 h32", "&Delete...").OnEvent("Click", DoDelete)
    mg.AddButton("x+8 yp w100 h32", "Re&veal").OnEvent("Click", DoReveal)
    mg.AddButton("x+8 yp w100 h32", "&Add...").OnEvent("Click", DoAdd)
    mg.AddButton("x+40 yp w100 h32", "Close").OnEvent("Click", CloseManage)
    ApplyDarkTheme(mg)
    mg.Show()
}
