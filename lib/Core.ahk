; ============================================================
; SHARED UTILITIES: run & capture, show output, pick menus, temp PS
; ============================================================

; Run a console command hidden and return its stdout + stderr (merged, in
; order). Blocks until the command finishes.
; Why a temp file and not WScript.Shell.Exec: Exec always flashes a console
; window, and reading its two pipes one after the other deadlocks as soon as
; the child fills the pipe we are NOT reading (~4 KB of PowerShell errors on
; stderr is enough). cmd's "> file 2>&1" has no pipes, so it cannot deadlock.
; Caveat: the line goes through cmd, so a literal %NAME% in it is expanded.
; exitCode (optional, by ref): the command's exit code, -1 if it couldn't run.
RunCapture(cmd, &exitCode := 0) {
    static runCount := 0
    runCount += 1
    capFile := A_Temp "\toolbox_cap" DllCall("GetCurrentProcessId") "_" runCount ".txt"
    output := ""
    try {
        ; /S: strip exactly the outer quote pair, keep every inner quote as-is
        exitCode := RunWait(A_ComSpec ' /S /C "' cmd ' > "' capFile '" 2>&1"', , "Hide")
        if FileExist(capFile)
            output := FileRead(capFile, "CP" DllCall("GetOEMCP", "UInt"))  ; console output is OEM codepage
    } catch as err {
        exitCode := -1
        output := "Error: " err.Message
    }
    try FileDelete(capFile)
    return output
}

; ---- Background (non-blocking) capture ----
; Same hidden "> file 2>&1" trick as RunCapture, but without waiting: the
; command runs while hotkeys/menus stay responsive. A timer polls the
; process; meanwhile tooltip #2 lists what's running ("Notify" uses #1).
; onDone(output, exitCode, timedOut) is called once, on the main thread.
; On timeout the whole process tree (cmd + PowerShell + children) is killed.
global gRunningTasks := Map()   ; task id -> {label, start}

RunCaptureAsync(cmd, onDone, label := "", timeoutMs := 120000) {
    static taskCount := 0
    global gRunningTasks
    taskCount += 1
    id := taskCount
    capFile := A_Temp "\toolbox_acap" DllCall("GetCurrentProcessId") "_" id ".txt"
    cmdPid := 0
    try Run(A_ComSpec ' /S /C "' cmd ' > "' capFile '" 2>&1"', , "Hide", &cmdPid)
    catch as err {
        onDone("Error: " err.Message, -1, false)
        return
    }
    ; SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION: wait + read exit code
    hProc := DllCall("OpenProcess", "UInt", 0x00101000, "Int", 0, "UInt", cmdPid, "Ptr")
    start := A_TickCount
    if label != ""
        gRunningTasks[id] := {label: label, start: start}

    Poll() {
        done := !hProc || DllCall("WaitForSingleObject", "Ptr", hProc, "UInt", 0, "UInt") = 0
        timedOut := false
        if !done && (A_TickCount - start) > timeoutMs {
            RunWait('taskkill /T /F /PID ' cmdPid, , "Hide")
            timedOut := done := true
        }
        if !done {
            RefreshRunningTip()
            return
        }
        SetTimer(Poll, 0)
        code := -1
        if hProc {
            DllCall("GetExitCodeProcess", "Ptr", hProc, "UInt*", &code)
            DllCall("CloseHandle", "Ptr", hProc)
        }
        output := ""
        try output := FileRead(capFile, "CP" DllCall("GetOEMCP", "UInt"))
        try FileDelete(capFile)
        if gRunningTasks.Has(id)
            gRunningTasks.Delete(id)
        RefreshRunningTip()
        onDone(output, code, timedOut)
    }
    SetTimer(Poll, 150)
}

; Tooltip #2: one line per running background task, with elapsed seconds.
; Short tasks (< 0.5 s) never show it.
RefreshRunningTip() {
    global gRunningTasks
    text := ""
    for , t in gRunningTasks {
        secs := (A_TickCount - t.start) // 1000
        if (A_TickCount - t.start) >= 500
            text .= (text = "" ? "" : "`n") "Running: " t.label "  (" secs " s)"
    }
    if text = ""
        ToolTip(, , , 2)
    else
        ToolTip(text, , , 2)
}

; PsCapture, non-blocking: onDone(output, exitCode, timedOut)
PsCaptureAsync(psLines, name, onDone, label := "", timeoutMs := 120000) {
    tmpPs := PsWrite(psLines, name)
    Finish(output, code, timedOut) {
        Try FileDelete(tmpPs)
        onDone(output, code, timedOut)
    }
    RunCaptureAsync('powershell -NoProfile -ExecutionPolicy Bypass -File "' tmpPs '"', Finish, label, timeoutMs)
}

; The common case: run an info script in the background, show the result
; in the output console when it's done (title doubles as the task label).
PsShowAsync(psLines, name, title, timeoutMs := 120000) {
    Show(output, code, timedOut) {
        if timedOut
            output .= "`n`n[Stopped: no result after " timeoutMs // 1000 " s]"
        ShowText(title, output)
    }
    PsCaptureAsync(psLines, name, Show, title, timeoutMs)
}

; Short status tooltip that clears itself. One shared timer: a newer message
; restarts it, so an older timer can't clear the newer tooltip early.
Notify(msg, ms := 1500) {
    static clearFn := () => ToolTip()
    ToolTip(msg)
    SetTimer(clearFn, -ms)
}

; ---- CNG (bcrypt.dll) helpers: hashing + crypto RNG, no PowerShell ----
; algo: "SHA256" | "SHA1" | "MD5" (CNG algorithm ids). Returns uppercase hex.
BcryptCheck(status, what) {
    if status != 0
        throw Error(what " failed (NTSTATUS 0x" Format("{:08X}", status & 0xFFFFFFFF) ")")
}

BcryptBegin(algo) {
    hAlg := 0, hHash := 0, digestLen := 0, cb := 0
    BcryptCheck(DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &hAlg, "WStr", algo, "Ptr", 0, "UInt", 0, "UInt"), "BCryptOpenAlgorithmProvider")
    DllCall("bcrypt\BCryptGetProperty", "Ptr", hAlg, "WStr", "HashDigestLength", "UInt*", &digestLen, "UInt", 4, "UInt*", &cb, "UInt", 0, "UInt")
    st := DllCall("bcrypt\BCryptCreateHash", "Ptr", hAlg, "Ptr*", &hHash, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0, "UInt", 0, "UInt")
    if st != 0 {
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)
        BcryptCheck(st, "BCryptCreateHash")
    }
    return {alg: hAlg, hash: hHash, len: digestLen}
}

BcryptUpdate(h, ptr, size) {
    BcryptCheck(DllCall("bcrypt\BCryptHashData", "Ptr", h.hash, "Ptr", ptr, "UInt", size, "UInt", 0, "UInt"), "BCryptHashData")
}

BcryptFinish(h) {
    out := Buffer(h.len)
    BcryptCheck(DllCall("bcrypt\BCryptFinishHash", "Ptr", h.hash, "Ptr", out, "UInt", h.len, "UInt", 0, "UInt"), "BCryptFinishHash")
    hex := ""
    loop h.len
        hex .= Format("{:02X}", NumGet(out, A_Index - 1, "UChar"))
    return hex
}

BcryptClose(h) {
    DllCall("bcrypt\BCryptDestroyHash", "Ptr", h.hash)
    DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", h.alg, "UInt", 0)
}

; Hash text as its UTF-8 bytes (no BOM) — same bytes any other tool sees
HashText(text, algo := "SHA256") {
    n := StrPut(text, "UTF-8") - 1
    buf := Buffer(Max(n, 1))
    StrPut(text, buf, "UTF-8")
    h := BcryptBegin(algo)
    try {
        BcryptUpdate(h, buf, n)
        return BcryptFinish(h)
    } finally
        BcryptClose(h)
}

; Hash a file in 1 MB chunks (constant memory, works on multi-GB files)
HashFile(path, algo := "SHA256") {
    f := FileOpen(path, "r")
    if !f
        throw Error("cannot open file")
    h := BcryptBegin(algo)
    try {
        buf := Buffer(1 << 20)
        while (n := f.RawRead(buf, buf.Size)) > 0
            BcryptUpdate(h, buf, n)
        return BcryptFinish(h)
    } finally {
        f.Close()
        BcryptClose(h)
    }
}

; Fill a Buffer with cryptographically secure random bytes
RandomBytes(n) {
    buf := Buffer(n)
    BcryptCheck(DllCall("bcrypt\BCryptGenRandom", "Ptr", 0, "Ptr", buf, "UInt", n, "UInt", 2, "UInt"), "BCryptGenRandom")  ; 2 = BCRYPT_USE_SYSTEM_PREFERRED_RNG
    return buf
}

; Random string over an alphabet, without modulo bias: bytes >= the largest
; multiple of the alphabet size are thrown away and redrawn.
RandomString(len, alphabet) {
    k := StrLen(alphabet)
    limit := 256 - Mod(256, k)
    out := ""
    while StrLen(out) < len {
        buf := RandomBytes(len * 2)
        loop buf.Size {
            b := NumGet(buf, A_Index - 1, "UChar")
            if b < limit
                out .= SubStr(alphabet, Mod(b, k) + 1, 1)
            if StrLen(out) = len
                break
        }
    }
    return out
}

; New random GUID, lowercase, no braces (CoCreateGuid = v4 random)
NewGuid() {
    g := Buffer(16)
    if DllCall("ole32\CoCreateGuid", "Ptr", g) != 0
        throw Error("CoCreateGuid failed")
    s := Buffer(39 * 2)
    DllCall("ole32\StringFromGUID2", "Ptr", g, "Ptr", s, "Int", 39)
    return StrLower(Trim(StrGet(s, "UTF-16"), "{}"))
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

; The standard pattern for all the "show me info" tools:
;   1. build an array of PowerShell lines   psLines := [] / psLines.Push('...')
;   2. run it in the background + display   PsShowAsync(psLines, "name", "Title")
; PsCapture is the blocking variant (returns the output) for callers that
; need the result right away. Temp file names are unique (PsWrite), so two
; tools can run at the same time; CleanupOldTemp removes leftovers on the
; next Toolbox start.
PsCapture(psLines, name := "ps") {
    tmpPs := PsWrite(psLines, name)
    output := RunCapture('powershell -NoProfile -ExecutionPolicy Bypass -File "' tmpPs '"')
    Try FileDelete(tmpPs)
    return output
}

; Same idea for the scripts that run in a VISIBLE window: join + write the
; lines to a unique temp .ps1 and return its path for RunTempPsVisible().
PsWrite(psLines, name := "ps") {
    static runCount := 0
    runCount += 1
    psScript := ""
    for , line in psLines
        psScript .= line "`n"
    return WriteTempPs("toolbox_" name runCount ".ps1", psScript)
}

; Quote a value as a PowerShell single-quoted literal ('it''s' style) —
; safe for adapter names, paths, URLs: nothing inside gets expanded.
PsQuote(s) {
    sq := "'"
    return sq StrReplace(s, sq, sq sq) sq
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

; ---- Address validation for user input that lands on a command line ----
; Accepts an IPv4 address, an IPv6 literal or a DNS name. Anything with
; quotes, spaces or shell characters (& | ^ < >) fails, so it can't break
; out of the quoted argument it is placed in.
IsValidHost(s) {
    if s = ""
        return false
    if RegExMatch(s, "^[\d.]+$")              ; all digits/dots: must be real IPv4
        return IpToInt(s) >= 0
    if RegExMatch(s, "^[0-9A-Fa-f:]+(%[\w.-]+)?$") && StrLen(s) - StrLen(StrReplace(s, ":")) >= 2
        return true                           ; IPv6 literal (optional %zone)
    return RegExMatch(s, "^(?=.{1,253}$)[A-Za-z0-9_](?:[A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?"
        . "(?:\.[A-Za-z0-9_](?:[A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\.?$") > 0
}

; kind: "host" | "user@host" (SSH, user optional) | "host:port" (port
; optional) | "url" (host[:port][/path], for the browser)
IsValidAddress(s, kind := "host") {
    switch kind {
        case "user@host":
            ; user must start with a letter/digit: "-oOption@host" would be read as an ssh option
            if RegExMatch(s, "^(\w[\w.-]*)@(.+)$", &m)
                s := m[2]
            return IsValidHost(s)
        case "host:port":
            if RegExMatch(s, "^([^:]+):(\d{1,5})$", &m)
                return IsValidHost(m[1]) && Integer(m[2]) >= 1 && Integer(m[2]) <= 65535
            return IsValidHost(s)
        case "url":  ; [http(s)://]host[:port][/path]
            s := RegExReplace(s, "i)^https?://")
            if !RegExMatch(s, "^([^/\s`"'<>|^&]+)(/[^\s`"'<>|^]*)?$", &m)
                return false
            return IsValidAddress(m[1], "host:port")
    }
    return IsValidHost(s)
}

; Prompt for an address with the shared [AddressFavorites] quick-pick,
; validate it, and only then remember it. Re-prompts (pre-filled) on bad
; input. Returns "" when cancelled.
AskAddress(prompt, title, kind := "host", boxOpts := "w500 h320") {
    favs := LoadFavorites("AddressFavorites")
    fullPrompt := prompt "`n" FormatFavoritesPrompt(favs, "Recent addresses: ")
    value := ""
    loop {
        r := TbInputBox(fullPrompt, title, boxOpts, value)
        if r.Result != "OK" || Trim(r.Value) = ""
            return ""
        value := Trim(ResolveInput(r.Value, favs))
        if IsValidAddress(value, kind) {
            AddFavorite(value, "AddressFavorites")
            return value
        }
        hint := kind = "user@host" ? "an IP or hostname, optionally user@host"
              : kind = "host:port" ? "an IP or hostname, optionally :port"
              : kind = "url" ? "an IP or hostname, optionally :port and /path"
              : "an IP address or hostname"
        MsgBox("'" value "' is not valid.`n`nExpected " hint ".", title, 48)
    }
}

; Validate + normalize static-IP input BEFORE it is put on a netsh command
; line (this runs elevated; an unchecked "&" would be a command injection).
; ip / dns: comma-separated IPv4 lists; mask: dotted or /N; gw, dns optional.
; Returns {ok: true, ips: [...], mask: "255.255.255.0", gw: "", dns: [...]}
; or {ok: false, error: "..."}. Pure — no GUI.
ValidateStaticIp(ip, mask, gw, dns) {
    ips := ParseIpList(ip)
    if ips.Length = 0
        return {ok: false, error: "No IP address given."}
    for , a in ips {
        if IpToInt(a) < 0
            return {ok: false, error: "'" a "' is not a valid IPv4 address."}
    }
    r := SubnetCalc(ips[1] " " Trim(mask))
    if !r.ok
        return {ok: false, error: r.error}
    if r.cidr < 1
        return {ok: false, error: "Mask /0 is not usable for a static address."}
    gw := Trim(gw)
    if gw != "" && IpToInt(gw) < 0
        return {ok: false, error: "Gateway '" gw "' is not a valid IPv4 address."}
    dnsList := ParseIpList(dns)
    for , d in dnsList {
        if IpToInt(d) < 0
            return {ok: false, error: "DNS server '" d "' is not a valid IPv4 address."}
    }
    return {ok: true, ips: ips, mask: IntToIp(r.mask), gw: gw, dns: dnsList}
}

; Parse "IP MASK", "IP /N" or "IP/N" and compute the subnet. Pure — no GUI.
; Returns {ok: true, ip, mask, cidr, network, broadcast, hosts} (ints), or
; {ok: false, error: "..."}.
SubnetCalc(text) {
    text := Trim(StrReplace(text, "/", " /"))
    parts := StrSplit(RegExReplace(text, "\s+", " "), " ")
    if parts.Length != 2
        return {ok: false, error: "Enter IP and mask, separated by a space (or IP/CIDR like 10.0.0.5/22)."}
    ip := IpToInt(parts[1])
    mask := ParseMask(parts[2])
    if ip < 0 || mask < 0
        return {ok: false, error: "Invalid IP or mask."}
    wild := mask ^ 0xFFFFFFFF
    if (wild & (wild + 1)) != 0  ; mask bits must be contiguous (no 255.0.255.0)
        return {ok: false, error: "Invalid mask (bits not contiguous)."}
    cidr := 0
    loop 32 {
        if (mask >> (32 - A_Index)) & 1
            cidr++
    }
    network := ip & mask
    broadcast := network | wild
    hosts := mask = 0xFFFFFFFF ? 1 : broadcast - network - 1
    return {ok: true, ip: ip, mask: mask, cidr: cidr, network: network, broadcast: broadcast, hosts: hosts}
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
; Called from every WM_CTLCOLOR* paint message, so the INI + registry
; lookup is cached briefly (a system theme switch still shows up within 2 s).
IsDarkMode() {
    static cached := false, cachedTick := 0
    if cachedTick && (A_TickCount - cachedTick) < 2000
        return cached
    cached := ReadDarkModeSetting()
    cachedTick := A_TickCount
    return cached
}

ReadDarkModeSetting() {
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

; ---- dark ListView header text via NM_CUSTOMDRAW ----
; Themed headers ignore WM_CTLCOLOR*, so we custom-draw their text.
global gDarkHeaders := Map()

OnWmNotify(wParam, lParam, msg, hwnd) {
    global gDarkHeaders
    if !gDarkHeaders.Count
        return
    if (NumGet(lParam + 0, 16, "Int") != -12)  ; NM_CUSTOMDRAW
        return
    hwndFrom := NumGet(lParam + 0, 0, "Ptr")
    if !gDarkHeaders.Has(hwndFrom)
        return
    stage := NumGet(lParam + 0, 24, "UInt")   ; NMCUSTOMDRAW.dwDrawStage
    if (stage = 1)                             ; CDDS_PREPAINT
        return 0x20                            ; CDRF_NOTIFYITEMDRAW
    if (stage = 0x10001) {                     ; CDDS_ITEMPREPAINT
        hdc := NumGet(lParam + 0, 32, "Ptr")
        DllCall("gdi32\SetTextColor", "Ptr", hdc, "UInt", 0x00E8E8EA)
        DllCall("gdi32\SetBkColor", "Ptr", hdc, "UInt", 0x00202020)
        return 2                               ; CDRF_NEWFONT
    }
}

; Drop a window's controls from the per-control color + dark-header maps.
; Call before Destroy(): window handles are recycled, so a stale entry
; would paint some unrelated future control with these colors.
ForgetGuiColors(guiObj) {
    global gCtlColors, gDarkHeaders
    for , ctrl in guiObj {
        try {
            gCtlColors.Delete(ctrl.Hwnd)
        }
        try {
            if ctrl.Type = "ListView"
                gDarkHeaders.Delete(SendMessage(0x101F, 0, 0, ctrl.Hwnd))  ; LVM_GETHEADER
        }
    }
}

; Remove entries whose window no longer exists (GUIs closed without
; ForgetGuiColors — most dialogs just Destroy()). Run when registering.
PruneDeadColorEntries() {
    global gCtlColors, gDarkHeaders
    for , m in [gCtlColors, gDarkHeaders] {
        dead := []
        for hwnd in m
            if !DllCall("IsWindow", "Ptr", hwnd)
                dead.Push(hwnd)
        for , hwnd in dead
            m.Delete(hwnd)
    }
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
    for msgId in [0x0133, 0x0134, 0x0135, 0x0138]  ; WM_CTLCOLOREDIT/LISTBOX/BTN/STATIC
        OnMessage(msgId, OnWmCtlColor)
    OnMessage(0x004E, OnWmNotify)          ; WM_NOTIFY (dark header custom draw)
    done := true
}

; One handler for all four WM_CTLCOLOR* messages. Per-control colors
; (SetCtlColors) win; otherwise, in dark mode, a per-message default.
; LISTBOX also covers ComboBox dropped lists — that popup is a separate
; top-level window, so SetWindowTheme alone doesn't darken it.
; Brushes come from ThemeBrush(): they must outlive the message.
OnWmCtlColor(wParam, lParam, msg, hwnd) {
    global gCtlColors
    static defaults := Map(                    ; msg -> [text, background] (BGR)
        0x0133, [0x00FFFFFF, 0x002B2B2B],      ; EDIT
        0x0134, [0x00FFFFFF, 0x002B2B2B],      ; LISTBOX
        0x0135, [0x00FFFFFF, 0x001F1F1F],      ; BTN
        0x0138, [0x00E0E0E0, 0x001F1F1F])      ; STATIC (Text, read-only Edit)
    if gCtlColors.Has(lParam) {
        c := gCtlColors[lParam]
        fg := c.fg, bk := c.bk
    } else {
        if !IsDarkMode()
            return
        fg := defaults[msg][1], bk := defaults[msg][2]
    }
    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", fg)
    DllCall("gdi32\SetBkColor", "Ptr", wParam, "UInt", bk)
    return ThemeBrush(bk)
}

; Set a top-level Gui window's titlebar/taskbar icon (Gui has no SetIcon).
; Loads .ico from file and sets both big + small via WM_SETICON.
SetWindowIcon(guiObj, icoPath) {
    static WM_SETICON := 0x80, ICON_BIG := 1, ICON_SMALL := 0, LR_LOADFROMFILE := 0x10
    if !FileExist(icoPath)
        return
    hIcon := DllCall("user32\LoadImage", "Ptr", 0, "Str", icoPath, "UInt", 1  ; IMAGE_ICON
        , "Int", 0, "Int", 0, "UInt", LR_LOADFROMFILE, "Ptr")
    if !hIcon
        return
    SendMessage(WM_SETICON, ICON_BIG, hIcon, guiObj)
    SendMessage(WM_SETICON, ICON_SMALL, hIcon, guiObj)
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
    global THEME_TEXT
    if !IsDarkMode()
        return
    PruneDeadColorEntries()  ; keep the maps from filling with closed GUIs' hwnds
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
                ; Theme header control + color fallback (themed header may
                ; ignore CTLCOLOR; if so the hook below still supplies colors)
                hdrHwnd := SendMessage(0x101F, 0, 0, ctrl.Hwnd)
                if hdrHwnd {
                    DllCall("uxtheme\SetWindowTheme", "Ptr", hdrHwnd, "WStr", "DarkMode_ItemsView", "Ptr", 0)
                    gDarkHeaders[hdrHwnd] := true
                }
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
