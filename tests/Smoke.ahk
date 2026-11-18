#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All
; Smoke tests for Toolbox pure functions. Writes PASS/FAIL lines to
; tests/smoke-results.txt. Run: AutoHotkey64.exe tests/Smoke.ahk

#Include ..\lib\Config.ahk
#Include ..\lib\DarkMenu.ahk
#Include ..\lib\Recent.ahk
#Include ..\lib\Core.ahk
#Include ..\lib\Console.ahk
#Include ..\lib\Updater.ahk
#Include ..\lib\Files.ahk
#Include ..\lib\Network.ahk
#Include ..\lib\System.ahk
#Include ..\lib\Clipboard.ahk
#Include ..\lib\Tools.ahk
#Include ..\lib\Palette.ahk
#Include ..\lib\HotkeyGui.ahk
#Include ..\lib\MenuLayout.ahk
#Include ..\lib\MenuEditor.ahk
#Include ..\lib\Menu.ahk

outFile := A_ScriptDir "\smoke-results.txt"
Try FileDelete(outFile)
fails := 0

TbAssert(name, ok) {
    global outFile, fails
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", outFile)
    if !ok
        fails++
}

RunTests() {
    global
    TbAssert("fuzzy hit", FuzzyScore("pin", "ping address...") >= 0)
    TbAssert("fuzzy in-order", FuzzyScore("pgd", "ping address...") >= 0)
    TbAssert("fuzzy miss", FuzzyScore("xyz", "ping address...") = -1)
    TbAssert("fuzzy tight beats loose", FuzzyScore("pa", "ping address") <= FuzzyScore("pa", "open adapter"))

    TbAssert("ip->int", IpToInt("192.168.1.1") = 3232235777)
    TbAssert("int->ip", IntToIp(3232235777) = "192.168.1.1")
    TbAssert("bad ip", IpToInt("999.1.1.1") = -1)
    TbAssert("mask /24", ParseMask("/24") = ParseMask("255.255.255.0"))
    TbAssert("mask /32", ParseMask("/32") = 4294967295)
    TbAssert("mask bad", ParseMask("/40") = -1)
    TbAssert("ip list", ParseIpList("10.0.0.1, 10.0.0.2,,").Length = 2)

    TbAssert("strjoin", StrJoin(["a", "b", "c"], "-") = "a-b-c")

    enc := B64EncodeText("hello caf" Chr(233))
    TbAssert("b64 encode", enc = "aGVsbG8gY2Fmw6k=")
    TbAssert("b64 roundtrip", B64DecodeText(enc) = "hello caf" Chr(233))
    TbAssert("b64 decode classic", B64DecodeText("aGVsbG8=") = "hello")

    root := JsonParse(FileRead(A_ScriptDir "\..\catalog.json", "UTF-8"))
    TbAssert("json tools array", IsObject(root["tools"]) && root["tools"].Length >= 20)
    TbAssert("json fields", root["tools"][1]["name"] = "Process Explorer" && root["tools"][1]["exes"].Length = 2)
    yt := ""
    for , t in root["tools"] {
        if t["name"] = "yt-dlp"
            yt := t
    }
    TbAssert("json direct field", yt != "" && yt["direct"] = "yt-dlp.exe")

    cat := BuildToolCatalog(A_ScriptDir "\..\catalog.json")
    TbAssert("catalog built", cat.Count >= 20)
    TbAssert("catalog key lower", cat.Has("procmon64.exe"))
    TbAssert("catalog direct", cat["yt-dlp.exe"].direct = "yt-dlp.exe")

    favs2 := ["192.168.1.1", "10.0.0.5"]
    TbAssert("resolve numeric pick", ResolveInput("2", favs2) = "10.0.0.5")
    TbAssert("resolve literal", ResolveInput("8.8.8.8", favs2) = "8.8.8.8")

    TbAssert("file version", GetFileVer(A_WinDir "\notepad.exe") != "")

    ads := GetAdapters(true)
    TbAssert("adapters array", ads is Array)
    ads2 := GetAdapters(false)
    TbAssert("adapters cached", ads.Length = ads2.Length)

    cap := RunCapture("echo toolbox-ok")
    TbAssert("runcapture echo", InStr(cap, "toolbox-ok"))
}

; New tests live here with LOCAL variables: RunTests() is assume-global, so
; names like items/it/m/r there would become globals and trip #Warn
; (LocalSameAsGlobal) in every lib function using the same local name.
RunTests2() {
    global favoritesFile, commandRegistry
    ; ~80 KB on stderr: deadlocked the old two-pipe Exec version
    flood := RunCapture('powershell -NoProfile -Command "1..2000 | ForEach-Object { [Console]::Error.WriteLine([string]::new([char]120, 40)) }; Write-Output toolbox-done"')
    TbAssert("runcapture stderr flood", InStr(flood, "toolbox-done") && InStr(flood, "xxxxxxxx"))
    TbAssert("runcapture stderr merged", InStr(RunCapture('taskkill /F /IM "toolbox-no-such-proc.exe"'), "toolbox-no-such-proc"))

    ; --- subnet calculator (all three input forms) ---
    r := SubnetCalc("192.168.1.130 /24")
    TbAssert("subnet space-cidr", r.ok && IntToIp(r.network) = "192.168.1.0" && r.cidr = 24 && r.hosts = 254)
    r := SubnetCalc("192.168.1.130/24")
    TbAssert("subnet slash-cidr", r.ok && IntToIp(r.broadcast) = "192.168.1.255")
    r := SubnetCalc("  10.0.0.5   255.255.252.0 ")
    TbAssert("subnet dotted mask", r.ok && r.cidr = 22 && IntToIp(r.network) = "10.0.0.0" && IntToIp(r.broadcast) = "10.0.3.255" && r.hosts = 1022)
    TbAssert("subnet /32", SubnetCalc("10.1.1.1/32").hosts = 1)
    TbAssert("subnet noncontiguous", !SubnetCalc("10.0.0.1 255.0.255.0").ok)
    TbAssert("subnet missing mask", !SubnetCalc("10.0.0.1").ok)

    ; --- JSON parser: escapes + malformed input throws (used to hang) ---
    j := JsonParse('{"a": "q\"b\\c\/dA\n"}')
    TbAssert("json escapes", j["a"] = 'q"b\c/dA' "`n")
    threw := false
    try JsonParse('{"a": "unterminated')
    catch
        threw := true
    TbAssert("json unterminated throws", threw)
    threw := false
    try JsonParse('{"a": 1 "b": 2}')
    catch
        threw := true
    TbAssert("json missing comma throws", threw)

    ; --- menus: build against a scratch INI ---
    favoritesFile := A_Temp "\toolbox_smoke.ini"
    Try FileDelete(favoritesFile)
    FileAppend("", favoritesFile)
    BuildMenus()

    ; every RequireAdmin label must be a registry label (auto-elevate resumes by it)
    badLabels := ""
    Loop Files A_ScriptDir "\..\lib\*.ahk" {
        src := FileRead(A_LoopFilePath, "UTF-8")
        pos := 1
        while pos := RegExMatch(src, 'RequireAdmin\("([^"]+)"\)', &m, pos) {
            if !commandRegistry.Has(m[1])
                badLabels .= m[1] "; "
            pos += m.Len
        }
    }
    TbAssert("admin labels registered" (badLabels != "" ? " (missing: " badLabels ")" : ""), badLabels = "")
    TbAssert("folder label single backslash", commandRegistry.Has("AppData\Roaming"))

    ; saved layout + known list: new default merged, deliberately removed one stays out
    k1 := "Open selected in Notepad++", k2 := "Copy paths of selected files"
    k3 := "Open terminal at current location", k4 := "Open current folder in Explorer"
    IniWrite("&1. x|" k1, favoritesFile, "Menu", "Files~1")
    IniWrite("&4. y|" k4, favoritesFile, "Menu", "Files~2")
    IniWrite(k1, favoritesFile, "MenuKnown", "Files~1")
    IniWrite(k2, favoritesFile, "MenuKnown", "Files~2")
    IniWrite(k4, favoritesFile, "MenuKnown", "Files~3")
    items := GetLayoutItems("Files")
    TbAssert("layout merges new default", items.Length = 3 && items[2].action = k3 && items[3].action = k4)
    removedBack := false
    for it in items
        if it.action = k2
            removedBack := true
    TbAssert("layout keeps removed item out", !removedBack)

    ; legacy layout (no known list): unchanged, baseline written, old "\\" action aliased
    IniWrite("&2. AppData\\Roaming|AppData\\Roaming", favoritesFile, "Menu", "Folders~1")
    items := GetLayoutItems("Folders")
    TbAssert("legacy layout untouched", items.Length = 1 && items[1].action = "AppData\Roaming" && items[1].label = "&2. AppData\Roaming")
    TbAssert("legacy baseline written", IniRead(favoritesFile, "MenuKnown", "Folders~1", "") != "")
    Try FileDelete(favoritesFile)

    names := GetRegisteredCommandNames()
    sorted := names.Length > 10
    loop names.Length - 1
        if StrCompare(names[A_Index], names[A_Index + 1]) > 0
            sorted := false
    TbAssert("command names sorted", sorted)
}

; Clipboard text functions, CNG helpers, misc (locals only — see RunTests2)
RunTests3() {
    ; URL encode: whole-string UTF-8, emoji (surrogate pair) stays one char
    TbAssert("urlencode ascii", UrlEncode("a b/c-d_e.f~g") = "a%20b%2Fc-d_e.f~g")
    TbAssert("urlencode utf8+emoji", UrlEncode(Chr(233) Chr(0x1F600)) = "%C3%A9%F0%9F%98%80")

    ; &amp; decoded last: "&amp;lt;" is the literal text "&lt;"
    TbAssert("html amp last", HtmlToText("<b>a</b> &amp;lt; &lt;x&gt;") = "a &lt; <x>")
    TbAssert("html numeric", HtmlToText("&#65;&#x42;<br/>c") = "AB`nc")

    TbAssert("sort asc", SortLines("b`r`nA`r`nc`r`n") = "A`nb`nc")
    TbAssert("sort desc", SortLines("b`nA`nc", true) = "c`nb`nA")
    removed := 0
    TbAssert("dedupe", DedupeLines("a`n a`nb`n`na", &removed) = "a`nb" && removed = 3)
    TbAssert("strjoin keeps trailing sep chars", StrJoin(["a,", "b,"], ",") = "a,,b,")
    TbAssert("psquote", PsQuote("it's") = "'it''s'")

    ; CNG hashing (known vectors for "abc")
    TbAssert("sha256", HashText("abc") = "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD")
    TbAssert("sha1", HashText("abc", "SHA1") = "A9993E364706816ABA3E25717850C26C9CD0D89D")
    TbAssert("md5", HashText("abc", "MD5") = "900150983CD24FB0D6963F7D28E17F72")
    tmpF := A_Temp "\toolbox_smoke_hash.txt"
    Try FileDelete(tmpF)
    FileAppend("abc", tmpF, "UTF-8-RAW")
    TbAssert("hash file", HashFile(tmpF) = HashText("abc"))
    Try FileDelete(tmpF)

    pw := RandomString(64, "AB")
    TbAssert("random string", StrLen(pw) = 64 && RegExMatch(pw, "^[AB]+$") && InStr(pw, "A") && InStr(pw, "B"))
    TbAssert("guid", RegExMatch(NewGuid(), "^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$") && NewGuid() != NewGuid())

    rc := 0
    RunCapture("exit 3", &rc)
    TbAssert("runcapture exit code", rc = 3)
    Notify("smoke", 10)
    TbAssert("notify", true)
}

; Round trips, ranking, validation, background runner, integrity checks
RunTests4() {
    global favoritesFile

    ; --- hotkey syntax <-> friendly form ---
    rt := true
    for hk in ["^+m", "^!t", "#e", "+F5", "^!Delete", "!Space", "^+NumpadAdd"]
        if FriendlyToHk(HkToFriendly(hk)) != hk
            rt := false, TbAssert("hotkey roundtrip " hk " -> " HkToFriendly(hk), false)
    TbAssert("hotkey roundtrip raw->friendly->raw", rt)
    TbAssert("hotkey roundtrip friendly", HkToFriendly(FriendlyToHk("Ctrl+Alt+Q")) = "Ctrl+Alt+Q")
    TbAssert("hotkey typo rejected", FriendlyToHk("Ctrl+Shit+Q") = "")

    ; --- menu layout save -> load round trip (sep, renamed item, raw run:) ---
    favoritesFile := A_Temp "\toolbox_smoke_layout.ini"
    Try FileDelete(favoritesFile)
    FileAppend("", favoritesFile)
    saved := [{kind: "item", label: "Renamed NPP", action: "Open selected in Notepad++"}
        , {kind: "sep", label: "", action: ""}
        , {kind: "item", label: "Calc", action: "run:calc.exe"}
        , {kind: "item", label: "Open current folder in Explorer", action: "Open current folder in Explorer"}]
    SaveMenuLayout(Map("Files", saved))
    loaded := GetLayoutItems("Files")
    same := loaded.Length = saved.Length
    if same
        for i, it in saved
            if loaded[i].kind != it.kind || loaded[i].label != it.label || loaded[i].action != it.action
                same := false
    TbAssert("layout roundtrip (removed defaults stay out)", same)
    TbAssert("layout value forms", LayoutValue(saved[2]) = "-" && LayoutValue(saved[1]) = "Renamed NPP|Open selected in Notepad++"
        && LayoutValue(saved[4]) = "Open current folder in Explorer" && LayoutValue({kind: "sub", label: "NirSoft", action: "@"}) = "NirSoft|@")
    Try FileDelete(favoritesFile)

    ; --- palette ranking ---
    TbAssert("rank prefix > word start", PaletteScore("ping", "ping address...") < PaletteScore("ping", "scan subnet (ping sweep)"))
    TbAssert("rank word start > mid-word", PaletteScore("ping", "scan subnet (ping sweep)") < PaletteScore("ping", "shopping list"))
    TbAssert("rank substring > scattered", PaletteScore("dns", "flush dns") < PaletteScore("dns", "add new site"))
    TbAssert("rank initials", PaletteScore("tw", "toggle wi-fi") < PaletteScore("tw", "network tools"))
    TbAssert("rank recent boost", PaletteScore("sh", "show ip config", 1) < PaletteScore("sh", "show ip config"))
    TbAssert("rank no match", PaletteScore("zzz", "ping address...") = -1)
    TbAssert("word initials", WordInitials("toggle wi-fi") = "twf")

    ; --- address validation ---
    good := ["192.168.1.1", "router.lan", "example.com.", "fe80::1%12", "::1", "my_host-01"]
    bad := ["999.1.1.1", "1.2.3", 'a" & calc', "host name", "a|b", ""]
    okAll := true
    for s in good
        if !IsValidHost(s)
            okAll := false, TbAssert("host should be valid: " s, false)
    for s in bad
        if IsValidHost(s)
            okAll := false, TbAssert("host should be invalid: " s, false)
    TbAssert("host validation", okAll)
    TbAssert("user@host", IsValidAddress("admin@10.0.0.1", "user@host") && !IsValidAddress("a b@x", "user@host"))
    TbAssert("host:port", IsValidAddress("srv:3390", "host:port") && !IsValidAddress("srv:70000", "host:port"))
    TbAssert("url", IsValidAddress("http://10.0.0.1:8080/admin", "url") && IsValidAddress("printer.lan/status", "url")
        && !IsValidAddress('x/"&calc', "url"))

    ; --- background runner: result arrives via callback, UI thread free ---
    result := ""
    gotCode := -99
    OnDone(out, code, timedOut) {
        result := out, gotCode := code
    }
    RunCaptureAsync("echo async-ok", OnDone)
    t0 := A_TickCount
    while result = "" && A_TickCount - t0 < 10000
        Sleep(50)  ; timers (the poller) run during Sleep
    TbAssert("async capture", InStr(result, "async-ok") && gotCode = 0)

    timedOutFlag := ""
    OnSlow(out, code, timedOut) {
        timedOutFlag := timedOut
    }
    t0 := A_TickCount
    RunCaptureAsync("ping -n 30 127.0.0.1", OnSlow, "smoke slow task", 800)
    while timedOutFlag = "" && A_TickCount - t0 < 10000
        Sleep(50)
    TbAssert("async timeout kills task", timedOutFlag = true && A_TickCount - t0 < 6000)

    ; --- download integrity ---
    TbAssert("signature valid (MS-signed)", VerifySignature(A_WinDir "\explorer.exe", "Microsoft Corporation") = "")
    unsigned := A_Temp "\toolbox_smoke_unsigned.txt"
    Try FileDelete(unsigned)
    FileAppend("abc", unsigned, "UTF-8-RAW")
    TbAssert("signature missing rejected", VerifySignature(unsigned, "Microsoft Corporation") != "")
    TbAssert("signature wrong signer rejected", InStr(VerifySignature(A_WinDir "\explorer.exe", "Evil Corp"), "someone else"))
    Try FileDelete(unsigned)
    sums := "f5389d3698ecde4ef06f4e6b1ce0294fe9ac1396228c8990b8d3416d6d177a7d  yt-dlp.exe`n"
          . "0000000000000000000000000000000000000000000000000000000000000000  yt-dlp_x86.exe`n"
    TbAssert("sums parse", SumFor(sums, "yt-dlp.exe") = "F5389D3698ECDE4EF06F4E6B1CE0294FE9AC1396228C8990B8D3416D6D177A7D")
    TbAssert("sums exact name", SumFor(sums, "yt-dlp") = "" && SumFor(sums, "dlp.exe") = "")
    cat4 := BuildToolCatalog(A_ScriptDir "\..\catalog.json")
    TbAssert("catalog integrity fields", cat4["procexp64.exe"].signer = "Microsoft Corporation" && InStr(cat4["yt-dlp.exe"].sums, "SHA2-256SUMS"))
}

; Input hardening (static IP, process names, delays), JSON numbers, admin badge
RunTests5() {
    global favoritesFile, isAdmin

    ; --- static IP input is validated before it reaches netsh ---
    v := ValidateStaticIp("10.0.0.5, 10.0.0.6", "/24", "10.0.0.1", "8.8.8.8, 1.1.1.1")
    TbAssert("static ip valid + normalized", v.ok && v.ips.Length = 2 && v.mask = "255.255.255.0" && v.gw = "10.0.0.1" && v.dns.Length = 2)
    TbAssert("static ip gw/dns optional", ValidateStaticIp("10.0.0.5", "255.255.0.0", "", "").ok)
    TbAssert("static ip injection rejected", !ValidateStaticIp('10.0.0.5" & calc & "', "/24", "", "").ok)
    TbAssert("static ip bad mask rejected", !ValidateStaticIp("10.0.0.5", "255.0.255.0", "", "").ok)
    TbAssert("static ip /0 rejected", !ValidateStaticIp("10.0.0.5", "/0", "", "").ok)
    TbAssert("static ip bad gw rejected", !ValidateStaticIp("10.0.0.5", "/24", "10.0.0.999", "").ok)
    TbAssert("static ip bad dns rejected", !ValidateStaticIp("10.0.0.5", "/24", "", "8.8.8.8 & calc").ok)
    TbAssert("static ip empty rejected", !ValidateStaticIp("", "/24", "", "").ok)

    ; --- shutdown delay: a typo is an error, not "immediately" ---
    TbAssert("delay valid", ParseDelaySeconds("0") = 0 && ParseDelaySeconds(" 30 ") = 30)
    TbAssert("delay invalid", ParseDelaySeconds("5s") = -1 && ParseDelaySeconds("") = -1 && ParseDelaySeconds("-1") = -1
        && ParseDelaySeconds("1234567890") = -1 && ParseDelaySeconds("315360001") = -1)

    ; --- taskkill image name ---
    TbAssert("process name valid", IsValidProcessName("notepad.exe") && IsValidProcessName("chrome*.exe") && IsValidProcessName("My App.exe"))
    TbAssert("process name injection rejected", !IsValidProcessName('x" & calc') && !IsValidProcessName("a%PATH%") && !IsValidProcessName("a|b"))

    ; --- ssh user part can't be an option ---
    TbAssert("ssh option-looking user rejected", !IsValidAddress("-J@10.0.0.1", "user@host") && IsValidAddress("_svc.01@10.0.0.1", "user@host"))

    ; --- JSON numbers (the old ParseNumber threw on any number) ---
    j := JsonParse('{"a": 12, "b": -3.5, "c": [1, 2e2], "d": true}')
    TbAssert("json numbers", j["a"] = 12 && j["b"] = -3.5 && j["c"][2] = 200 && j["d"] = true)
    threw := false
    try JsonParse('{"a": x}')
    catch
        threw := true
    TbAssert("json bad value throws", threw)

    ; --- signer must match the O= field exactly ---
    TbAssert("signature substring signer rejected", InStr(VerifySignature(A_WinDir "\explorer.exe", "Microsoft"), "someone else"))

    ; --- [admin] badge follows the CURRENT elevation, never the saved layout ---
    favoritesFile := A_Temp "\toolbox_smoke_badge.ini"
    Try FileDelete(favoritesFile)
    FileAppend("", favoritesFile)
    BuildMenus()
    TbAssert("layout value strips badge", LayoutValue({kind: "item", label: "&7. Flush DNS  [admin]", action: "Flush DNS"}) = "&7. Flush DNS|Flush DNS")
    want := isAdmin ? "&7. Flush DNS" : "&7. Flush DNS  [admin]"
    IniWrite("&7. Flush DNS  [admin]|Flush DNS", favoritesFile, "Menu", "Networking~1")
    TbAssert("saved badge re-evaluated", GetLayoutItems("Networking")[1].label = want)
    IniWrite("&7. Flush DNS|Flush DNS", favoritesFile, "Menu", "Networking~1")
    TbAssert("missing badge re-added when needed", GetLayoutItems("Networking")[1].label = want)
    Try FileDelete(favoritesFile)
}

; An exception inside a test group is a FAIL line, never an error dialog
; (a dialog would block CI until the job timeout, and pops up locally).
RunGroup(fn) {
    try
        fn()
    catch as err
        TbAssert("exception in " fn.Name ": " err.Message " (line " err.Line ")", false)
}
OnError((err, mode) => (TbAssert("uncaught: " err.Message " (line " err.Line ")", false), 1))  ; 1 = no dialog

RunGroup(RunTests)
RunGroup(RunTests2)
RunGroup(RunTests3)
RunGroup(RunTests4)
RunGroup(RunTests5)
FileAppend(fails = 0 ? "ALL OK" : fails " FAILURES", outFile)
ExitApp()
