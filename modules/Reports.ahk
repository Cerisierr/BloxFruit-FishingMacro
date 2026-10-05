; ============================================================================
;  REPORT CARD  (StatMonitor-style PNG drawn with GDI+, attached to the webhook)
;  Shows only: money gained, levels gained, session time (+ a few small stats).
; ============================================================================
class Gp {
    static token := 0
    static clsid := 0
    static fonts := Map()

    static Start() {
        if this.token
            return true
        si := Buffer(24, 0)
        NumPut("UInt", 1, si, 0)
        tk := 0
        if (DllCall("gdiplus\GdiplusStartup", "ptr*", &tk, "ptr", si, "ptr", 0) != 0)
            return false
        this.token := tk
        this.clsid := Buffer(16, 0)
        DllCall("ole32\CLSIDFromString", "wstr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "ptr", this.clsid)
        return true
    }

    static Canvas(w, h, bg) {
        bmp := 0
        g := 0
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", w, "int", h, "int", 0, "int", 0x26200A, "ptr", 0, "ptr*", &bmp)
        DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", bmp, "ptr*", &g)
        DllCall("gdiplus\GdipSetSmoothingMode", "ptr", g, "int", 4)
        DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", g, "int", 4)
        DllCall("gdiplus\GdipGraphicsClear", "ptr", g, "uint", bg)
        return {bmp: bmp, g: g, w: w, h: h}
    }

    static Brush(argb) {
        b := 0
        DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &b)
        return b
    }

    static RoundRect(c, x, y, w, h, r, argb) {
        path := 0
        d := r * 2
        DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &path)
        DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x, "float", y, "float", d, "float", d, "float", 180, "float", 90)
        DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x + w - d, "float", y, "float", d, "float", d, "float", 270, "float", 90)
        DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x + w - d, "float", y + h - d, "float", d, "float", d, "float", 0, "float", 90)
        DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x, "float", y + h - d, "float", d, "float", d, "float", 90, "float", 90)
        DllCall("gdiplus\GdipClosePathFigure", "ptr", path)
        br := this.Brush(argb)
        DllCall("gdiplus\GdipFillPath", "ptr", c.g, "ptr", br, "ptr", path)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
        DllCall("gdiplus\GdipDeletePath", "ptr", path)
    }

    ; pts = [x1, y1, x2, y2, ...]
    static Pts(pts) {
        b := Buffer(pts.Length * 4, 0)
        for i, v in pts
            NumPut("float", v, b, (i - 1) * 4)
        return b
    }

    static Line(c, pts, argb, width) {
        if (pts.Length < 4)
            return
        pen := 0
        DllCall("gdiplus\GdipCreatePen1", "uint", argb, "float", width, "int", 2, "ptr*", &pen)
        DllCall("gdiplus\GdipSetPenLineJoin", "ptr", pen, "int", 2)
        b := this.Pts(pts)
        DllCall("gdiplus\GdipDrawLines", "ptr", c.g, "ptr", pen, "ptr", b, "int", pts.Length // 2)
        DllCall("gdiplus\GdipDeletePen", "ptr", pen)
    }

    static Poly(c, pts, argb) {
        if (pts.Length < 6)
            return
        br := this.Brush(argb)
        b := this.Pts(pts)
        DllCall("gdiplus\GdipFillPolygon", "ptr", c.g, "ptr", br, "ptr", b, "int", pts.Length // 2, "int", 0)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
    }

    static Font(size, bold) {
        key := size . (bold ? "b" : "r")
        if this.fonts.Has(key)
            return this.fonts[key]
        fam := 0
        font := 0
        if (DllCall("gdiplus\GdipCreateFontFamilyFromName", "wstr", "Segoe UI", "ptr", 0, "ptr*", &fam) != 0)
            DllCall("gdiplus\GdipCreateFontFamilyFromName", "wstr", "Arial", "ptr", 0, "ptr*", &fam)
        DllCall("gdiplus\GdipCreateFont", "ptr", fam, "float", size, "int", bold ? 1 : 0, "int", 2, "ptr*", &font)
        this.fonts[key] := font
        return font
    }

    ; align / valign: 0 = near, 1 = centre, 2 = far
    static Text(c, txt, x, y, w, h, size, argb, bold := false, align := 0, valign := 1) {
        font := this.Font(size, bold)
        fmt := 0
        DllCall("gdiplus\GdipCreateStringFormat", "int", 0x1000, "int", 0, "ptr*", &fmt)     ; NoWrap
        DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", fmt, "int", align)
        DllCall("gdiplus\GdipSetStringFormatLineAlign", "ptr", fmt, "int", valign)
        rc := Buffer(16, 0)
        NumPut("float", x, "float", y, "float", w, "float", h, rc)
        br := this.Brush(argb)
        DllCall("gdiplus\GdipDrawString", "ptr", c.g, "wstr", String(txt), "int", -1, "ptr", font
            , "ptr", rc, "ptr", fmt, "ptr", br)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
        DllCall("gdiplus\GdipDeleteStringFormat", "ptr", fmt)
    }

    static Save(c, path) {
        ok := (DllCall("gdiplus\GdipSaveImageToFile", "ptr", c.bmp, "wstr", path, "ptr", this.clsid, "ptr", 0) == 0)
        DllCall("gdiplus\GdipDeleteGraphics", "ptr", c.g)
        DllCall("gdiplus\GdipDisposeImage", "ptr", c.bmp)
        return (ok && FileExist(path)) ? true : false
    }
}

HistPush(*) {
    if !BotState.running
        return
    Hist.Push([Now() - BotStats.started, BotStats.income, BotStats.levels, BotStats.catches])
    if (Hist.Length > HIST_MAX) {                        ; thin out: keep every second sample
        keep := []
        for i, smp in Hist {
            if (Mod(i, 2) == 1 || i == Hist.Length)
                keep.Push(smp)
        }
        Hist.Length := 0
        for smp in keep
            Hist.Push(smp)
    }
}

LvlGain(n) {
    return (Cfg.trackLevel && BotState.levelStart >= 0) ? "+" . n : "n/a"
}

Trim0(x) {
    s := Format("{:.2f}", x)
    if InStr(s, ".")
        s := RTrim(RTrim(s, "0"), ".")
    return s
}

ShortNum(v, money := true) {
    a := Abs(v)
    pre := money ? "$" : ""
    if (a >= 1e12)
        return pre . Trim0(v / 1e12) . "T"
    if (a >= 1e9)
        return pre . Trim0(v / 1e9) . "B"
    if (a >= 1e6)
        return pre . Trim0(v / 1e6) . "M"
    if (a >= 1e3)
        return pre . Trim0(v / 1e3) . "K"
    return pre . Trim0(v)
}

NiceMax(v) {
    if (v <= 0)
        return 4
    p := 10 ** Floor(Log(v))
    m := v / p
    for n in [1, 1.2, 1.6, 2, 2.4, 3, 4, 5, 6, 8, 10] {
        if (m <= n)
            return n * p
    }
    return 10 * p
}

; One area chart panel. series = [[elapsed s, value], ...], t0 = start timestamp.
CardChart(c, x, y, w, h, title, series, tMax, color, t0, money, nowText) {
    Gp.RoundRect(c, x, y, w, h, 14, 0xFF1E1E22)
    Gp.Text(c, title, x, y + 8, w, 28, 17, 0xFFEDEDED, true, 1, 1)
    Gp.Text(c, nowText, x, y + 10, w - 18, 26, 14, color, true, 2, 1)
    px := x + 70
    py := y + 48
    pw := w - 70 - 20
    ph := h - 48 - 36
    tMax := Max(60, tMax)
    vmax := 0
    for smp in series
        vmax := Max(vmax, smp[2])
    vmax := money ? NiceMax(vmax) : Max(4, Ceil(vmax / 4) * 4)

    Loop 5 {
        i := A_Index - 1
        gy := py + ph - ph * i / 4
        Gp.Line(c, [px, gy, px + pw, gy], 0xFF35353B, 1)
        Gp.Text(c, ShortNum(vmax * i / 4, money), x + 4, gy - 10, 60, 20, 11, 0xFF9A9AA4, false, 2, 1)
    }
    Loop 5 {
        i := A_Index - 1
        tx := px + pw * i / 4
        lbl := FormatTime(DateAdd(t0, Round(tMax * i / 4), "Seconds"), "HH:mm")
        Gp.Text(c, lbl, tx - 30, py + ph + 8, 60, 20, 11, 0xFF9A9AA4, false, 1, 1)
    }

    line := []
    for smp in series {
        line.Push(px + pw * Min(1, smp[1] / tMax))
        line.Push(py + ph - ph * Min(1, smp[2] / vmax))
    }
    if (line.Length >= 4) {
        poly := [line[1], py + ph]
        for v in line
            poly.Push(v)
        poly.Push(line[line.Length - 1])
        poly.Push(py + ph)
        Gp.Poly(c, poly, (0x55 << 24) | (color & 0xFFFFFF))
        Gp.Line(c, line, color, 2.5)
    }
}

; Stat panel: title + rows of [label, value, colour].
CardPanel(c, x, y, w, h, title, rows) {
    Gp.RoundRect(c, x, y, w, h, 14, 0xFF1E1E22)
    Gp.Text(c, title, x, y + 8, w, 28, 15, 0xFFEDEDED, true, 1, 1)
    ry := y + 42
    for r in rows {
        Gp.Text(c, r[1], x + 18, ry, w // 2, 36, 14, 0xFF9A9AA4, false, 0, 1)
        Gp.Text(c, r[2], x + w // 2 - 10, ry, w // 2 - 8, 36, 20, r[3], true, 2, 1)
        ry += 38
    }
}

; Full-width panel: quests of this report window (counts + the last few quests).
CardQuests(c, x, y, w, h) {
    Gp.RoundRect(c, x, y, w, h, 14, 0xFF1E1E22)
    Gp.Text(c, "QUESTS", x, y + 8, w, 28, 15, 0xFFEDEDED, true, 1, 1)
    cells := [["ACCEPTED", Hour.questsAcc, 0xFFFBBF24], ["DONE", Hour.quests, 0xFF4ADE80], ["FAILED", Hour.questsFail, 0xFFF87171]]
    for i, cell in cells {
        cx := x + 18 + (i - 1) * 110
        Gp.Text(c, cell[1], cx, y + 44, 104, 18, 11, 0xFF9A9AA4, false, 0, 1)
        Gp.Text(c, cell[2], cx, y + 62, 104, 40, 26, cell[3], true, 0, 1)
    }
    n := Hour.qlog.Length
    if (n = 0) {
        Gp.Text(c, "No quest this window", x + 360, y + 60, w - 380, 24, 12, 0xFF9A9AA4, false, 0, 1)
        return
    }
    i := Max(1, n - 2)
    ry := y + 44
    while (i <= n) {
        e := Hour.qlog[i]
        col := (e.status == "done") ? 0xFF4ADE80 : (e.status == "failed") ? 0xFFF87171 : 0xFFFBBF24
        tag := (e.status == "done") ? "DONE" : (e.status == "failed") ? "FAILED" : "ONGOING"
        Gp.Text(c, tag, x + 360, ry, 80, 22, 11, col, true, 0, 1)
        Gp.Text(c, e.label, x + 445, ry, w - 465, 22, 12, 0xFFEDEDED, false, 0, 1)
        ry += 25
        i++
    }
}

; Full-width panel: per-hour rates of fish / money / levels against the previous hour.
; prev = 0 when there is no previous hour yet.
CardCompare(c, x, y, w, h, title, cur, prev) {
    Gp.RoundRect(c, x, y, w, h, 14, 0xFF1E1E22)
    Gp.Text(c, title, x, y + 8, w, 28, 15, 0xFFEDEDED, true, 1, 1)
    cw := (w - 36) // 3
    items := [["FISH / HOUR", Round(cur.fish, 1), IsObject(prev) ? Round(prev.fish, 1) : "", cur.fish, IsObject(prev) ? prev.fish : 0, 0xFFEDEDED]
            , ["MONEY / HOUR", ShortNum(cur.money), IsObject(prev) ? ShortNum(prev.money) : "", cur.money, IsObject(prev) ? prev.money : 0, 0xFF4ADE80]
            , ["LEVELS / HOUR", Round(cur.lvl, 1), IsObject(prev) ? Round(prev.lvl, 1) : "", cur.lvl, IsObject(prev) ? prev.lvl : 0, 0xFFFBBF24]]
    for i, it in items {
        cx := x + 18 + (i - 1) * cw
        if (i > 1)
            Gp.Line(c, [cx - 8, y + 48, cx - 8, y + h - 14], 0xFF35353B, 1)
        Gp.Text(c, it[1], cx, y + 44, cw - 16, 18, 11, 0xFF9A9AA4, false, 0, 1)
        Gp.Text(c, it[2], cx, y + 62, cw - 16, 34, 22, it[6], true, 0, 1)
        if IsObject(prev) {
            d := DeltaInfo(it[4], it[5])
            Gp.Text(c, d.txt, cx, y + 62, cw - 20, 34, 16, d.col, true, 2, 1)
            Gp.Text(c, "previous hour: " . it[3], cx, y + 96, cw - 16, 18, 11, 0xFF9A9AA4, false, 0, 1)
        } else {
            Gp.Text(c, "no previous hour yet", cx, y + 96, cw - 16, 18, 11, 0xFF9A9AA4, false, 0, 1)
        }
    }
}

; kind = "hour" (periodic report) or "stop" (final summary). Returns a PNG path or "".
ReportCard(kind) {
    try {
        return ReportCardDraw(kind)
    } catch as err {
        extra := ""
        try extra := " | " . err.What . " | " . err.Extra . " | line " . err.Line
        LogMsg("[card] could not draw the report image: " . err.Message . extra)
        return ""
    }
}

ReportCardDraw(kind) {
    if !Gp.Start()
        return ""
    stopKind := (kind == "stop")
    up := stopKind ? Max(1, BotStats.lastUp) : Max(1, Now() - BotStats.started)
    hsec := Max(3, Now() - Hour.started)
    t0 := DateAdd(A_Now, -Round(up), "Seconds")

    money := []
    lvls := []
    for smp in Hist {
        if (smp[1] > up)
            continue
        money.Push([smp[1], smp[2]])
        lvls.Push([smp[1], smp[3]])
    }
    money.Push([up, BotStats.income])
    lvls.Push([up, BotStats.levels])

    green := 0xFF4ADE80
    amber := 0xFFFBBF24
    white := 0xFFEDEDED
    blue := 0xFF60A5FA

    c := Gp.Canvas(1000, 830, 0xFF121214)
    CardChart(c, 24, 24, 632, 276, "MONEY EARNED", money, up, green, t0, true, "$" . Fmt(BotStats.income))
    CardChart(c, 24, 312, 632, 224, "LEVELS GAINED", lvls, up, amber, t0, false, LvlGain(BotStats.levels))

    X := 680
    W := 296
    hourTitle := "LAST " . ((hsec >= 3540 && hsec <= 3660) ? "HOUR" : StrUpper(FmtDur(hsec)))
    sessRows := [["Money gained", "$" . Fmt(BotStats.income), green]
        , ["Levels gained", LvlGain(BotStats.levels), amber]
        , ["Session time", FmtDur(up), white]]
    hourRows := [["Money gained", "$" . Fmt(Hour.income), green]
        , ["Levels gained", LvlGain(Hour.levels), amber]
        , ["Time", FmtDur(hsec), white]]
    if stopKind {
        CardPanel(c, X, 24, W, 168, "SESSION", sessRows)
        CardPanel(c, X, 204, W, 168, "SINCE LAST REPORT", hourRows)
    } else {
        CardPanel(c, X, 24, W, 168, hourTitle, hourRows)
        CardPanel(c, X, 204, W, 168, "SESSION", sessRows)
    }

    Gp.RoundRect(c, X, 384, W, 92, 14, 0xFF1E1E22)
    cells := [["Fish caught", Fmt(BotStats.catches)]
        , ["Fish per hour", Round(BotStats.catches * 3600 / up, 1)]
        , ["Level now", BotState.levelLast >= 0 ? BotState.levelLast : "n/a"]
        , ["Bait spent", "$" . Fmt(BotStats.spent)]]
    for i, cell in cells {
        cx := X + 18 + Mod(i - 1, 2) * 138
        cy := 394 + ((i - 1) // 2) * 40
        Gp.Text(c, cell[1], cx, cy, 130, 16, 11, 0xFF9A9AA4, false, 0, 1)
        Gp.Text(c, cell[2], cx, cy + 15, 130, 24, 15, white, true, 0, 1)
    }

    Gp.RoundRect(c, X, 488, W, 48, 14, 0xFF1E1E22)
    Gp.Text(c, APP_NAME . "  v" . APP_VERSION, X, 492, W, 20, 12, blue, true, 1, 1)
    Gp.Text(c, FormatTime(t0, "HH:mm") . " - " . FormatTime(A_Now, "HH:mm") . "  |  " . FormatTime(A_Now, "MMMM d, yyyy")
        , X, 512, W, 20, 11, amber, false, 1, 1)

    ; ---- hourly advantage: this window vs the previous hour (per-hour rates) ----
    cur := Rates(Hour.catches, Hour.income, Hour.levels, hsec)
    cmpTitle := "HOURLY ADVANTAGE  -  THIS HOUR VS PREVIOUS HOUR  (per-hour rates)"
    if (stopKind && hsec < 300) {                        ; too short to be fair: use the whole session
        cur := Rates(BotStats.catches, BotStats.income, BotStats.levels, up)
        cmpTitle := "HOURLY ADVANTAGE  -  SESSION VS PREVIOUS HOUR  (per-hour rates)"
    }
    prv := PrevHour.valid ? Rates(PrevHour.catches, PrevHour.income, PrevHour.levels, PrevHour.secs) : 0
    if !PrevHour.valid
        cmpTitle := "HOURLY RATES  -  comparison starts with the next report"
    CardCompare(c, 24, 552, 952, 124, cmpTitle, cur, prv)
    CardQuests(c, 24, 692, 952, 124)

    path := TMP_DIR . "\card_" . FormatTime(, "yyyyMMdd_HHmmss") . ".png"
    return Gp.Save(c, path) ? path : ""
}
