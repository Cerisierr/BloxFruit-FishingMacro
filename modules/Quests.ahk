; ============================================================================
;  ANGLER QUEST  (one quest every 15 min: accept at the Angler, fish, hand in)
; ============================================================================
; The four quests: catch a Common..Mythical fish / catch 3 fish within 2:05 /
; 3 perfect casts + 3 perfect reactions / use a fishing-rod skill 3 times.
; The 15 min cooldown starts when a quest is ACCEPTED. A quest that is still open must
; be finished (or abandoned) before the Angler offers a new one, so the macro only asks
; for a new quest when the quest panel (top-left HUD) shows nothing.
; Finished = the progress bar is full (bright yellow) / the counters read n/n.
QuestOn() {
    return Cfg.questOn && Cfg.npc == "Angler"
}

QuestLabel() {
    switch BotState.questType {
        case "rarity":
            return "catch a " . (BotState.questRarity != "" ? StrLower(BotState.questRarity) . " " : "") . "fish"
        case "timed":
            return "catch 3 fish in 2 min"
        case "perfect":
            return "3 perfect casts + 3 reactions"
        case "skill":
            return "use a rod skill 3 times"
    }
    return "unknown quest"
}

QuestShort() {
    switch BotState.questState {
        case "active":
            return "Quest: " . QuestLabel() . (BotState.questProg != "" ? "  (" . BotState.questProg . ")" : "")
        case "done":
            return "Quest: handing in"
        case "none":
            left := BotState.questNextTry - Now()
            return (left > 30) ? "Quest in " . Ceil(left / 60) . " min" : "Quest: asking"
    }
    return "Quest: checking"
}

QuestTimedActive() {
    return QuestOn() && BotState.questState == "active" && BotState.questTimed
}

; "3 perfect casts" quest: the charge meter is read and released at the top, whatever the
; Perfect cast setting is.
QuestPerfectActive() {
    return QuestOn() && BotState.questState == "active" && BotState.questType == "perfect"
}

PerfectOn() {
    return Cfg.perfect || QuestPerfectActive()
}

; "Perfect reaction" quest: react to the bite as fast as the Fast bite mode does.
FastBiteOn() {
    return Cfg.fastBite || QuestPerfectActive() || QuestTimedActive()
}

QuestSkillWanted() {
    return QuestOn() && BotState.questState == "active" && BotState.questType == "skill" && BotState.questSkillUses < 8
}

QuestUseSkill() {
    sc := Keys.SKILLS.Has(Cfg.questKey) ? Keys.SKILLS[Cfg.questKey] : Keys.SKILLS["Z"]
    Keys.Tap(sc, 0.08)
    BotState.questSkillUses += 1
    LogMsg("[quest] rod skill " . Cfg.questKey . " used (" . BotState.questSkillUses . ")")
}

; Is the quest progress bar full? A thin, long, bright-yellow bar in the quest panel.
; Thick yellow areas (sand, clothes) are rejected by the thickness limits.
QuestBarDone() {
    win := BotState.win
    r := SubRect(win, Regions.quest)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    w := r.w, h := r.h
    minRun := Round(win.w * 0.125)
    minT := Max(3, Round(win.h * 0.006))
    maxT := Round(win.h * 0.022)
    thick := 0
    y := 0
    while (y <= h) {
        hit := false
        if (y < h) {
            base := y * w * 4
            inRun := false, start := 0, last := 0, best := 0
            x := 0
            while (x < w) {
                v := NumGet(bits, base + x * 4, "UInt")
                rr := (v >> 16) & 255
                gg := (v >> 8) & 255
                bb := v & 255
                if (rr >= 220 && gg >= 180 && bb <= 90 && rr >= gg) {
                    if !inRun {
                        inRun := true
                        start := x
                    }
                    last := x
                } else if (inRun && x - last > 4) {
                    best := Max(best, last - start)
                    inRun := false
                }
                x += 2
            }
            if inRun
                best := Max(best, last - start)
            hit := (best >= minRun)
        }
        if hit {
            thick += 2
        } else {
            if (thick >= minT && thick <= maxT)
                return true
            thick := 0
        }
        y += 2
    }
    return false
}

; OCR text of the quest panel -> {active, done, timed, type, rarity, cur, tot, text}.
QuestParse(txt) {
    t := RegExReplace(txt, "\s+", " ")
    q := {active: false, done: false, timed: false, type: "other", rarity: "", cur: 0, tot: 0, text: t, prog: ""}
    if !RegExMatch(t, "i)trust|catch|within|remain|perfect|skill|deliver|fishin")
        return q
    q.active := true
    q.timed := RegExMatch(t, "i)within|remain|minute|\b\d:\d\d\b") ? true : false
    n := 0
    allDone := true
    pos := 1
    while RegExMatch(t, "(\d{1,3})\s*/\s*(\d{1,3})", &m, pos) {
        pos := m.Pos + Max(1, m.Len)
        c := Integer(m[1])
        tt := Integer(m[2])
        if (tt < 1 || tt > 20)
            continue
        n++
        q.prog .= (q.prog != "" ? " + " : "") . c . "/" . tt
        if (n == 1) {
            q.cur := c
            q.tot := tt
        }
        if (c < tt)
            allDone := false
    }
    q.done := (n > 0 && allDone)
    if RegExMatch(t, "i)perfect") {
        q.type := "perfect"
        if (n < 2)                                       ; two objectives: one counter read = OCR missed a line
            q.done := false
    } else if RegExMatch(t, "i)skill") {
        q.type := "skill"
    } else if RegExMatch(t, "i)catch\s+(?:an?\s+)?(common|uncommon|rare|epic|legendary|mythic\w*)\s+fish", &rm) {
        q.type := "rarity"
        q.rarity := rm[1]
    } else if q.timed {
        q.type := "timed"
    }
    return q
}

; The Angler said "Still waitin' on you to get that task done": the quest is NOT finished, so
; "done" (bar or OCR) is ignored for a while.
QuestBlocked() {
    return Now() < BotState.questBlock
}

; Fold what the panel shows into the quest state.
QuestApply(q) {
    QuestApplyCore(q)
    QuestSave()
}

QuestApplyCore(q) {
    st := BotState.questState
    if !q.active {
        if (BotState.questResumed && (st == "active" || st == "done")) {
            BotState.questMiss += 1
            if (BotState.questMiss < 2)
                return
            LogMsg("[quest] the quest saved from the last session is not on the panel any more (finished or expired while the macro was stopped)")
            QuestEntryDrop()
            BotState.questResumed := false
            BotState.questMiss := 0
            BotState.questState := "none"
            BotState.questProg := ""
            return
        }
        if (st == "active" || st == "done") {
            BotState.questMiss += 1                      ; one empty read may be an OCR miss
            if (BotState.questMiss < 2)
                return
            LogMsg("[quest] the quest panel is gone - the quest is over (handed in, timed out or abandoned)")
            if (st == "active")
                QuestEnded("failed", "The quest panel disappeared before the objective was complete (timed out or abandoned).")
            else
                QuestEnded("done", "The objective was complete and the quest panel is gone.")
        }
        BotState.questMiss := 0
        BotState.questState := "none"
        BotState.questProg := ""
        BotState.questBlock := 0.0
        return
    }
    BotState.questMiss := 0
    if BotState.questResumed {
        BotState.questResumed := false
        LogMsg("[quest] the quest saved from the last session is still on the panel - continuing it: " . QuestLabel())
    }
    if (q.prog != BotState.questProg) {
        BotState.questProg := q.prog
        if (q.prog != "")
            LogMsg("[quest] progress: " . q.prog)
    }
    BotState.questTimed := q.timed
    if (q.type != "other" || BotState.questObjective == "")
        BotState.questObjective := SubStr(q.text, 1, 180)
    if (st != "active" && st != "done") {
        BotState.questSkillUses := 0
        BotState.questType := q.type
        BotState.questRarity := q.rarity
        LogMsg("[quest] active quest: " . QuestLabel() . (q.tot > 0 ? "  (" . q.cur . "/" . q.tot . ")" : "")
            . (q.timed ? "  - timed" : ""))
        QuestEntryOpen()
        if (q.type == "other") {
            utxt := SubStr(RegExReplace(q.text, "\s+", " "), 1, 200)
            LogMsg("[quest] UNKNOWN quest text (send this line + the screenshot): '" . utxt . "'")
            ReportError("quest-unknown", "Unknown quest", "The macro does not know this quest. Panel text: " . utxt, 120)
        }
    } else if (q.type != "other" && q.type != BotState.questType) {
        BotState.questType := q.type
        BotState.questRarity := q.rarity
    }
    if (q.done && QuestBlocked() && InStr(q.prog, "+"))
        BotState.questBlock := 0.0                       ; every counter really reads n/n: trust it
    if ((q.done && !QuestBlocked()) || st == "done") {
        if (st != "done")
            LogMsg("[quest] objective complete (" . q.cur . "/" . q.tot . ") - handing it in")
        BotState.questState := "done"
    } else {
        BotState.questState := "active"
    }
}

QuestRead() {
    BotState.questRead := Now()
    r := SubRect(BotState.win, Regions.quest)
    path := TMP_DIR . "\quest.png"
    if !PngSave(r.x, r.y, r.w, r.h, path)
        return
    raw := OcrFile(path)
    if RegExMatch(raw, "^ERR:") {
        LogMsg("[quest] OCR failed: " . raw)
        return
    }
    q := QuestParse(raw)
    BotState.lastOcr := q.text
    QuestApply(q)
}

; Once per cycle, with the HUD visible: the bar is checked every cycle (cheap pixel
; scan), the panel text every 20 s (timed quest) / 45 s (others) with OCR.
QuestTick() {
    if !QuestOn()
        return
    st := BotState.questState
    if (st == "unknown") {
        QuestRead()
        if (BotState.questState == "none") {             ; one empty first read may be an OCR miss: look again
            Wait(2.0)
            QuestRead()
        }
        return
    }
    if (st == "active") {
        ; Several objectives = several bars (3 perfect casts + 3 perfect reactions): one full bar
        ; does NOT mean the quest is done. Only the OCR counters (all n/n) decide there.
        multi := (BotState.questType == "perfect" || InStr(BotState.questProg, "+"))
        if (!multi && !QuestBlocked() && QuestBarDone()) {
            BotState.questState := "done"
            LogMsg("[quest] the progress bar is full - handing the quest in")
            QuestSave(true)
            return
        }
        if (Now() - BotState.questRead >= (BotState.questTimed ? 20 : (multi ? 10 : 45)))
            QuestRead()
    }
}

QuestDue() {
    if (!QuestOn() || BotState.questFails >= 3)
        return false
    st := BotState.questState
    if (st == "done")
        return true
    return (st == "none" && Now() >= BotState.questNextTry)
}

; The dialogue text line of the NPC ("Lookin' to do something for me?").
QuestDialogText() {
    r := SubRect(BotState.win, Regions.questText)
    path := TMP_DIR . "\quest_dialog.png"
    if !PngSave(r.x, r.y, r.w, r.h, path)
        return ""
    return RegExReplace(OcrFile(path), "\s+", " ")
}

QuestFail(why) {
    BotState.questFails += 1
    BotState.questNextTry := Now() + 60
    if (BotState.questFails >= 3) {
        LogMsg("[quest] 3 failed visits in a row - auto-quest is off until the macro is restarted")
        HookQuestFail("Auto-quest", "3 failed visits to the Angler in a row (" . why . "). Auto-quest is off until the macro is restarted.")
    }
    return ShopFail(why, "quest")
}

; The NPC speech after "Yes" (or after a hand-in) is a text-only box: the gold name banner
; and one line, NO buttons. It stays on screen until it is clicked (the Angler's "Use your
; fishing rod's skill 3 times." line). Click the box until the banner is gone or the button
; stack comes back. Returns true when it clicked at least once.
AdvanceDialogueText(maxClicks := 6) {
    clicked := 0
    Loop maxClicks {
        if !Alive()
            break
        if (MenuPanels().Length >= 2)
            break                                        ; buttons are back: LeaveDialogue takes over
        if !DialogueHeader()
            break                                        ; no banner: the speech is closed
        p := PtAbs(Points.dialogueText)
        clicked += 1
        LogMsg("[quest] text-only dialogue on screen - clicking to continue (" . clicked . ")")
        Mouse.ClickAt(p.x, p.y, 0.20, 0.08)
        Wait(0.7)
    }
    return clicked > 0
}

; Talk to the Angler: Quest. A finished quest is handed in by that one click (then the
; menu is left with Nevermind). When a quest is on offer the page is "Lookin' to do
; something for me?  Yes / No / Back": Yes accepts it.
QuestVisit() {
    mode := (BotState.questState == "done") ? "turnin" : "accept"
    LogMsg("[quest] talking to the Angler: " . (mode == "turnin" ? "handing in the finished quest" : "asking for a quest"))
    Mouse.trace := true
    try r := QuestVisitCore(mode)
    catch as err {
        Mouse.trace := false
        throw err
    }
    Mouse.trace := false
    return r
}

QuestVisitCore(mode) {
    if !OpenNpcDialogue()
        return QuestFail("NPC dialogue never opened")
    if !WaitMenuPage("root", ShopCfg.rootTimeout + 1.0)
        return QuestFail("the Angler menu did not settle")
    ClickMenuAction("root", "quest")
    Wait(1.8)                                            ; let the answer text appear

    offered := false
    cooldown := false
    deadline := Now() + 8.0
    while (Alive() && Now() < deadline) {
        n := MenuPanels().Length
        if (n == PageRows("quest")) {
            if WaitMenuPage("quest", 1.6) {
                offered := true
                break
            }
        } else if (n == PageRows("root")) {
            if WaitMenuPage("root", 1.6)
                break                                    ; back on the Angler menu: nothing more to answer
        } else if (n < 2 && DialogueHeader()) {
            ; Text-only answer. Read it BEFORE clicking it away. "I don't have any tasks for you
            ; right now, come back in a little bit." = the 15 min cooldown is still running.
            Wait(0.7)                                    ; let the text finish typing
            said := QuestDialogText()
            LogMsg("[quest] the Angler says (no buttons): '" . said . "'")
            if RegExMatch(said, "i)any tasks|come back|little bit|right now|nothing for you")
                cooldown := true
            if (mode == "turnin" && RegExMatch(said, "i)still wait|waitin|task done|get that")) {
                BotState.questBlock := Now() + 120
                LogMsg("[quest] the Angler says the task is NOT done yet - back to the quest (finished signals ignored for 2 min)")
            }
            AdvanceDialogueText()
            if cooldown
                break
        }
        Wait(0.15)
    }
    if !Alive()
        return false

    txt := cooldown ? "" : QuestDialogText()
    if !cooldown
        LogMsg("[quest] the Angler says: '" . txt . "'" . (offered ? "  (Yes / No / Back page)" : "  (no answer page)"))
    accepted := false
    if offered {
        isOffer := RegExMatch(txt, "i)lookin|do something|something for me") ? true : false
        if (!isOffer && txt == "")                       ; OCR gave nothing: trust the empty quest panel
            isOffer := (BotState.questState == "none")
        if isOffer {
            LogMsg("[quest] a quest is on offer - answering Yes")
            ClickMenuAction("quest", "yes")
            accepted := true
            Wait(1.2)
            AdvanceDialogueText()                        ; the quest line must be clicked or the dialogue stays stuck
        } else {
            LogMsg("[quest] this is not the quest offer (maybe an abandon prompt) - NOT answering, backing out")
            ReportError("quest-notoffer", "Quest page not recognised", "The Angler page was not the quest offer: '" . txt . "'", 60)
        }
    }

    if !LeaveDialogue() {
        LogMsg("[quest] the dialogue did not close - stopping safely")
        Halt("the NPC dialogue would not close after the quest talk")
        return true
    }
    Wait(ShopCfg.afterNevermind)
    SetRod(true)
    EnterFishingStance(true)
    NoteResponse()
    Wait(1.0)
    QuestAfterVisit(mode, accepted, cooldown)
    return true
}

; Read the quest panel again and decide what the visit achieved.
QuestAfterVisit(mode, accepted, cooldown := false) {
    QuestAfterVisitCore(mode, accepted, cooldown)
    QuestSave(true)
}

QuestAfterVisitCore(mode, accepted, cooldown := false) {
    BotState.questState := (mode == "turnin" && QuestBlocked()) ? "active" : "none"   ; the panel now decides
    BotState.questMiss := 0
    QuestRead()
    st := BotState.questState
    if (mode == "turnin") {
        if (QuestBlocked() && (st == "active" || st == "done")) {
            BotState.questState := "active"
            BotState.questHandFails := 0
            return
        }
        if (st == "done") {
            BotState.questHandFails += 1
            LogMsg("[quest] the quest still shows as finished (hand-in attempt " . BotState.questHandFails . ")")
            if (BotState.questHandFails >= 3) {
                LogMsg("[quest] giving up on this hand-in - clearing it")
                QuestEnded("failed", "The hand-in did not register after 3 tries.")
                BotState.questHandFails := 0
                BotState.questState := "none"
                BotState.questNextTry := Now() + 120
            }
            return
        }
        BotState.questHandFails := 0
        Tally("quests")
        LogMsg("[quest] quest handed in (" . BotStats.quests . " this session)")
        QuestEntryOpen()
        e := BotState.questEntry
        e.status := "done"
        took := Now() - e.t
        inList := false
        for x in Hour.qlog {
            if (x == e) {
                inList := true
                break
            }
        }
        if !inList
            Hour.qlog.Push(e)
        BotState.questEntry := ""
        HookQuestDone(e.label, took)
        if (!accepted && BotState.questNextTry < Now() + 20)
            BotState.questNextTry := Now() + 20
    }
    if accepted {
        if (st == "active") {
            BotState.questAcceptedAt := Now()
            BotState.questNextTry := Now() + 905         ; next offer: 15 min after accepting
            BotState.questStreak := 0
            BotState.questFails := 0
            LogMsg("[quest] accepted: " . QuestLabel())
            Tally("questsAcc")
            QuestEntryOpen()
            HookQuestAccepted()
        } else {
            LogMsg("[quest] answered Yes but no quest panel showed up - checking again soon")
            ReportError("quest-nopanel", "No quest panel after Yes", "The Angler was answered Yes but no quest panel appeared.", 60)
            BotState.questNextTry := Now() + 45
        }
        return
    }
    if (mode == "accept") {
        if (st == "active" || st == "done")
            return                                       ; a quest was open after all: normal tracking takes over
        if cooldown {
            ; The Angler has no task yet: the 15 min cooldown counts from the last ACCEPT.
            ; Ask again when it ends (never more than 15 min from now, never sooner than 60 s).
            nxt := (BotState.questAcceptedAt > 0) ? BotState.questAcceptedAt + 905 : Now() + 300
            nxt := Min(Now() + 905, Max(Now() + 60, nxt))
            BotState.questNextTry := nxt
            BotState.questStreak := 0
            BotState.questFails := 0
            LogMsg("[quest] the Angler has no task yet (15 min cooldown) - asking again in " . Ceil((nxt - Now()) / 60) . " min")
            return
        }
        BotState.questStreak += 1
        delay := Min(300, 60 * BotState.questStreak)
        BotState.questNextTry := Now() + delay
        LogMsg("[quest] nothing to accept - asking again in " . delay . " s")
    }
}

; One entry per quest, for the hourly report: {label, status, t}. status = ongoing / done / failed.
QuestEntryOpen() {
    e := BotState.questEntry
    if (IsObject(e) && e.status == "ongoing")
        return e
    e := {label: QuestLabel(), status: "ongoing", t: Now()}
    BotState.questEntry := e
    Hour.qlog.Push(e)
    return e
}

; Forget the open entry without counting it (a resumed quest that turned out to be over).
QuestEntryDrop() {
    e := BotState.questEntry
    BotState.questEntry := ""
    if !IsObject(e)
        return
    i := Hour.qlog.Length
    while (i >= 1) {
        if (Hour.qlog[i] == e) {
            Hour.qlog.RemoveAt(i)
            break
        }
        i--
    }
}

; ---- the quest survives a stop / restart of the macro (saved in BloxFishing.ini, [quest]) ----
QuestSave(force := false) {
    if !QuestOn()
        return
    st := BotState.questState
    if (st == "unknown")
        return
    sig := st . "|" . BotState.questType . "|" . BotState.questRarity . "|" . BotState.questTimed . "|" . BotState.questProg
        . "|" . Round(BotState.questNextTry) . "|" . Round(BotState.questAcceptedAt)
    if (!force && sig == BotState.questSig)
        return
    BotState.questSig := sig
    try {
        age := (BotState.questAcceptedAt > 0) ? Round(Max(0, Now() - BotState.questAcceptedAt)) : -1
        left := Round(Max(0, BotState.questNextTry - Now()))
        e := BotState.questEntry
        IniWrite(st, INI_FILE, "quest", "state")
        IniWrite(BotState.questType, INI_FILE, "quest", "type")
        IniWrite(BotState.questRarity, INI_FILE, "quest", "rarity")
        IniWrite(BotState.questTimed ? "1" : "0", INI_FILE, "quest", "timed")
        IniWrite(BotState.questProg, INI_FILE, "quest", "prog")
        IniWrite(StrReplace(BotState.questObjective, "`n", " "), INI_FILE, "quest", "objective")
        IniWrite(IsObject(e) ? e.label : "", INI_FILE, "quest", "label")
        IniWrite((age >= 0) ? DateAdd(A_Now, -age, "Seconds") : "", INI_FILE, "quest", "accepted")
        IniWrite(DateAdd(A_Now, left, "Seconds"), INI_FILE, "quest", "next")
    }
}

; At start-up: take the quest (and the 15 min cooldown) of the last session back.
QuestResume() {
    BotState.questResumed := false
    if !QuestOn()
        return
    try {
        nxt := IniRead(INI_FILE, "quest", "next", "")
        if (nxt != "") {
            left := DateDiff(nxt, A_Now, "Seconds")
            if (left > 0 && left <= 3600)
                BotState.questNextTry := Now() + left
        }
        acc := IniRead(INI_FILE, "quest", "accepted", "")
        age := -1
        if (acc != "")
            age := DateDiff(A_Now, acc, "Seconds")
        if (age >= 0 && age <= 43200)
            BotState.questAcceptedAt := Now() - age
        st := IniRead(INI_FILE, "quest", "state", "none")
        if ((st != "active" && st != "done") || age < 0 || age > 43200)
            return
        BotState.questType := IniRead(INI_FILE, "quest", "type", "")
        BotState.questRarity := IniRead(INI_FILE, "quest", "rarity", "")
        BotState.questTimed := (IniRead(INI_FILE, "quest", "timed", "0") == "1")
        BotState.questProg := IniRead(INI_FILE, "quest", "prog", "")
        BotState.questObjective := IniRead(INI_FILE, "quest", "objective", "")
        BotState.questState := st
        BotState.questResumed := true
        BotState.questRead := 0.0                        ; check the panel at the first tick
        e := QuestEntryOpen()
        lbl := IniRead(INI_FILE, "quest", "label", "")
        if (lbl != "")
            e.label := lbl
        e.t := Now() - age
        LogMsg("[quest] resuming the quest from the last session: " . QuestLabel()
            . (BotState.questProg != "" ? "  (" . BotState.questProg . ")" : "") . "  - accepted " . Round(age / 60, 1) . " min ago")
    }
}

; The quest is over: record it, count it, and post the webhook.
QuestEnded(kind, why := "") {
    e := QuestEntryOpen()
    e.label := (QuestLabel() != "unknown quest") ? QuestLabel() : e.label
    e.status := kind
    took := Now() - e.t
    inList := false
    for x in Hour.qlog {
        if (x == e) {
            inList := true
            break
        }
    }
    if !inList
        Hour.qlog.Push(e)
    BotState.questEntry := ""
    if (kind == "done") {
        Tally("quests")
        HookQuestDone(e.label, took)
    } else {
        Tally("questsFail")
        LogMsg("[quest] FAILED: " . e.label . " - " . why)
        shot := ErrorShot("quest-failed", 10)
        if (shot != "")
            LogMsg("[error] game screenshot saved: " . shot)
        HookQuestFail(e.label, why, took, shot)
    }
}

QuestFields() {
    return [["Quests this session", BotStats.questsAcc . " accepted  |  " . BotStats.quests . " done  |  "
        . BotStats.questsFail . " failed"]]
}

; Quest accepted: what the quest is.
HookQuestAccepted() {
    if !(HookReady() && Cfg.hkQuest)
        return
    obj := Trim(RegExReplace(BotState.questObjective, "\s+", " "))
    f := [["Quest", QuestLabel()]]
    if (obj != "")
        f.Push(["Panel text", obj, false])
    f.Push(["Type", BotState.questTimed ? "Timed" : "Normal"])
    f.Push(["Next quest", "in about 15 min"])
    for x in QuestFields()
        f.Push(x)
    HookPost(EmbedJson("Quest accepted", QuestLabel(), 0xFBBF24, f), , , "quest accepted")
}

HookQuestDone(label, took) {
    if !(HookReady() && Cfg.hkQuestDone)
        return
    f := [["Quest", label], ["Time taken", FmtDur(took)]]
    for x in QuestFields()
        f.Push(x)
    HookPost(EmbedJson("Quest finished", "The quest was completed.", 0x34D399, f), , , "quest done")
}

HookQuestFail(label, why, took := 0, shot := "") {
    if !(HookReady() && Cfg.hkQuestFail)
        return
    useShot := (shot != "" && FileExist(shot))
    f := [["Quest", label]]
    if (took > 0)
        f.Push(["Open for", FmtDur(took)])
    for x in QuestFields()
        f.Push(x)
    HookPost(EmbedJson("Quest failed", why, 0xF87171, f, useShot ? "error.png" : ""), useShot ? shot : ""
        , , "quest failed", "error.png")
}

NeedsBait() {
    return Cfg.buyBait && BotState.bait >= 0 && BotState.bait <= ShopCfg.buyAt
}

NeedsSell() {
    return Cfg.sellOn && Cfg.npc != "Angler" && Cfg.sellEvery > 0 && BotState.sinceSell >= Cfg.sellEvery
}

Cycle() {
    ; Pause: the top of a cycle is the only safe point (no mouse button held here).
    if BotState.paused {
        Mouse.Hold(false)
        while (BotState.paused && BotState.running) {
            NoteResponse()                              ; a long pause must not trip the response timeout
            Sleep(200)
        }
        if !BotState.running
            return
    }
    UpdateStats()
    RefreshGame()
    if !FocusGame() {
        LogMsg("[warn] Roblox is not focused / not found")
        Wait(1.0)
        return
    }
    ReadBaitLine()
    ; Recover mid-cycle: a bar is already up (started mid-fight).
    if FindBar() {
        if Reel(false)
            DismissCatch()
        WaitBarClear()
        return
    }

    if (Cfg.trackLevel && Now() - BotState.levelRead > 300)
        UpdateLevel()
    if BotState.reportDue {                              ; hourly report: fresh level first
        BotState.reportDue := false
        UpdateLevel()
        SendHourly()
    }

    ; Angler quest: hand in / ask for a quest first (a timed quest must be handed in fast).
    QuestTick()
    visited := false
    if QuestDue() {
        QuestVisit()
        visited := true
        if !Alive()
            return
    }
    ; A timed quest (3 fish in 2 min) is not interrupted by a sale or a bait trip, unless bait is nearly gone.
    timedQuest := QuestTimedActive()
    sellDue := NeedsSell() && !timedQuest
    baitDue := NeedsBait() && !(timedQuest && BotState.bait > 5)
    if sellDue
        LogMsg("[sell] due: " . BotState.sinceSell . " catches since the last sale")
    if baitDue
        LogMsg("[bait] low (" . BotState.bait . " left) - restocking")
    if sellDue {
        ok := SellFish(baitDue)
        if !Alive()
            return
        baitDue := baitDue && ok
    }
    if baitDue {
        BuyBait()
        if !Alive()
            return
    }

    if (visited || sellDue || baitDue)
        ClearNpcRange("after the shop")
    if (BotState.bait == 0) {                          ; tracked count hit zero and nothing bought it back
        Halt("out of bait" . (Cfg.buyBait ? "" : " (enable auto-buy to restock automatically)"))
        return
    }
    if !DoCast()
        return
    if !Alive()
        return
    if !WaitForBite() {
        BotState.biteMisses += 1
        ; First missed bite: the view may have been moved (boss event, teleport, knockback),
        ; so re-establish the NPC anchor (camera + position) before casting again.
        if (BotState.biteMisses == 1 && Cfg.anchor && Alive()) {
            LogMsg("[reanchor] no bite - re-establishing the NPC anchor (view may have shifted)")
            if !EstablishAnchor()
                Halt("re-anchor failed after a missed bite")
            return
        }
        if (BotState.biteMisses >= 2 && Alive()) {
            BotState.biteMisses := 0
            ReadBaitLine()
            if (BotState.bait > 0) {
                LogMsg("[bait] two casts got no bite, but the game still shows x" . BotState.bait . " - keeping the count")
            } else {
                SetBait(0)
                LogMsg("[bait] two casts in a row got no bite and no bait is shown - assuming the bait ran out")
            }
        }
        return
    }
    BotState.biteMisses := 0
    if !Alive()
        return
    if Reel() {
        DismissCatch()
    } else if Alive() {
        ClearNpcRange("no reel bar after a bite")
    }
    WaitBarClear()
}

RunBot() {
    BotState.running := true
    BotState.paused := false
    BotState.diedHudArmed := false
    BotState.diedHudSeen := false
    BotState.diedHudReads := 0
    BotState.diedHudMisses := 0
    ResetStats()
    SyncSettings()
    profile := ApplyResolution()
    RefreshGame()
    NoteResponse()
    LogMsg("[start] control loop started - profile " . profile . ", game area "
        . BotState.win.w . "x" . BotState.win.h)
    CheckResolution()
    SetStatus("Running")

    if !WinExist(ROBLOX_WIN) {
        LogMsg("[start] Roblox window not found - start Roblox first")
        FinishRun()
        return
    }
    FocusGame()
    Wait(0.15)

    BotState.shiftLock := false
    BotState.shiftVerified := false
    BotState.rodEquipped := true
    BotState.atNpc := true
    BotState.sinceSell := 0
    BotState.flicked := false
    BotState.witness := ""
    BotState.bait := (Cfg.baitNow > 0) ? Min(90, Cfg.baitNow) : -1 ; tracked whenever a count is given
    BotState.meterFull := 0
    BotState.zoomedAt := -1
    BotState.biteMisses := 0
    BotState.buyFailures := 0
    BotState.npcHits := 0
    BotState.stopReason := ""
    BotState.stopShot := ""
    BotState.levelStart := -1
    BotState.levelLast := -1
    BotState.levelRead := Now()
    BotState.reportDue := false
    BotState.questState := "unknown"
    BotState.questType := ""
    BotState.questRarity := ""
    BotState.questTimed := false
    BotState.questRead := 0.0
    BotState.questMiss := 0
    BotState.questNextTry := 0.0
    BotState.questAcceptedAt := 0.0
    BotState.questFails := 0
    BotState.questStreak := 0
    BotState.questHandFails := 0
    BotState.questSkillUses := 0
    BotState.questProg := ""
    BotState.questResumed := false
    BotState.questSig := ""
    BotState.questEntry := ""
    BotState.questObjective := ""
    QuestResume()
    MeterReset()

    LogMsg("[start] npc=" . Cfg.npc . " bait=" . CurBait().name . " buyBait=" . (Cfg.buyBait ? "on" : "OFF") . " baitNow=" . Cfg.baitNow
        . " baitPerPurchase=" . Cfg.baitPer . " sell=" . (Cfg.sellOn ? "on" : "OFF")
        . " sellEvery=" . Cfg.sellEvery . " zoomLock=" . (Cfg.zoomLock ? "on" : "off")
        . " perfect=" . (Cfg.perfect ? "on" : "off"))
    if (Cfg.buyBait && Cfg.baitNow <= 0)
        LogMsg("[start] bait count not given: restocking happens only after 2 casts in a row get no bite")
    if Cfg.gameFast
        ApplyGameSettings()
    startOk := true
    if Cfg.anchor
        startOk := EstablishAnchor()
    else
        startOk := EnterFishingStance()
    if !startOk {
        BotState.stopReason := "start-up failed (NPC anchor / Shift Lock) - see the log"
        BotState.stopShot := ErrorShot("startup")
        if (BotState.stopShot != "")
            LogMsg("[error] game screenshot saved: " . BotState.stopShot)
        FinishRun()
        return
    }
    ; Establish the exact-text baseline only after NPC setup and dialogue are done.
    ReadBaitLine(true)
    BotState.diedHudArmed := true
    if BotState.diedHudSeen
        LogMsg("[death] recent-death badge was already present at fishing start; monitoring new appearances")
    UpdateLevel()
    HookStartMsg()

    while Alive() {
        try {
            Cycle()
        } catch as err {
            Mouse.Hold(false)
            LogMsg("[warn] cycle error: " . err.Message . " (line " . err.Line . ") - recovering")
            ReportError("cycle", "Cycle error", err.Message . "  (line " . err.Line . ")", 60)
            Wait(Timing.errorRecovery)
        }
    }
    FinishRun()
}

ResetStats() {
    BotStats.casts := 0
    BotStats.bites := 0
    BotStats.catches := 0
    BotStats.escapes := 0
    BotStats.missedBar := 0
    BotStats.biteTimeouts := 0
    BotStats.sales := 0
    BotStats.purchases := 0
    BotStats.baitBought := 0
    BotStats.spent := 0
    BotStats.income := 0
    BotStats.unreadable := 0
    BotStats.levels := 0
    BotStats.chests := 0
    BotStats.quests := 0
    BotStats.questsAcc := 0
    BotStats.questsFail := 0
    BotStats.lastUp := 0.0
    BotStats.started := Now()
    Hist.Length := 0
    Hist.Push([0, 0, 0, 0])
    PrevHour.valid := false
    ResetHour()
}

FinishRun() {
    BotState.running := false
    try Mouse.Hold(false)
    BotState.shiftVerified := false
    mins := Max(0.001, (Now() - BotStats.started) / 60)
    LogMsg("[stop] casts " . BotStats.casts . " | bites " . BotStats.bites
        . " | catches " . BotStats.catches . " | escapes " . BotStats.escapes
        . " | sales " . BotStats.sales . " | " . Round(BotStats.catches / mins, 1) . " fish/min")
    BotStats.lastUp := Now() - BotStats.started
    SetStatus("Idle")
    QuestSave(true)
    HookStopMsg()
}

ToggleRun(*) {
    if BotState.running {
        BotState.running := false
        BotState.paused := false
        LogMsg("[stop] stopping...")
        return
    }
    BotState.running := true
    SetTimer(RunBot, -10)
}

ToggleDebug(*) {
    BotState.debug := !BotState.debug
    LogMsg("[debug] log file " . (BotState.debug ? "ON -> " . LOG_FILE : "OFF"))
}
