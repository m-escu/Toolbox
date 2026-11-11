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
}

RunTests()
RunTests2()
FileAppend(fails = 0 ? "ALL OK" : fails " FAILURES", outFile)
ExitApp()
