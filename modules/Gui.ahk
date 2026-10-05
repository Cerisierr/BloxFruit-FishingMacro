; ============================================================================
;  THEMES
; ============================================================================
THEME_ORDER := ["Obsidian", "Midnight", "Ocean", "Emerald", "Sunset", "Rose", "Daylight"]
THEMES := Map(
    "Midnight", {bg: "071321", side: "06101D", card: "0D1C2D", inp: "0A1928", txt: "F0F5FC", muted: "A5B4C8"
               , accent: "3297F5", onAccent: "FFFFFF", good: "55D98A", bad: "F87171", line: "25384D", dark: true}
  , "Obsidian", {bg: "141414", side: "0C0C0C", card: "1D1D1D", inp: "262626", txt: "EDEDED", muted: "9A9A9A"
               , accent: "B388FF", onAccent: "150A25", good: "4ADE80", bad: "F87171", line: "333333", dark: true}
  , "Ocean",    {bg: "0B1B26", side: "07131B", card: "102A39", inp: "163547", txt: "E3F4FA", muted: "7FA7B8"
               , accent: "22D3EE", onAccent: "04202A", good: "4ADE80", bad: "FB7185", line: "1E4258", dark: true}
  , "Emerald",  {bg: "0D1A14", side: "08120E", card: "12261C", inp: "193327", txt: "E4F6EC", muted: "84AA95"
               , accent: "34D399", onAccent: "04200F", good: "86EFAC", bad: "F87171", line: "21402F", dark: true}
  , "Sunset",   {bg: "1A1214", side: "120B0D", card: "251A1D", inp: "2F2024", txt: "F8EAE4", muted: "B49A94"
               , accent: "FB923C", onAccent: "2A1204", good: "4ADE80", bad: "F87171", line: "42292E", dark: true}
  , "Rose",     {bg: "1B1020", side: "130A18", card: "261630", inp: "321D3E", txt: "F7E9F8", muted: "B195B8"
               , accent: "F472B6", onAccent: "2A0A1C", good: "4ADE80", bad: "FB7185", line: "43284F", dark: true}
  , "Daylight", {bg: "F3F5FA", side: "E3E8F2", card: "FFFFFF", inp: "FFFFFF", txt: "1B2033", muted: "5F6786"
               , accent: "3B6EF5", onAccent: "FFFFFF", good: "16A34A", bad: "DC2626", line: "CDD3E4", dark: false})

; ============================================================================
;  STATUS LINE / STATS
; ============================================================================
SetStatus(text := "") {
    run := BotState.running
    try {
        Ui.sbDot.Text := run ? "●  Running" : "●  Idle"
        Ui.sbDot.SetFont("c" . (run ? Ui.th.good : Ui.th.muted))
    }
    try ApplyRunVis()
    UpdateStats()
}

; What the macro believes, so a wrong setting is visible at a glance.
UpdateStats() {
    try {
        up := BotState.running ? (Now() - BotStats.started) : BotStats.lastUp
        if BotState.running
            BotStats.lastUp := up
        Ui.tCatch.Text := Fmt(BotStats.catches)
        Ui.tBait.Text := (BotState.bait >= 0) ? Fmt(BotState.bait) : "n/a"
        Ui.tIncome.Text := "$" . Fmt(BotStats.income)
        Ui.tUp.Text := FmtDur(up)
        Ui.tLevel.Text := (BotState.levelLast >= 0) ? String(BotState.levelLast) : "n/a"
        Ui.tLevelLbl.Text := (BotStats.levels > 0) ? "Level  (+" . BotStats.levels . ")" : "Level"
        t := "Casts " . BotStats.casts . "   |   Escapes " . BotStats.escapes
            . "   |   Spent $" . Fmt(BotStats.spent)
        if (BotState.running && QuestOn())
            t .= "   |   " . QuestShort() . (BotStats.quests > 0 ? "  (" . BotStats.quests . " done)" : "")
        if (Cfg.sellOn && Cfg.sellEvery > 0 && Cfg.npc != "Angler")
            t .= "   |   Sale in " . Max(0, Cfg.sellEvery - BotState.sinceSell)
        if (BotState.running && HookReady())
            t .= "   |   Hourly report at " . FormatTime(DateAdd(A_Now, 1, "Hours"), "HH:00")
        Ui.info.Text := t
        try Ui.questStatus.Text := !BotState.running ? "Macro not running."
            : QuestOn() ? QuestShort() . (BotStats.quests > 0 ? "   (" . BotStats.quests . " done this session)" : "")
            : "Auto-quest is off or not at the Angler."
    }
    try HtmlSync()
}

CheckSetup(*) {
    SyncSettings()
    name := ApplyResolution()
    win := RefreshGame()
    LogMsg("---- setup check ----")
    LogMsg("Administrator: " . (A_IsAdmin ? "yes" : "NO - input to Roblox will be dropped"))
    LogMsg("Screen: " . A_ScreenWidth . "x" . A_ScreenHeight . " | profile: " . name
        . " (" . BotState.resW . "x" . BotState.resH . ")")
    LogMsg("NPC: " . Cfg.npc . " | bait: " . CurBait().name . " x" . Cfg.baitPer
        . " | webhook: " . (HookReady() ? "ready" : (Cfg.hkOn ? "URL invalid" : "off")))
    LogMsg("curl.exe: " . (FileExist(A_WinDir . "\System32\curl.exe") ? "found" : "MISSING (webhook disabled)"))
    if WinExist(ROBLOX_WIN) {
        LogMsg("Roblox game area: " . win.w . "x" . win.h . " at " . win.x . "," . win.y)
        promptVisible := NpcLabelVisible()
        LogMsg(promptVisible ? "NPC position: Interact prompt visible (in range)." : "NPC position: Interact prompt not visible; move onto the lower white circle below the green marker.")
        if CheckResolution()
            LogMsg("Resolution matches the selected profile.")
        FindBarReport()
    } else {
        LogMsg("Roblox window NOT found.")
    }
}

FindBarReport() {
    geo := FindBar()
    LogMsg(geo ? "Reel bar visible: track " . geo.tw . " px" : "Reel bar: not on screen (normal when idle)")
}

; ============================================================================
;  GUI HELPERS
; ============================================================================
Reg(page, ctrl) {
    if (page != "")
        Ui.pages[page].Push(ctrl)
    return ctrl
}

Box(g, page, x, y, w, h, color) {
    return Reg(page, g.Add("Text", Format("x{} y{} w{} h{} Background{}", x, y, w, h, color)))
}

Lbl(g, page, x, y, w, txt, color := "", size := 9, weight := 400, h := 0) {
    if (h <= 0)
        h := Round(size * 2.1) + 2                       ; big fonts need a tall box or they get clipped
    opt := Format("x{} y{} w{} h{}", x, y, w, h)
    c := g.Add("Text", opt, txt)
    c.SetFont(Format("s{} w{} c{}", size, weight, (color != "") ? color : Ui.th.txt), "Segoe UI")
    return Reg(page, c)
}

Section(g, page, x, y, txt) {
    Box(g, page, x, y + 2, 3, 16, Ui.th.accent)
    return Lbl(g, page, x + 12, y, 400, txt, Ui.th.accent, 9, 700)
}

Panel(g, page, x, y, w, h) {
    th := Ui.th
    Box(g, page, x, y, w, h, th.line)
    return Box(g, page, x + 1, y + 1, w - 2, h - 2, th.card)
}

HomeCard(g, x, y, title, detail, target) {
    th := Ui.th
    Panel(g, "dash", x, y, 288, 112)
    Box(g, "dash", x + 14, y + 13, 34, 34, th.inp)
    Lbl(g, "dash", x + 14, y + 13, 34, SubStr(title, 1, 1), th.accent, 12, 700, 32)
    Lbl(g, "dash", x + 58, y + 12, 218, title, th.txt, 11, 700)
    Lbl(g, "dash", x + 58, y + 38, 218, detail, th.muted, 9, 400, 34)
    Btn(g, "dash", x + 16, y + 76, 118, 25, "Configure", NavHandler(target), "ghost")
}

Btn(g, page, x, y, w, h, txt, cb, kind := "primary") {
    th := Ui.th
    bg := (kind == "primary") ? th.accent : (kind == "danger") ? th.bad : th.inp
    fg := (kind == "ghost") ? th.txt : th.onAccent
    c := g.Add("Text", Format("x{} y{} w{} h{} Center +0x200 Background{}", x, y, w, h, bg), txt)
    c.SetFont("s10 w600 c" . fg, "Segoe UI")
    c.OnEvent("Click", cb)
    return Reg(page, c)
}

AddEdit(g, page, key, x, y, w, val, numeric := false, mask := false) {
    th := Ui.th
    Box(g, page, x, y, w, 24, th.line)
    opt := Format("x{} y{} w{} h20 -E0x200 Background{} c{}", x + 1, y + 2, w - 2, th.inp, th.txt)
    if numeric
        opt .= " Number"
    e := g.Add("Edit", opt, val)
    e.SetFont("s10", "Segoe UI")
    SendMessage(0x00D3, 3, 6 | (6 << 16), e)                 ; EM_SETMARGINS left/right
    if mask
        SendMessage(0x00CC, 0x25CF, 0, e)                    ; EM_SETPASSWORDCHAR
    e.OnEvent("Change", OnUiChange)
    Ui.%key% := e
    return Reg(page, e)
}

AddDdl(g, page, key, x, y, w, items, choose) {
    th := Ui.th
    d := g.Add("DropDownList", Format("x{} y{} w{} Choose{} Background{} c{}", x, y, w, choose, th.inp, th.txt), items)
    d.SetFont("s10", "Segoe UI")
    if th.dark {
        try DllCall("uxtheme\SetWindowTheme", "ptr", d.Hwnd, "str", "DarkMode_CFD", "str", "")
    }
    d.OnEvent("Change", OnUiChange)
    Ui.%key% := d
    return Reg(page, d)
}

; A switch: two stacked labels (ON / OFF), only one visible at a time.
AddToggle(g, page, key, x, y, label, val, w := 220) {
    th := Ui.th
    on := g.Add("Text", Format("x{} y{} w46 h22 Center +0x200 Background{}", x, y, th.accent), "ON")
    on.SetFont("s8 w700 c" . th.onAccent, "Segoe UI")
    off := g.Add("Text", Format("x{} y{} w46 h22 Center +0x200 Background{}", x, y, th.line), "OFF")
    off.SetFont("s8 w700 c" . th.muted, "Segoe UI")
    t := g.Add("Text", Format("x{} y{} w{} h22 +0x200", x + 58, y, w), label)
    t.SetFont("s10 c" . th.txt, "Segoe UI")
    h := FlipHandler(key)
    on.OnEvent("Click", h)
    off.OnEvent("Click", h)
    t.OnEvent("Click", h)
    Reg(page, on)
    Reg(page, off)
    Reg(page, t)
    Ui.tog[key] := val ? true : false
    Ui.togCtl[key] := [on, off]
    Ui.togPage[key] := page
}

FlipHandler(key) {
    return (*) => FlipToggle(key)
}

FlipToggle(key) {
    SetToggle(key, !Ui.tog[key])
    OnUiChange()
}

SetToggle(key, v) {
    v := v ? true : false
    Ui.tog[key] := v
    if (!Ui.htmlMode && Ui.page == Ui.togPage[key]) {
        p := Ui.togCtl[key]
        p[1].Visible := v
        p[2].Visible := !v
    }
}

NavHandler(pg) {
    return (*) => ShowPage(pg)
}

; The visible interface is HTML hosted by the built-in WebBrowser ActiveX
; control. The existing AHK controls remain the settings model so all macro
; behavior, validation and INI persistence continue to use the same code.
class HtmlBrowserEvents {
    BeforeNavigate2(pDisp, &URL, &Flags, &TargetFrameName, &PostData, &Headers, &Cancel, ComObj) {
        address := String(URL)
        if InStr(address, "https://ahk.local/") {
            Cancel := true
            HtmlCommand(address)
        }
    }
}

HtmlDecode(value) {
    s := StrReplace(value, "+", " ")
    out := ""
    i := 1
    while i <= StrLen(s) {
        if (SubStr(s, i, 1) == "%" && RegExMatch(SubStr(s, i), "^%[0-9A-Fa-f]{2}", &m)) {
            out .= Chr(Integer("0x" . SubStr(m[0], 2, 2)))
            i += 3
        } else {
            out .= SubStr(s, i, 1)
            i += 1
        }
    }
    return out
}

HtmlCommand(address) {
    global Ui, Cfg
    query := Map()
    if !InStr(address, "?")
        return
    for pair in StrSplit(SubStr(address, InStr(address, "?") + 1), "&") {
        bits := StrSplit(pair, "=")
        if (bits.Length >= 2)
            query[HtmlDecode(bits[1])] := HtmlDecode(bits[2])
    }
    cmd := query.Has("do") ? query["do"] : ""
    if (cmd == "page") {
        ShowPage(query.Has("name") ? query["name"] : "dash")
    } else if (cmd == "toggle") {
        key := query.Has("key") ? query["key"] : ""
        if Ui.tog.Has(key) {
            SetToggle(key, !Ui.tog[key])
            OnUiChange()
        }
    } else if (cmd == "set") {
        key := query.Has("key") ? query["key"] : ""
        value := query.Has("value") ? query["value"] : ""
        try {
            if (key == "bait")
                Ui.bait.Choose(Integer(value))
            else if (key == "npc")
                Ui.npc.Choose(value)
            else if (key == "res")
                Ui.res.Choose(value)
            else if (key == "rod")
                Ui.rod.Choose(value)
            else if (key == "questKey")
                Ui.questKey.Choose(value)
            else if (key == "baitPer")
                Ui.baitPer.Choose(value)
            else if Ui.HasOwnProp(key)
                Ui.%key%.Value := value
            OnUiChange()
        }
    } else if (cmd == "start") {
        ToggleRun()
    } else if (cmd == "pause") {
        TogglePause()
    } else if (cmd == "check") {
        CheckSetup()
    } else if (cmd == "update") {
        CheckForUpdates(true)
    } else if (cmd == "test") {
        HookTest()
    } else if (cmd == "report") {
        SendHourly()
    } else if (cmd == "quit") {
        ExitApp()
    } else if (cmd == "theme") {
        ChangeTheme(query.Has("name") ? query["name"] : Cfg.theme)
    }
    HtmlSync(true)
}

HtmlField(doc, id, value) {
    try {
        element := doc.getElementById(id)
        target := String(value)
        if (element.tagName == "SELECT") {
            found := false
            Loop element.options.length {
                index := A_Index - 1
                option := element.options.item(index)
                if (String(option.value) == target || Trim(String(option.innerText)) == target) {
                    element.selectedIndex := index
                    found := true
                    break
                }
            }
            ; Never leave a dropdown visually empty when a saved value is stale.
            if !found && element.options.length
                element.selectedIndex := 0
        } else if (String(element.value) != target) {
            element.value := target
        }
    }
}

HtmlFileURL(path) {
    url := StrReplace(path, "\", "/")
    url := StrReplace(url, " ", "%20")
    return "file:///" . url
}
HtmlSync(syncFields := false) {
    global Ui, BotState, BotStats, BAITS, Cfg, APP_VERSION, THEME_ORDER, THEMES
    try {
        doc := Ui.browser.Document
        accent := "#" . THEMES[Cfg.theme].accent
        accentText := "#" . THEMES[Cfg.theme].onAccent
        palette := THEMES[Cfg.theme]
        doc.getElementById("runstatus").innerText := BotState.running ? (BotState.paused ? "Paused" : "Running") : "Idle"
        doc.getElementById("footstatus").innerText := BotState.running ? (BotState.paused ? "Paused" : "Running") : "Idle"
        doc.getElementById("runbtn").innerText := BotState.running ? "■ Stop macro" : "▶ Start macro"
        doc.getElementById("catch").innerText := Fmt(BotStats.catches)
        doc.getElementById("baitstat").innerText := (BotState.bait >= 0) ? Fmt(BotState.bait) : "n/a"
        doc.getElementById("income").innerText := "$" . Fmt(BotStats.income)
        up := BotState.running ? (Now() - BotStats.started) : BotStats.lastUp
        doc.getElementById("uptime").innerText := FmtDur(up)
        doc.getElementById("sessioninfo").innerText := Ui.info.Text
        doc.getElementById("queststatus").innerText := Ui.questStatus.Text
        npcWarn := doc.getElementById("npcwarning")
        npcWarn.style.display := (Cfg.npc == "Angler") ? "block" : "none"
        if (Cfg.npc == "Angler")
            npcWarn.innerText := "Auto-sell only works with the Fisherman. It is unavailable while Angler is selected."
        doc.getElementById("log").innerText := BotState.logBuf
        doc.querySelector(".brand small").style.color := accent
        callouts := doc.querySelectorAll(".callout")
        Loop callouts.length {
            callout := callouts.item(A_Index - 1)
            callout.style.backgroundColor := "#" . palette.card
            callout.style.borderColor := "#" . palette.line
            callout.style.color := "#" . palette.muted
        }
        calloutHeads := doc.querySelectorAll(".callout b")
        Loop calloutHeads.length
            calloutHeads.item(A_Index - 1).style.color := accent
        for key, value in Ui.tog {
            toggle := doc.getElementById("toggle-" . key)
            toggle.className := "switch" . (value ? " on" : "")
            toggle.style.backgroundColor := value ? accent : ""
        }
        buttons := doc.getElementsByTagName("button")
        Loop buttons.length {
            button := buttons.item(A_Index - 1)
            classes := " " . button.className . " "
            if InStr(classes, " btn ") {
                button.style.backgroundColor := accent
                button.style.color := accentText
                button.style.borderColor := accent
            }
            if InStr(classes, " active ") {
                button.style.backgroundColor := accent
                button.style.borderColor := accent
            }
            if InStr(classes, " selected ") {
                button.style.borderColor := accent
                button.style.boxShadow := "0 0 0 2px " . accent
            }
        }
        navButtons := doc.querySelectorAll(".nav button")
        Loop navButtons.length {
            navButton := navButtons.item(A_Index - 1)
            if (navButton.className == "active") {
                navButton.style.backgroundColor := accent
                navButton.style.color := accentText
                navButton.style.borderColor := accent
                navButton.style.boxShadow := "inset 3px 0 " . accent
            } else if (navButton.getAttribute("data-hover") == "1") {
                navButton.style.backgroundColor := accent
                navButton.style.color := accentText
            } else {
                navButton.style.backgroundColor := ""
                navButton.style.color := ""
                navButton.style.borderColor := ""
                navButton.style.boxShadow := ""
            }
        }
        doc.getElementById("version").innerText := APP_VERSION
        doc.getElementById("version-footer").innerText := APP_VERSION
        doc.body.setAttribute("data-theme", Cfg.theme)
        doc.body.setAttribute("data-accent", accent)
        doc.body.setAttribute("data-accent-text", accentText)
        baitSelect := doc.getElementById("bait")
        if (baitSelect.options.length == 0) {
            for i, bait in BAITS {
                option := doc.createElement("option")
                option.value := i
                option.text := BaitLabel(bait)
                baitSelect.options.add(option)
            }
        }
        HtmlField(doc, "bait", IdxOf(BAITS, CurBait(), 1))
        if syncFields {
            for key in ["perfectPct", "zoomOut", "zoomEvery", "tiltPx", "dockWalk", "baitNow", "sellEvery"]
                HtmlField(doc, key, Cfg.%key%)
            for key in ["hkUrl", "hkUrlHourly", "hkName", "hkMention"]
                HtmlField(doc, key, Cfg.%key%)
            HtmlField(doc, "npc", Cfg.npc)
            HtmlField(doc, "res", Cfg.resolution)
            HtmlField(doc, "rod", Cfg.rodSlot)
            HtmlField(doc, "baitPer", Cfg.baitPer)
            HtmlField(doc, "questKey", Cfg.questKey)
        }
        for name in THEME_ORDER {
            theme := doc.getElementById("theme-" . name)
            theme.className := "theme" . (name == Cfg.theme ? " selected" : "")
            if (name == Cfg.theme) {
                theme.style.borderColor := accent
                theme.style.boxShadow := "0 0 0 2px " . accent
            } else {
                theme.style.borderColor := ""
                theme.style.boxShadow := ""
            }
        }
    }
}

ThemeHandler(name) {
    return (*) => ChangeTheme(name)
}

ShowPage(name) {
    Ui.page := name
    if !Ui.htmlMode {
        for pg, list in Ui.pages {
            vis := (pg == name)
            for c in list
                c.Visible := vis
        }
        for key, v in Ui.tog {
            if (Ui.togPage[key] == name) {
                p := Ui.togCtl[key]
                p[1].Visible := v
                p[2].Visible := !v
            }
        }
        for pg, trio in Ui.nav {
            selected := (pg == name)
            trio[1].Visible := !selected
            trio[2].Visible := selected
            trio[3].Visible := selected
        }
    }
    ApplyRunVis()
}

ApplyRunVis() {
    if Ui.htmlMode
        return
    run := BotState.running
    Ui.btnStart.Visible := !run
    Ui.btnStop.Visible := run
    Ui.btnPause.Visible := run
    Ui.btnCheck.Visible := !run
    Ui.btnUpdate.Visible := !run
}

VersionIsNewer(remoteVersion, installedVersion) {
    remoteParts := StrSplit(remoteVersion, ".")
    installedParts := StrSplit(installedVersion, ".")
    Loop Max(remoteParts.Length, installedParts.Length) {
        remotePart := (A_Index <= remoteParts.Length) ? Integer(remoteParts[A_Index]) : 0
        installedPart := (A_Index <= installedParts.Length) ? Integer(installedParts[A_Index]) : 0
        if (remotePart != installedPart)
            return remotePart > installedPart
    }
    return false
}

CheckForUpdates(manual := false, *) {
    global UPDATE_MODULES, UPDATE_MODULE_URL
    if BotState.running {
        if manual
            MsgBox("Stop the macro before installing an update.", APP_NAME, "Icon!")
        return
    }
    try {
        request := ComObject("WinHttp.WinHttpRequest.5.1")
        request.Open("GET", UPDATE_URL, false)
        request.SetTimeouts(4000, 4000, 6000, 6000)
        request.SetRequestHeader("User-Agent", "Blox-Fruits-Fishing-Macro")
        request.Send()
        if (request.Status != 200)
            throw Error("GitHub returned HTTP " . request.Status)
        latest := request.ResponseText
        if (StrLen(latest) < 5000 || !InStr(latest, '#Include "modules\Input.ahk"'))
            throw Error("GitHub returned an incomplete macro file")
        htmlRequest := ComObject("WinHttp.WinHttpRequest.5.1")
        htmlRequest.Open("GET", UPDATE_HTML_URL, false)
        htmlRequest.SetTimeouts(4000, 4000, 6000, 6000)
        htmlRequest.SetRequestHeader("User-Agent", "Blox-Fruits-Fishing-Macro")
        htmlRequest.Send()
        if (htmlRequest.Status != 200)
            throw Error("GitHub could not provide BloxFishing.html (HTTP " . htmlRequest.Status . ")")
        latestHtml := htmlRequest.ResponseText
        if (StrLen(latestHtml) < 5000 || !InStr(latestHtml, 'id="page-dash"'))
            throw Error("GitHub returned an incomplete BloxFishing.html")
        logoRequest := ComObject("WinHttp.WinHttpRequest.5.1")
        logoRequest.Open("GET", UPDATE_LOGO_URL, false)
        logoRequest.SetTimeouts(4000, 4000, 6000, 6000)
        logoRequest.SetRequestHeader("User-Agent", "CeriFish")
        logoRequest.Send()
        if (logoRequest.Status != 200)
            throw Error("GitHub could not provide the CeriFish logo (HTTP " . logoRequest.Status . ")")
        latestLogo := logoRequest.ResponseBody
        iconRequest := ComObject("WinHttp.WinHttpRequest.5.1")
        iconRequest.Open("GET", UPDATE_ICON_URL, false)
        iconRequest.SetTimeouts(4000, 4000, 6000, 6000)
        iconRequest.SetRequestHeader("User-Agent", "CeriFish")
        iconRequest.Send()
        if (iconRequest.Status != 200)
            throw Error("GitHub could not provide the CeriFish window icon (HTTP " . iconRequest.Status . ")")
        latestIcon := iconRequest.ResponseBody
        if !RegExMatch(latest, 'APP_VERSION\s*:=\s*"([0-9.]+)"', &match)
            throw Error("Could not read the version from GitHub")
        remoteVersion := match[1]
        if !VersionIsNewer(remoteVersion, APP_VERSION) {
            if manual
                MsgBox("You already have the latest version (" . APP_VERSION . ").", APP_NAME)
            return
        }
        answer := MsgBox("Version " . remoteVersion . " is available (you have " . APP_VERSION
            . "). Install it and restart the macro now?", APP_NAME, "YesNo")
        if (answer != "Yes")
            return
        latestModules := Map()
        for moduleName in UPDATE_MODULES {
            moduleRequest := ComObject("WinHttp.WinHttpRequest.5.1")
            moduleRequest.Open("GET", UPDATE_MODULE_URL . moduleName, false)
            moduleRequest.SetTimeouts(4000, 4000, 6000, 6000)
            moduleRequest.SetRequestHeader("User-Agent", "CeriFish")
            moduleRequest.Send()
            if (moduleRequest.Status != 200)
                throw Error("GitHub could not provide module " . moduleName . " (HTTP " . moduleRequest.Status . ")")
            moduleText := moduleRequest.ResponseText
            if (StrLen(moduleText) < 500)
                throw Error("GitHub returned an incomplete " . moduleName)
            latestModules[moduleName] := moduleText
        }
        InstallUpdate(latest, latestHtml, latestLogo, latestIcon, latestModules, remoteVersion)
    } catch as err {
        if manual
            MsgBox("Could not check GitHub for updates.`n`n" . err.Message, APP_NAME, "Icon!")
    }
}

InstallUpdate(source, htmlSource, logoSource, iconSource, moduleSources, version) {
    target := A_ScriptFullPath
    htmlTarget := A_ScriptDir . "\BloxFishing.html"
    temp := A_Temp . "\BloxFishing-update-" . version . ".ahk"
    htmlTemp := A_Temp . "\BloxFishing-update-" . version . ".html"
    logoTarget := A_ScriptDir . "\images\cerifish-mark.png"
    iconTarget := A_ScriptDir . "\images\cerifish.ico"
    logoTemp := A_Temp . "\CeriFish-logo-update-" . version . ".png"
    iconTemp := A_Temp . "\CeriFish-icon-update-" . version . ".ico"
    moduleTempDir := A_Temp . "\CeriFish-modules-update-" . version
    moduleTemps := Map()
    moduleTargets := Map()
    moduleBackups := Map()
    moduleInstalled := []
    backup := target . ".bak"
    htmlBackup := htmlTarget . ".bak"
    htmlBackedUp := false
    htmlInstalled := false
    logoBackedUp := false
    logoInstalled := false
    iconBackedUp := false
    iconInstalled := false
    try {
        if FileExist(temp)
            FileDelete(temp)
        if FileExist(htmlTemp)
            FileDelete(htmlTemp)
        if FileExist(logoTemp)
            FileDelete(logoTemp)
        if FileExist(iconTemp)
            FileDelete(iconTemp)
        DirCreate(moduleTempDir)
        FileAppend(source, temp, "UTF-8-RAW")
        FileAppend(htmlSource, htmlTemp, "UTF-8-RAW")
        WriteBinaryFile(logoTemp, logoSource)
        WriteBinaryFile(iconTemp, iconSource)
        for moduleName, moduleText in moduleSources {
            moduleTemp := moduleTempDir . "\" . moduleName
            if FileExist(moduleTemp)
                FileDelete(moduleTemp)
            moduleTemps[moduleName] := moduleTemp
            FileAppend(moduleText, moduleTemp, "UTF-8-RAW")
            if (FileGetSize(moduleTemp) < 500)
                throw Error("The downloaded " . moduleName . " is incomplete")
            moduleTargets[moduleName] := A_ScriptDir . "\modules\" . moduleName
            backupModule := moduleTargets[moduleName] . ".bak"
            if FileExist(moduleTargets[moduleName]) {
                FileCopy(moduleTargets[moduleName], backupModule, true)
                moduleBackups[moduleName] := true
            } else {
                moduleBackups[moduleName] := false
            }
        }
        if (FileGetSize(temp) < 5000)
            throw Error("The downloaded file is incomplete")
        if (FileGetSize(htmlTemp) < 5000)
            throw Error("The downloaded interface file is incomplete")
        if (FileGetSize(logoTemp) < 1000 || FileGetSize(iconTemp) < 1000)
            throw Error("The downloaded logo files are incomplete")
        try {
            Ui.browser.Navigate("about:blank")
            while (Ui.browser.ReadyState != 4)
                Sleep(10)
        }
        if FileExist(htmlTarget) {
            FileCopy(htmlTarget, htmlBackup, true)
            htmlBackedUp := true
        }
        if FileExist(logoTarget) {
            FileCopy(logoTarget, logoTarget . ".bak", true)
            logoBackedUp := true
        }
        if FileExist(iconTarget) {
            FileCopy(iconTarget, iconTarget . ".bak", true)
            iconBackedUp := true
        }
        DirCreate(A_ScriptDir . "\images")
        DirCreate(A_ScriptDir . "\modules")
        FileCopy(target, backup, true)
        for moduleName, moduleTemp in moduleTemps {
            moduleInstalled.Push(moduleName)
            FileCopy(moduleTemp, moduleTargets[moduleName], true)
        }
        FileMove(htmlTemp, htmlTarget, true)
        htmlInstalled := true
        FileMove(logoTemp, logoTarget, true)
        logoInstalled := true
        FileMove(iconTemp, iconTarget, true)
        iconInstalled := true
        for moduleName, moduleTemp in moduleTemps {
            try FileDelete(moduleTemp)
        }
        try DirDelete(moduleTempDir)
        FileMove(temp, target, true)
        Run('"' . A_AhkPath . '" "' . target . '"')
        ExitApp()
    } catch as err {
        for moduleName in moduleInstalled {
            moduleTarget := moduleTargets[moduleName]
            if moduleBackups[moduleName] {
                try {
                    FileCopy(moduleTarget . ".bak", moduleTarget, true)
                }
            } else if FileExist(moduleTarget) {
                try {
                    FileDelete(moduleTarget)
                }
            }
        }
        if htmlBackedUp {
            try FileCopy(htmlBackup, htmlTarget, true)
        } else if htmlInstalled {
            try {
                if FileExist(htmlTarget)
                    FileDelete(htmlTarget)
            }
        }
        if logoBackedUp {
            try FileCopy(logoTarget . ".bak", logoTarget, true)
        } else if logoInstalled {
            try FileDelete(logoTarget)
        }
        if iconBackedUp {
            try FileCopy(iconTarget . ".bak", iconTarget, true)
        } else if iconInstalled {
            try FileDelete(iconTarget)
        }
        try {
            if FileExist(temp)
                FileDelete(temp)
        }
        try {
            if FileExist(htmlTemp)
                FileDelete(htmlTemp)
        }
        try {
            if FileExist(logoTemp)
                FileDelete(logoTemp)
        }
        try {
            if FileExist(iconTemp)
                FileDelete(iconTemp)
        }
        for moduleName, moduleTemp in moduleTemps {
            try {
                if FileExist(moduleTemp)
                    FileDelete(moduleTemp)
            }
        }
        try DirDelete(moduleTempDir)
        try {
            Ui.browser.Navigate(HtmlFileURL(htmlTarget))
        }
        MsgBox("The update was downloaded but could not be installed.`nYour current macro is unchanged.`n`n"
            . err.Message, APP_NAME, "Icon!")
    }
}

WriteBinaryFile(path, bytes) {
    stream := ComObject("ADODB.Stream")
    stream.Type := 1
    stream.Open()
    stream.Write(bytes)
    stream.SaveToFile(path, 2)
    stream.Close()
}

ChangeTheme(name) {
    if (name == Cfg.theme)
        return
    SyncSettings(false)
    Cfg.theme := name
    SaveSettings()
    SetTimer(RebuildGui.Bind(Ui.page), -10)
}

RebuildGui(page) {
    try Ui.gui.Destroy()
    BuildGui(page)
}

ToggleUrlMask(*) {
    Ui.urlShown := !Ui.urlShown
    for ctl in [Ui.hkUrl, Ui.hkUrlHourly] {
        SendMessage(0x00CC, Ui.urlShown ? 0 : 0x25CF, 0, ctl)
        DllCall("InvalidateRect", "ptr", ctl.Hwnd, "ptr", 0, "int", 1)
    }
    Ui.btnShow.Text := Ui.urlShown ? "Hide" : "Show"
}

IdxOf(arr, val, def := 1) {
    for i, v in arr {
        if (v == val)
            return i
    }
    return def
}

PageHeader(g, page, title, sub) {
    th := Ui.th
    Lbl(g, page, 214, 16, 590, title, th.txt, 18, 700)
    Lbl(g, page, 214, 60, 590, sub, th.muted, 9)
    Box(g, page, 214, 88, 590, 1, th.line)
}

Tile(g, x, y, w, label, key, lblKey := "") {
    th := Ui.th
    Box(g, "dash", x, y, w, 76, th.card)
    v := g.Add("Text", Format("x{} y{} w{} h34 Background{}", x + 12, y + 8, w - 16, th.card), "0")
    v.SetFont("s14 w700 c" . th.accent, "Segoe UI")
    Reg("dash", v)
    l := g.Add("Text", Format("x{} y{} w{} h20 Background{}", x + 12, y + 48, w - 16, th.card), label)
    l.SetFont("s8 c" . th.muted, "Segoe UI")
    Reg("dash", l)
    Ui.%key% := v
    if (lblKey != "")
        Ui.%lblKey% := l
}

ThemeCard(g, name, x, y) {
    th := Ui.th
    t := THEMES[name]
    sel := (name == Cfg.theme)
    h := ThemeHandler(name)
    Box(g, "look", x - 3, y - 3, 192, 90, sel ? th.accent : th.line)
    c := Box(g, "look", x, y, 186, 84, t.bg)
    c.OnEvent("Click", h)
    s := Box(g, "look", x, y, 38, 84, t.side)
    s.OnEvent("Click", h)
    Box(g, "look", x + 52, y + 14, 30, 10, t.accent)
    Box(g, "look", x + 88, y + 14, 30, 10, t.good)
    Box(g, "look", x + 124, y + 14, 30, 10, t.bad)
    n := g.Add("Text", Format("x{} y{} w{} h26 +0x200 Background{}", x + 52, y + 34, 128, t.bg)
        , name . (sel ? "   (active)" : ""))
    n.SetFont("s10 w600 c" . t.txt, "Segoe UI")
    n.OnEvent("Click", h)
    Reg("look", n)
    k := g.Add("Text", Format("x{} y{} w{} h18 Background{}", x + 52, y + 62, 128, t.bg), t.dark ? "Dark" : "Light")
    k.SetFont("s8 c" . t.muted, "Segoe UI")
    k.OnEvent("Click", h)
    Reg("look", k)
}

; ============================================================================
;  MAIN WINDOW
; ============================================================================
BuildGui(startPage := "dash") {
    global HTML_FILE
    MonitorGetWorkArea(1, &workLeft, &workTop, &workRight, &workBottom)
    workWidth := workRight - workLeft
    workHeight := workBottom - workTop
    windowWidth := Min(1160, Max(480, workWidth - 32))
    windowHeight := Min(758, Max(420, workHeight - 52))
    windowX := workLeft + Floor((workWidth - windowWidth) / 2)
    windowY := workTop + Floor((workHeight - windowHeight) / 2)
    if !FileExist(HTML_FILE) {
        MsgBox("The interface file is missing:`n" . HTML_FILE . "`n`nKeep BloxFishing.html next to BloxFishing.ahk.", APP_NAME, "Iconx")
        ExitApp()
    }
    th := THEMES.Has(Cfg.theme) ? THEMES[Cfg.theme] : THEMES["Obsidian"]
    Ui.th := th
    g := Gui("+MinimizeBox", APP_NAME . "  v" . APP_VERSION)
    g.BackColor := th.bg
    g.MarginX := 0
    g.MarginY := 0
    g.SetFont("s9 c" . th.txt, "Segoe UI")
    g.OnEvent("Close", (*) => ExitApp())
    Ui.gui := g
    Ui.htmlMode := false
    Ui.pages := Map()
    Ui.nav := Map()
    Ui.tog := Map()
    Ui.togCtl := Map()
    Ui.togPage := Map()
    Ui.urlShown := false
    Ui.switchingTab := false
    Ui.page := "dash"
    for pg in ["dash", "fish", "quest", "shop", "hook", "look", "logs"]
        Ui.pages[pg] := []

    ; ---- left navigation ---------------------------------------------------
    Panel(g, "", 0, 0, 210, 758)
    Box(g, "", 209, 0, 1, 704, th.line)
    Box(g, "", 18, 20, 36, 36, th.accent)
    Lbl(g, "", 18, 21, 36, "CF", th.onAccent, 12, 700, 32)
    Lbl(g, "", 64, 20, 132, "CeriFish", th.txt, 11, 700)
    Lbl(g, "", 64, 42, 132, "Fishing Macro", th.accent, 9, 600)
    Box(g, "", 16, 70, 178, 1, th.line)
    navDefs := [["dash", "Dashboard", "⌂"], ["fish", "Fishing", "⚓"], ["shop", "NPC + Bait", "▣"]
              , ["quest", "Quests", "✓"], ["hook", "Webhook", "✉"], ["look", "Appearance", "⚙"]
              , ["logs", "Logs", "≡"]]
    ny := 88
    for item in navDefs {
        normal := g.Add("Text", Format("x14 y{} w182 h38 +0x200 Background{}", ny, th.side)
            , "  " . item[3] . "    " . item[2])
        normal.SetFont("s10 c" . th.muted, "Segoe UI")
        normal.OnEvent("Click", NavHandler(item[1]))
        active := g.Add("Text", Format("x14 y{} w182 h38 +0x200 Background{}", ny, th.card)
            , "  " . item[3] . "    " . item[2])
        active.SetFont("s10 w600 c" . th.txt, "Segoe UI")
        active.OnEvent("Click", NavHandler(item[1]))
        marker := g.Add("Text", Format("x14 y{} w3 h38 Background{}", ny, th.accent))
        Ui.nav[item[1]] := [normal, active, marker]
        ny += 42
    }
    Panel(g, "", 12, 414, 184, 132)
    Lbl(g, "", 26, 428, 156, "MACRO STATUS", th.muted, 8, 700)
    Ui.sbDot := Lbl(g, "", 26, 450, 156, "●  Idle", th.muted, 10, 600)
    Lbl(g, "", 26, 480, 156, "GAME", th.muted, 8, 700)
    Lbl(g, "", 26, 498, 156, "Blox Fruits", th.txt, 9, 600)
    Box(g, "", 26, 520, 156, 1, th.line)
    Lbl(g, "", 26, 526, 156, "Version  " . APP_VERSION, th.muted, 8)


    ; ---- DASHBOARD ---------------------------------------------------------
    PageHeader(g, "dash", "CeriFish Control Panel", "Your fishing setup, session status and quick links.")
    Ui.btnStart := Btn(g, "", 14, 716, 86, 30, "Start (F2)", ToggleRun, "primary")
    Ui.btnStop := Btn(g, "", 14, 716, 86, 30, "Stop (F2)", ToggleRun, "danger")
    Ui.btnCheck := Btn(g, "", 106, 716, 98, 30, "Check setup", CheckSetup, "ghost")
    Ui.btnUpdate := Btn(g, "", 210, 716, 96, 30, "Updates", CheckForUpdates.Bind(true), "ghost")
    Ui.btnPause := Btn(g, "", 210, 716, 96, 30, "Pause (F3)", TogglePause, "primary")
    Tile(g, 214, 158, 96, "Fish caught", "tCatch")
    Tile(g, 320, 158, 96, "Bait left", "tBait")
    Tile(g, 426, 158, 150, "Money generated", "tIncome")
    Tile(g, 586, 158, 104, "Level", "tLevel", "tLevelLbl")
    Tile(g, 700, 158, 104, "Run time", "tUp")
    Panel(g, "dash", 213, 240, 592, 80)
    Box(g, "dash", 213, 240, 3, 80, th.accent)
    Lbl(g, "dash", 228, 247, 560, "BEFORE STARTING", th.accent, 9, 700)
    Lbl(g, "dash", 228, 266, 560, "NPC visits: lower white circle below the green ring.`nFishing: stand at the dock edge. Choose NPC + bait, then press F2.", th.txt, 9, 400, 42)
    Ui.info := Lbl(g, "dash", 214, 326, 590, "", th.muted, 9)
    HomeCard(g, 213, 356, "Fishing setup", "Camera, casting, reeling and dock recovery.", "fish")
    HomeCard(g, 514, 356, "NPC + Bait", "Choose your fishing NPC, bait and sale interval.", "shop")
    HomeCard(g, 213, 480, "Quests", "Angler quest options and current quest status.", "quest")
    HomeCard(g, 514, 480, "Webhook", "Choose which updates are sent to Discord.", "hook")

    ; ---- LOGS --------------------------------------------------------------
    PageHeader(g, "logs", "Logs", "Live activity, setup checks and error details.")
    Panel(g, "logs", 213, 100, 592, 522)
    Ui.log := g.Add("Edit", Format("x214 y101 w590 h520 ReadOnly -Wrap +VScroll -E0x200 Background{} c{}", th.inp, th.txt))
    Ui.log.SetFont("s9", "Consolas")
    Reg("logs", Ui.log)
    if th.dark {
        try DllCall("uxtheme\SetWindowTheme", "ptr", Ui.log.Hwnd, "str", "DarkMode_Explorer", "str", "")
    }

    ; ---- FISHING -----------------------------------------------------------
    PageHeader(g, "fish", "Fishing", "Set casting, camera and reeling. Start at the lower white NPC circle under the green marker.")
    Panel(g, "fish", 213, 100, 592, 142)
    Panel(g, "fish", 213, 256, 592, 150)
    Panel(g, "fish", 213, 406, 592, 188)
    Section(g, "fish", 214, 100, "CAMERA + CASTING")
    AddToggle(g, "fish", "perfect", 214, 126, "Release at the selected charge level", Cfg.perfect, 230)
    Lbl(g, "fish", 470, 129, 90, "Release at", th.muted)
    AddEdit(g, "fish", "perfectPct", 548, 125, 54, Cfg.perfectPct, true)
    Lbl(g, "fish", 610, 129, 190, "% of charge bar", th.muted)
    AddToggle(g, "fish", "zoomLock", 214, 166, "Keep zoom distance fixed", Cfg.zoomLock, 210)
    Lbl(g, "fish", 470, 169, 120, "Zoom-out notches", th.muted)
    AddEdit(g, "fish", "zoomOut", 598, 165, 54, Cfg.zoomOut, true)
    Lbl(g, "fish", 272, 209, 170, "Re-apply the zoom every", th.muted)
    AddEdit(g, "fish", "zoomEvery", 430, 205, 54, Cfg.zoomEvery, true)
    Lbl(g, "fish", 492, 209, 100, "casts", th.muted)
    Lbl(g, "fish", 590, 209, 100, "Camera tilt (px)", th.muted)
    AddEdit(g, "fish", "tiltPx", 690, 205, 54, Cfg.tiltPx, true)
    Section(g, "fish", 214, 256, "REELING AND RECOVERY")
    AddToggle(g, "fish", "chest", 214, 282, "Collect treasure chests", Cfg.chest, 200)
    AddToggle(g, "fish", "fastBite", 500, 282, "Faster bite reaction", Cfg.fastBite, 200)
    AddToggle(g, "fish", "slowFlick", 214, 322, "Slower fish trick", Cfg.slowFlick, 200)
    AddToggle(g, "fish", "anchor", 500, 322, "Use lower white NPC circle at start", Cfg.anchor, 270)
    AddToggle(g, "fish", "rodSkill", 214, 355, "Use fishing rod skill (Z)", Cfg.rodSkill, 270)
    Section(g, "fish", 214, 406, "GAME")
    Lbl(g, "fish", 214, 434, 120, "Roblox resolution", th.muted)
    AddDdl(g, "fish", "res", 340, 430, 130, ["Auto", "1920x1080", "2560x1440", "1366x768"]
        , IdxOf(["Auto", "1920x1080", "2560x1440", "1366x768"], Cfg.resolution))
    Lbl(g, "fish", 500, 434, 120, "Rod slot", th.muted)
    slots := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    AddDdl(g, "fish", "rod", 624, 430, 60, slots, IdxOf(slots, Cfg.rodSlot, 4))
    Lbl(g, "fish", 214, 474, 210, "Extra walk (0.1 s per step)", th.muted)
    AddEdit(g, "fish", "dockWalk", 430, 470, 54, Cfg.dockWalk, true)
    Lbl(g, "fish", 494, 474, 150, "8 = 0.8 seconds", th.muted)
    AddToggle(g, "fish", "gameFast", 214, 508, "Enable Roblox Fast Mode and Reduce Motion at startup", Cfg.gameFast, 480)
    Lbl(g, "fish", 214, 536, 590, "Perfect cast reads the charge meter continuously and releases at the selected percentage."
        . " The current default is 97%.", th.muted, 9, 400, 42)

    ; ---- QUEST -------------------------------------------------------------
    PageHeader(g, "quest", "Quests", "Optional: accept and track the Angler quests this macro supports.")
    Panel(g, "quest", 213, 100, 592, 128)
    Panel(g, "quest", 213, 236, 592, 56)
    Panel(g, "quest", 213, 306, 592, 114)
    Panel(g, "quest", 213, 436, 592, 90)
    Panel(g, "quest", 213, 528, 592, 88)
    Section(g, "quest", 214, 100, "ANGLER QUEST")
    AddToggle(g, "quest", "questOn", 214, 126, "Accept supported quests near the Angler", Cfg.questOn, 340)
    Lbl(g, "quest", 590, 129, 96, "Rod skill key", th.muted)
    AddDdl(g, "quest", "questKey", 690, 125, 60, ["Z", "X", "C", "V", "F"], IdxOf(["Z", "X", "C", "V", "F"], Cfg.questKey))
    Ui.questNote := Lbl(g, "quest", 214, 166, 590, "", th.muted, 9, 400, 56)
    Section(g, "quest", 214, 236, "STATUS")
    Ui.questStatus := Lbl(g, "quest", 214, 262, 590, "Macro not running.", th.txt, 10, 600)
    Section(g, "quest", 214, 306, "QUESTS THE MACRO HANDLES")
    Lbl(g, "quest", 214, 332, 590, "1. Catch a Common / Uncommon / Rare / Epic / Legendary / Mythical fish`n"
        . "2. Catch 3 fish within 2:05 (fast bite forced on, sales and bait trips wait)`n"
        . "3. 3 perfect casts + 3 perfect reactions (Perfect cast + fast bite are forced on by the macro)`n"
        . "4. Use a rod skill 3 times (uses the Rod skill key above)", th.muted, 9, 400, 84)
    Section(g, "quest", 214, 436, "FISHERMAN QUESTS")
    Lbl(g, "quest", 214, 462, 590, "The Fisherman has other quests, but the macro does not know their dialogue pages yet. "
        . "Send a screenshot of each Fisherman quest page and of the quest panel and they can be added. "
        . "Until then, every quest text the macro cannot match is written to the log as [quest] ... so nothing is lost.", th.muted, 9, 400, 56)
    Section(g, "quest", 214, 528, "DISCORD (needs the Webhook page set up)")
    AddToggle(g, "quest", "hkQuest", 214, 554, "Quest accepted", Cfg.hkQuest, 140)
    AddToggle(g, "quest", "hkQuestDone", 400, 554, "Quest finished", Cfg.hkQuestDone, 140)
    AddToggle(g, "quest", "hkQuestFail", 586, 554, "Quest failed", Cfg.hkQuestFail, 140)
    Lbl(g, "quest", 214, 588, 590, "The hourly report also lists the quests of the hour (accepted / done / failed).", th.muted, 9)

    ; ---- SHOP AND BAIT -----------------------------------------------------
    PageHeader(g, "shop", "NPC + Bait", "Choose where to fish, prepare bait, and schedule sales.")
    Panel(g, "shop", 213, 100, 592, 96)
    Panel(g, "shop", 213, 202, 592, 206)
    Panel(g, "shop", 213, 424, 592, 174)
    Section(g, "shop", 214, 100, "FISHING NPC")
    Lbl(g, "shop", 214, 130, 70, "NPC", th.muted)
    AddDdl(g, "shop", "npc", 280, 126, 150, NPC_LIST, IdxOf(NPC_LIST, Cfg.npc))
    Ui.npcNote := Lbl(g, "shop", 214, 160, 590, "", th.muted, 9, 400, 34)
    Section(g, "shop", 214, 202, "BAIT AND STOCK")
    AddToggle(g, "shop", "buyBait", 214, 228, "Auto-buy bait when it runs low", Cfg.buyBait, 280)
    Lbl(g, "shop", 214, 272, 90, "Bait type", th.muted)
    baitItems := []
    for b in BAITS
        baitItems.Push(BaitLabel(b))
    AddDdl(g, "shop", "bait", 300, 268, 440, baitItems, IdxOf(BAITS, CurBait(), 1))
    Lbl(g, "shop", 214, 312, 170, "Bait already in bag", th.muted)
    AddEdit(g, "shop", "baitNow", 390, 308, 70, Cfg.baitNow, true)
    Lbl(g, "shop", 470, 312, 330, "Enter 0 to let the macro track bait itself (max 90).", th.muted)
    Lbl(g, "shop", 214, 352, 170, "Buy up to", th.muted)
    AddDdl(g, "shop", "baitPer", 390, 348, 70, ["10", "20", "30", "40", "50", "60", "70", "80", "90", "100"]
        , Min(10, Max(1, Cfg.baitPer // 10)))
    Ui.costLbl := Lbl(g, "shop", 470, 352, 340, "", th.txt)
    Lbl(g, "shop", 214, 384, 590, "The inventory holds 90 bait at most: the macro only buys what fits (50 in stock + 100 wanted = 40 bought).", th.muted)
    Section(g, "shop", 214, 424, "SELLING + STATS")
    AddToggle(g, "shop", "sellOn", 214, 450, "Auto-sell fish every", Cfg.sellOn, 140)
    AddEdit(g, "shop", "sellEvery", 420, 446, 64, Cfg.sellEvery, true)
    Lbl(g, "shop", 492, 450, 100, "catches", th.muted)
    Ui.sellNote := Lbl(g, "shop", 600, 450, 210, "", th.bad, 9)
    AddToggle(g, "shop", "trackIncome", 214, 490, "Read money from the HUD (Windows OCR)", Cfg.trackIncome, 400)
    AddToggle(g, "shop", "trackLevel", 214, 520, "Read your level from the HUD (Windows OCR)", Cfg.trackLevel, 400)
    Lbl(g, "shop", 214, 556, 590, "Sea 2 and Sea 3 baits also need their material (Demonic Wisp, Yeti Fur, Terror Eyes, Dragon Scale)"
        . " in your inventory. Locked baits cannot be bought.", th.muted, 9, 400, 34)

    ; ---- WEBHOOK -----------------------------------------------------------
    PageHeader(g, "hook", "Webhook", "Configure Discord notifications and scheduled reports.")
    Panel(g, "hook", 213, 98, 592, 162)
    Panel(g, "hook", 213, 276, 592, 154)
    Panel(g, "hook", 213, 444, 592, 250)
    Section(g, "hook", 214, 98, "DISCORD")
    AddToggle(g, "hook", "hkOn", 214, 122, "Enable webhook", Cfg.hkOn, 200)
    Lbl(g, "hook", 214, 158, 300, "Webhook URL", th.muted)
    AddEdit(g, "hook", "hkUrl", 214, 180, 400, Cfg.hkUrl, false, true)
    Ui.btnShow := Btn(g, "hook", 622, 180, 56, 24, "Show", ToggleUrlMask, "ghost")
    Ui.btnShow.SetFont("s9 w600 c" . th.txt, "Segoe UI")
    Btn(g, "hook", 686, 180, 118, 24, "Send test", HookTest, "primary")
    Lbl(g, "hook", 214, 214, 180, "Display name", th.muted)
    AddEdit(g, "hook", "hkName", 214, 236, 170, Cfg.hkName)
    Lbl(g, "hook", 400, 214, 300, "Mention user ID on errors (optional)", th.muted)
    AddEdit(g, "hook", "hkMention", 400, 236, 214, Cfg.hkMention)
    Section(g, "hook", 214, 276, "RESULTS")
    AddToggle(g, "hook", "hkStart", 214, 300, "Macro started", Cfg.hkStart, 200)
    AddToggle(g, "hook", "hkStop", 500, 300, "Stopped + session summary", Cfg.hkStop, 230)
    AddToggle(g, "hook", "hkSale", 214, 334, "Fish sold", Cfg.hkSale, 200)
    AddToggle(g, "hook", "hkShot", 500, 334, "Screenshots (sale, bait, report)", Cfg.hkShot, 230)
    AddToggle(g, "hook", "hkBait", 214, 368, "Bait purchased", Cfg.hkBait, 200)
    AddToggle(g, "hook", "hkErr", 500, 368, "Errors + game screenshot", Cfg.hkErr, 230)
    Lbl(g, "hook", 214, 405, 368, "Hourly report: automatic every hour at :00 (PC local time)", th.muted)
    Btn(g, "hook", 600, 400, 204, 26, "Send report now", SendHourly, "ghost")
    Section(g, "hook", 214, 444, "LIVE ACTIVITY  (what the macro is doing right now)")
    AddToggle(g, "hook", "hkBuy", 214, 468, "Buying bait / selling fish", Cfg.hkBuy, 200)
    AddToggle(g, "hook", "hkActions", 500, 468, "Send each action as its own embed", Cfg.hkActions, 280)
    AddToggle(g, "hook", "hkCatch", 214, 502, "Fish caught + progress", Cfg.hkCatch, 200)
    AddToggle(g, "hook", "hkCatchShot", 500, 502, "Catch screenshot (slower)", Cfg.hkCatchShot, 230)
    AddToggle(g, "hook", "hkBarMiss", 214, 536, "Reel bar never appeared + screenshot", Cfg.hkBarMiss, 270)
    AddToggle(g, "hook", "hkChest", 500, 536, "Chest collected", Cfg.hkChest, 200)
    Lbl(g, "hook", 214, 594, 400, "Hourly report webhook URL (optional - empty = same channel)", th.muted)
    AddEdit(g, "hook", "hkUrlHourly", 214, 616, 400, Cfg.hkUrlHourly, false, true)
    Ui.hookStatus := Lbl(g, "hook", 214, 644, 590, "", th.muted, 9)

    ; ---- APPEARANCE --------------------------------------------------------
    PageHeader(g, "look", "Display", "Choose a colour theme. It is saved automatically.")
    px := 214
    py := 112
    for nm in THEME_ORDER {
        ThemeCard(g, nm, px, py)
        px += 202
        if (px > 640) {
            px := 214
            py += 104
        }
    }

    ; Widen the content column while retaining the same functional controls.
    for pg, list in Ui.pages {
        for c in list {
            c.GetPos(&cx, &cy, &cw, &ch)
            c.Move(232 + (cx - 214) * 1.45, cy, cw * 1.45, ch)
        }
    }
    Box(g, "", 0, 704, 1160, 1, th.line)
    Ui.btnStart.Move(230, 716, 124, 32)
    Ui.btnStop.Move(230, 716, 124, 32)
    Ui.btnCheck.Move(362, 716, 136, 32)
    Ui.btnUpdate.Move(506, 716, 106, 32)
    Ui.btnPause.Move(506, 716, 106, 32)
    Ui.btnQuit := Btn(g, "", 620, 716, 94, 32, "Quit (F4)", (*) => ExitApp(), "ghost")
    Lbl(g, "", 838, 722, 280, "v" . APP_VERSION . "   |   F2 Start   F3 Pause   F4 Quit", th.muted, 9)

    ; Render the web-style panel inside the AHK window (no external browser).
    for pg, list in Ui.pages {
        for c in list
            c.Visible := false
    }
    for c in [Ui.btnStart, Ui.btnStop, Ui.btnPause, Ui.btnCheck, Ui.btnUpdate, Ui.btnQuit]
        c.Visible := false
    for pg, trio in Ui.nav {
        for c in trio
            c.Visible := false
    }
    Ui.browserCtl := g.Add("ActiveX", "x0 y0 w" . windowWidth . " h" . windowHeight, "Shell.Explorer")
    Ui.browser := Ui.browserCtl.Value
    Ui.browser.Silent := true
    Ui.browserEvents := HtmlBrowserEvents()
    ComObjConnect(Ui.browser, Ui.browserEvents)
    Ui.browser.Navigate(HtmlFileURL(HTML_FILE))
    while (Ui.browser.ReadyState != 4)
        Sleep(10)
    doc := Ui.browser.Document
    Ui.htmlMode := true
    try doc.parentWindow.execScript("page('" . startPage . "')")

    ShowPage(startPage)
    g.Show("x" . windowX . " y" . windowY . " w" . windowWidth . " h" . windowHeight)
    ; Showing the parent window can put its older native child controls above
    ; the hosted browser. Explicitly restore the browser host to the top.
    DllCall("SetWindowPos", "ptr", Ui.browserCtl.Hwnd, "ptr", 0
        , "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x13)
    if th.dark {
        try {
            b := Buffer(4, 0)
            NumPut("Int", 1, b)
            DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "int", 20, "ptr", b, "int", 4)
        }
    }
    try {
        Ui.log.Value := BotState.logBuf
        n := StrLen(BotState.logBuf)
        SendMessage(0x00B1, n, n, Ui.log)
        SendMessage(0x00B7, 0, 0, Ui.log)                    ; EM_SCROLLCARET
    }
    RefreshDynamic()
    HtmlSync(true)
    SetStatus()
}

Cleanup(*) {
    try Mouse.Hold(false)
    try DllCall("winmm\timeEndPeriod", "UInt", 1)
}
