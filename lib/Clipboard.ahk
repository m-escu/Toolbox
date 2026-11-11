; ============================================================
; CLIPBOARD COMMANDS
; Each command = a pure text function (testable, see tests/Smoke.ahk)
; + a thin Clip* wrapper that reads/writes the clipboard and notifies.
; ============================================================

; Clipboard text, or "" (with a tooltip) when it's empty
ClipTextOrNotify() {
    text := A_Clipboard
    if text = ""
        Notify("Clipboard is empty.", 2000)
    return text
}

; --- Remove duplicate lines ---
; Compares trimmed lines, keeps the first occurrence with its original
; whitespace; blank lines are dropped.
DedupeLines(text, &removed := 0) {
    lines := StrSplit(text, "`n", "`r")
    seen := Map()
    unique := []
    for line in lines {
        trimmed := Trim(line)
        if trimmed = "" || seen.Has(trimmed)
            continue
        seen[trimmed] := true
        unique.Push(line)
    }
    removed := lines.Length - unique.Length
    return StrJoin(unique, "`n")
}

ClipRemoveDuplicates() {
    if (text := ClipTextOrNotify()) = ""
        return
    A_Clipboard := result := DedupeLines(text, &removed)
    remain := StrSplit(result, "`n").Length
    Notify(removed > 0 ? "Removed " removed " duplicate(s) — " remain " line(s) remain"
                       : "No duplicates found — " remain " line(s)", 2000)
}

; --- Sort lines (case-insensitive; built-in Sort) ---
SortLines(text, descending := false) {
    text := StrReplace(RTrim(text, "`r`n"), "`r`n", "`n")
    return Sort(text, descending ? "R" : "")
}

ClipSortLines(descending := false) {
    if (text := ClipTextOrNotify()) = ""
        return
    A_Clipboard := result := SortLines(text, descending)
    Notify("Sorted " StrSplit(result, "`n").Length " lines (" (descending ? "Z-A" : "A-Z") ")")
}

; --- URL encode (RFC 3986 unreserved chars kept, everything else %XX of
; the UTF-8 bytes). Encoding the whole string at once keeps surrogate
; pairs (emoji) intact — per-character encoding split them in two.
UrlEncode(text) {
    n := StrPut(text, "UTF-8") - 1
    buf := Buffer(Max(n, 1))
    StrPut(text, buf, "UTF-8")
    out := ""
    loop n {
        b := NumGet(buf, A_Index - 1, "UChar")
        if (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
            || b = 0x2D || b = 0x2E || b = 0x5F || b = 0x7E  ; - . _ ~
            out .= Chr(b)
        else
            out .= "%" Format("{:02X}", b)
    }
    return out
}

ClipUrlEncode() {
    if (text := ClipTextOrNotify()) = ""
        return
    A_Clipboard := UrlEncode(text)
    Notify("URL encoded (UTF-8) — pasted to clipboard")
}

; --- Base64 encode (Crypt32, UTF-8 safe) ---
B64EncodeText(text) {
    nBytes := StrPut(text, "UTF-8") - 1  ; byte count, excl. null
    buf := Buffer(nBytes)
    StrPut(text, buf, "UTF-8")
    req := 0
    if !DllCall("Crypt32\CryptBinaryToStringW", "ptr", buf.Ptr, "uint", nBytes, "uint", 1, "ptr", 0, "uint*", &req)  ; CRYPT_STRING_BASE64
        throw Error("CryptBinaryToString size query failed")
    out := Buffer(req * 2)
    if !DllCall("Crypt32\CryptBinaryToStringW", "ptr", buf.Ptr, "uint", nBytes, "uint", 1, "ptr", out.Ptr, "uint*", &req)
        throw Error("CryptBinaryToString failed")
    b64 := RTrim(StrGet(out, req, "UTF-16"), "`0")
    return StrReplace(StrReplace(b64, "`r"), "`n")
}

B64DecodeText(b64) {
    src := Trim(b64)
    size := 0
    if !DllCall("Crypt32\CryptStringToBinaryW", "wstr", src, "uint", StrLen(src), "uint", 1, "ptr", 0, "uint*", &size, "ptr", 0, "ptr", 0)
        throw Error("invalid base64 input")
    buf := Buffer(size)
    if !DllCall("Crypt32\CryptStringToBinaryW", "wstr", src, "uint", StrLen(src), "uint", 1, "ptr", buf.Ptr, "uint*", &size, "ptr", 0, "ptr", 0)
        throw Error("CryptStringToBinary failed")
    return StrGet(buf, size, "UTF-8")
}

ClipBase64Encode() {
    if (text := ClipTextOrNotify()) = ""
        return
    try A_Clipboard := B64EncodeText(text)
    catch as err
        return ClipBase64Fail(err.Message)
    Notify("Base64 encoded — pasted to clipboard")
}

ClipBase64Decode() {
    if (text := ClipTextOrNotify()) = ""
        return
    try A_Clipboard := B64DecodeText(text)
    catch as err
        return ClipBase64Fail(err.Message)
    Notify("Base64 decoded — pasted to clipboard")
}

ClipBase64Fail(msg) {
    MsgBox("Base64 failed: " msg, "Error", 48)
}

; --- Insert timestamp ---
ClipInsertTimestamp(format) {
    now := A_Now
    switch format {
        case "iso":
            ts := FormatTime(now, "yyyy-MM-ddTHH:mm:ss")
        case "unix":
            ts := "" . GetUnixEpoch()
        case "readable":
            ts := FormatTime(now, "dddd, MMMM d, yyyy HH:mm:ss")
        default:
            ts := FormatTime(now)
    }
    A_Clipboard := ts
    Notify("Timestamp: " ts)
}

; --- Strip HTML formatting ---
; &amp; is decoded LAST: decoding it first would turn "&amp;lt;" (the
; literal text "&lt;") into "<".
HtmlToText(text) {
    text := RegExReplace(text, "i)<br\s*/?>", "`n")
    text := RegExReplace(text, "<[^>]+>", "")
    text := StrReplace(text, "&nbsp;", " ")
    text := StrReplace(text, "&lt;", "<")
    text := StrReplace(text, "&gt;", ">")
    text := StrReplace(text, "&quot;", '"')
    text := StrReplace(text, "&#39;", "'")
    text := DecodeNumericEntities(text)
    text := StrReplace(text, "&amp;", "&")
    return RegExReplace(text, "[ \t]+", " ")
}

; &#65; / &#x41; -> "A". A loop, because AHK v2's RegExReplace takes no
; callback function (passing one throws — Strip HTML used to always fail).
DecodeNumericEntities(text) {
    out := "", pos := 1
    while found := RegExMatch(text, "i)&#(x[0-9a-f]{1,6}|\d{1,7});", &m, pos) {
        out .= SubStr(text, pos, found - pos)
        v := m[1]
        code := (SubStr(v, 1, 1) = "x") ? Integer("0x" SubStr(v, 2)) : Integer(v)
        out .= (code > 0 && code <= 0x10FFFF) ? Chr(code) : m[0]  ; invalid: keep as-is
        pos := found + m.Len
    }
    return out SubStr(text, pos)
}

ClipStripHtml() {
    if (text := ClipTextOrNotify()) = ""
        return
    A_Clipboard := result := HtmlToText(text)
    Notify("HTML stripped — " StrLen(result) " chars")
}

; --- Trim each line ---
ClipTrimLines() {
    if (text := ClipTextOrNotify()) = ""
        return
    lines := StrSplit(text, "`n", "`r")
    for i, line in lines
        lines[i] := Trim(line)
    A_Clipboard := StrJoin(lines, "`n")
    Notify("Trimmed " lines.Length " line(s)")
}

; --- Count chars / words / lines ---
ClipCountStats() {
    if (text := ClipTextOrNotify()) = ""
        return
    chars := StrLen(text)
    lines := StrSplit(text, "`n", "`r").Length
    words := 0
    pos := 1
    while RegExMatch(text, "\S+", &m, pos) {
        words++
        pos := m.Pos + m.Len
    }
    MsgBox("Clipboard Statistics:`n`n  Lines:   " lines "`n  Words:   " words "`n  Chars:   " chars, "Clipboard Stats", 64)
}

; --- SHA-256 of the clipboard text (UTF-8 bytes), result copied ---
ClipHashText() {
    if (text := ClipTextOrNotify()) = ""
        return
    try hash := HashText(text, "SHA256")
    catch as err {
        MsgBox("Hash failed:`n" err.Message, "Clipboard Hash", 48)
        return
    }
    A_Clipboard := hash
    Notify("SHA-256 copied: " SubStr(hash, 1, 24) "...", 3000)
}

; --- Generate a random GUID (v4) and copy it ---
ClipNewGuid() {
    try g := NewGuid()
    catch as err {
        MsgBox("Could not generate a GUID:`n" err.Message, "Generate GUID", 48)
        return
    }
    A_Clipboard := g
    Notify("GUID copied: " g, 2500)
}
