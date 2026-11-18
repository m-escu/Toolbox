; ============================================================
; TOOL UPDATER — catalog of known suites, download zip, keep binaries
; ============================================================
; Maps exe name (lowercase) → {name, suite, url, exes, direct}
; "Newer available" detection: compare HTTP Last-Modified / ETag of the remote
; file against the timestamp stored in INI [ToolUpdates] at last download.
; Load catalog from catalog.json next to the script.
; Maps exe name (lowercase) → {name, suite, url, exes, direct}
BuildToolCatalog(jsonFile := "") {
    cat := Map()
    if jsonFile = ""
        jsonFile := A_ScriptDir "\catalog.json"
    if !FileExist(jsonFile) {
        Notify("catalog.json not found — updater disabled", 3000)
        return cat
    }
    try {
        root := JsonParse(FileRead(jsonFile, "UTF-8"))
        for , t in root["tools"] {
            ; optional integrity fields: signer (Authenticode publisher every
            ; binary must be validly signed by), sha256sums (URL of a
            ; "<sha256>  <file>" list the download must match)
            info := {name: t["name"], suite: t["suite"], url: t["url"], exes: t["exes"]
                , direct: t.Has("direct") ? t["direct"] : ""
                , signer: t.Has("signer") ? t["signer"] : ""
                , sums: t.Has("sha256sums") ? t["sha256sums"] : ""}
            for , e in info.exes
                cat[StrLower(e)] := info
        }
    } catch as err {
        Notify("catalog.json parse error: " err.Message, 4000)
    }
    return cat
}

; Minimal JSON parser for catalog.json (objects, arrays, strings).
; Returns Map (with case-sensitive keys) / Array / string / integer / true / false / null.
JsonParse(text) {
    pos := 1
    SkipWs()
    v := ParseValue()
    return v

    SkipWs() {
        while pos <= StrLen(text) && InStr(" `t`r`n", SubStr(text, pos, 1))
            pos++
    }
    ParseValue() {
        SkipWs()
        ch := SubStr(text, pos, 1)
        if ch = "{"
            return ParseObject()
        if ch = "["
            return ParseArray()
        if ch = '"'
            return ParseString()
        if SubStr(text, pos, 4) = "true" {
            pos += 4
            return true
        }
        if SubStr(text, pos, 5) = "false" {
            pos += 5
            return false
        }
        if SubStr(text, pos, 4) = "null" {
            pos += 4
            return ""
        }
        return ParseNumber()
    }
    ParseObject() {
        obj := Map()
        pos++  ; {
        SkipWs()
        if SubStr(text, pos, 1) = "}" {
            pos++
            return obj
        }
        loop {
            SkipWs()
            if SubStr(text, pos, 1) != '"'
                Fail("expected object key")
            key := ParseString()
            SkipWs()
            if SubStr(text, pos, 1) != ":"
                Fail("expected ':'")
            pos++
            obj[key] := ParseValue()
            SkipWs()
            ch := SubStr(text, pos, 1)
            pos++
            if ch = "}"
                return obj
            if ch != ","
                Fail("expected ',' or '}'")
        }
    }
    Fail(what) {
        throw Error("JSON: " what " at position " pos)
    }
    ParseArray() {
        arr := []
        pos++  ; [
        SkipWs()
        if SubStr(text, pos, 1) = "]" {
            pos++
            return arr
        }
        loop {
            arr.Push(ParseValue())
            SkipWs()
            ch := SubStr(text, pos, 1)
            pos++
            if ch = "]"
                return arr
            if ch != ","
                Fail("expected ',' or ']'")
        }
    }
    ParseString() {
        pos++  ; opening quote
        out := ""
        loop {
            if pos > StrLen(text)
                Fail("unterminated string")
            ch := SubStr(text, pos, 1)
            if ch = '"' {
                pos++
                return out
            }
            if ch = "\" {  ; AHK has no backslash escapes: "\" is ONE backslash
                esc := SubStr(text, pos + 1, 1)
                if esc = "u" {
                    hex := SubStr(text, pos + 2, 4)
                    if !RegExMatch(hex, "^[0-9A-Fa-f]{4}$")
                        Fail("bad \u escape")
                    out .= Chr(Integer("0x" hex))
                    pos += 6
                    continue
                }
                pos += 2
                out .= esc = "n" ? "`n" : esc = "t" ? "`t" : esc = "r" ? "`r"
                     : esc = "b" ? "`b" : esc = "f" ? "`f" : esc  ; \" \\ \/ map to themselves
            } else {
                out .= ch
                pos++
            }
        }
    }
    ParseNumber() {
        ; (the old "m := RegExMatch(..., &m)" overwrote the match object with
        ; the position, so any numeric value threw; also it wasn't anchored)
        if !RegExMatch(text, "-?\d+(\.\d+)?([eE][+-]?\d+)?", &nm, pos) || nm.Pos != pos
            throw Error("Unexpected character at " pos ": '" SubStr(text, pos, 1) "'")
        pos := nm.Pos + nm.Len
        return RegExMatch(nm[0], "[.eE]") ? Number(nm[0]) : Integer(nm[0])
    }
}

; File version from exe metadata (VS_FIXEDFILEINFO), e.g. "17.4.0.0"
GetFileVer(path) {
    if path = "" || !FileExist(path)
        return ""
    size := DllCall("version\GetFileVersionInfoSizeW", "wstr", path, "ptr", 0, "uint")
    if !size
        return ""
    buf := Buffer(size)
    if !DllCall("version\GetFileVersionInfoW", "wstr", path, "uint", 0, "uint", size, "ptr", buf.Ptr)
        return ""
    if !DllCall("version\VerQueryValueW", "ptr", buf.Ptr, "wstr", "\", "ptr*", &pVal := 0, "uint*", &len := 0)
        return ""
    ms := NumGet(pVal, 8, "uint"), ls := NumGet(pVal, 12, "uint")
    return Format("{}.{}.{}.{}", ms >> 16, ms & 0xFFFF, ls >> 16, ls & 0xFFFF)
}

; Change token of a URL ("" on failure) — HEAD request.
; Prefers ETag (content hash on most CDNs); falls back to Last-Modified.
HttpGetChangeToken(url) {
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(3000, 3000, 3000, 3000)
        req.Open("HEAD", url, false)
        req.Send()
        try {
            etag := req.GetResponseHeader("ETag")
            if etag != ""
                return "ETag:" etag
        }
        return "LM:" req.GetResponseHeader("Last-Modified")
    } catch {
        return ""
    }
}

; ---- integrity checks (run BEFORE anything is written into Tools\) ----
; Each returns "" when the file passes, else the reason it was rejected.

; Valid Authenticode signature whose certificate subject names `signer`
VerifySignature(path, signer) {
    psLines := ['$s = Get-AuthenticodeSignature -LiteralPath ' PsQuote(path)
        , 'Write-Output ("{0}|{1}" -f $s.Status, $s.SignerCertificate.Subject)']
    out := Trim(PsCapture(psLines, "sigcheck"), " `t`r`n")
    if !RegExMatch(out, "^(\w+)\|(.*)$", &m)
        return "signature check failed: " out
    if m[1] != "Valid"
        return "signature " m[1] " (expected a valid " signer " signature)"
    ; the organisation field must equal `signer` exactly ("O=Microsoft" must not
    ; accept "O=Microsoft Corporation Ltd" or the reverse)
    if !RegExMatch(m[2], "(?:^|, )O=" RegExEscape(signer) "(?:,|$)")
        return "signed by someone else: " m[2]
    return ""
}

; SHA-256 of `path` must equal the entry for `fileName` in the sums file
VerifySha256Sums(path, sumsUrl, fileName) {
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(5000, 5000, 10000, 10000)
        req.Open("GET", sumsUrl, false)
        req.Send()
        if req.Status != 200
            return "checksum list: HTTP " req.Status
        sums := req.ResponseText
    } catch as err {
        return "checksum list download failed: " err.Message
    }
    expected := SumFor(sums, fileName)
    if expected = ""
        return "no checksum for " fileName " in the published list"
    actual := HashFile(path, "SHA256")
    if actual != expected
        return "SHA-256 mismatch (got " SubStr(actual, 1, 12) "…, expected " SubStr(expected, 1, 12) "…)"
    return ""
}

; "<sha256>  <name>" / "<sha256> *<name>" (sha256sum format) -> uppercase hash, or ""
SumFor(sums, fileName) {
    return RegExMatch(sums, "im)^([0-9a-f]{64})\s+\*?" RegExEscape(fileName) "\s*$", &m) ? StrUpper(m[1]) : ""
}

RegExEscape(s) {
    return RegExReplace(s, "[\\.*?+\[\]{}()^$|]", "\$0")
}

VerifyDownload(path, fileName, info) {
    if info.sums != "" {
        if (err := VerifySha256Sums(path, info.sums, fileName)) != ""
            return err
    }
    if info.signer != "" {
        if (err := VerifySignature(path, info.signer)) != ""
            return err
    }
    return ""
}

; Download a catalog tool, install binaries to Tools\, cleanup.
; Direct-download entries (info.direct) skip the zip/extract path.
; Returns "" on success, error text on failure.
DownloadAndInstallTool(exeName, info) {
    ; Direct single-exe download
    if info.direct != "" {
        dst := A_ScriptDir "\Tools\" info.direct
        if !DirExist(A_ScriptDir "\Tools")
            DirCreate(A_ScriptDir "\Tools")
        ; Download next to the target, then swap it in: a failed or partial
        ; download must not destroy the working copy.
        part := dst ".download"
        Try FileDelete(part)
        try {
            Download(info.url, part)
        } catch as err {
            Try FileDelete(part)
            return "download failed: " err.Message
        }
        if !FileExist(part) || FileGetSize(part) = 0 {
            Try FileDelete(part)
            return "download failed (empty)"
        }
        if (bad := VerifyDownload(part, info.direct, info)) != "" {
            Try FileDelete(part)
            return "REJECTED — " bad
        }
        try {
            FileMove(part, dst, 1)
        } catch as err {
            Try FileDelete(part)
            return "could not replace " info.direct " (in use?): " err.Message
        }
        return ""
    }

    tmpZip := A_Temp "\toolbox_tool.zip"
    tmpDir := A_Temp "\toolbox_tool"
    Try FileDelete(tmpZip)
    Try DirDelete(tmpDir, true)

    try {
        Download(info.url, tmpZip)
    } catch as err {
        return "download failed: " err.Message
    }
    if !FileExist(tmpZip)
        return "download failed (empty)"

    ; Extract via PowerShell (handles nested x64 folders)
    unzipOut := PsCapture(['Expand-Archive -LiteralPath ' PsQuote(tmpZip) ' -DestinationPath ' PsQuote(tmpDir) ' -Force'], "unzip")
    if !DirExist(tmpDir)
        return "extract failed" (Trim(unzipOut) != "" ? ": " Trim(unzipOut) : "")

    ; Find each catalog binary (search recursively — NirSoft nests x64)
    found := []
    for , want in info.exes {
        best := ""
        Loop Files tmpDir "\*.*", "R" {
            if StrLower(A_LoopFileName) = StrLower(want) {
                ; prefer a build inside an x64\ folder when the zip has one
                ; (checked on the path INSIDE the zip, not the temp dir)
                relPath := StrLower(SubStr(A_LoopFilePath, StrLen(tmpDir) + 2))
                if best = "" || InStr(relPath, "x64\")
                    best := A_LoopFilePath
            }
        }
        if best != ""
            found.Push({src: best, name: want})
    }

    ; Verify every binary BEFORE touching Tools\ — one bad file rejects the
    ; whole package, so a tampered zip can't leave half its files installed
    for , f in found {
        if (bad := VerifyDownload(f.src, f.name, info)) != "" {
            Try FileDelete(tmpZip)
            Try DirDelete(tmpDir, true)
            return "REJECTED " f.name " — " bad
        }
    }

    if !DirExist(A_ScriptDir "\Tools")
        DirCreate(A_ScriptDir "\Tools")
    copied := 0
    for , f in found {
        try {
            FileCopy(f.src, A_ScriptDir "\Tools\" f.name, 1)
            copied++
        }
    }

    ; Cleanup
    Try FileDelete(tmpZip)
    Try DirDelete(tmpDir, true)

    if copied = 0
        return "no expected binaries found in zip"
    return ""
}

; --- Update tools GUI: checkbox list, versions, "newer available" detection ---
ToolUpdater() {
    global favoritesFile, toolCatalog
    entries := []
    loop 50 {
        tLabel := IniRead(favoritesFile, "Tools", "Label" A_Index, "")
        tExe := IniRead(favoritesFile, "Tools", "Exe" A_Index, "")
        if tLabel = "" || tExe = ""
            continue
        info := ""
        if toolCatalog.Has(StrLower(tExe))
            info := toolCatalog[StrLower(tExe)]
        entries.Push({label: tLabel, exe: tExe, info: info})
    }
    ; Built-in tools (skip if already listed in INI)
    for , b in ["yt-dlp.exe", "handle64.exe"] {
        known := false
        for , e in entries {
            if StrLower(e.exe) = StrLower(b)
                known := true
        }
        if !known && toolCatalog.Has(StrLower(b))
            entries.Push({label: StrReplace(b, ".exe", "") " (built-in)", exe: b, info: toolCatalog[StrLower(b)]})
    }

    upg := Gui("", "Toolbox — Update Tools")
    upg.SetFont("s10", "Segoe UI")
    upg.OnEvent("Escape", (*) => upg.Destroy())
    upg.OnEvent("Close", (*) => upg.Destroy())
    upg.AddText("xm", "Outdated tools are pre-checked. Update downloads latest into Tools\ (binaries only).")
    lv := upg.AddListView("xm y+8 w680 h340 -LV0x10 Checked", ["Tool", "Exe", "Version", "Source", "Status"])
    lv.ModifyCol(1, 150), lv.ModifyCol(2, 140), lv.ModifyCol(3, 90), lv.ModifyCol(4, 90), lv.ModifyCol(5, 190)

    ; Build rows: local file version + Last-Modified check vs INI [ToolUpdates]
    for , e in entries {
        if e.info = "" {
            lv.Add("", e.label, e.exe, "", "unknown", "no download source in catalog")
            continue
        }
        resolved := ResolveToolPath(e.exe)
        ver := GetFileVer(resolved)
        status := ""
        check := ""
        if resolved = "" {
            status := "not installed — will download"
            check := "Check"  ; missing: pre-check so first run installs it
        } else {
            status := "checking..."
        }
        lv.Add(check, e.label, e.exe, ver, e.info.suite, status)
    }

    ; Parallel async HEAD requests via WinHttpRequest async mode
    CheckRemoteStatus() {
        reqs := Map()
        for idx, e in entries {
            if e.info = "" || !ResolveToolPath(e.exe)
                continue
            lastSeen := IniRead(favoritesFile, "ToolUpdates", StrLower(e.exe), "")
            if lastSeen = "" {
                lv.Modify(idx, , , , , , "installed — unknown age")
                continue
            }
            try {
                req := ComObject("WinHttp.WinHttpRequest.5.1")
                req.SetTimeouts(2000, 2000, 2000, 2000)
                req.Open("HEAD", e.info.url, true)  ; async mode = true
                req.Send()
                reqs[idx] := {req: req, lastSeen: lastSeen, e: e}
            } catch {
                lv.Modify(idx, , , , , , "installed (check failed)")
            }
        }

        PollAsyncReqs() {
            doneIndices := []
            for idx, item in reqs {
                try {
                    if item.req.WaitForResponse(0.01) {
                        etag := ""
                        try etag := item.req.GetResponseHeader("ETag")
                        lm := ""
                        if etag != ""
                            lm := "ETag:" etag
                        else
                            lm := "LM:" item.req.GetResponseHeader("Last-Modified")

                        if lm = ""
                            newStatus := "installed (check failed)"
                        else if lm = item.lastSeen
                            newStatus := "up to date"
                        else {
                            newStatus := "UPDATE AVAILABLE"
                            lv.Modify(idx, "Check")
                        }
                        lv.Modify(idx, , , , , , newStatus)
                        doneIndices.Push(idx)
                    }
                } catch {
                    lv.Modify(idx, , , , , , "installed (check failed)")
                    doneIndices.Push(idx)
                }
            }
            for , d in doneIndices
                reqs.Delete(d)
            if reqs.Count = 0
                SetTimer(PollAsyncReqs, 0)
        }

        if reqs.Count > 0
            SetTimer(PollAsyncReqs, 50)
    }
    SetTimer(CheckRemoteStatus, -50)

    DoUpdate(*) {
        upg.Opt("+Disabled")  ; block input during sequential downloads
        done := 0, failed := 0
        row := 0
        loop {
            row := lv.GetNext(row, "C")  ; next checked row from last
            if row = 0
                break
            exeName := lv.GetText(row, 2)
            info := toolCatalog[StrLower(exeName)]
            lv.Modify(row, , , , , , "downloading...")
            Sleep(50)
            err := DownloadAndInstallTool(exeName, info)
            if err = "" {
                ; Record remote timestamp so future opens detect changes
                lm := HttpGetChangeToken(info.url)
                if lm != ""
                    IniWrite(lm, favoritesFile, "ToolUpdates", StrLower(exeName))
                lv.Modify(row, "-Check", , , GetFileVer(A_ScriptDir "\Tools\" exeName), , "updated (local)")
                done++
            } else {
                lv.Modify(row, "-Check", , , , , "FAILED: " err)
                failed++
            }
            Sleep(50)
        }
        upg.Opt("-Disabled")
        Notify("Update finished: " done " ok, " failed " failed", 3000)
    }
    upg.AddButton("xm y+10 w160 h32", "&Update checked").OnEvent("Click", DoUpdate)
    allBtn := ""
    DoToggleAll(*) {
        checkedCount := 0
        row := 0
        loop {
            row := lv.GetNext(row, "C")
            if row = 0
                break
            checkedCount++
        }
        if checkedCount < lv.GetCount() {
            loop lv.GetCount()
                lv.Modify(A_Index, "Check")
            allBtn.Text := "Select &none"
        } else {
            loop lv.GetCount()
                lv.Modify(A_Index, "-Check")
            allBtn.Text := "Select &all"
        }
    }
    allBtn := upg.AddButton("x+10 yp w160 h32", "Select &all")
    allBtn.OnEvent("Click", DoToggleAll)
    upg.AddButton("x+10 yp w150 h32", "&Browse catalog...").OnEvent("Click", (*) => (upg.Destroy(), ToolBrowseCatalog()))
    upg.AddButton("x+10 yp w120 h32", "Close").OnEvent("Click", (*) => upg.Destroy())
    ApplyDarkTheme(upg)  ; before Show: DWM paints the caption at show-time
    upg.Show()
}

; --- Browse catalog: install any known tool, auto-register in INI ---
ToolBrowseCatalog() {
    global favoritesFile, toolCatalog
    ; Unique by URL (zip entries appear once per exe in the catalog)
    seen := Map()
    items := []
    for , info in toolCatalog {
        if seen.Has(info.url)
            continue
        seen[info.url] := true
        items.Push(info)
    }

    brw := Gui("", "Toolbox — Tool Catalog")
    brw.SetFont("s10", "Segoe UI")
    brw.OnEvent("Escape", (*) => brw.Destroy())
    brw.OnEvent("Close", (*) => brw.Destroy())
    brw.AddText("xm", "Checked tools are downloaded to Tools\ and added to the Tools menu automatically.")
    lv := brw.AddListView("xm y+8 w640 h380 -LV0x10 Checked", ["Tool", "Source", "Files", "Status"])
    lv.ModifyCol(1, 160), lv.ModifyCol(2, 100), lv.ModifyCol(3, 210), lv.ModifyCol(4, 150)

    for , info in items {
        anyLocal := false
        for , e in info.exes {
            if FileExist(A_ScriptDir "\Tools\" e) || ResolveToolPath(e) != ""
                anyLocal := true
        }
        status := anyLocal ? "already available" : "not installed"
        lv.Add("", info.name, info.suite, StrJoin(info.exes, ", "), status)
    }

    DoInstall(*) {
        brw.Opt("+Disabled")
        done := 0, failed := 0, added := 0
        row := 0
        loop {
            row := lv.GetNext(row, "C")
            if row = 0
                break
            name := lv.GetText(row, 1)
            ; find catalog info by display name
            info := ""
            for , i2 in items {
                if i2.name = name
                    info := i2
            }
            if info = "" {
                lv.Modify(row, "-Check", , , , "FAILED: not found")
                failed++
                continue
            }
            primary := info.exes[1]
            lv.Modify(row, , , , , "downloading...")
            Sleep(50)
            err := DownloadAndInstallTool(primary, info)
            if err = "" {
                lm := HttpGetChangeToken(info.url)
                if lm != ""
                    IniWrite(lm, favoritesFile, "ToolUpdates", StrLower(primary))
                if RegisterToolInIni(info.name, primary)
                    added++
                lv.Modify(row, "-Check", , , , "installed + added to menu")
                done++
            } else {
                lv.Modify(row, "-Check", , , , "FAILED: " err)
                failed++
            }
            Sleep(50)
        }
        brw.Opt("-Disabled")
        msg := "Installed: " done ", failed: " failed ", menu entries added: " added
        if added > 0
            msg .= "`n`nReload Toolbox to show new menu entries?"
        if added > 0 {
            if MsgBox(msg, "Tool Catalog", 52) = "Yes"
                Reload()
        } else {
            Notify(msg, 3000)
        }
    }
    brw.AddButton("xm y+10 w160 h32", "&Install checked").OnEvent("Click", DoInstall)
    brw.AddButton("x+10 yp w160 h32", "Close").OnEvent("Click", (*) => brw.Destroy())
    ApplyDarkTheme(brw)  ; before Show: DWM paints the caption at show-time
    brw.Show()
}

; Register a downloaded tool in INI [Tools] (skip if already present by exe).
; Returns true if a new entry was added.
RegisterToolInIni(label, exeName) {
    global favoritesFile
    loop 50 {
        existing := IniRead(favoritesFile, "Tools", "Exe" A_Index, "")
        if StrLower(existing) = StrLower(exeName)
            return false  ; already registered
    }
    slot := 0
    loop 50 {
        if IniRead(favoritesFile, "Tools", "Label" A_Index, "") = "" {
            slot := A_Index
            break
        }
    }
    if slot = 0
        return false
    IniWrite(label, favoritesFile, "Tools", "Label" slot)
    IniWrite(exeName, favoritesFile, "Tools", "Exe" slot)
    return true
}

; Join array of strings with separator
; (separator only BETWEEN items — RTrim(out, sep) would also eat trailing
; separator characters that belong to the last item)
StrJoin(arr, sep) {
    out := ""
    for i, s in arr
        out .= (i > 1 ? sep : "") s
    return out
}
