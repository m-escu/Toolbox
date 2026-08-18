; ============================================================
; SYSTEM COMMANDS
; ============================================================

; --- Toggle Wi-Fi ---
ToggleWifi() {
    if !RequireAdmin("Toggle Wi-Fi")
        return
    ; Detect the Wi-Fi adapter name dynamically
    wifiAdapter := ""
    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec('powershell -NoProfile -Command "(Get-NetAdapter -InterfaceType Wi-Fi).Name"')
        wifiAdapter := Trim(exec.StdOut.ReadAll())
        ; Remove any newlines (take first result)
        if InStr(wifiAdapter, "`n")
            wifiAdapter := Trim(StrSplit(wifiAdapter, "`n", "`r")[1])
    }
    if wifiAdapter = "" {
        MsgBox("No Wi-Fi adapter detected.", "Wi-Fi Toggle", 48)
        return
    }
    ; Check current state via PowerShell (Status: Up / Disabled) and toggle
    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec("powershell -NoProfile -Command `"(Get-NetAdapter -Name '" wifiAdapter "').Status`"")
        status := Trim(exec.StdOut.ReadAll())
        if InStr(status, "Up") || InStr(status, "Connected") {
            Run('cmd /k netsh interface set interface "' wifiAdapter '" disable')
            ToolTip(wifiAdapter " disabled")
        } else {
            Run('cmd /k netsh interface set interface "' wifiAdapter '" enable')
            ToolTip(wifiAdapter " enabled")
        }
        SetTimer(() => ToolTip(), -2000)
    } catch as err {
        MsgBox("Could not toggle Wi-Fi: " err.Message, "Wi-Fi Toggle", 48)
    }
}

; ============================================================
; NEW SYSTEM COMMANDS
; ============================================================

; --- Restart ---
SysRestart() {
    if !RequireAdmin("Restart")
        return
    delay := TbInputBox("Restart delay in seconds (0 = immediate):", "Restart", "w350 h160", "0")
    if delay.Result != "OK"
        return
    secs := RegExMatch(delay.Value, "^\d+$") ? Integer(delay.Value) : 0
    ; Confirmation safeguard (INI-toggleable: ConfirmRestart in [Settings], default 1)
    confirm := IniRead(favoritesFile, "Settings", "ConfirmRestart", "1")
    if confirm = "1" {
        delayText := secs > 0 ? "in " secs " seconds" : "immediately"
        result := MsgBox("Restart " delayText "?`n`nThis cannot be undone.", "Confirm Restart", 49)  ; OK+Cancel with ! icon
        if result != "OK"
            return
    }
    if secs > 0
        Run('cmd /k shutdown /r /t ' secs)
    else
        Run('cmd /k shutdown /r /t 0')
}

; --- Shutdown ---
SysShutdown() {
    if !RequireAdmin("Shutdown")
        return
    delay := TbInputBox("Shutdown delay in seconds (0 = immediate):", "Shutdown", "w350 h160", "0")
    if delay.Result != "OK"
        return
    secs := RegExMatch(delay.Value, "^\d+$") ? Integer(delay.Value) : 0
    ; Confirmation safeguard (INI-toggleable: ConfirmShutdown in [Settings], default 1)
    confirm := IniRead(favoritesFile, "Settings", "ConfirmShutdown", "1")
    if confirm = "1" {
        delayText := secs > 0 ? "in " secs " seconds" : "immediately"
        result := MsgBox("Shutdown " delayText "?`n`nThis cannot be undone.", "Confirm Shutdown", 49)  ; OK+Cancel with ! icon
        if result != "OK"
            return
    }
    if secs > 0
        Run('cmd /k shutdown /s /t ' secs)
    else
        Run('cmd /k shutdown /s /t 0')
}

; --- Kill process by name ---
SysKillProcess() {
    if !RequireAdmin("Kill process")
        return
    input := TbInputBox("Enter process name (e.g. notepad.exe):", "Kill Process", "w400 h160")
    if input.Result = "OK" && input.Value != "" {
        procName := Trim(input.Value)
        if !InStr(procName, ".")
            procName .= ".exe"
        output := ""
        try {
            shell := ComObject("WScript.Shell")
            exec := shell.Exec('taskkill /F /IM "' procName '"')
            output := exec.StdOut.ReadAll()
        } catch as err {
            output := "Error: " err.Message
        }
        MsgBox(output, "Kill Process: " procName, 64)
    }
}

; Helper: proper Unix epoch via GetSystemTimeAsFileTime
GetUnixEpoch() {
    ft := Buffer(8, 0)
    DllCall("GetSystemTimeAsFileTime", "Ptr", ft)
    fileTime := NumGet(ft, 0, "Int64")
    return fileTime // 10000000 - 11644473600
}

; ============================================================
; SYSTEM INFO COMMANDS
; ============================================================

; --- Copy computer name / IP / username to clipboard ---
GetLocalIps() {
    psLines := []
    psLines.Push('Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike "169.*" -and $_.IPAddress -ne "127.0.0.1"} | Select-Object -ExpandProperty IPAddress')
    psScript := ""
    for , line in psLines
        psScript .= line "`n"
    tmpPs := WriteTempPs("toolbox_ips.ps1", psScript)
    output := RunCapture('powershell -NoProfile -ExecutionPolicy Bypass -File "' tmpPs '"')
    Try FileDelete(tmpPs)
    return output
}

CopyInfoItem(what) {
    text := ""
    if what = "computername"
        text := A_ComputerName
    else if what = "user"
        text := A_UserName
    else if what = "ip"
        text := StrReplace(Trim(GetLocalIps()), "`r`n", ", ")
    else if what = "all" {
        ip := StrReplace(Trim(GetLocalIps()), "`r`n", ", ")
        text := "Host: " A_ComputerName "`nUser: " A_UserName "`nIP: " ip
    }
    if text != "" {
        A_Clipboard := text
        ToolTip("Copied: " StrReplace(text, "`n", "  "))
        SetTimer(() => ToolTip(), -2500)
    } else {
        ToolTip("Could not get info.")
        SetTimer(() => ToolTip(), -2000)
    }
}

; --- Uptime & disk space ---
SysUptimeDisk() {
    psLines := []
    psLines.Push('$os = Get-CimInstance Win32_OperatingSystem')
    psLines.Push('$up = (Get-Date) - $os.LastBootUpTime')
    psLines.Push('Write-Host ("Uptime: {0}d {1:00}h {2:00}m" -f $up.Days, $up.Hours, $up.Minutes)')
    psLines.Push('Write-Host ""')
    psLines.Push('Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object { $free=[math]::Round($_.FreeSpace/1GB,1); $total=[math]::Round($_.Size/1GB,1); Write-Host ("{0}  {1} GB free of {2} GB" -f $_.DeviceID, $free, $total) }')
    psScript := ""
    for , line in psLines
        psScript .= line "`n"
    tmpPs := WriteTempPs("toolbox_uptime.ps1", psScript)
    output := RunCapture('powershell -NoProfile -ExecutionPolicy Bypass -File "' tmpPs '"')
    Try FileDelete(tmpPs)
    MsgBox(output, "Uptime & Disk Space", 64)
}

; --- Recent event log errors ---
SysEventErrors() {
    psLines := []
    psLines.Push('$ev = Get-WinEvent -FilterHashtable @{LogName="System"; Level=2} -MaxEvents 25 -ErrorAction SilentlyContinue')
    psLines.Push('if ($ev) { $ev | Format-Table -AutoSize TimeCreated, ProviderName, Id, @{N="Message";E={($_.Message -split "``r?``n")[0]}} | Out-String -Width 250 }')
    psLines.Push('else { Write-Host "No error events found." }')
    psScript := ""
    for , line in psLines
        psScript .= line "`n"
    tmpPs := WriteTempPs("toolbox_events.ps1", psScript)
    output := RunCapture('powershell -NoProfile -ExecutionPolicy Bypass -File "' tmpPs '"')
    Try FileDelete(tmpPs)
    ShowText("Event Log Errors (System)", output)
}

; --- Reduce working set of running processes (free RAM) ---
SysReduceWorkingSet() {
    if !RequireAdmin("Reduce working set")
        return
    psLines := []
    psLines.Push('$sig = "[DllImport(\"psapi.dll\")] public static extern int EmptyWorkingSet(IntPtr h);"')
    psLines.Push('$psapi = Add-Type -MemberDefinition $sig -Name PSAPI -Namespace Win32 -PassThru')
    psLines.Push('$before = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB, 2)')
    psLines.Push('$trimmed = 0; $skipped = 0')
    psLines.Push('Get-Process | Where-Object { $_.WorkingSet64 -gt 20MB } | ForEach-Object {')
    psLines.Push('    try { if ($psapi::EmptyWorkingSet($_.Handle)) { $trimmed++ } else { $skipped++ } } catch { $skipped++ }')
    psLines.Push('}')
    psLines.Push('Start-Sleep -Seconds 1')
    psLines.Push('$after = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB, 2)')
    psLines.Push('Write-Host ("Trimmed: {0} process(es), skipped: {1} (access denied)" -f $trimmed, $skipped)')
    psLines.Push('Write-Host ("Free RAM: {0} GB -> {1} GB  ({2:+0.00;-0.00} GB)" -f $before, $after, ($after - $before))')
    psScript := ""
    for , line in psLines
        psScript .= line "`n"
    tmpPs := WriteTempPs("toolbox_trimmem.ps1", psScript)
    output := RunCapture('powershell -NoProfile -ExecutionPolicy Bypass -File "' tmpPs '"')
    Try FileDelete(tmpPs)
    MsgBox(output, "Reduce Working Set", 64)
}

; --- Clean temp folder (delete contents of %TEMP%, skip in-use files) ---
SysCleanTemp() {
    result := MsgBox("Delete the contents of your temp folder?`n`n" A_Temp "`n`nFiles currently in use are skipped automatically.", "Clean Temp Folder", 49)
    if result != "OK"
        return
    psLines := []
    psLines.Push('$temp = [System.IO.Path]::GetTempPath()')
    psLines.Push('$before = 0; $after = 0')
    psLines.Push('Get-ChildItem $temp -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $before += $_.Length }')
    psLines.Push('$removed = 0; $skipped = 0')
    psLines.Push('Get-ChildItem $temp -Force | Where-Object { $_.Name -notlike "toolbox_*" } | ForEach-Object {')
    psLines.Push('    try { Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop; $removed++ } catch { $skipped++ }')
    psLines.Push('}')
    psLines.Push('Get-ChildItem $temp -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $after += $_.Length }')
    psLines.Push('$freed = [math]::Round(($before - $after)/1MB, 1)')
    psLines.Push('Write-Host ("Removed: {0} item(s), skipped: {1} (in use / access denied)" -f $removed, $skipped)')
    psLines.Push('Write-Host ("Freed: {0} MB" -f $freed)')
    psScript := ""
    for , line in psLines
        psScript .= line "`n"
    tmpPs := WriteTempPs("toolbox_cleantemp.ps1", psScript)
    output := RunCapture('powershell -NoProfile -ExecutionPolicy Bypass -File "' tmpPs '"')
    Try FileDelete(tmpPs)
    MsgBox(output, "Clean Temp Folder", 64)
}

; Subsequence fuzzy match: every needle char must appear in order.
; Returns gap-sum score (lower = tighter), or -1 if no match.
FuzzyScore(needle, hay) {
    pos := 1, score := 0
    for , ch in StrSplit(needle) {
        found := InStr(hay, ch, true, pos)
        if found = 0
            return -1
        score += found - pos  ; consecutive chars add 1, skips add more
        pos := found + 1
    }
    return score
}
