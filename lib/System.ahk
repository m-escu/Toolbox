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
    psLines.Push("$sig = '[DllImport(`"psapi.dll`")] public static extern int EmptyWorkingSet(IntPtr h);'")
    psLines.Push('$psapi = Add-Type -MemberDefinition $sig -Name PSAPI -Namespace Win32 -PassThru')
    psLines.Push("$getAvail = { [math]::Round((Get-Counter `"\Memory\Available MBytes`").CounterSamples.CookedValue/1024, 2) }")
    psLines.Push('$before = & $getAvail')
    psLines.Push('$trimmed = 0; $skipped = 0')
    psLines.Push('Get-Process | Where-Object { $_.WorkingSet64 -gt 20MB } | ForEach-Object {')
    psLines.Push('    try { if ($psapi::EmptyWorkingSet($_.Handle)) { $trimmed++ } else { $skipped++ } } catch { $skipped++ }')
    psLines.Push('}')
    psLines.Push('Start-Sleep -Seconds 1')
    psLines.Push('$after = & $getAvail')
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

; ============================================================
; PS-BASED SYSTEM INFO TOOLS
; Same recipe as the Network.ahk info tools: psLines -> PsCapture()
; -> ShowText() into the themed console. See the quoting cheat-sheet
; at the top of the Network.ahk section.
; ============================================================

; --- System info summary (OS, PC, CPU, RAM, BIOS, GPU, uptime) ---
SysInfoSummary() {
    psLines := []
    psLines.Push('$os = Get-CimInstance Win32_OperatingSystem')
    psLines.Push('$cs = Get-CimInstance Win32_ComputerSystem')
    psLines.Push('$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1')
    psLines.Push('$bios = Get-CimInstance Win32_BIOS')
    psLines.Push('Write-Host ("OS:       {0} ({1})" -f $os.Caption, $os.OSArchitecture)')
    psLines.Push('Write-Host ("Version:  {0}  build {1}" -f $os.Version, $os.BuildNumber)')
    psLines.Push('Write-Host ("PC:       {0} {1}" -f $cs.Manufacturer, $cs.Model)')
    psLines.Push('Write-Host ("CPU:      {0}  ({1} cores / {2} threads)" -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)')
    psLines.Push('Write-Host ("RAM:      {0:N1} GB total, {1:N1} GB free" -f ($cs.TotalPhysicalMemory/1GB), ($os.FreePhysicalMemory*1KB/1GB))')
    psLines.Push('Write-Host ("BIOS:     {0}  ({1})" -f $bios.SMBIOSBIOSVersion, $bios.Manufacturer)')
    psLines.Push('Get-CimInstance Win32_VideoController | ForEach-Object { Write-Host ("GPU:      {0}  (driver {1})" -f $_.Name, $_.DriverVersion) }')
    psLines.Push('$up = (Get-Date) - $os.LastBootUpTime')
    psLines.Push('Write-Host ("Uptime:   {0}d {1:00}h {2:00}m" -f $up.Days, $up.Hours, $up.Minutes)')
    ShowText("System Info", PsCapture(psLines, "sysinfo"))
}

; --- Startup programs: startup folders + registry Run keys ---
SysStartupItems() {
    psLines := []
    psLines.Push('Write-Host "=== Startup folder items ==="')
    psLines.Push('Get-CimInstance Win32_StartupCommand | Sort-Object Location, Name |')
    psLines.Push('    Format-Table Name, Command, Location -AutoSize | Out-String -Width 240')
    psLines.Push('Write-Host ""')
    psLines.Push('Write-Host "=== Registry Run keys ==="')
    psLines.Push('$roots = @(')
    psLines.Push('  "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",')
    psLines.Push('  "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",')
    psLines.Push('  "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"')
    psLines.Push(')')
    psLines.Push('foreach ($r in $roots) {')
    psLines.Push('  if (-not (Test-Path $r)) { continue }')
    psLines.Push('  Write-Host ""')
    psLines.Push('  Write-Host ("[" + $r + "]")')
    psLines.Push('  $k = Get-ItemProperty $r')
    psLines.Push('  foreach ($p in $k.PSObject.Properties) {')
    psLines.Push('    if ($p.Name -notmatch "^PS") { Write-Host ("  " + $p.Name + "  =  " + $p.Value) }')
    psLines.Push('  }')
    psLines.Push('}')
    ShowText("Startup Programs", PsCapture(psLines, "startup"))
}

; --- Top processes by memory and by CPU time ---
SysTopProcesses() {
    psLines := []
    psLines.Push('Write-Host "=== Top 15 by memory ==="')
    psLines.Push('Get-Process | Sort-Object WS -Descending | Select-Object -First 15 | ForEach-Object {')
    psLines.Push('  Write-Host ("{0,-32} {1,9:N1} MB" -f $_.ProcessName, ($_.WS/1MB))')
    psLines.Push('}')
    psLines.Push('Write-Host ""')
    psLines.Push('Write-Host "=== Top 10 by CPU time ==="')
    psLines.Push('Get-Process | Where-Object { $_.CPU } | Sort-Object CPU -Descending | Select-Object -First 10 | ForEach-Object {')
    psLines.Push('  Write-Host ("{0,-32} {1,10:N1} s" -f $_.ProcessName, $_.CPU)')
    psLines.Push('}')
    ShowText("Top Processes", PsCapture(psLines, "topproc"))
}

; --- Running services ---
SysRunningServices() {
    psLines := []
    psLines.Push('$s = Get-Service | Where-Object { $_.Status -eq "Running" } | Sort-Object DisplayName')
    psLines.Push('$s | Format-Table Status, Name, DisplayName -AutoSize | Out-String -Width 160')
    psLines.Push('Write-Host ""')
    psLines.Push('Write-Host ("{0} running service(s) of {1} total." -f ($s | Measure-Object).Count, (Get-Service | Measure-Object).Count)')
    ShowText("Running Services", PsCapture(psLines, "services"))
}

; --- Installed applications (from the registry uninstall keys) ---
SysInstalledApps() {
    psLines := []
    psLines.Push('$paths = @(')
    psLines.Push('  "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",')
    psLines.Push('  "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",')
    psLines.Push('  "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"')
    psLines.Push(')')
    psLines.Push('$apps = Get-ItemProperty $paths -ErrorAction SilentlyContinue |')
    psLines.Push('    Where-Object DisplayName | Sort-Object DisplayName |')
    psLines.Push('    Select-Object DisplayName, DisplayVersion, Publisher, @{N="SizeMB";E={ if ($_.EstimatedSize) { [math]::Round($_.EstimatedSize/1024) } }}')
    psLines.Push('$apps | Format-Table -AutoSize | Out-String -Width 200')
    psLines.Push('Write-Host ""')
    psLines.Push('Write-Host ("Total: {0} entr(ies)." -f ($apps | Measure-Object).Count)')
    ShowText("Installed Applications", PsCapture(psLines, "apps"))
}

; --- Windows updates (hotfixes) history ---
SysUpdateHistory() {
    psLines := []
    psLines.Push('$hf = Get-HotFix | Sort-Object InstalledOn -Descending')
    psLines.Push('$hf | Format-Table HotFixID, Description, InstalledOn -AutoSize | Out-String -Width 100')
    psLines.Push('Write-Host ""')
    psLines.Push('Write-Host ("{0} update(s) on record." -f ($hf | Measure-Object).Count)')
    ShowText("Windows Update History", PsCapture(psLines, "updates"))
}

; --- Disk health: SMART-style status, temperature, SSD wear ---
SysDiskHealth() {
    psLines := []
    psLines.Push('Get-PhysicalDisk | ForEach-Object {')
    psLines.Push('  Write-Host ("Disk:    {0}  ({1:N0} GB, {2}, {3})" -f $_.FriendlyName, ($_.Size/1GB), $_.MediaType, $_.BusType)')
    psLines.Push('  Write-Host ("Health:  {0}   Operational: {1}" -f $_.HealthStatus, ($_.OperationalStatus -join ", "))')
    psLines.Push('  try {')
    psLines.Push('    $rc = $_ | Get-StorageReliabilityCounter -ErrorAction Stop')
    psLines.Push('    if ($rc.Temperature)  { Write-Host ("Temp:    {0} C" -f $rc.Temperature) }')
    psLines.Push('    if ($rc.Wear)         { Write-Host ("Wear:    {0}%" -f $rc.Wear) }')
    psLines.Push('    if ($rc.PowerOnHours) { Write-Host ("PowerOn: {0} h" -f $rc.PowerOnHours) }')
    psLines.Push('    if ($rc.ReadErrorsTotal -or $rc.WriteErrorsTotal) { Write-Host ("Errors:  read {0} / write {1}" -f $rc.ReadErrorsTotal, $rc.WriteErrorsTotal) }')
    psLines.Push('  } catch { Write-Host "         (reliability counters need admin rights)" }')
    psLines.Push('  Write-Host ""')
    psLines.Push('}')
    ShowText("Disk Health (SMART)", PsCapture(psLines, "disk"))
}

; --- Battery status + full HTML battery report (opens in browser) ---
SysBattery() {
    psLines := []
    psLines.Push('$b = Get-CimInstance Win32_Battery')
    psLines.Push('if (-not $b) { Write-Host "No battery detected (desktop PC?)."; exit }')
    psLines.Push('$st = switch ([int]$b.BatteryStatus) { 1 {"Discharging"} 2 {"On AC power"} 3 {"Fully charged"} default {"code " + $b.BatteryStatus} }')
    psLines.Push('Write-Host ("Charge:  {0}%" -f $b.EstimatedChargeRemaining)')
    psLines.Push('Write-Host ("State:   {0}" -f $st)')
    psLines.Push('if ($b.EstimatedRunTime -lt 70000000) { Write-Host ("Runtime: ~{0} min" -f $b.EstimatedRunTime) }')
    psLines.Push('try {')
    psLines.Push('  $d = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop).DesignedCapacity')
    psLines.Push('  $f = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop).FullChargedCapacity')
    psLines.Push('  if ($d -and $f) { Write-Host ("Health:  {0}% of design capacity ({1} / {2} mAh)" -f [math]::Round($f/$d*100), $f, $d) }')
    psLines.Push('} catch {}')
    psLines.Push('$rep = Join-Path $env:TEMP "toolbox_battery_report.html"')
    psLines.Push('powercfg /batteryreport /output $rep | Out-Null')
    psLines.Push('if (Test-Path $rep) { Write-Host ""; Write-Host ("Full report opened: " + $rep); Start-Process $rep }')
    ShowText("Battery Status", PsCapture(psLines, "battery"))
}

; --- Display & GPU info (driver, resolution, connected monitors) ---
SysGpuInfo() {
    psLines := []
    psLines.Push('Get-CimInstance Win32_VideoController | ForEach-Object {')
    psLines.Push('  Write-Host ("GPU: {0}" -f $_.Name)')
    psLines.Push('  Write-Host ("  Driver:     {0}  ({1:yyyy-MM-dd})" -f $_.DriverVersion, $_.DriverDate)')
    psLines.Push('  Write-Host ("  Resolution: {0} x {1} @ {2} Hz" -f $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution, $_.CurrentRefreshRate)')
    psLines.Push('  Write-Host ""')
    psLines.Push('}')
    psLines.Push('Write-Host "Monitors:"')
    psLines.Push('try {')
    psLines.Push('  Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop | ForEach-Object {')
    psLines.Push('    $name = (($_.UserFriendlyName  | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join "")')
    psLines.Push('    $mfr  = (($_.ManufacturerName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join "")')
    psLines.Push('    Write-Host ("  " + $mfr + " " + $name)')
    psLines.Push('  }')
    psLines.Push('} catch { Write-Host "  (monitor info not available)" }')
    ShowText("Display & GPU", PsCapture(psLines, "gpu"))
}

; --- Installed printers (default one marked) ---
SysPrinters() {
    psLines := []
    psLines.Push('$def = (Get-CimInstance Win32_Printer | Where-Object Default).Name')
    psLines.Push('Get-Printer | Sort-Object Name | ForEach-Object {')
    psLines.Push('  $tag = if ($_.Name -eq $def) { "  [default]" } else { "" }')
    psLines.Push('  Write-Host ($_.Name + $tag)')
    psLines.Push('}')
    ShowText("Installed Printers", PsCapture(psLines, "printers"))
}

; --- Power plans: pick one from a popup menu and activate it ---
SysPowerPlans() {
    output := RunCapture("powercfg /list")
    plans := []
    ; Match ANY GUID followed by "(name)" — locale-independent parsing,
    ; the asterisk marking the active plan is kept as a flag.
    loop parse output, "`n", "`r" {
        if RegExMatch(A_LoopField, "i)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s+\((.+?)\)\s*(\*)?", &m)
            plans.Push({guid: m[1], name: Trim(m[2]), active: (m[3] != "")})
    }
    if plans.Length = 0 {
        MsgBox("Could not read the power plan list.", "Power Plans", 48)
        return
    }
    items := []
    for i, p in plans
        items.Push("[" i "] " p.name (p.active ? "  [active]" : ""))
    ShowPickMenu(items, (choice) => ApplyPowerPlan(choice, plans))
}

ApplyPowerPlan(choice, plans) {
    if !RegExMatch(choice, "^\[(\d+)\]", &m)
        return
    idx := Integer(m[1])
    if idx < 1 || idx > plans.Length
        return
    p := plans[idx]
    RunCapture("powercfg /setactive " p.guid)
    ToolTip("Power plan: " p.name)
    SetTimer(() => ToolTip(), -2000)
}

; --- Windows activation status ---
SysActivation() {
    psLines := []
    psLines.Push('$names = @{0="Unlicensed"; 1="Licensed"; 2="Out-of-box grace"; 3="Out-of-box grace (ext)"; 4="Non-genuine grace"; 5="Notification"; 6="Extended grace"}')
    ; ApplicationID 55c92734-... is always the Windows itself; the ''
    ; WQL strings need single quotes around the GUID; the AHK string is
    ; double-quoted, so literal `" pairs escape the PS double quotes.
    psLines.Push('if (-not $w) { Write-Host "Could not query the licensing service."; exit }')
    psLines.Push('foreach ($x in $w) {')
    psLines.Push('  Write-Host ("Edition: {0}" -f $x.Name)')
    psLines.Push('  Write-Host ("Status:  {0}" -f $names[[int]$x.LicenseStatus])')
    psLines.Push('  Write-Host ("Channel: {0}" -f $x.ProductKeyChannel)')
    psLines.Push('}')
    ShowText("Windows Activation", PsCapture(psLines, "activation"))
}

; --- Copy the OEM BIOS product key (empty on retail/digital licenses) ---
SysCopyProductKey() {
    psLines := []
    psLines.Push('(Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey')
    output := Trim(PsCapture(psLines, "oemkey"))
    if output = "" {
        MsgBox("No OEM key is embedded in this PC's firmware.`n(Retail or digital-license Windows installs don't have one.)", "Windows Product Key", 64)
        return
    }
    A_Clipboard := output
    ToolTip("Product key copied: " output)
    SetTimer(() => ToolTip(), -3000)
}

; --- Open the Environment Variables editor directly ---
SysEditEnvVars() {
    Run("rundll32 sysdm.cpl,EditEnvironmentVariables")
}
