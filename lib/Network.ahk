; ============================================================
; NETWORKING COMMANDS
; ============================================================

; --- Ping ---
NetPing() {
    if (addr := AskAddress("Enter address to ping:", "Ping")) != ""
        Run('cmd /k ping -t "' addr '"')
}

; --- Traceroute ---
NetTraceroute() {
    if (addr := AskAddress("Enter address to traceroute:", "Traceroute")) != ""
        Run('cmd /k tracert "' addr '"')
}

; --- NS Lookup ---
NetNslookup() {
    if (addr := AskAddress("Enter domain or address:", "NS Lookup")) != ""
        Run('cmd /k nslookup "' addr '"')
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
    if !RequireAdmin("Set static IP on adapter...")
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
    if ips.Length = 0 {
        MsgBox("No IP address given.", "Set Static IP", 48)
        return
    }
    output := ""
    rc := 0
    addrFailed := false

    ; First IP: use "set address" (sets/replaces primary). netsh prints
    ; nothing on success and exits 1 on failure.
    cmd := 'netsh interface ip set address "' adapter '" static ' ips[1] ' ' mask
    if gw != ""
        cmd .= ' ' gw
    output .= RunCapture(cmd, &rc) "`n"
    addrFailed := rc != 0

    ; Additional IPs: use "add address" (secondary IPs on same interface)
    loop ips.Length - 1 {
        output .= RunCapture('netsh interface ip add address "' adapter '" ' ips[A_Index + 1] ' ' mask, &rc) "`n"
        if rc != 0
            addrFailed := true
    }

    ; DNS failures are reported separately: netsh also exits 1 when it merely
    ; can't reach the new server ("configured DNS server is incorrect"),
    ; although the setting was applied.
    dnsFailed := false
    if dns != "" {
        output .= RunCapture('netsh interface ip set dns "' adapter '" static ' dns, &rc) "`n"
        dnsFailed := rc != 0
    }

    ; Only remember profiles that actually applied
    if !addrFailed
        try AddIpProfile(adapter, ip, mask, gw, dns)

    msg := "Adapter: " adapter "`nIP(s): " ip "`nMask: " mask
    if gw != ""
        msg .= "`nGW: " gw
    if dns != ""
        msg .= "`nDNS: " dns
    if Trim(output, " `t`r`n") != ""
        msg .= "`n`nnetsh output:`n" Trim(output, " `t`r`n")
    if addrFailed
        MsgBox(msg "`n`n(Not saved as a profile.)", "Static IP — FAILED", 16)
    else if dnsFailed
        MsgBox(msg, "Static IP Applied (DNS warning)", 48)
    else
        MsgBox(msg, "Static IP Applied", 64)
}

; --- Set adapter to DHCP (popup menu pick) ---
NetSetDhcp() {
    if !RequireAdmin("Set adapter to DHCP...")
        return
    adapters := GetAdapters()
    if adapters.Length == 0 {
        MsgBox("Could not list network adapters.", "Error", 48)
        return
    }
    ShowPickMenu(adapters, (chosenAdapter) => ApplyDhcp(chosenAdapter))
}

ApplyDhcp(chosenAdapter) {
    ; Remove the static IPv4 config completely — addresses, the static default
    ; route (else the old gateway lingers next to the DHCP one) and the static
    ; DNS servers — then turn DHCP on. IPv6 (incl. link-local) is left alone.
    psLines := []
    psLines.Push('$a = ' PsQuote(chosenAdapter))
    psLines.Push('Remove-NetIPAddress -InterfaceAlias $a -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue')
    psLines.Push('Remove-NetRoute -InterfaceAlias $a -DestinationPrefix 0.0.0.0/0 -Confirm:$false -ErrorAction SilentlyContinue')
    psLines.Push('Set-NetIPInterface -InterfaceAlias $a -AddressFamily IPv4 -Dhcp Enabled')
    psLines.Push('Set-DnsClientServerAddress -InterfaceAlias $a -ResetServerAddresses')
    output := Trim(PsCapture(psLines, "set_dhcp"), " `t`r`n")

    MsgBox("Adapter: " chosenAdapter " set to DHCP (address, gateway and DNS)"
        . (output != "" ? "`n`nOutput:`n" output : ""), "DHCP Applied", 64)
}

; --- Port check ---
NetPortCheck() {
    favs := LoadFavorites("PortFavorites")
    prompt := "Enter IP:port (e.g. 192.168.1.10:80)`nFor multiple, separate with commas:`n192.168.1.10:80, 192.168.1.10:502, 192.168.1.10:4840`n`n" FormatFavoritesPrompt(favs, "Recent targets: ")
    input := TbInputBox(prompt, "Port Check", "w500 h400")
    if input.Result != "OK" || input.Value = ""
        return

    ; Each comma-separated part may be a favorite number; every target must
    ; be host:port with a valid host and port 1-65535. Only valid ones are
    ; remembered; invalid ones are listed instead of silently dropped.
    targets := []
    invalid := ""
    for part in StrSplit(input.Value, ",") {
        entry := Trim(ResolveInput(Trim(part), favs))
        if entry = ""
            continue
        if RegExMatch(entry, "^([^:]+):(\d{1,5})$", &m) && IsValidAddress(entry, "host:port") {
            targets.Push({ip: m[1], port: Integer(m[2])})
            AddFavorite(entry, "PortFavorites")
        } else
            invalid .= "  " entry "`n"
    }

    if targets.Length == 0 {
        MsgBox("No valid host:port entries found." (invalid != "" ? "`n`nInvalid:`n" invalid : ""), "Port Check", 48)
        return
    }
    if invalid != ""
        Notify("Skipped invalid: " StrReplace(Trim(invalid), "`n", ", "), 4000)

    ; ConnectAsync + Wait(timeout): a plain Connect() waits ~21 s on a
    ; filtered port. Refused -> CLOSED; no answer in time -> FILTERED.
    ; 3 s, not less: Windows retries the SYN after a RST, so even a refused
    ; port takes ~2.1 s to report. Name lookup is done first so a DNS
    ; failure isn't mislabelled as FILTERED.
    psLines := []
    psLines.Push('function Test-Port([string]$h, [int]$p) {')
    psLines.Push('  try { $ip = [System.Net.Dns]::GetHostAddresses($h) | Select-Object -First 1 }')
    psLines.Push('  catch { Write-Host ("{0}:{1} - DNS lookup failed" -f $h, $p) -ForegroundColor Red; return }')
    psLines.Push('  $tcp = New-Object System.Net.Sockets.TcpClient($ip.AddressFamily)')
    psLines.Push('  $sw = [System.Diagnostics.Stopwatch]::StartNew()')
    psLines.Push('  try {')
    psLines.Push('    if ($tcp.ConnectAsync($ip, $p).Wait(3000)) { $s = "OPEN (" + $sw.ElapsedMilliseconds + " ms)"; $c = "Green" }')
    psLines.Push('    else { $s = "FILTERED (no reply within 3 s)"; $c = "DarkYellow" }')
    psLines.Push('  } catch { $s = "CLOSED - " + $_.Exception.GetBaseException().Message; $c = "Red" }')
    psLines.Push('  $tcp.Close()')
    psLines.Push('  Write-Host ("{0}:{1} - {2}" -f $h, $p, $s) -ForegroundColor $c')
    psLines.Push('}')
    for t in targets
        psLines.Push('Test-Port ' PsQuote(t.ip) ' ' t.port)
    psLines.Push('Write-Host ""; Write-Host "Done. Press any key to close."; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")')

    tmpPs := PsWrite(psLines, "portcheck")
    try {
        RunTempPsVisible(tmpPs, "", false, "Port Check")
    } catch as err {
        ; Fallback: open a cmd window and run Test-NetConnection instead
        for t in targets
            Run('cmd /k powershell -NoProfile -Command "Test-NetConnection -ComputerName ' t.ip ' -Port ' t.port '"')
    }
}

; --- Browse to device (open IP in browser) ---
; Type http:// or https:// to pick directly; a bare address asks which
; (many routers / PLCs / printers only serve plain http).
NetBrowseToDevice() {
    addr := AskAddress("Enter IP address or hostname (optionally :port, /path):`n(e.g. 192.168.1.10 — or http://... / https://... to skip the choice)"
        , "Browse to Device", "url")
    if addr = ""
        return
    if RegExMatch(addr, "i)^https?://")
        Run(addr)
    else
        ShowPickMenu(["https://" addr, "http://" addr], (url) => Run(url))
}

; --- ARP table ---
NetArpTable() {
    arpOutput := RunCapture("arp -a")
    if InStr(arpOutput, "Error: ") {
        Run('cmd /k arp -a')
        return
    }
    ShowText("ARP Table", arpOutput)
    Notify("ARP table opened", 1500)
}

; --- Route table ---
NetRoutePrint() {
    routeOutput := RunCapture("route print")
    if InStr(routeOutput, "Error: ") {
        Run('cmd /k route print')
        return
    }
    ShowText("Route Table", routeOutput)
    Notify("Route table opened", 1500)
}

; --- Add route ---
; Admin is checked FIRST (auto-elevate relaunches — typed input would be lost).
NetRouteAdd() {
    if !RequireAdmin("Add route...")
        return
    r := AskRoute("Add Route", true)
    if r = ""
        return
    cmd := 'route add ' r.dest ' mask ' r.mask ' ' r.gw
    if r.metric != ""
        cmd .= ' metric ' r.metric
    Run('cmd /k ' cmd ' -p')  ; -p: persistent
}

; --- Delete route ---
NetRouteDelete() {
    if !RequireAdmin("Delete route...")
        return
    r := AskRoute("Delete Route", false)
    if r != ""
        Run('cmd /k route delete ' r.dest ' mask ' r.mask ' ' r.gw)
}

; Prompt for destination / mask / gateway (/ metric), each validated and
; re-asked until valid or cancelled. Returns {dest, mask, gw, metric} with
; the mask in dotted form (CIDR "/24" accepted), or "" on cancel.
AskRoute(title, withMetric) {
    dest := AskValidated("Destination network (e.g. 10.0.0.0)", title, "", (v) => IpToInt(v) >= 0 ? "" : "Not an IPv4 address.")
    if dest = ""
        return ""
    CheckMask(v) {
        r := SubnetCalc(dest " " v)
        if !r.ok
            return r.error
        if r.network != IpToInt(dest)  ; host bits set: route.exe rejects it
            return dest " has host bits set for this mask — did you mean " IntToIp(r.network) "?"
        return ""
    }
    mask := AskValidated("Subnet mask (e.g. 255.255.255.0 or /24)", title " — Mask", "255.255.255.0", CheckMask)
    if mask = ""
        return ""
    gw := AskValidated("Gateway (e.g. 192.168.1.1)", title " — Gateway", "", (v) => IpToInt(v) >= 0 ? "" : "Not an IPv4 address.")
    if gw = ""
        return ""
    metric := ""
    if withMetric {
        m := TbInputBox("Metric (optional, 1-9999, leave blank for auto)", title " — Metric", "w400 h150")
        if m.Result != "OK"
            return ""
        metric := Trim(m.Value)
        if metric != "" && !(RegExMatch(metric, "^\d{1,4}$") && Integer(metric) >= 1) {
            MsgBox("Metric must be a number from 1 to 9999.", title, 48)
            return ""
        }
    }
    return {dest: dest, mask: IntToIp(ParseMask(mask)), gw: gw, metric: metric}
}

; TbInputBox that re-asks (pre-filled) until check(value) returns "" (= OK).
; Returns the trimmed value, or "" when cancelled / left empty.
AskValidated(prompt, title, defaultVal, check) {
    value := defaultVal
    loop {
        r := TbInputBox(prompt, title, "w400 h150", value)
        if r.Result != "OK" || Trim(r.Value) = ""
            return ""
        value := Trim(r.Value)
        if (err := check(value)) = ""
            return value
        MsgBox(err, title, 48)
    }
}

; --- Reset routes / re-register DNS ---
NetRouteReset() {
    if !RequireAdmin("Reset routes")
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
    mac := StrUpper(RegExReplace(Trim(resolved), "[-\s]", ":"))
    if !RegExMatch(mac, "^([0-9A-F]{2}:){5}[0-9A-F]{2}$") {
        MsgBox("Invalid MAC address format.`nExpected: AA:BB:CC:DD:EE:FF", "Wake-on-LAN", 48)
        return
    }
    AddFavorite(mac, "MacFavorites")  ; only valid MACs, in one normalized form

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

    tmpPs := PsWrite([psCmd], "wol")
    try {
        RunTempPsVisible(tmpPs, "", false, "Wake-on-LAN")
        Notify("WOL magic packet sent to " mac, 2000)
    } catch as err {
        MsgBox("Failed to send WOL packet:`n" err.Message, "Wake-on-LAN", 48)
    }
}

; --- SSH to device ---
NetSsh() {
    addr := AskAddress("Enter IP or hostname for SSH (optionally user@host):", "SSH to Device", "user@host", "w500 h350")
    if addr = ""
        return
    ; Try Windows Terminal SSH first, then fall back to cmd
    if HasWindowsTerminal()
        Run('wt.exe ssh "' addr '"')
    else
        Run('cmd /k ssh "' addr '"')
}

; --- RDP to device ---
NetRdp() {
    addr := AskAddress("Enter IP or hostname for RDP (optionally :port):", "RDP to Device", "host:port", "w500 h350")
    if addr != ""
        Run('mstsc /v:"' addr '"')
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
    tmpPs := PsWrite(psLines, "scan")
    RunTempPsVisible(tmpPs, "", false, "Subnet Scanner")
}

; --- Subnet calculator ---
NetSubnetCalc() {
    input := TbInputBox("Enter IP and mask:`n(e.g. 192.168.1.130 /24 or 192.168.1.130 255.255.255.0)", "Subnet Calculator", "w450 h170")
    if input.Result != "OK" || input.Value = ""
        return

    r := SubnetCalc(input.Value)
    if !r.ok {
        MsgBox(r.error, "Subnet Calculator", 48)
        return
    }
    ipText := IntToIp(r.ip)
    msg := "IP:       " ipText "`n"
    msg .= "Mask:     " IntToIp(r.mask) " (/" r.cidr ")`n`n"
    msg .= "Network:  " IntToIp(r.network) "`n"
    msg .= "Broadcast:" IntToIp(r.broadcast) "`n"
    if r.hosts > 1 {
        msg .= "First host: " IntToIp(r.network + 1) "`n"
        msg .= "Last host:  " IntToIp(r.broadcast - 1) "`n"
    }
    msg .= "Usable hosts: " r.hosts
    A_Clipboard := msg
    MsgBox(msg "`n`n(Copied to clipboard)", "Subnet Calculator — " ipText "/" r.cidr, 64)
}

; --- Set DNS on adapter (quick presets) ---
NetDnsToggle() {
    if !RequireAdmin("Set DNS on adapter")
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
    if !RequireAdmin("Set DNS on adapter")
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
    tmpPs := PsWrite(psLines, "speedtest")
    RunTempPsVisible(tmpPs, "", true, "Internet Speed Test")  ; -NoExit: window stays open even on crash
}

; ============================================================
; PS-BASED INFO TOOLS
; One recipe, many tools: build a small PowerShell script in an
; array, run it hidden in the background (PsShowAsync), show the text in the
; themed output console via ShowText(). Nothing is written to
; disk except the temp .ps1 (auto-deleted after the run).
;
; Quoting cheat-sheet for the psLines below (see also STEP1-NOTES):
;   - PS double quotes " sit happily inside AHK '...' strings
;   - PS single quotes ' must be DOUBLED inside AHK '...' — better:
;     put the quote character in a variable (sq := "'") and
;     concatenate, like RunTempPsVisible does. Never stack '''.
;   - keep PS output ASCII-only: PS 5.1 reads no-BOM .ps1 files
;     as ANSI, so accented chars in the script would garble.
; ============================================================

; --- Show DNS cache (which names did this PC resolve recently?) ---
NetDnsCache() {
    psLines := []
    psLines.Push('$c = Get-DnsClientCache -ErrorAction SilentlyContinue')
    psLines.Push('if (-not $c) { Write-Host "DNS cache is empty."; exit }')
    psLines.Push('$c | Sort-Object Entry | Select-Object Entry, Data, Type, TimeToLive |')
    psLines.Push('    Format-Table -AutoSize | Out-String -Width 160')
    psLines.Push('Write-Host ""')
    psLines.Push('Write-Host ("{0} entrie(s) in the DNS cache." -f ($c | Measure-Object).Count)')
    PsShowAsync(psLines, "dnscache", "DNS Cache")
}

; --- Show current Wi-Fi connection details (SSID, channel, speed) ---
NetWifiDetails() {
    output := RunCapture("netsh wlan show interfaces")
    ShowText("Wi-Fi Connection Details", output)
}

; --- Show Wi-Fi networks in range (SSID, signal, BSSID/channels) ---
NetWifiNetworks() {
    output := RunCapture("netsh wlan show networks mode=bssid")
    ShowText("Wi-Fi Networks In Range", output)
}

; --- Show saved Wi-Fi profiles AND their plaintext passwords ---
; netsh only reveals keys to an elevated prompt, hence RequireAdmin.
; "Key Content" is the EN label of the password line; on non-English
; Windows we fall back to dumping the whole profile block so the key
; can still be found by eye.
NetWifiPasswords() {
    if !RequireAdmin("Wi-Fi profiles & passwords")
        return
    psLines := []
    ; Locale-proof profile names: every profile line is 4+ spaces
    ; indented and ends in " : <NAME>", whatever the label language is.
    psLines.Push('$names = @()')
    psLines.Push('foreach ($l in (netsh wlan show profiles)) {')
    psLines.Push('  if ($l -match "^\s{4,}.*\s:\s(.+?)\s*$") { $names += $Matches[1] }')
    psLines.Push('}')
    psLines.Push('$names = $names | Select-Object -Unique')
    psLines.Push('if (-not $names) { Write-Host "No Wi-Fi profiles found."; exit }')
    psLines.Push('foreach ($n in $names) {')
    psLines.Push('  Write-Host ("PROFILE: " + $n)')
    psLines.Push('  $detail = netsh wlan show profile name="$n" key=clear')
    psLines.Push('  $key = ""')
    psLines.Push('  foreach ($d in $detail) {')
    psLines.Push('    if ($d -match "Key Content\s*:\s*(.+?)\s*$") { $key = $Matches[1] }')
    psLines.Push('  }')
    psLines.Push('  if ($key) { Write-Host ("  password: " + $key) }')
    psLines.Push('  else { $detail | ForEach-Object { Write-Host ("  " + $_) } }')
    psLines.Push('  Write-Host ""')
    psLines.Push('}')
    PsShowAsync(psLines, "wifipw", "Wi-Fi Profiles & Passwords")
}

; --- Show TCP ports that are listening + the process that owns them ---
NetListeningPorts() {
    psLines := []
    psLines.Push('$rows = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object {')
    psLines.Push('  $p = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue')
    psLines.Push('  [PSCustomObject]@{ Port = $_.LocalPort; Address = $_.LocalAddress; PID = $_.OwningProcess;')
    psLines.Push('                   Process = $(if ($p) { $p.ProcessName } else { "?" }) }')
    psLines.Push('}')
    psLines.Push('$rows | Sort-Object Port, Address | Format-Table -AutoSize | Out-String -Width 120')
    psLines.Push('Write-Host ""')
    psLines.Push('Write-Host "Tip: system services may show as ? unless Toolbox runs as admin."')
    PsShowAsync(psLines, "ports", "Listening Ports (TCP)")
}

; --- Show folders this PC shares on the network (SMB) ---
NetSmbShares() {
    psLines := []
    psLines.Push('$s = Get-SmbShare -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "IPC$" }')
    psLines.Push('if (-not $s) {')
    psLines.Push('  Write-Host "No shared folders found (or access denied - run Toolbox as admin)."')
    psLines.Push('  exit')
    psLines.Push('}')
    psLines.Push('$s | Select-Object Name, Path, Description | Format-Table -AutoSize | Out-String -Width 200')
    PsShowAsync(psLines, "smb", "Shared Folders (SMB)")
}

; --- Show public IP / ISP and copy the IP to the clipboard ---
NetPublicIp() {
    psLines := []
    psLines.Push('try {')
    psLines.Push('  $m = Invoke-RestMethod "https://ipinfo.io/json" -TimeoutSec 8')
    psLines.Push('  Write-Host ("IP:      {0}" -f $m.ip)')
    psLines.Push('  Write-Host ("ISP:     {0}" -f $m.org)')
    psLines.Push('  Write-Host ("City:    {0}, {1}, {2}" -f $m.city, $m.region, $m.country)')
    psLines.Push('} catch { Write-Host ("Lookup failed: " + $_.Exception.Message) }')
    Done(output, *) {
        if RegExMatch(output, "IP:\s+(\S+)", &m) {
            A_Clipboard := Trim(m[1])
            Notify("IP copied to clipboard", 1500)
        }
        ShowText("Public IP", output)
    }
    PsCaptureAsync(psLines, "publicip", Done, "Public IP")
}

; --- Test a website: HTTP status code + response time ---
NetTestWebsite() {
    ; Pre-fill the box from the clipboard when it looks like a URL
    clip := Trim(A_Clipboard)
    defUrl := RegExMatch(clip, "i)^https?://\S+$") ? clip : ""
    input := TbInputBox("URL to test:`n(bare domains get https:// added)", "Test Website", "w450 h170", defUrl)
    if input.Result != "OK" || Trim(input.Value) = ""
        return
    url := Trim(input.Value)
    if !RegExMatch(url, "i)^https?://")
        url := "https://" url
    ; Quote chars as data — see the cheat-sheet above
    sq := "'"
    psLines := []
    psLines.Push('$u = ' sq StrReplace(url, sq, sq sq) sq)
    psLines.Push('$sw = [System.Diagnostics.Stopwatch]::StartNew()')
    psLines.Push('try {')
    psLines.Push('  $r = Invoke-WebRequest -Uri $u -Method GET -UseBasicParsing -TimeoutSec 15')
    psLines.Push('  $sw.Stop()')
    psLines.Push('  Write-Host ("{0} -> HTTP {1} {2}  ({3:N0} ms)" -f $u, [int]$r.StatusCode, $r.StatusDescription, $sw.Elapsed.TotalMilliseconds)')
    psLines.Push('} catch {')
    psLines.Push('  $sw.Stop()')
    psLines.Push('  $code = $null')
    psLines.Push('  try { $code = [int]$_.Exception.Response.StatusCode } catch {}')
    psLines.Push('  if ($code) { Write-Host ("{0} -> HTTP {1}  ({2:N0} ms)" -f $u, $code, $sw.Elapsed.TotalMilliseconds) }')
    psLines.Push('  else { Write-Host ("{0} -> FAILED: {1}" -f $u, $_.Exception.Message) }')
    psLines.Push('}')
    PsShowAsync(psLines, "webtest", "Website Test")
}

; --- Show the hosts file (static name overrides) ---
NetHostsFile() {
    hostsPath := A_WinDir "\System32\drivers\etc\hosts"
    if !FileExist(hostsPath) {
        MsgBox("Hosts file not found at:`n" hostsPath, "Hosts File", 48)
        return
    }
    content := FileRead(hostsPath, "UTF-8")
    ShowText("Hosts File (" hostsPath ")", content)
}
