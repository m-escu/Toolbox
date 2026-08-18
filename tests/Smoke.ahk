#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All
; Smoke tests for Toolbox pure functions. Writes PASS/FAIL lines to
; tests/smoke-results.txt. Run: AutoHotkey64.exe tests/Smoke.ahk

#Include ..\lib\Config.ahk
#Include ..\lib\Recent.ahk
#Include ..\lib\Core.ahk
#Include ..\lib\Updater.ahk
#Include ..\lib\Files.ahk
#Include ..\lib\Network.ahk
#Include ..\lib\System.ahk
#Include ..\lib\Clipboard.ahk
#Include ..\lib\Tools.ahk
#Include ..\lib\Palette.ahk
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

RunTests()
FileAppend(fails = 0 ? "ALL OK" : fails " FAILURES", outFile)
ExitApp()
