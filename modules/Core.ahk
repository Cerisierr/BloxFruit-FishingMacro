; ============================================================================
;  UTILITIES
; ============================================================================
Now() {
    static counter := 0
    DllCall("QueryPerformanceCounter", "Int64*", &counter)
    return counter / QPF
}

Median(arr) {
    a := []
    for v in arr
        a.Push(v)
    Loop a.Length - 1 {                      ; insertion sort
        i := A_Index + 1
        key := a[i]
        j := i - 1
        while (j >= 1 && a[j] > key) {
            a[j + 1] := a[j]
            j--
        }
        a[j + 1] := key
    }
    n := a.Length
    if (n == 0)
        return 0.0
    return (Mod(n, 2) == 1) ? a[(n + 1) // 2] : (a[n // 2] + a[n // 2 + 1]) / 2
}

; Sleep that ends early when the run is stopped.
Wait(sec) {
    endAt := Now() + sec
    while (BotState.running && Now() < endAt)
        Sleep(Min(20, Max(1, Round((endAt - Now()) * 1000))))
}

Alive(hp := false) {
    if !BotState.running
        return false
    if (Timing.responseTimeout > 0 && Now() - BotState.lastResponse > Timing.responseTimeout) {
        LogMsg("[safety] no confirmed game response for "
            . Round(Timing.responseTimeout) . " s - stopping")
        Halt("no confirmed game response for " . Round(Timing.responseTimeout) . " s")
        return false
    }
    if BotState.diedHudArmed {
        if DeathRecentlyHud() {
            if !BotState.diedHudSeen {
                if (BotState.atNpc || InDialogue()) {
                    BotState.diedHudVisible := false
                    BotState.diedHudReads := 0
                } else {
                    BotState.diedHudSeen := true
                    LogMsg("[death] the 'Died Recently - PvP disabled' HUD appeared during fishing - stopping")
                    Halt("death detected (Died Recently HUD)")
                    return false
                }
            }
        } else {
            BotState.diedHudSeen := false
        }
    }
    ; hp = true only inside the fishing loops (the HP bar is hidden during NPC dialogues)
    if (hp && HealthLost()) {
        LogMsg("[death] Health reads 0/x - character is dead, stopping")
        Halt("character dead (Health 0)")
        return false
    }
    return true
}

; OCR verdict is refreshed at the safe top of each fishing cycle. Never scan
; pixels here: Selected Bait and hotkey labels look like the death badge.
DeathRecentlyHud() {
    return BotState.diedHudVisible
}

; True once the HP bar has been empty for 3 s. Checked at most twice a second.
HealthLost() {
    if (Now() < BotState.hpNext)
        return BotState.hpDead
    BotState.hpNext := Now() + 0.5
    win := BotState.win
    r := SubRect(win, Regions.health)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    green := 0, total := 0
    y := 0
    while (y < r.h) {
        x := 0
        while (x < r.w) {
            v := NumGet(bits, (y * r.w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            if (gg >= 180 && rr <= 120 && bb <= 80)     ; lime HP fill
                green++
            total++
            x += 4
        }
        y += 4
    }
    if (total > 0 && green / total < 0.03) {
        ; No green fill: only a Health text of 0/x counts as dead. When the HUD is hidden (catch card,
        ; NPC speech) there is no Health text at all, which is not a death.
        if (Now() >= BotState.hpOcrNext) {
            BotState.hpOcrNext := Now() + 1.0
            if HealthTextZero() {
                BotState.hpZeroReads += 1
                if (BotState.hpZeroReads == 1)
                    LogMsg("[death] Health reads 0 - checking again")
            } else {
                BotState.hpZeroReads := 0
            }
        }
        BotState.hpDead := (BotState.hpZeroReads >= 2)
    } else {
        BotState.hpZeroReads := 0
        BotState.hpDead := false
    }
    return BotState.hpDead
}

; OCR of the Health bar text ("Health 0/2345"): true when the current value is 0.
HealthTextZero() {
    r := SubRect(BotState.win, Regions.health)
    path := TMP_DIR . "\hp.png"
    if !PngSave(r.x, r.y, r.w, r.h, path)
        return false
    raw := OcrFile(path)
    if RegExMatch(raw, "^ERR:")
        return false
    t := RegExReplace(raw, "\s+", " ")
    if !RegExMatch(t, "([\dOo][\d,.OoIl]*)\s*/\s*(\d[\d,.]*)", &m)
        return false
    cur := RegExReplace(StrReplace(StrReplace(m[1], "O", "0"), "o", "0"), "\D")
    mx := RegExReplace(m[2], "\D")
    return (cur != "" && mx != "" && Integer(cur) == 0 && Integer(mx) > 0)
}

NoteResponse() {
    BotState.lastResponse := Now()
}

; Stop the run from inside the engine and remember why (shown in the webhook).
Halt(reason, captureShot := true) {
    BotState.running := false
    first := (BotState.stopReason == "")
    if first
        BotState.stopReason := reason
    LogMsg("[stop] " . reason)
    if first {
        BotState.stopShot := captureShot ? ErrorShot("stop") : ""
        if (BotState.stopShot != "")
            LogMsg("[error] game screenshot saved: " . BotState.stopShot)
    }
}

; Screenshot of the whole game window, saved in the errors folder (kept: the newest 40).
; minGap > 0: the same tag is not captured again within that many seconds ("" is returned).
ErrorShot(tag, minGap := 0) {
    try {
        t := Now()
        if (minGap > 0 && BotState.errAt.Has(tag) && t - BotState.errAt[tag] < minGap)
            return ""
        BotState.errAt[tag] := t
        win := BotState.win
        if !IsObject(win) {
            RefreshGame()
            win := BotState.win
        }
        if !IsObject(win)
            return ""
        DirCreate(ERR_DIR)
        path := ERR_DIR . "\err_" . FormatTime(, "yyyyMMdd_HHmmss") . "_" . RegExReplace(tag, "[^\w-]", "") . ".png"
        if !PngSave(win.x, win.y, win.w, win.h, path)
            return ""
        names := []
        Loop Files, ERR_DIR . "\err_*.png"
            names.Push(A_LoopFileName)
        if (names.Length > 40) {
            names := StrSplit(Sort(StrJoin(names, "`n")), "`n")
            Loop names.Length - 40
                try FileDelete(ERR_DIR . "\" . names[A_Index])
        }
        return path
    }
    return ""
}

; Full-window diagnostic screenshots for fishing and camera transitions.
; Keep a rolling set so long fishing sessions do not fill the drive.
DebugShot(stage, trigger, minGap := 0) {
    try {
        t := Now()
        if (minGap > 0 && BotState.debugAt.Has(stage) && t - BotState.debugAt[stage] < minGap)
            return ""
        BotState.debugAt[stage] := t
        win := BotState.win
        if !IsObject(win) {
            RefreshGame()
            win := BotState.win
        }
        if !IsObject(win)
            return ""
        dir := ERR_DIR . "\debug"
        DirCreate(dir)
        tag := RegExReplace(stage, "[^\w-]", "")
        path := dir . "\debug_" . FormatTime(, "yyyyMMdd_HHmmss") . "_" . A_TickCount . "_" . tag . ".png"
        if !PngSave(win.x, win.y, win.w, win.h, path)
            return ""
        LogMsg("[debug] trigger=" . trigger . " | screenshot=" . path)
        names := []
        Loop Files, dir . "\debug_*.png"
            names.Push(A_LoopFileName)
        if (names.Length > 80) {
            names := StrSplit(Sort(StrJoin(names, "`n")), "`n")
            Loop names.Length - 80
                try FileDelete(dir . "\" . names[A_Index])
        }
        return path
    }
    return ""
}

StrJoin(arr, sep) {
    out := ""
    for v in arr
        out .= (A_Index > 1 ? sep : "") . v
    return out
}

; Something went wrong: screenshot the game, log where it was saved, post it to Discord.
ReportError(tag, title, desc, minGap := 0) {
    shot := ErrorShot(tag, minGap)
    if (shot == "")
        return ""
    LogMsg("[error] game screenshot saved: " . shot)
    HookError(title, desc, shot)
    return shot
}

; The last few log lines, for the error message.
LogTail(n := 8) {
    lines := StrSplit(RTrim(BotState.logBuf, "`r`n"), "`n", "`r")
    from := Max(1, lines.Length - n + 1)
    out := ""
    i := from
    while (i <= lines.Length) {
        out .= (out != "" ? "`n" : "") . lines[i]
        i++
    }
    return SubStr(out, -900)
}

HookError(title, desc, shot := "") {
    if !(HookReady() && Cfg.hkErr)
        return
    useShot := (shot != "" && FileExist(shot))
    f := [["Run time", FmtDur(Now() - BotStats.started)], ["Fish caught", Fmt(BotStats.catches)]
        , ["Last log lines", LogTail(8), false]]
    HookPost(EmbedJson(title, desc, 0xF87171, f, useShot ? "error.png" : ""), useShot ? shot : ""
        , , "error", "error.png")
}

HookBarNeverAppeared(shot := "", falseHook := false) {
    if !(HookReady() && Cfg.hkBarMiss)
        return
    useShot := (shot != "" && FileExist(shot))
    f := [["Bites / catches", BotStats.bites . " / " . BotStats.catches]
        , ["Bite marker detected", BotState.biteInfo, false]
        , ["Hook-to-reel delay", Round(Timing.hookedDelay * 1000) . " ms"]
        , ["Waited for reel bar", Round(Timing.biteToBar, 1) . " s"]
        , ["Possible causes", "Game lag, click not registered, or false Hooked detection", false]]
    desc := falseHook
        ? "Possible false Hooked: the attached bite-zone crop has a red frame around the pixels that triggered detection. The reel bar did not appear before timeout."
        : "The red bite marker was detected and clicked, but the reel minigame bar did not appear before timeout. See the [bite]/[reel] log entries."
    imageName := falseHook ? "bite-detection.png" : "debug.png"
    HookPost(EmbedJson(falseHook ? "Possible false Hooked" : "Fishing bar never appeared", desc, 0xF87171, f, useShot ? imageName : "")
        , useShot ? shot : "", , falseHook ? "false hooked" : "bar never appeared", imageName)
}

; Count into both the session totals and the current hourly-report window.
Tally(field, n := 1) {
    BotStats.%field% += n
    Hour.%field% += n
}

ResetHour() {
    for k in ["casts", "catches", "escapes", "sales", "purchases", "baitBought", "spent"
            , "income", "unreadable", "levels", "chests", "quests", "questsAcc", "questsFail", "bites", "missedBar", "biteTimeouts"]
        Hour.%k% := 0
    Hour.qlog := []
    Hour.started := Now()
}

; 1234567 -> "1,234,567"
Fmt(n) {
    try {
        v := Integer(n)
    } catch {
        return String(n)
    }
    s := String(Abs(v))
    out := ""
    while (StrLen(s) > 3) {
        out := "," . SubStr(s, -3) . out
        s := SubStr(s, 1, StrLen(s) - 3)
    }
    return (v < 0 ? "-" : "") . s . out
}

; seconds -> "1h 05m" / "7m 12s"
FmtDur(sec) {
    sec := Max(0, Round(sec))
    h := sec // 3600
    m := Mod(sec // 60, 60)
    s := Mod(sec, 60)
    if (h > 0)
        return h . "h " . Format("{:02}", m) . "m"
    return m . "m " . Format("{:02}", s) . "s"
}

LogMsg(msg) {
    line := FormatTime(, "HH:mm:ss") . "  " . msg
    try HookAction(msg)
    BotState.logBuf .= line . "`r`n"
    if (StrLen(BotState.logBuf) > 24000)
        BotState.logBuf := SubStr(BotState.logBuf, -12000)
    try {
        if Ui.HasOwnProp("log") {
            len := SendMessage(0x000E, 0, 0, Ui.log)         ; WM_GETTEXTLENGTH
            if (len > 24000) {
                Ui.log.Value := ""
                len := 0
            }
            SendMessage(0x00B1, len, len, Ui.log)            ; EM_SETSEL at end
            EditPaste(line . "`r`n", Ui.log)
        }
    }
    if BotState.debug
        try FileAppend(line . "`n", LOG_FILE)
    try HtmlSync()
}

; ---- geometry --------------------------------------------------------------
; Uses the real Roblox client rectangle (so windowed mode works too); the
; selected resolution profile is used for validation and as the fallback.
RefreshGame() {
    rect := 0
    hwnd := WinExist(ROBLOX_WIN)
    if hwnd {
        try {
            WinGetClientPos(&cx, &cy, &cw, &ch, hwnd)
            if (cw >= 400 && ch >= 300)
                rect := {x: cx, y: cy, w: cw, h: ch}
        }
    }
    if !rect
        rect := {x: 0, y: 0, w: BotState.resW, h: BotState.resH}
    BotState.win := rect
    BotState.sc := rect.h / 1080.0
    return rect
}

ApplyResolution() {
    name := Cfg.resolution
    if (name == "Auto" || !RES_PROFILES.Has(name)) {
        best := "", bestD := 1e9
        for k, v in RES_PROFILES {
            d := Abs(v[1] - A_ScreenWidth) + Abs(v[2] - A_ScreenHeight)
            if (d < bestD) {
                bestD := d
                best := k
            }
        }
        name := best
    }
    BotState.resW := RES_PROFILES[name][1]
    BotState.resH := RES_PROFILES[name][2]
    return name
}

CheckResolution() {
    win := RefreshGame()
    okW := Abs(win.w - BotState.resW) <= BotState.resW * 0.03
    okH := Abs(win.h - BotState.resH) <= BotState.resH * 0.03
    if (!okW || !okH)
        LogMsg("[warn] game area is " . win.w . "x" . win.h . " but the profile is "
            . BotState.resW . "x" . BotState.resH
            . " - set Roblox fullscreen (F11) at that resolution, or pick the matching profile")
    return okW && okH
}

SubRect(win, fr) {
    return {x: win.x + Round(win.w * fr[1]), y: win.y + Round(win.h * fr[2])
          , w: Max(1, Round(win.w * (fr[3] - fr[1])))
          , h: Max(1, Round(win.h * (fr[4] - fr[2])))}
}

PtAbs(fr) {
    win := BotState.win
    return {x: win.x + Round(win.w * fr[1]), y: win.y + Round(win.h * fr[2])}
}

FocusGame() {
    if WinActive(ROBLOX_WIN)
        return true
    hwnd := WinExist(ROBLOX_WIN)
    if !hwnd
        return false
    try WinActivate(hwnd)
    return WinWaitActive(hwnd, , 1) ? true : false
}
