; ============================================================
; OUTPUT CONSOLE — themed window for command output (Step 1)
; Replaces the "temp .txt in Notepad" path of ShowText() in dark
; mode. Look mirrors ShellExView Modern: OLED #0D0D0D background,
; Win11-blue #60CDFF accent, Segoe UI + Consolas.
;
; Teaching notes (why it looks the way it does):
;   * A Gui object is a window; you AddText/AddEdit/AddButton onto it
;     and hook events with OnEvent("Click"/"Escape"/"Size", callback).
;   * Event callbacks must accept EXACTLY the parameters that event
;     passes, or end in * to be variadic. Size passes FOUR (gui, minMax,
;     width, height): a 3-param OnSize loads fine but throws "Invalid
;     callback function." the instant the event fires. Our buttons and
;     Escape/Close hooks use (*) so they never cared about the count.
;   * AHK has no layout engine (unlike WPF's Grid/DockPanel) — on
;     resize we reposition controls MANUALLY inside the Size event.
;   * A Text control with a Background option doubles as a colored
;     rectangle — that is our 4px accent bar (WPF Rectangle stand-in).
;   * A read-only Edit paints via WM_CTLCOLORSTATIC, not WM_CTLCOLOREDIT
;     — our per-control color map covers both paths in Core.ahk.
; ============================================================

; Open consoles are kept referenced so AutoHotkey cannot garbage-collect
; a live window, and so a future "close all windows" action can find them.
global gOpenConsoles := []

ConsoleShow(title, body) {
    global gOpenConsoles, THEME_BG, THEME_TEXT, THEME_TEXT_DIM, THEME_TEXT_MUTE, THEME_ACCENT

    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    ; count lines without building an array: newlines = length difference
    lineCount := (body = "") ? 0 : StrLen(body) - StrLen(StrReplace(body, "`n")) + 1

    g := Gui("+Resize +MinSize560x400", "Toolbox — " title)
    g.MarginX := 0
    g.MarginY := 0

    ; ---- header: 4px accent bar + title + dim subtitle ----
    g.SetFont("s10", "Segoe UI")
    bar := g.AddText("x12 y14 w4 h34 Background" THEME_ACCENT)
    g.SetFont("s10 Bold")
    ttl := g.AddText("x26 y14 w520 h22", title)
    g.SetFont("s9 Norm")
    sub := g.AddText("x26 y38 w540 h16", "captured " ts "  ·  " lineCount " lines")

    ; ---- output: read-only monospace edit, fills the window ----
    g.SetFont("s10", "Consolas")
    ed := g.AddEdit("x12 y62 w736 h382 ReadOnly Multi VScroll", body)

    ; ---- footer: buttons right-aligned, status line left, hint right ----
    g.SetFont("s10", "Segoe UI")
    btnCopy   := g.AddButton("x456 y452 w86 h30 Default", "Copy")
    btnEditor := g.AddButton("x550 y452 w110 h30", "Open in editor")
    btnClose  := g.AddButton("x668 y452 w80 h30", "Close")
    stL := g.AddText("x12 y490 w416 h18", "")
    stR := g.AddText("x440 y490 w308 h18 Right", "Esc closes  ·  Ctrl+A select all  ·  Enter copies")

    ; ---- events (closures capture the controls above) ----
    ; Size signature is (guiObj, minMax, w, h) — 4 params, fixed.
    ; minMax: 0 = restored/normal, -1 = minimized, 1 = maximized.
    OnSize(guiObj, minMax, w, h) {
        if (minMax = -1 || w < 100)   ; minimized / degenerate
            return
        ed.Move(12, 62, w - 24, h - 138)
        btnCopy.Move(w - 304, h - 68)
        btnEditor.Move(w - 210, h - 68)
        btnClose.Move(w - 92, h - 68)
        stL.Move(12, h - 30, w - 344, 18)
        stR.Move(w - 320, h - 30, 308, 18)
    }

    CopyClicked(*) {
        A_Clipboard := body
        stL.Text := "Copied " lineCount " lines to clipboard."
        SetTimer(() => stL.Text := "", -2000)
    }
    CloseClicked(*) {
        for i, c in gOpenConsoles
            if (c = g) {
                gOpenConsoles.RemoveAt(i)
                break
            }
        g.Destroy()
    }

    btnCopy.OnEvent("Click", CopyClicked)
    btnEditor.OnEvent("Click", (*) => ShowTextInEditor(title, body))
    btnClose.OnEvent("Click", CloseClicked)
    g.OnEvent("Escape", CloseClicked)
    g.OnEvent("Close", CloseClicked)
    g.OnEvent("Size", OnSize)

    ; ---- dark theme: OLED bg + exact per-control colors ----
    ; In light mode everything above still works with system colors.
    if IsDarkMode() {
        ApplyDarkTheme(g, THEME_BG)   ; window bg, dark caption, control loop
        ; Exact colors per control (COLORREF BGR via BgrOf). These win over
        ; the generic dark-theme brushes inside the WM_CTLCOLOR* hooks.
        SetCtlColors(bar.Hwnd, BgrOf(THEME_ACCENT),    BgrOf(THEME_ACCENT))
        SetCtlColors(ttl.Hwnd, BgrOf(THEME_TEXT),      BgrOf(THEME_BG))
        SetCtlColors(sub.Hwnd, BgrOf(THEME_TEXT_MUTE), BgrOf(THEME_BG))
        SetCtlColors(ed.Hwnd,  BgrOf(THEME_TEXT),      BgrOf(THEME_BG))
        SetCtlColors(stL.Hwnd, BgrOf(THEME_TEXT_DIM),  BgrOf(THEME_BG))
        SetCtlColors(stR.Hwnd, BgrOf(THEME_TEXT_MUTE), BgrOf(THEME_BG))
    }

    ; ---- show: fill most of the work area height (nicer default size) ----
    MonitorGetWorkArea(, &waL, &waT, &waR, &waB)
    defW := Min(880, waR - waL - 60)
    defH := Max(480, Min(860, waB - waT - 90))
    g.Show("w" defW " h" defH " Center")

    ; Initial focus lands on the Edit, and a classic EDIT control selects
    ; ALL of its text when it gains focus programmatically. Send
    ; EM_SETSEL (0xB1) with (0,0) to park the caret at the top, unselected.
    SendMessage(0x00B1, 0, 0, ed.Hwnd)

    ; Controls were created for the old fixed 760x520 layout — reflow once
    ; for the real size, using the same handler the Size event calls.
    OnSize(0, 0, defW, defH)

    gOpenConsoles.Push(g)
}
