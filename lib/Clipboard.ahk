; ============================================================
; CLIPBOARD COMMANDS
; ============================================================

; --- Remove duplicate lines ---
ClipRemoveDuplicates() {
    if A_Clipboard = "" {
        ToolTip("Clipboard is empty.")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    lines := StrSplit(A_Clipboard, "`n", "`r")
    seen := Map()
    unique := []

    for line in lines {
        trimmed := Trim(line)
        if trimmed = "" || seen.Has(trimmed)
            continue
        seen[trimmed] := true
        unique.Push(line)  ; keep original (with original whitespace/indent)
    }

    originalCount := lines.Length
    result := ""
    for line in unique
        result .= line "`n"
    result := RTrim(result, "`n")

    A_Clipboard := result
    removed := originalCount - unique.Length
    if removed > 0
        ToolTip("Removed " removed " duplicate(s) — " unique.Length " line(s) remain")
    else
        ToolTip("No duplicates found — " unique.Length " line(s)")
    SetTimer(() => ToolTip(), -2000)
}

; --- Sort lines ---
ClipSortLines(descending := false) {
    if A_Clipboard = "" {
        ToolTip("Clipboard is empty.")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    arr := StrSplit(RTrim(A_Clipboard, "`r`n"), "`n", "`r")
    n := arr.Length

    ; Build a parallel array of lowercase keys for case-insensitive sort
    keys := []
    for i, line in arr
        keys.Push(StrLower(line))

    ; Selection sort (O(n^2) but no bubble sort hang risk on large data)
    loop n - 1 {
        best := A_Index
        loop n - A_Index {
            j := A_Index + best
            a := keys[best]
            b := keys[j]
            if (descending ? (b > a) : (b < a))
                best := j
        }
        if best != A_Index {
            ; Swap both arrays
            tmp := arr[A_Index], arr[A_Index] := arr[best], arr[best] := tmp
            tmp := keys[A_Index], keys[A_Index] := keys[best], keys[best] := tmp
        }
    }

    result := ""
    for line in arr
        result .= line "`n"
    A_Clipboard := RTrim(result, "`n")

    dir := descending ? "Z-A" : "A-Z"
    ToolTip("Sorted " n " lines (" dir ")")
    SetTimer(() => ToolTip(), -1500)
}

; --- URL encode (UTF-8 safe) ---
ClipUrlEncode() {
    if A_Clipboard = "" {
        ToolTip("Clipboard is empty.")
        SetTimer(() => ToolTip(), -2000)
        return
    }
    encoded := ""
    for i, char in StrSplit(A_Clipboard) {
        code := Ord(char)
        if (code >= 48 && code <= 57)    ; 0-9
            || (code >= 65 && code <= 90)   ; A-Z
            || (code >= 97 && code <= 122)  ; a-z
            || char = "-" || char = "_" || char = "." || char = "~"
            encoded .= char
        else if code < 128 {
            ; Single-byte ASCII
            encoded .= "%" Format("{:02X}", code)
        } else {
            ; Multi-byte UTF-8: encode each byte
            buf := Buffer(8)
            wbuf := Buffer(4, 0)
            NumPut("UShort", Ord(char) & 0xFFFF, wbuf, 0)
            nBytes := DllCall("WideCharToMultiByte", "UInt", 65001, "UInt", 0, "Ptr", wbuf.Ptr, "Int", 1, "Ptr", buf.Ptr, "Int", buf.Size, "Ptr", 0, "Ptr", 0)
            loop nBytes
                encoded .= "%" Format("{:02X}", NumGet(buf, A_Index - 1, "UChar"))
        }
    }
    A_Clipboard := encoded
    ToolTip("URL encoded (UTF-8) — pasted to clipboard")
    SetTimer(() => ToolTip(), -1500)
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
    if A_Clipboard = "" {
        ToolTip("Clipboard is empty.")
        SetTimer(() => ToolTip(), -2000)
        return
    }
    try A_Clipboard := B64EncodeText(A_Clipboard)
    catch as err
        return ClipBase64Fail(err.Message)
    ToolTip("Base64 encoded — pasted to clipboard")
    SetTimer(() => ToolTip(), -1500)
}

; --- Base64 decode (Crypt32) ---
ClipBase64Decode() {
    if A_Clipboard = "" {
        ToolTip("Clipboard is empty.")
        SetTimer(() => ToolTip(), -2000)
        return
    }
    try A_Clipboard := B64DecodeText(A_Clipboard)
    catch as err
        return ClipBase64Fail(err.Message)
    ToolTip("Base64 decoded — pasted to clipboard")
    SetTimer(() => ToolTip(), -1500)
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
    ToolTip("Timestamp: " ts)
    SetTimer(() => ToolTip(), -1500)
}

; --- Strip HTML formatting ---
ClipStripHtml() {
    if A_Clipboard = "" {
        ToolTip("Clipboard is empty.")
        SetTimer(() => ToolTip(), -2000)
        return
    }
    text := A_Clipboard
    text := RegExReplace(text, "<br\s*/?>", "`n")
    text := RegExReplace(text, "<[^>]+>", "")
    text := RegExReplace(text, "&nbsp;", " ")
    text := RegExReplace(text, "&amp;", "&")
    text := RegExReplace(text, "&lt;", "<")
    text := RegExReplace(text, "&gt;", ">")
    text := RegExReplace(text, "&quot;", '"')
    text := RegExReplace(text, "&#(\d+);", m => Chr(Integer(m[1])))
    text := RegExReplace(text, "[ \t]+", " ")
    A_Clipboard := text
    ToolTip("HTML stripped — " StrLen(text) " chars")
    SetTimer(() => ToolTip(), -1500)
}

; --- Trim each line ---
ClipTrimLines() {
    if A_Clipboard = "" {
        ToolTip("Clipboard is empty.")
        SetTimer(() => ToolTip(), -2000)
        return
    }
    lines := StrSplit(A_Clipboard, "`n", "`r")
    result := ""
    for line in lines
        result .= Trim(line) "`n"
    A_Clipboard := RTrim(result, "`n")
    ToolTip("Trimmed " lines.Length " line(s)")
    SetTimer(() => ToolTip(), -1500)
}

; --- Count chars / words / lines ---
ClipCountStats() {
    if A_Clipboard = "" {
        ToolTip("Clipboard is empty.")
        SetTimer(() => ToolTip(), -2000)
        return
    }
    chars := StrLen(A_Clipboard)
    lines := StrSplit(A_Clipboard, "`n", "`r").Length
    words := 0
    pos := 1
    while RegExMatch(A_Clipboard, "\S+", &m, pos) {
        words++
        pos := m.Pos + m.Len
    }
    MsgBox("Clipboard Statistics:`n`n  Lines:   " lines "`n  Words:   " words "`n  Chars:   " chars, "Clipboard Stats", 64)
}

