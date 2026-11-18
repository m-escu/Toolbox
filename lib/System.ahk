; ============================================================
; SYSTEM COMMANDS
; ============================================================

; --- Toggle Wi-Fi ---
ToggleWifi() {
    if !RequireAdmin("Toggle Wi-Fi")
        return
    ; First physical 802.11 adapter (NdisPhysicalMedium 9) -> "Name|Status".
    ; [char]124 is "|" (avoids nesting quotes inside the -Command string).
    out := Trim(RunCapture('powershell -NoProfile -Command "$a = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.NdisPhysicalMedium -eq 9 } | Select-Object -First 1; if ($a) { $a.Name + [char]124 + $a.Status }"'))
    if !RegExMatch(out, "^([^\r\n|]+)\|(\w+)$", &m) {
        MsgBox("No Wi-Fi adapter detected.", "Wi-Fi Toggle", 48)
        return
    }
    wifiAdapter := m[1], status := m[2]
    ; Status is Up / Disconnected / Disabled — only "Disabled" means switched off
    action := (status = "Disabled") ? "enable" : "disable"
    Run('cmd /k netsh interface set interface "' wifiAdapter '" ' action)
    Notify(wifiAdapter " " action "d", 2000)
}

; ============================================================
; NEW SYSTEM COMMANDS
; ============================================================

; Delay in whole seconds from user text; -1 when invalid (blank, "5s", negative,
; beyond shutdown.exe's 10-year limit). A typo must never mean "immediately".
ParseDelaySeconds(text) {
    text := Trim(text)
    if !RegExMatch(text, "^\d{1,9}$")
        return -1
    secs := Integer(text)
    return secs <= 315360000 ? secs : -1
}

; --- Restart ---
SysRestart() {
    if !RequireAdmin("Restart...")
        return
    delay := TbInputBox("Restart delay in seconds (0 = immediate):", "Restart", "w350 h160", "0")
    if delay.Result != "OK"
        return
    secs := ParseDelaySeconds(delay.Value)
    if secs < 0 {
        MsgBox("Enter a whole number of seconds (0 = immediate).", "Restart", 48)
        return
    }
    ; Confirmation safeguard (INI-toggleable: ConfirmRestart in [Settings], default 1)
    confirm := IniRead(favoritesFile, "Settings", "ConfirmRestart", "1")
    if confirm = "1" {
        delayText := secs > 0 ? "in " secs " seconds" : "immediately"
        result := MsgBox("Restart " delayText "?`n`nThis cannot be undone.", "Confirm Restart", 49)  ; OK+Cancel with ! icon
        if result != "OK"
            return
    }
    Run('cmd /k shutdown /r /t ' secs)
}

; --- Shutdown ---
SysShutdown() {
    if !RequireAdmin("Shutdown...")
        return
    delay := TbInputBox("Shutdown delay in seconds (0 = immediate):", "Shutdown", "w350 h160", "0")
    if delay.Result != "OK"
        return
    secs := ParseDelaySeconds(delay.Value)
    if secs < 0 {
        MsgBox("Enter a whole number of seconds (0 = immediate).", "Shutdown", 48)
        return
    }
    ; Confirmation safeguard (INI-toggleable: ConfirmShutdown in [Settings], default 1)
    confirm := IniRead(favoritesFile, "Settings", "ConfirmShutdown", "1")
    if confirm = "1" {
        delayText := secs > 0 ? "in " secs " seconds" : "immediately"
        result := MsgBox("Shutdown " delayText "?`n`nThis cannot be undone.", "Confirm Shutdown", 49)  ; OK+Cancel with ! icon
        if result != "OK"
            return
    }
    Run('cmd /k shutdown /s /t ' secs)
}

; --- Abort a pending (delayed) shutdown / restart ---
; shutdown /a exits 1116 (ERROR_NO_SHUTDOWN_IN_PROGRESS) when nothing is pending
SysAbortShutdown() {
    out := Trim(RunCapture("shutdown /a", &rc), " `t`r`n")
    if rc = 0
        Notify("Pending shutdown / restart aborted.", 2500)
    else if rc = 1116
        Notify("No shutdown or restart is pending.", 2500)
    else
        MsgBox("shutdown /a failed (exit " rc "):`n`n" out, "Abort Shutdown", 48)
}

; Image name for taskkill /IM: letters, digits, space, . _ + ( ) * - only.
; The value is placed inside quotes on an elevated command line, so quotes,
; % (cmd expansion) and & | < > ^ must never get through.
IsValidProcessName(s) {
    return RegExMatch(s, "^[\w .+()*-]+$") > 0
}

; --- Kill process by name ---
SysKillProcess() {
    if !RequireAdmin("Kill process...")
        return
    input := TbInputBox("Enter process name (e.g. notepad.exe):", "Kill Process", "w400 h160")
    if input.Result = "OK" && Trim(input.Value) != "" {
        procName := Trim(input.Value)
        if !IsValidProcessName(procName) {
            MsgBox("'" procName "' is not a valid process name.`n`nAllowed: letters, digits, space and . _ + ( ) * -", "Kill Process", 48)
            return
        }
        if !InStr(procName, ".")
            procName .= ".exe"
        ; RunCapture merges stderr — taskkill reports "not found" there
        output := Trim(RunCapture('taskkill /F /IM "' procName '"'))
        MsgBox(output != "" ? output : "(no output)", "Kill Process: " procName, 64)
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
    output := PsCapture(psLines, "ips")
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
        Notify("Copied: " StrReplace(text, "`n", "  "), 2500)
    } else {
        Notify("Could not get info.", 2000)
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
    PsCaptureAsync(psLines, "uptime", (output, *) => MsgBox(output, "Uptime & Disk Space", 64), "Uptime & Disk Space")
}

; --- Recent event log errors ---
SysEventErrors() {
    psLines := []
    psLines.Push('$ev = Get-WinEvent -FilterHashtable @{LogName="System"; Level=2} -MaxEvents 25 -ErrorAction SilentlyContinue')
    psLines.Push('if ($ev) { $ev | Format-Table -AutoSize TimeCreated, ProviderName, Id, @{N="Message";E={($_.Message -split "``r?``n")[0]}} | Out-String -Width 250 }')
    psLines.Push('else { Write-Host "No error events found." }')
    PsShowAsync(psLines, "events", "Event Log Errors (System)")
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
    PsCaptureAsync(psLines, "trimmem", (output, *) => MsgBox(output, "Reduce Working Set", 64), "Reduce Working Set")
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
    PsCaptureAsync(psLines, "cleantemp", (output, *) => MsgBox(output, "Clean Temp Folder", 64), "Clean Temp Folder")
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
; Same recipe as the Network.ahk info tools: psLines -> PsShowAsync()
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
    PsShowAsync(psLines, "sysinfo", "System Info")
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
    PsShowAsync(psLines, "startup", "Startup Programs")
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
    PsShowAsync(psLines, "topproc", "Top Processes")
}

; --- Running services ---
SysRunningServices() {
    psLines := []
    psLines.Push('$s = Get-Service | Where-Object { $_.Status -eq "Running" } | Sort-Object DisplayName')
    psLines.Push('$s | Format-Table Status, Name, DisplayName -AutoSize | Out-String -Width 160')
    psLines.Push('Write-Host ""')
    psLines.Push('Write-Host ("{0} running service(s) of {1} total." -f ($s | Measure-Object).Count, (Get-Service | Measure-Object).Count)')
    PsShowAsync(psLines, "services", "Running Services")
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
    PsShowAsync(psLines, "apps", "Installed Applications")
}

; --- Windows updates (hotfixes) history ---
SysUpdateHistory() {
    psLines := []
    psLines.Push('$hf = Get-HotFix | Sort-Object InstalledOn -Descending')
    psLines.Push('$hf | Format-Table HotFixID, Description, InstalledOn -AutoSize | Out-String -Width 100')
    psLines.Push('Write-Host ""')
    psLines.Push('Write-Host ("{0} update(s) on record." -f ($hf | Measure-Object).Count)')
    PsShowAsync(psLines, "updates", "Windows Update History")
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
    PsShowAsync(psLines, "disk", "Disk Health (SMART)")
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
    PsShowAsync(psLines, "battery", "Battery Status")
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
    PsShowAsync(psLines, "gpu", "Display & GPU")
}

; --- Installed printers (default one marked) ---
SysPrinters() {
    psLines := []
    psLines.Push('$def = (Get-CimInstance Win32_Printer | Where-Object Default).Name')
    psLines.Push('Get-Printer | Sort-Object Name | ForEach-Object {')
    psLines.Push('  $tag = if ($_.Name -eq $def) { "  [default]" } else { "" }')
    psLines.Push('  Write-Host ($_.Name + $tag)')
    psLines.Push('}')
    PsShowAsync(psLines, "printers", "Installed Printers")
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
    Notify("Power plan: " p.name, 2000)
}

; --- Windows activation status ---
SysActivation() {
    psLines := []
    psLines.Push('$names = @{0="Unlicensed"; 1="Licensed"; 2="Out-of-box grace"; 3="Out-of-box grace (ext)"; 4="Non-genuine grace"; 5="Notification"; 6="Extended grace"}')
    ; ApplicationID 55c92734-... is always Windows itself. The WQL filter
    ; needs single quotes around the GUID — quote char as data (sq), see
    ; the cheat-sheet in Network.ahk.
    sq := "'"
    psLines.Push('$w = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID=' sq '55c92734-d682-4d71-983e-d6ec3f16059f' sq ' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue')
    psLines.Push('if (-not $w) { Write-Host "Could not query the licensing service."; exit }')
    psLines.Push('foreach ($x in $w) {')
    psLines.Push('  Write-Host ("Edition: {0}" -f $x.Name)')
    psLines.Push('  Write-Host ("Status:  {0}" -f $names[[int]$x.LicenseStatus])')
    psLines.Push('  Write-Host ("Channel: {0}" -f $x.ProductKeyChannel)')
    psLines.Push('}')
    PsShowAsync(psLines, "activation", "Windows Activation")
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
    Notify("Product key copied: " output, 3000)
}

; --- Open the Environment Variables editor directly ---
SysEditEnvVars() {
    Run("rundll32 sysdm.cpl,EditEnvironmentVariables")
}
