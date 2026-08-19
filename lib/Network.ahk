; ============================================================
; NETWORKING COMMANDS
; ============================================================

; --- Ping ---
NetPing() {
    favs := LoadFavorites("AddressFavorites")
    prompt := "Enter address to ping:`n" FormatFavoritesPrompt(favs, "Recent addresses: ")
    addr := TbInputBox(prompt, "Ping", "w500 h320")
    if addr.Result = "OK" && addr.Value != "" {
        resolved := ResolveInput(addr.Value, favs)
        AddFavorite(resolved, "AddressFavorites")
        Run('cmd /k ping -t "' resolved '"')
    }
}

; --- Traceroute ---
NetTraceroute() {
    favs := LoadFavorites("AddressFavorites")
    prompt := "Enter address to traceroute:`n" FormatFavoritesPrompt(favs, "Recent addresses: ")
    addr := TbInputBox(prompt, "Traceroute", "w500 h320")
    if addr.Result = "OK" && addr.Value != "" {
        resolved := ResolveInput(addr.Value, favs)
        AddFavorite(resolved, "AddressFavorites")
        Run('cmd /k tracert "' resolved '"')
    }
}

; --- NS Lookup ---
NetNslookup() {
    favs := LoadFavorites("AddressFavorites")
    prompt := "Enter domain or address:`n" FormatFavoritesPrompt(favs, "Recent addresses: ")
    addr := TbInputBox(prompt, "NS Lookup", "w500 h320")
    if addr.Result = "OK" && addr.Value != "" {
        resolved := ResolveInput(addr.Value, favs)
        AddFavorite(resolved, "AddressFavorites")
        Run('cmd /k nslookup "' resolved '"')
    }
}

; --- Flush DNS ---
NetFlushDns() {
    if !RequireAdmin("Flush DNS")
        return
    Run('cmd /k ipconfig /flushdns')
}

; --- IP Config ---
NetIpConfig() {
    Run('cmd /k ipconfig /all')
}

; --- List network adapters ---
NetListAdapters() {
    output := RunCapture("netsh interface show interface")
    if Trim(output) != ""
        ShowText("Network Adapters", output)
    else
        Run('cmd /k netsh interface show interface')
}

; --- Set static IP (popup menu: saved profiles first, then adapters) ---
NetSetStatic() {
    if !RequireAdmin("Set static IP")
        return
    profiles := LoadIpProfiles()
    if profiles.Length > 0 {
        items := []
        for i, p in profiles
            items.Push("[" i "] " p.adapter " — " p.ip "/" p.mask (p.gw != "" ? " GW:" p.gw : "") (p.dns != "" ? " DNS:" p.dns : ""))
        items.Push("Manual configuration...")
        ShowPickMenu(items, (choice) => HandleStaticPick(choice, profiles))
    } else {
        PickAdapterThenManual()
    }
}

HandleStaticPick(choice, profiles) {
    if choice = "Manual configuration..."
        return PickAdapterThenManual()
    if RegExMatch(choice, "^\[(\d+)\]", &m) {
        idx := Integer(m[1])
        if idx >= 1 && idx <= profiles.Length {
            p := profiles[idx]
            ApplyStaticIp(p.adapter, p.ip, p.mask, p.gw, p.dns)
        }
    }
}

PickAdapterThenManual() {
    adapters := GetAdapters()
    if adapters.Length == 0 {
        MsgBox("Could not list network adapters.", "Error", 48)
        return
    }
    ShowPickMenu(adapters, (adapter) => ManualStaticForAdapter(adapter))
}

ManualStaticForAdapter(chosenAdapter) {
    ipInput := TbInputBox("Adapter: " chosenAdapter "`n`nEnter IP Address (comma-separated for multiple):", "Set Static IP — Address", "w450 h180")
    if ipInput.Result != "OK" || ipInput.Value = ""
        return
    ipAddr := ipInput.Value

    maskInput := TbInputBox("Enter Subnet Mask:", "Set Static IP — Mask", "w400 h160", "255.255.255.0")
    if maskInput.Result != "OK" || maskInput.Value = ""
        return

    ; GW/DNS optional — leave blank to skip
    gw := ""
    gwInput := TbInputBox("Gateway (optional — leave blank to skip):", "Set Static IP — Gateway", "w400 h150")
    if gwInput.Result != "OK"
        return
    gw := Trim(gwInput.Value)

    dns := ""
    dnsInput := TbInputBox("DNS (optional — leave blank to skip):", "Set Static IP — DNS", "w400 h150")
    if dnsInput.Result != "OK"
        return
    dns := Trim(dnsInput.Value)

    ApplyStaticIp(chosenAdapter, ipAddr, maskInput.Value, gw, dns)
}

; Actually apply the static IP(s) and save profile
ApplyStaticIp(adapter, ip, mask, gw, dns) {
    ips := ParseIpList(ip)
    output := ""

    try {
        shell := ComObject("WScript.Shell")

        ; First IP: use "set address" (sets/replaces primary)
        if ips.Length > 0 {
            cmd := 'netsh interface ip set address "' adapter '" static ' ips[1] ' ' mask
            if gw != ""
                cmd .= ' ' gw
            exec := shell.Exec(cmd)
            output .= exec.StdOut.ReadAll() "`n"

            ; Additional IPs: use "add address" (secondary IPs on same interface)
            if ips.Length > 1 {
                loop ips.Length - 1 {
                    addCmd := 'netsh interface ip add address "' adapter '" ' ips[A_Index + 1] ' ' mask
                    exec := shell.Exec(addCmd)
                    output .= exec.StdOut.ReadAll() "`n"
                }
            }
        }

        if dns != "" {
            exec := shell.Exec('netsh interface ip set dns "' adapter '" static ' dns)
            output .= exec.StdOut.ReadAll() "`n"
        }
    } catch as err {
        output := "Error: " err.Message
    }

    ; Save to favorites
    try AddIpProfile(adapter, ip, mask, gw, dns)

    ; Show result in a message box so the user actually sees it
    msg := "Adapter: " adapter "`nIP(s): " ip "`nMask: " mask
    if gw != ""
        msg .= "`nGW: " gw
    if dns != ""
        msg .= "`nDNS: " dns
    msg .= "`n`nnetsh output:`n" output
    MsgBox(msg, "Static IP Applied", 64)
}

; --- Set adapter to DHCP (popup menu pick) ---
NetSetDhcp() {
    if !RequireAdmin("Set adapter to DHCP")
        return
    adapters := GetAdapters()
    if adapters.Length == 0 {
        MsgBox("Could not list network adapters.", "Error", 48)
        return
    }
    ShowPickMenu(adapters, (chosenAdapter) => ApplyDhcp(chosenAdapter))
}

ApplyDhcp(chosenAdapter) {
    ; Use PowerShell to properly remove static IPs and enable DHCP
    psScript := 'Remove-NetIPAddress -InterfaceAlias "' chosenAdapter '" -Confirm:$false -ErrorAction SilentlyContinue' "`n"
    psScript .= 'Set-NetIPInterface -InterfaceAlias "' chosenAdapter '" -Dhcp Enabled' "`n"

    tmpPs := WriteTempPs("toolbox_set_dhcp.ps1", psScript)
    output := RunCapture('powershell -NoProfile -ExecutionPolicy Bypass -File "' tmpPs '" 2>&1')
    Try FileDelete(tmpPs)

    MsgBox("Adapter: " chosenAdapter " set to DHCP`n`nOutput:`n" output, "DHCP Applied", 64)
}

; --- Port check ---
NetPortCheck() {
    favs := LoadFavorites("PortFavorites")
    prompt := "Enter IP:port (e.g. 192.168.1.10:80)`nFor multiple, separate with commas:`n192.168.1.10:80, 192.168.1.10:502, 192.168.1.10:4840`n`n" FormatFavoritesPrompt(favs, "Recent targets: ")
    input := TbInputBox(prompt, "Port Check", "w500 h400")
    if input.Result != "OK" || input.Value = ""
        return

    ; If they typed a favorite number, resolve it (could be comma-separated numbers or values)
    rawInput := input.Value
    resolvedParts := []
    for part in StrSplit(rawInput, ",") {
        part := Trim(part)
        if part = ""
            continue
        resolved := ResolveInput(part, favs)
        resolvedParts.Push(resolved)
        ; Save each resolved target as a favorite
        AddFavorite(resolved, "PortFavorites")
    }

    ; Parse targets
    targets := []
    for entry in resolvedParts {
        entry := Trim(entry)
        if entry = ""
            continue
        parts := StrSplit(entry, ":")
        if parts.Length >= 2 {
            ip := Trim(parts[1])
            port := Trim(parts[2])
            if ip != "" && RegExMatch(port, "^\d+$") && Integer(port) > 0
                targets.Push({ip: ip, port: Integer(port)})
        }
    }

    if targets.Length == 0 {
        MsgBox("No valid IP:port entries found.", "Port Check", 48)
        return
    }

    ; Build PowerShell script and write to script directory (avoids A_Temp issues)
    psLines := ""
    for t in targets
        psLines .= '$tcp = New-Object System.Net.Sockets.TcpClient; $sw = [System.Diagnostics.Stopwatch]::StartNew(); try { $tcp.Connect("' t.ip '", ' t.port '); $tcp.Close(); Write-Host ("' t.ip ':' t.port ' - OPEN (" + $sw.ElapsedMilliseconds + "ms)") } catch { Write-Host "' t.ip ':' t.port ' - CLOSED" }; $sw.Stop()' "`n"
    psLines .= 'Write-Host ""; Write-Host "Done. Press any key to close."; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")'

    tmpPs := WriteTempPs("toolbox_portcheck.ps1", psLines)
    try {
        RunTempPsVisible(tmpPs)
    } catch as err {
        ; Fallback: open a cmd window and run Test-NetConnection instead
        for t in targets
            Run('cmd /k powershell -NoProfile -Command "Test-NetConnection -ComputerName ' t.ip ' -Port ' t.port '"')
    }
}

; --- Browse to device (open IP in browser) ---
NetBrowseToDevice() {
    favs := LoadFavorites("AddressFavorites")
    prompt := "Enter IP address or hostname:`n(e.g. 192.168.1.10)`n`n" FormatFavoritesPrompt(favs, "Recent addresses: ")
    addr := TbInputBox(prompt, "Browse to Device", "w500 h320")
    if addr.Result = "OK" && addr.Value != "" {
        resolved := ResolveInput(addr.Value, favs)
        AddFavorite(resolved, "AddressFavorites")
        Run("https://" Trim(resolved))
    }
}

; --- ARP table ---
NetArpTable() {
    arpOutput := RunCapture("arp -a")
    if InStr(arpOutput, "Error: ") {
        Run('cmd /k arp -a')
        return
    }
    ShowText("ARP Table", arpOutput)
    ToolTip("ARP table opened")
    SetTimer(() => ToolTip(), -1500)
}

; --- Route table ---
NetRoutePrint() {
    routeOutput := RunCapture("route print")
    if InStr(routeOutput, "Error: ") {
        Run('cmd /k route print')
        return
    }
    ShowText("Route Table", routeOutput)
    ToolTip("Route table opened")
    SetTimer(() => ToolTip(), -1500)
}

; --- Add route ---
NetRouteAdd() {
    dest := TbInputBox("Destination network (e.g. 10.0.0.0)", "Add Route", "w400 h150").Value
    if dest = ""
        return
    mask := TbInputBox("Subnet mask (e.g. 255.255.255.0)", "Add Route — Mask", "w400 h150").Value
    if mask = ""
        return
    gateway := TbInputBox("Gateway (e.g. 192.168.1.1)", "Add Route — Gateway", "w400 h150").Value
    if gateway = ""
        return
    metric := TbInputBox("Metric (optional, leave blank for auto)", "Add Route — Metric", "w400 h150").Value

    if !RequireAdmin("Add Route")
        return

    cmd := 'route add ' dest ' mask ' mask ' ' gateway
    if metric != ""
        cmd .= ' metric ' metric
    cmd .= ' -p'  ; make persistent

    Run('cmd /k ' cmd)
}

; --- Delete route ---
NetRouteDelete() {
    dest := TbInputBox("Destination network to remove (e.g. 10.0.0.0)", "Delete Route", "w400 h150").Value
    if dest = ""
        return
    mask := TbInputBox("Subnet mask (e.g. 255.255.255.0)", "Delete Route — Mask", "w400 h150").Value
    if mask = ""
        return
    gateway := TbInputBox("Gateway (e.g. 192.168.1.1)", "Delete Route — Gateway", "w400 h150").Value
    if gateway = ""
        return

    if !RequireAdmin("Delete Route")
        return

    cmd := 'route delete ' dest ' mask ' mask ' ' gateway
    Run('cmd /k ' cmd)
}

; --- Reset routes / re-register DNS ---
NetRouteReset() {
    if !RequireAdmin("Reset Routes")
        return
    Run('cmd /k route -f && netsh winsock reset && netsh int ip reset && ipconfig /flushdns && ipconfig /registerdns && echo Routes reset complete. Reboot recommended. && pause')
}

; ============================================================
; NEW NETWORKING COMMANDS
; ============================================================

; --- Wake-on-LAN ---
NetWakeOnLan() {
    favs := LoadFavorites("MacFavorites")
    prompt := "Enter MAC address (e.g. AA:BB:CC:DD:EE:FF)`n`n" FormatFavoritesPrompt(favs, "Recent MACs: ")
    input := TbInputBox(prompt, "Wake-on-LAN", "w500 h350")
    if input.Result != "OK" || input.Value = ""
        return

    resolved := ResolveInput(input.Value, favs)
    AddFavorite(resolved, "MacFavorites")

    mac := RegExReplace(resolved, "[-\s]", ":")
    if !RegExMatch(mac, "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$") {
        MsgBox("Invalid MAC address format.`nExpected: AA:BB:CC:DD:EE:FF", "Wake-on-LAN", 48)
        return
    }

    ; Build magic packet hex: 6 bytes FF + 16x MAC (colons stripped — hex pairs!)
    macHex := StrReplace(mac, ":")
    hex := "FFFFFFFFFFFF"
    loop 16
        hex .= macHex

    ; Build PowerShell to send UDP broadcast to port 9
    byteList := ""
    loop 102
        byteList .= "0x" SubStr(hex, (A_Index - 1) * 2 + 1, 2) ", "
    byteList := RTrim(byteList, ", ")

    psCmd := '$bytes = [byte[]](' byteList '); $udp = New-Object System.Net.Sockets.UdpClient; $udp.Connect([System.Net.IPAddress]::Broadcast, 9); $udp.Send($bytes, $bytes.Length); $udp.Close(); Write-Host "Magic packet sent to ' mac '"'

    tmpPs := WriteTempPs("toolbox_wol.ps1", psCmd)
    try {
        RunTempPsVisible(tmpPs)
        ToolTip("WOL magic packet sent to " mac)
        SetTimer(() => ToolTip(), -2000)
    } catch as err {
        MsgBox("Failed to send WOL packet:`n" err.Message, "Wake-on-LAN", 48)
    }
}

; --- SSH to device ---
NetSsh() {
    favs := LoadFavorites("AddressFavorites")
    prompt := "Enter IP or hostname for SSH:`n`n" FormatFavoritesPrompt(favs, "Recent addresses: ")
    input := TbInputBox(prompt, "SSH to Device", "w500 h350")
    if input.Result != "OK" || input.Value = ""
        return

    resolved := ResolveInput(input.Value, favs)
    AddFavorite(resolved, "AddressFavorites")

    ; Try Windows Terminal SSH first, then fall back to cmd
    wtPath := userProfile "\AppData\Local\Microsoft\WindowsApps\wt.exe"
    if FileExist(wtPath)
        Run('wt.exe ssh "' resolved '"')
    else
        Run('cmd /k ssh "' resolved '"')
}

; --- RDP to device ---
NetRdp() {
    favs := LoadFavorites("AddressFavorites")
    prompt := "Enter IP or hostname for RDP:`n`n" FormatFavoritesPrompt(favs, "Recent addresses: ")
    input := TbInputBox(prompt, "RDP to Device", "w500 h350")
    if input.Result != "OK" || input.Value = ""
        return

    resolved := ResolveInput(input.Value, favs)
    AddFavorite(resolved, "AddressFavorites")
    Run('mstsc /v:"' resolved '"')
}

; --- Scan subnet: async ping sweep of a /24 + DNS resolve ---
NetIpScanner() {
    input := TbInputBox("Enter subnet (first 3 octets, e.g. 192.168.1):", "Scan Subnet", "w400 h160")
    if input.Result != "OK"
        return
    subnet := Trim(input.Value)
    if !RegExMatch(subnet, "^(\d{1,3}\.){2}\d{1,3}$") {
        MsgBox("Invalid subnet. Expected format: 192.168.1", "Scan Subnet", 48)
        return
    }

    psLines := []
    psLines.Push('$subnet = "' subnet '"')
    psLines.Push('$results = foreach ($i in 1..254) {')
    psLines.Push('    $ip = "$subnet.$i"')
    psLines.Push('    $p = New-Object System.Net.NetworkInformation.Ping')
    psLines.Push('    @{ IP = $ip; Task = $p.SendPingAsync($ip, 600) }')
    psLines.Push('}')
    psLines.Push('Write-Host "Pinging $subnet.1-254, waiting for replies..." -ForegroundColor Cyan')
    psLines.Push('$alive = @()')
    psLines.Push('foreach ($r in $results) {')
    psLines.Push('    try {')
    psLines.Push('        if ($r.Task.Result.Status -eq "Success") {')
    psLines.Push('            $hostName = ""')
    psLines.Push('            try { $hostName = [System.Net.Dns]::GetHostEntry($r.IP).HostName } catch {}')
    psLines.Push('            $line = $r.IP')
    psLines.Push('            if ($hostName) { $line += "  $hostName" }')
    psLines.Push('            Write-Host $line -ForegroundColor Green')
    psLines.Push('            $alive += $line')
    psLines.Push('        }')
    psLines.Push('    } catch {}')
    psLines.Push('}')
    psLines.Push('Write-Host ""')
    psLines.Push('Write-Host ("Done. {0} host(s) responded." -f $alive.Count) -ForegroundColor Cyan')
    psLines.Push('Write-Host "Press any key to close..."')
    psLines.Push('$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")')
    psScript := ""
    for , line in psLines
        psScript .= line "`n"
    tmpPs := WriteTempPs("toolbox_scan.ps1", psScript)
    RunTempPsVisible(tmpPs)
}

; --- Subnet calculator ---
NetSubnetCalc() {
    input := TbInputBox("Enter IP and mask:`n(e.g. 192.168.1.130 /24 or 192.168.1.130 255.255.255.0)", "Subnet Calculator", "w450 h170")
    if input.Result != "OK" || input.Value = ""
        return

    parts := StrSplit(Trim(input.Value))
    if parts.Length < 2 {
        MsgBox("Enter IP and mask, separated by a space (or IP/CIDR like 10.0.0.5/22).", "Subnet Calculator", 48)
        return
    }
    ip := IpToInt(parts[1])
    mask := ParseMask(parts[2])
    if ip < 0 || mask < 0 {
        MsgBox("Invalid IP or mask.", "Subnet Calculator", 48)
        return
    }

    ; Count mask bits for CIDR notation
    cidr := 0
    loop 32 {
        if (mask >> (32 - A_Index)) & 1
            cidr++
    }

    network := ip & mask
    broadcast := network | (mask ^ 0xFFFFFFFF)
    hosts := mask = 0xFFFFFFFF ? 1 : broadcast - network - 1

    msg := "IP:       " parts[1] "`n"
    msg .= "Mask:     " IntToIp(mask) " (/" cidr ")`n`n"
    msg .= "Network:  " IntToIp(network) "`n"
    msg .= "Broadcast:" IntToIp(broadcast) "`n"
    if hosts > 0 {
        msg .= "First host: " IntToIp(network + 1) "`n"
        msg .= "Last host:  " IntToIp(broadcast - 1) "`n"
    }
    msg .= "Usable hosts: " hosts
    A_Clipboard := msg
    MsgBox(msg "`n`n(Copied to clipboard)", "Subnet Calculator — " parts[1] "/" cidr, 64)
}

; --- Set DNS on adapter (quick presets) ---
NetDnsToggle() {
    if !RequireAdmin("Set DNS")
        return
    adapters := GetAdapters()
    if adapters.Length == 0 {
        MsgBox("Could not list network adapters.", "Error", 48)
        return
    }
    ShowPickMenu(adapters, (adapter) => PickDnsPreset(adapter))
}

PickDnsPreset(adapter) {
    presets := ["Cloudflare (1.1.1.1)", "Google (8.8.8.8)", "DHCP (automatic)"]
    ShowPickMenu(presets, (preset) => ApplyDnsPreset(adapter, preset))
}

ApplyDnsPreset(adapter, preset) {
    if !RequireAdmin("Set DNS")
        return
    output := ""
    if preset = "Cloudflare (1.1.1.1)" {
        output := RunCapture('netsh interface ip delete dns "' adapter '" all')
        output .= RunCapture('netsh interface ip set dns "' adapter '" static 1.1.1.1 primary')
        output .= RunCapture('netsh interface ip add dns "' adapter '" 1.0.0.1 index=2')
    } else if preset = "Google (8.8.8.8)" {
        output := RunCapture('netsh interface ip delete dns "' adapter '" all')
        output .= RunCapture('netsh interface ip set dns "' adapter '" static 8.8.8.8 primary')
        output .= RunCapture('netsh interface ip add dns "' adapter '" 8.8.4.4 index=2')
    } else {
        output := RunCapture('netsh interface ip delete dns "' adapter '" all')
        output .= RunCapture('netsh interface ip set dns "' adapter '" dhcp')
    }
    MsgBox("Adapter: " adapter "`nPreset: " preset "`n`nOutput:`n" output, "DNS Set", 64)
}

; --- Internet speed test: Cloudflare primary, OVH/httpbin fallbacks, dynamic sizes ---
NetSpeedTest() {
    psLines := []
    psLines.Push('$ProgressPreference = "SilentlyContinue"')
    psLines.Push('$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Toolbox/1.0"')
    psLines.Push('Write-Host "=== Internet Speed Test ===" -ForegroundColor Cyan')
    psLines.Push('try {')
    psLines.Push('  $meta = Invoke-RestMethod "https://ipinfo.io/json" -TimeoutSec 8')
    psLines.Push('  Write-Host ("ISP:      {0}" -f $meta.org)')
    psLines.Push('  Write-Host ("Your IP:  {0}" -f $meta.ip)')
    psLines.Push('} catch { Write-Host $_.Exception.Message }')
    psLines.Push('')
    psLines.Push('Write-Host "`nLatency (ping 1.1.1.1)..." -ForegroundColor Cyan')
    psLines.Push('try {')
    psLines.Push('  $p = Test-Connection 1.1.1.1 -Count 4 -ErrorAction Stop')
    psLines.Push('  $avg = ($p | Measure-Object -Property ResponseTime -Average).Average')
    psLines.Push('  Write-Host ("  avg {0:N0} ms over 4 pings" -f $avg)')
    psLines.Push('} catch { Write-Host "  ping failed" -ForegroundColor DarkYellow }')
    psLines.Push('')
    psLines.Push('$wc = New-Object System.Net.WebClient')
    psLines.Push('$wc.Headers.Add("User-Agent", $ua)')
    psLines.Push('function Test-Download([long]$bytes, [long]$mirrorBytes, [string]$cfUrl, [string]$mirrorUrl) {')
    psLines.Push('  $sw = [System.Diagnostics.Stopwatch]::StartNew()')
    psLines.Push('  try { $null = $wc.DownloadData($cfUrl); return @{ Secs = $sw.Elapsed.TotalSeconds; Src = "Cloudflare"; Bytes = $bytes } }')
    psLines.Push('  catch {')
    psLines.Push('    try {')
    psLines.Push('      $sw.Restart()')
    psLines.Push('      $null = $wc.DownloadData($mirrorUrl)')
    psLines.Push('      return @{ Secs = $sw.Elapsed.TotalSeconds; Src = "OVH mirror"; Bytes = $mirrorBytes }')
    psLines.Push('    } catch { return $null }')
    psLines.Push('  }')
    psLines.Push('}')
    psLines.Push('')
    psLines.Push('Write-Host "`nDownload probe..." -ForegroundColor Cyan')
    psLines.Push('$probe = Test-Download 5000000 10000000 "https://speed.cloudflare.com/__down?bytes=5000000" "https://proof.ovh.net/files/10Mb.dat"')
    psLines.Push('if (-not $probe) { Write-Host "  download failed on all mirrors" -ForegroundColor DarkYellow }')
    psLines.Push('else {')
    psLines.Push('  $mbps = $probe.Bytes*8/1000000/$probe.Secs')
    psLines.Push('  Write-Host ("  probe: {0:N0} Mbps" -f $mbps)')
    psLines.Push('  # OVH mirror only has 1/10/100 Mb files - snap the tier')
    psLines.Push('  $dlBytes = if ($mbps -ge 30) { 100000000 } elseif ($mbps -ge 8) { 10000000 } else { 1000000 }')
    psLines.Push('  Write-Host ("Download test ({0:N0} MB)..." -f ($dlBytes/1000000)) -ForegroundColor Cyan')
    psLines.Push('  $r = Test-Download $dlBytes $dlBytes ("https://speed.cloudflare.com/__down?bytes=" + $dlBytes) ("https://proof.ovh.net/files/" + ($dlBytes/1000000) + "Mb.dat")')
    psLines.Push('  if ($r) { Write-Host ("  {0:N0} Mbps  ({1:N1} s, {2})" -f ($r.Bytes*8/1000000/$r.Secs), $r.Secs, $r.Src) -ForegroundColor Green }')
    psLines.Push('  else { Write-Host "  full download failed" -ForegroundColor DarkYellow }')
    psLines.Push('}')
    psLines.Push('')
    psLines.Push('function Test-Upload([long]$bytes) {')
    psLines.Push('  $data = New-Object byte[] $bytes')
    psLines.Push('  $sw = [System.Diagnostics.Stopwatch]::StartNew()')
    psLines.Push('  try { $null = $wc.UploadData("https://speed.cloudflare.com/__up", "POST", $data); return @{ Secs = $sw.Elapsed.TotalSeconds; Src = "Cloudflare" } }')
    psLines.Push('  catch {')
    psLines.Push('    try {')
    psLines.Push('      $sw.Restart()')
    psLines.Push('      $null = Invoke-WebRequest -Uri "https://httpbin.org/post" -Method Post -Body $data -UserAgent $ua -TimeoutSec 90')
    psLines.Push('      return @{ Secs = $sw.Elapsed.TotalSeconds; Src = "httpbin" }')
    psLines.Push('    } catch { Write-Host ("  upload error: " + $_.Exception.Message) -ForegroundColor DarkRed; return $null }')
    psLines.Push('  }')
    psLines.Push('}')
    psLines.Push('Write-Host "`nUpload probe (2 MB)..." -ForegroundColor Cyan')
    psLines.Push('$up = Test-Upload 2000000')
    psLines.Push('if (-not $up) { Write-Host "  upload failed on all endpoints" -ForegroundColor DarkYellow }')
    psLines.Push('else {')
    psLines.Push('  Write-Host ("  probe: {0:N0} Mbps" -f (2000000*8/1000000/$up.Secs))')
    psLines.Push('  $upBytes = if ($up.Secs -le 2) { 25000000 } elseif ($up.Secs -le 6) { 10000000 } else { 4000000 }')
    psLines.Push('  Write-Host ("Upload test ({0:N0} MB)..." -f ($upBytes/1000000)) -ForegroundColor Cyan')
    psLines.Push('  $r = Test-Upload $upBytes')
    psLines.Push('  if ($r) { Write-Host ("  {0:N0} Mbps  ({1:N1} s, {2})" -f ($upBytes*8/1000000/$r.Secs), $r.Secs, $r.Src) -ForegroundColor Green }')
    psLines.Push('  else { Write-Host "  full upload failed" -ForegroundColor DarkYellow }')
    psLines.Push('}')
    psLines.Push('')
    psLines.Push('Write-Host "`nDone." -ForegroundColor Cyan')
    psScript := ""
    for , line in psLines
        psScript .= line "`n"
    tmpPs := WriteTempPs("toolbox_speedtest.ps1", psScript)
    RunTempPsVisible(tmpPs, "", true)  ; -NoExit: window stays open even on crash
}
