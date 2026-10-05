; ============================================================================
;  DISCORD WEBHOOK
; ============================================================================
JsonEsc(s) {
    s := String(s)
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return s
}

UrlIsHook(u) {
    return RegExMatch(u, "i)^https://(?:(?:canary|ptb)\.)?discord(?:app)?\.com/api/(?:v\d+/)?webhooks/\d+/[\w-]+$") ? true : false
}

HookUrlOk() {
    return UrlIsHook(Cfg.hkUrl)
}

; Channel for the hourly report: its own webhook when one is given and valid,
; otherwise the main one.
HourlyUrl() {
    return UrlIsHook(Cfg.hkUrlHourly) ? Cfg.hkUrlHourly : Cfg.hkUrl
}

HookReady() {
    return Cfg.hkOn && HookUrlOk()
}

; fields: array of [name, value, inline?]
EmbedJson(title, desc, color, fields := "", imageName := "") {
    j := '{"title":"' . JsonEsc(title) . '","description":"' . JsonEsc(desc) . '","color":' . color
    if (IsObject(fields) && fields.Length) {
        j .= ',"fields":['
        for i, f in fields {
            if (i > 1)
                j .= ","
            val := String(f[2])
            if (val == "")
                val := "-"
            inline := (f.Length >= 3 && !f[3]) ? "false" : "true"
            j .= '{"name":"' . JsonEsc(f[1]) . '","value":"' . JsonEsc(val) . '","inline":' . inline . '}'
        }
        j .= "]"
    }
    if (imageName != "")
        j .= ',"image":{"url":"attachment://' . imageName . '"}'
    j .= ',"footer":{"text":"' . JsonEsc(APP_NAME . "  v" . APP_VERSION) . '"}'
    j .= ',"timestamp":"' . FormatTime(A_NowUTC, "yyyy-MM-ddTHH:mm:ssZ") . '"}'
    return j
}

; Fire-and-forget POST through curl.exe (ships with Windows 10 1803+). The
; optional PNG is attached as multipart. The HTTP status is logged ~5 s later.
; Messages go through a queue (one every 2.2 s) so a busy macro never trips
; Discord's rate limit. Low-priority live-activity messages are dropped when it is full.
HookPost(embeds, filePath := "", content := "", label := "message", fname := "sale.png", lowPrio := false, url := "") {
    if !HookUrlOk()
        return false
    q := BotState.hookQ
    if (lowPrio && q.Length >= 4)
        return false
    if (q.Length >= 40)
        q.RemoveAt(1)
    q.Push([embeds, filePath, content, label, fname, url])
    return true
}

; Send each recorded macro action as a standalone Discord embed. The internal
; [webhook] status messages are excluded to prevent recursive webhook posts.
HookAction(message) {
    if !(BotState.running && HookReady() && Cfg.hkActions)
        return
    if !RegExMatch(message, "^\[([^\]]+)\]\s*(.*)$", &m)
        return
    tag := StrLower(m[1])
    detail := Trim(m[2])
    if (tag == "webhook" || tag == "debug" || detail == "")
        return

    ; Rich event embeds already contain the same action plus useful context.
    if (tag == "catch" && InStr(detail, "#"))
        return
    if (tag == "cast" && InStr(detail, "#") && !InStr(detail, "unverified"))
        return
    if (tag == "chest" && InStr(detail, "collected"))
        return
    if (tag == "bite" && InStr(detail, "possible FALSE HOOK"))
        return
    if (tag == "reel" && InStr(detail, "bar never appeared"))
        return

    title := "Macro action · " . StrTitle(tag)
    color := 0x60A5FA
    if (tag == "rod skill") {
        title := "Rod Power attempted"
        color := 0xFBBF24
    } else if (tag == "bite") {
        title := InStr(detail, "hooked") ? "Hooked detected" : "Bite check"
        color := 0xFBBF24
    } else if (tag == "cast") {
        title := "Fishing rod cast"
        color := 0x94A3B8
    } else if (tag == "catch" || tag == "sale" || tag == "sell") {
        color := 0x34D399
    } else if (tag == "error" || tag == "death" || tag == "stop") {
        color := 0xF87171
    }
    if (StrLen(detail) > 3500)
        detail := SubStr(detail, 1, 3480) . " ...[truncated]"
    HookPost(EmbedJson(title, detail, color), , , "action: " . tag)
}

HookPump() {
    q := BotState.hookQ
    if !q.Length
        return
    a := q.RemoveAt(1)
    HookSend(a[1], a[2], a[3], a[4], a[5], a.Length >= 6 ? a[6] : "")
}

HookSend(embeds, filePath := "", content := "", label := "message", fname := "sale.png", url := "") {
    if (url == "")
        url := Cfg.hkUrl
    if !UrlIsHook(url)
        return false
    curl := A_WinDir . "\System32\curl.exe"
    if !FileExist(curl) {
        LogMsg("[webhook] curl.exe not found (needs Windows 10 1803 or newer) - cannot send")
        return false
    }
    payload := '{"username":"' . JsonEsc(Cfg.hkName) . '","embeds":[' . embeds . ']'
    if (content != "")
        payload .= ',"content":"' . JsonEsc(content) . '"'
    payload .= '}'
    id := A_TickCount . "_" . Random(1000, 9999)
    pf := TMP_DIR . "\hook_" . id . ".json"
    res := TMP_DIR . "\hook_" . id . ".res"
    try {
        f := FileOpen(pf, "w", "UTF-8-RAW")
        f.Write(payload)
        f.Close()
    } catch {
        return false
    }
    cmd := '"' . curl . '" -s -S -m 40 -D "' . res . '" -o NUL -X POST -F "payload_json=<' . pf
        . ';type=application/json"'
    if (filePath != "" && FileExist(filePath))
        cmd .= ' -F "files[0]=@' . filePath . ';filename=' . fname . '"'
    cmd .= ' "' . url . '"'
    try {
        Run(cmd, , "Hide")
    } catch {
        return false
    }
    SetTimer(HookResult.Bind(res, pf, label), -5000)
    return true
}

HookResult(res, pf, label) {
    code := ""
    try {
        txt := FileRead(res)
        if RegExMatch(txt, "HTTP/[\d.]+\s+(\d{3})", &m)
            code := m[1]
    }
    ok := (code == "200" || code == "204")
    if ok {
        SetHookStatus("Last send: " . label . " delivered (HTTP " . code . ") at " . FormatTime(, "HH:mm:ss"))
    } else {
        msg := (code != "") ? "HTTP " . code . " - check the webhook URL" : "no answer - check the URL and your connection"
        LogMsg("[webhook] " . label . " FAILED (" . msg . ")")
        SetHookStatus("Last send FAILED: " . msg, true)
    }
    try FileDelete(res)
    try FileDelete(pf)
}

SetHookStatus(text, bad := false) {
    try {
        Ui.hookStatus.Text := text
        Ui.hookStatus.SetFont("c" . (bad ? Ui.th.bad : Ui.th.muted))
    }
}

HookStartMsg() {
    if !(HookReady() && Cfg.hkStart)
        return
    bait := CurBait()
    resolution := Cfg.resolution . " (profile " . BotState.resW . "x" . BotState.resH
        . "; game area " . BotState.win.w . "x" . BotState.win.h . ")"
    f := [["NPC to farm", Cfg.npc], ["Bait to buy", bait.name . " x" . Cfg.baitPer]
        , ["Auto-buy bait", Cfg.buyBait ? "on" : "off"]
        , ["Fishing rod slot", Cfg.rodSlot], ["Resolution", resolution]
        , ["Auto-sell", (Cfg.sellOn && Cfg.npc != "Angler") ? "every " . Cfg.sellEvery . " catches" : "off"]
        , ["Perfect cast", Cfg.perfect ? "release at " . Cfg.perfectPct . "%" : "off"]
        , ["Zoom-out", Cfg.zoomLock ? Cfg.zoomOut . " notches" : "unlocked"]
        , ["Level", BotState.levelLast >= 0 ? BotState.levelLast : "n/a"]]
    HookPost(EmbedJson("Macro started", "Fishing has begun.", 0x4ADE80, f), , , "start message")
}

HookStopMsg() {
    reason := BotState.stopReason
    if (reason != "") {
        if !(HookReady() && Cfg.hkErr)
            return
    } else if !(HookReady() && Cfg.hkStop) {
        return
    }
    up := BotStats.lastUp
    net := BotStats.income - BotStats.spent
    f := [["Run time", FmtDur(up)], ["Fish caught", Fmt(BotStats.catches)]
        , ["Money generated", "$" . Fmt(BotStats.income)]
        , ["Bait bought", Fmt(BotStats.baitBought) . "  ($" . Fmt(BotStats.spent) . ")"]
        , ["Net profit", (net < 0 ? "-$" : "$") . Fmt(Abs(net))]
        , ["Casts / escapes", BotStats.casts . " / " . BotStats.escapes]
        , ["Levels", LevelText()]
        , ["Quests", BotStats.questsAcc . " accepted  |  " . BotStats.quests . " done  |  " . BotStats.questsFail . " failed"]]
    ; The hourly report (image card) is NOT sent here: it only goes out on schedule, to the hourly URL.
    if (reason != "") {
        shot := BotState.stopShot
        useShot := (shot != "" && FileExist(shot))
        f.Push(["Last log lines", LogTail(8), false])
        mention := (Cfg.hkMention != "") ? "<@" . Cfg.hkMention . ">" : ""
        HookPost(EmbedJson("Macro stopped - needs attention", reason, 0xF87171, f, useShot ? "error.png" : "")
            , useShot ? shot : "", mention, "stop message", "error.png")
    } else {
        HookPost(EmbedJson("Macro stopped", "Stopped manually. Session summary:", 0xFBBF24, f), , , "stop message")
    }
}

HookSale(gained, fishCount, shot, before := -1, after := -1) {
    HistPush()
    if !(HookReady() && Cfg.hkSale)
        return
    f := [["Fish sold", Fmt(fishCount)]
        , ["Money gained", gained >= 0 ? "$" . Fmt(gained) : "unreadable"]
        , ["Session income", "$" . Fmt(BotStats.income)]]
    if (before >= 0 && after >= 0)
        f.Push(["Balance", "$" . Fmt(before) . "  >  $" . Fmt(after), false])
    useShot := (Cfg.hkShot && shot != "" && FileExist(shot))
    HookPost(EmbedJson("Fish sold", "The fish stock was sold at the " . Cfg.npc . ".", 0x34D399, f
        , useShot ? HOOK_SHOT_NAME : ""), useShot ? shot : "", , "sale message")
}

HookBait(bait, qty, cost, shot := "") {
    if !(HookReady() && Cfg.hkBait)
        return
    f := [["Bait", bait.name], ["Quantity", Fmt(qty)], ["Money used", "$" . Fmt(cost)]]
    if (bait.item != "")
        f.Push(["Material", (qty // 10) . " x " . bait.item])
    f.Push(["Total spent this session", "$" . Fmt(BotStats.spent)])
    f.Push(["Bait in inventory", BotState.bait >= 0 ? Min(90, Max(0, BotState.bait) + qty) . " / 90" : "n/a"])
    useShot := (shot != "" && FileExist(shot))
    HookPost(EmbedJson("Bait purchased", "The macro restocked its bait.", 0x60A5FA, f, useShot ? HOOK_SHOT_NAME : "")
        , useShot ? shot : "", , "bait message")
}

; ---- live activity ---------------------------------------------------------
HookBuying(bait, qty, cost) {
    if !(HookReady() && Cfg.hkBuy)
        return
    HookPost(EmbedJson("Buying bait", "x" . qty . " " . bait.name . "  -  $" . Fmt(cost), 0x60A5FA)
        , , , "buying", , true)
}

HookSelling(fishCount) {
    if !(HookReady() && Cfg.hkBuy)
        return
    HookPost(EmbedJson("Selling fish", Fmt(fishCount) . " fish in stock", 0x34D399), , , "selling", , true)
}

CatchShot() {
    r := SubRect(BotState.win, Regions.catchShot)
    path := TMP_DIR . "\catch_" . FormatTime(, "yyyyMMdd_HHmmss") . ".png"
    return PngSave(r.x, r.y, r.w, r.h, path) ? path : ""
}

; A fish was caught: progress (catches, sale countdown, bait, level) + optional screenshot.
HookCatch(shot := "") {
    if !(HookReady() && Cfg.hkCatch)
        return
    up := Max(1, Now() - BotStats.started)
    f := [["Catch", "#" . Fmt(BotStats.catches)]]
    if (Cfg.sellOn && Cfg.sellEvery > 0 && Cfg.npc != "Angler")
        f.Push(["Until next sale", BotState.sinceSell . " / " . Cfg.sellEvery])
    f.Push(["Bait left", BotState.bait >= 0 ? Fmt(BotState.bait) : "n/a"])
    f.Push(["Level", BotState.levelLast >= 0 ? BotState.levelLast . (BotStats.levels > 0 ? "  (+" . BotStats.levels . ")" : "") : "n/a"])
    f.Push(["Fish per hour", Round(BotStats.catches * 3600 / up, 1)])
    f.Push(["Chests", BotStats.chests])
    useShot := (shot != "" && FileExist(shot))
    HookPost(EmbedJson("Fish caught", "", 0x34D399, f, useShot ? "catch.png" : ""), useShot ? shot : ""
        , , "catch", "catch.png")
}

HookChest() {
    if !(HookReady() && Cfg.hkChest)
        return
    f := [["Chests this session", BotStats.chests], ["Fish caught", Fmt(BotStats.catches)]]
    HookPost(EmbedJson("Treasure chest collected", "A chest was grabbed during the reel minigame.", 0xFBBF24, f), , , "chest")
}

; Every N minutes while running (default 60).
HourlyTick() {
    if !(BotState.running && HookReady())
        return
    if (FormatTime(, "mm") != "00")
        return
    slot := FormatTime(, "yyyyMMddHH")
    if (slot == BotState.lastHourlySlot)
        return
    BotState.lastHourlySlot := slot
    BotState.reportDue := true
    LogMsg("[webhook] hourly report scheduled at " . FormatTime(, "HH:mm") . " (PC local time)")
}

; "done: catch a rare fish (12m 03s)" lines for the report, newest last.
QuestListText(maxN := 5) {
    out := ""
    n := Hour.qlog.Length
    from := Max(1, n - maxN + 1)
    i := from
    while (i <= n) {
        e := Hour.qlog[i]
        mark := (e.status == "done") ? "[done]" : (e.status == "failed") ? "[failed]" : "[ongoing]"
        out .= (out != "" ? "`n" : "") . mark . " " . e.label
        i++
    }
    if (from > 1)
        out := "(+" . (from - 1) . " earlier)`n" . out
    return out
}

SendHourly(*) {
    SyncSettings(false)
    if !HookUrlOk() {
        SetHookStatus("Enter a valid Discord webhook URL first.", true)
        return
    }
    h := Hour
    mins := Max(0.05, (Now() - h.started) / 60)
    net := h.income - h.spent
    f := [["Money generated", "$" . Fmt(h.income) . (h.unreadable ? "  (" . h.unreadable . " sale(s) unreadable)" : "")]
        , ["Bait bought", Fmt(h.baitBought) . "  ($" . Fmt(h.spent) . " spent)"]
        , ["Fish caught", Fmt(h.catches)]
        , ["Chests", h.chests]
        , ["Quests", h.questsAcc . " accepted  |  " . h.quests . " done  |  " . h.questsFail . " failed"]
        , ["Net profit", (net < 0 ? "-$" : "$") . Fmt(Abs(net))]
        , ["Casts / escapes", h.casts . " / " . h.escapes]
        , ["Levels gained", "+" . h.levels . "   (" . LevelText() . " this session)"]
        , ["Fish per hour", Round(h.catches * 60 / mins, 1)]
        , ["Session total", "$" . Fmt(BotStats.income) . " earned  |  " . Fmt(BotStats.catches)
            . " fish  |  " . FmtDur(Now() - BotStats.started) . " running", false]]
    ql := QuestListText(5)
    if (ql != "")
        f.Push(["Quests this hour", ql, false])
    cmp := CompareLine()
    if (cmp != "")
        f.Push(["Vs previous hour (per hour)", cmp, false])
    card := ReportCard("hour")
    if (card != "") {
        desc := "Last " . Round(mins) . " min  |  +$" . Fmt(h.income) . "  |  " . LvlGain(h.levels)
            . " levels  |  " . Fmt(h.catches) . " fish"
        if (cmp != "")
            desc .= "`nVs previous hour: " . cmp
        HookPost(EmbedJson("Hourly Report", desc, 0x6C8CFF, "", "report.png"), card, , "hourly report"
            , "report.png", false, HourlyUrl())
        LogMsg("[webhook] hourly report sent (card)")
        SavePrevHour()
        ResetHour()
        return
    }
    LogMsg("[webhook] hourly report: the image card could not be drawn - sending the text version instead (see the [card] line above)")
    shot := ""
    if (Cfg.hkShot && BotState.running) {                ; the $ + level block, bottom-left
        r := SubRect(BotState.win, Regions.hud)
        sp := TMP_DIR . "\hud_" . FormatTime(, "yyyyMMdd_HHmmss") . ".png"
        if PngSave(r.x, r.y, r.w, r.h, sp)
            shot := sp
    }
    HookPost(EmbedJson("Hourly Report", "Last " . Round(mins) . " min  |  " . Cfg.npc . "  |  "
        . CurBait().name, 0x6C8CFF, f, (shot != "") ? "hud.png" : ""), shot, , "hourly report", "hud.png", false, HourlyUrl())
    LogMsg("[webhook] hourly report sent")
    SavePrevHour()
    ResetHour()
}

; ---- hour-vs-previous-hour comparison ----------------------------------------
; Remember the window that was just reported, so the next report can compare against it.
; Windows shorter than 5 minutes are not a fair baseline and are ignored.
SavePrevHour() {
    secs := Max(3, Now() - Hour.started)
    PrevHour.valid := (secs >= 300)
    PrevHour.secs := secs
    PrevHour.catches := Hour.catches
    PrevHour.income := Hour.income
    PrevHour.levels := Hour.levels
}

; Counters of a window -> per-hour rates.
Rates(catches, income, levels, secs) {
    k := 3600 / Max(60, secs)
    return {fish: catches * k, money: income * k, lvl: levels * k}
}

; Change of cur against prev: text + ARGB colour.
DeltaInfo(cur, prev) {
    green := 0xFF4ADE80
    red := 0xFFF87171
    grey := 0xFF9A9AA4
    if (prev <= 0)
        return {txt: (cur > 0) ? "▲ new" : "=", col: (cur > 0) ? green : grey}
    pct := (cur - prev) / prev * 100
    if (Abs(pct) < 0.5)
        return {txt: "= same", col: grey}
    return {txt: (pct > 0 ? "▲ +" : "▼ ") . Round(pct) . "%", col: (pct > 0) ? green : red}
}

; One line for the text embed, or "" when there is no previous hour yet.
CompareLine() {
    if !PrevHour.valid
        return ""
    cur := Rates(Hour.catches, Hour.income, Hour.levels, Max(3, Now() - Hour.started))
    prv := Rates(PrevHour.catches, PrevHour.income, PrevHour.levels, PrevHour.secs)
    return "fish " . DeltaInfo(cur.fish, prv.fish).txt . "  |  money " . DeltaInfo(cur.money, prv.money).txt
        . "  |  levels " . DeltaInfo(cur.lvl, prv.lvl).txt
}

HookTest(*) {
    SyncSettings(false)
    if !HookUrlOk() {
        SetHookStatus("That is not a Discord webhook URL (https://discord.com/api/webhooks/...).", true)
        return
    }
    f := [["Theme", Cfg.theme], ["NPC", Cfg.npc], ["Bait", CurBait().name]]
    if HookPost(EmbedJson("Webhook connected", "Test message from CeriFish.", 0x4ADE80, f)
            , , , "test message")
        SetHookStatus("Test sent - waiting for Discord...")
    if (UrlIsHook(Cfg.hkUrlHourly) && Cfg.hkUrlHourly != Cfg.hkUrl)
        HookPost(EmbedJson("Hourly channel connected", "Hourly reports will be posted here.", 0x6C8CFF, f)
            , , , "hourly test", , false, Cfg.hkUrlHourly)
}
