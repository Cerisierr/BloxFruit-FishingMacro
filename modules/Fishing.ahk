; ============================================================================
;  FISHING ENGINE
; ============================================================================
DoCast() {
    if !FishingShiftReady() {
        Halt("Shift Lock not confirmed - stopping before a free-cursor cast")
        return false
    }
    ; Never cast into a live minigame.
    if FindBar() {
        LogMsg("[cast] a minigame is still running - not casting")
        deadline := Now() + Timing.maxReel
        while (Alive() && Now() < deadline && FindBar())
            Sleep(100)
        return false
    }
    if (Cfg.zoomLock && Cfg.zoomEvery > 0 && BotStats.casts > 0
        && Mod(BotStats.casts, Cfg.zoomEvery) == 0 && BotState.zoomedAt != BotStats.casts) {
        BotState.zoomedAt := BotStats.casts
        ZoomReset()
    }

    ; Give Roblox a short moment to register the previous cast before relaunching.
    Wait(Timing.recastDelay)
    if !Alive()
        return false

    ; Perfect cast = release when the charge bar is FULL. The bar bounces
    ; (fills, then drains again), so it is measured against the track height every
    ; tick and released the moment it reaches the threshold on the way up. If the
    ; first rise is missed, it simply waits for the next one (up to castHold s).
    perfectMode := PerfectOn()
    if !perfectMode
        return DoQuickCast()
    thr := Min(100, Max(QuestPerfectActive() ? 97 : 60, Cfg.perfectPct)) / 100.0
    lead := Timing.releaseLead                           ; RDP shows the bar late: look ahead by that delay
    if (Rdp.on && lead <= 0)
        lead := Rdp.castLead
    Loop Timing.maxCastAttempts {
        if !Alive()
            return false
        attempt := A_Index
        MeterReset()
        Mouse.Hold(true)
        t0 := Now()
        deadline := t0 + Timing.castHold
        charged := false, perfect := false, byPlateau := false
        level := 0.0, peak := 0.0
        prev := 0.0, prevT := 0.0, rate := 0.0
        topSince := 0.0, topRef := 0.0
        lost := 0

        while (Alive() && Now() < deadline) {
            lv := MeterRead()
            tn := Now()
            if (lv >= 0) {
                lost := 0
                charged := true
                level := lv
                if !perfectMode {                        ; classic: hold a beat, release
                    Wait(Min(0.15, Timing.castHold))
                    break
                }
                if (prevT > 0.0 && tn > prevT)
                    rate := rate * 0.6 + ((lv - prev) / (tn - prevT)) * 0.4    ; fill per second
                prev := lv
                prevT := tn
                if (lv > peak)
                    peak := lv
                if (lv + Max(0.0, rate) * lead >= thr) {
                    perfect := true
                    break
                }
                ; A bar that saturates just under the threshold sits still at the top.
                if (lv >= 0.85) {
                    if (topSince == 0.0 || lv > topRef + 0.01) {
                        topSince := tn
                        topRef := lv
                    } else if (lv >= topRef - 0.01 && tn - topSince >= 0.12) {
                        perfect := true
                        byPlateau := true
                        break
                    }
                } else {
                    topSince := 0.0
                    topRef := 0.0
                }
            } else if (charged && ++lost >= 6) {
                break                                    ; the bar is gone: the cast already left
            }
            Sleep(1)
        }
        Mouse.Hold(false)
        elapsed := Now() - t0
        MeterReset()

        if charged {
            if perfectMode
                LogMsg("[cast] released at " . Round(level * 100) . "% (peak " . Round(peak * 100)
                    . "%) after " . Round(elapsed, 2) . " s"
                    . (perfect ? (byPlateau ? " - bar saturated" : " - top reached")
                               : " - never reached " . Round(thr * 100) . "%, released anyway")
                    . (QuestPerfectActive() ? "  [perfect-cast quest]" : ""))
            BotState.npcHits := 0
            Tally("casts")
            LogMsg("[cast] #" . BotStats.casts . (attempt == 1 ? "" : " (attempt " . attempt . ")"))
            Wait(Timing.castSettle)
            return true
        }
        if !Alive()
            break
        ; A swallowed press may have hit the NPC instead: close it, step away.
        if EscapeDialogue()
            continue
        LogMsg("[cast] no charge - retrying (" . attempt . "/" . Timing.maxCastAttempts . ")")
        Wait(Timing.castRetryGap)
    }
    Tally("casts")
    LogMsg("[cast] #" . BotStats.casts . " unverified - continuing")
    Wait(Timing.castSettle)
    return false
}

; Perfect cast OFF: no need to find or read the charge meter (the search is what made the
; cast slow). Press, hold a short fixed time, release. A swallowed press (it hit the NPC)
; shows as an open dialogue, so that is the only check.
DoQuickCast() {
    Loop Timing.maxCastAttempts {
        if !Alive()
            return false
        attempt := A_Index
        Mouse.Tap(Timing.quickHold)
        Wait(0.15)
        if EscapeDialogue()
            continue
        BotState.npcHits := 0
        Tally("casts")
        LogMsg("[cast] #" . BotStats.casts . (attempt == 1 ? "" : " (attempt " . attempt . ")") . " - quick cast")
        Wait(Timing.quickSettle)
        return true
    }
    Tally("casts")
    LogMsg("[cast] #" . BotStats.casts . " unverified - continuing")
    Wait(Timing.quickSettle)
    return false
}

WaitForBite() {
    BotState.biteBase := 0
    BotState.biteBaseN := 0
    if Rdp.on
        BiteBaseline()
    if BotState.biteBaseN
        LogMsg("[bite] " . BotState.biteBaseN . " marker-coloured cells already on screen - ignored")
    fast := FastBiteOn()                       ; Fast bite setting, or forced on by a "perfect reaction" quest
    minHold := fast ? 0.04 : 0.15              ; le "!" doit rester visible au moins ce temps (s)
    deadline := Now() + Timing.maxWaitBite
    firstSeen := 0
    while (Alive(true) && Now() < deadline) {
        if BiteNow() {
            if (firstSeen == 0)
                firstSeen := Now()
            if (Now() - firstSeen >= minHold) {
                if !fast
                    Sleep(Round(Timing.biteClickDelay * 1000))
                Mouse.Tap()
                BotStats.bites += 1
                NoteResponse()
                LogMsg("[bite] hooked (" . BotState.biteInfo . ")")
                DebugShot("hooked", "red ! marker confirmed; hook tap sent")
                Wait(Timing.hookedDelay)                ; let the hooked state register before looking for the reel bar
                return true
            }
        } else {
            firstSeen := 0
        }
        Sleep(fast ? 1 : 8)
    }
    BotStats.biteTimeouts += 1
    LogMsg("[bite] timed out, recasting (" . BotState.biteInfo . ")")
    return false
}

; Drive the minigame. Returns true if it ran through to the end.
Reel(spend := true) {
    geo := 0
    deadline := Now() + Timing.biteToBar
    while (Alive() && Now() < deadline) {
        geo := FindBar()
        if geo
            break
        Sleep(20)
    }
    if !geo {
        BotStats.missedBar += 1
        LogMsg("[reel] bar never appeared")
        shot := DebugShot("reel-no-bar", "Hooked confirmed but no reel bar appeared before timeout")
        p := BiteDumpFrame()
        if (p != "")
            LogMsg("[bite] possible FALSE HOOK - frame that fired it: " . p)
        HookBarNeverAppeared(p != "" ? p : shot, p != "")
        return false
    }
    if (spend && BotState.bait > 0) {                    ; bait is only used up once the minigame really starts
        SetBait(BotState.bait - 1, BotState.bait > 90)
        LogMsg("[bait] " . BotState.bait . " left")
    }
    geo := AcquireWidest(geo)
    tw := geo.tw
    LogMsg("[reel] track width locked at " . tw . " px")

    zoneWRef := 0
    Loop 6 {
        s0 := ReadBar(geo, 0, 0)
        if s0
            zoneWRef := Max(zoneWRef, s0.zr - s0.zl)
    }

    if QuestSkillWanted() {                              ; quest skill takes priority; avoid double-tapping
        QuestUseSkill()
    } else if Cfg.rodSkill {
        ; Let the game reject the skill while Power is empty. Trying on each
        ; reel avoids stale catch counts and uses it on the first ready fish.
        Keys.Tap(Keys.SKILLS["Z"], 0.08)
        LogMsg("[rod skill] Z attempted at reel start; Power availability is game-controlled")
    }

    reelCtl.Reset()
    chestMinW := Cfg.chest ? Floor(0.035 * tw) : 0
    chestUntil := 0.0, chestAt := -1.0, chestOn := false
    chestDone := []
    chestSeen := 0, chestSeenX := -1.0, chestGoneSince := 0.0
    progress := -1.0
    lostSince := 0.0
    stalling := false
    lastHold := false
    flicked := false
    timedOut := false
    t0 := Now()
    errSum := 0.0, driveTicks := 0, outTicks := 0, ticks := 0

    while Alive(true) {
        tn := Now()
        ticks++
        if (tn - t0 > Timing.maxReel) {
            timedOut := true
            break
        }
        st := ReadBar(geo, zoneWRef, chestMinW)
        if !st {
            if (lostSince == 0.0) {
                lostSince := tn
                ; If the progress strip went too, the fight is over: flick NOW,
                ; the catch card renders within a couple of frames.
                if (!ProgressPresent(geo) && !flicked && UseFlick()) {
                    FlickRod()
                    flicked := true
                }
            }
            if (tn - lostSince >= Timing.barLost) {
                if ProgressPresent(geo) {                ; zone hidden (chest / alarm)
                    if !stalling {
                        stalling := true
                        LogMsg("[reel] zone hidden - bar still up, keeping the last input")
                    }
                    Mouse.Hold(lastHold)                 ; keep pushing the way we were going
                    lostSince := 0.0
                    continue
                }
                break
            }
            continue
        }
        if stalling {
            stalling := false
            LogMsg("[reel] zone visible again")
        }
        lostSince := 0.0

        if (st.fl < 0)                                   ; fish unreadable: coast
            continue

        zoneC := ((st.zl + st.zr) / 2) / tw
        fishC := ((st.fl + st.fr) / 2) / tw
        zoneHalf := (st.zr - st.zl) / tw / 2
        target := fishC

        ; ---- treasure chests: park the zone on the remembered spot ----------
        if (chestUntil > 0.0 && tn < chestUntil && chestAt >= 0) {
            target := chestAt
            if (!chestOn && Abs(zoneC - chestAt) <= Max(zoneHalf, 0.02)) {
                chestOn := true
                chestUntil := tn + Timing.chestHold
                LogMsg("[chest] reached it - holding " . Timing.chestHold . " s")
            }
        } else if (chestUntil > 0.0) {
            chestUntil := 0.0
            reelCtl.Retarget()
            LogMsg(chestOn ? "[chest] collected, back to the fish"
                           : "[chest] could not reach it in time, back to the fish")
            if chestOn {
                Tally("chests")
                HookChest()
            }
            chestAt := -1.0
            chestOn := false
        } else if (Cfg.chest && st.cl >= 0 && chestDone.Length < Timing.chestMaxGrabs) {
            cx := ((st.cl + st.cr) / 2) / tw
            cw := (st.cr - st.cl) / tw
            ; A real chest is a small tile that stays put: seen on 4 reads in a row at the same spot,
            ; and not wider than 14 % of the track. One-off orange pixels (fish, scenery) are ignored.
            if (chestSeenX >= 0 && Abs(cx - chestSeenX) <= 0.03)
                chestSeen++
            else
                chestSeen := 1
            chestSeenX := cx
            fresh := true
            for d0 in chestDone {
                if (Abs(cx - d0) <= 0.03)
                    fresh := false
            }
            if (fresh && chestSeen >= 4 && cw <= 0.14 && (progress < 0 || progress >= Timing.chestMinProgress)) {
                chestAt := cx
                chestOn := false
                chestUntil := tn + Timing.chestHold + Timing.chestGrace
                chestDone.Push(cx)
                reelCtl.Retarget()
                LogMsg("[chest] grabbing at " . Round(cx, 2))
                target := cx
            }
        } else {
            chestSeen := 0
            chestSeenX := -1.0
        }
        ; Before the zone reaches it: if the chest is not on the track any more it was a false chest
        ; (or it already went), so go back to the fish. Once the zone sits on it, the normal hold applies.
        if (chestUntil > 0.0 && tn < chestUntil && chestAt >= 0 && !chestOn) {
            if (st.cl >= 0 && Abs(((st.cl + st.cr) / 2) / tw - chestAt) <= 0.06) {
                chestGoneSince := 0.0
            } else {
                if (chestGoneSince == 0.0)
                    chestGoneSince := tn
                if (tn - chestGoneSince >= 0.8) {
                    LogMsg("[chest] it is not on the track any more (false chest) - back to the fish")
                    chestUntil := 0.0
                    chestAt := -1.0
                    chestGoneSince := 0.0
                    reelCtl.Retarget()
                    target := fishC
                }
            }
        } else {
            chestGoneSince := 0.0
        }

        d := reelCtl.Step(tn, zoneC, target, zoneHalf)
        Mouse.Hold(d.hold)
        lastHold := d.hold

        if !(chestUntil > 0.0 && tn < chestUntil) {
            ae := Abs(d.err)
            errSum += ae
            driveTicks++
            if (ae > Max(zoneHalf, 0.000001))
                outTicks++
        }
        ; The status label can cover the green strip, so don't let a partial
        ; read skew the escape estimate while still using the fish/zone control.
        if !DeathRecentlyHud() {
            p := ReadProgress(geo)
            if (p >= 0)
                progress := p
        }
    }

    Mouse.Hold(false)
    if !BotState.running
        return false
    elapsed := Now() - t0
    if timedOut {
        LogMsg("[reel] gave up after " . Round(elapsed, 1) . " s (bar never cleared); recasting")
        return false
    }
    BotState.flicked := flicked

    ; Losing the bar is not proof of a catch: watch briefly for it coming back.
    confirmEnd := Now() + Timing.catchConfirm
    while (Alive() && Now() < confirmEnd) {
        if FindBar() {
            LogMsg("[reel] bar came back - still fishing, not a catch")
            return false
        }
        Sleep(30)
    }

    escaped := (progress >= 0 && progress < 0.35)
    BotState.lastEscaped := escaped
    avgErr := driveTicks ? errSum / driveTicks : 0.0
    outPct := driveTicks ? 100.0 * outTicks / driveTicks : 0.0
    LogMsg("[reel] done in " . Round(elapsed, 2) . " s at " . Round(ticks / Max(elapsed, 0.001))
        . " Hz | accel " . Round(reelCtl.accel, 2) . " | err avg " . Round(avgErr * 100, 1)
        . "% | outside " . Round(outPct) . "%"
        . (progress >= 0 ? " | progress " . Round(progress * 100) . "%" : ""))
    if escaped {
        Tally("escapes")
        LogMsg("[reel] the fish got away")
    }
    NoteResponse()
    return true
}

; The fast "flick" trick hides the Species/Weight card, so it is off while the
; catch screenshot is wanted (the card has to be on screen to be photographed).
CatchShotOn() {
    return HookReady() && Cfg.hkCatch && Cfg.hkCatchShot
}

UseFlick() {
    return Cfg.flick && !CatchShotOn()
}

DismissCatch() {
    shot := ""
    if UseFlick() {
        if !BotState.flicked
            FlickRod()
        BotState.flicked := false
    } else {
        ; Fallback: wait for the Species/Weight card, then click it away twice.
        Wait(Timing.popupDelay)
        if (CatchShotOn() && !BotState.lastEscaped)
            shot := CatchShot()
        Mouse.Tap()
        Wait(Timing.catchClickGap)
        Mouse.Tap()
    }
    if BotState.lastEscaped {
        LogMsg("[catch] none - that one escaped; recasting")
    } else {
        Tally("catches")
        BotState.sinceSell += 1
        NoteResponse()
        LogMsg("[catch] #" . BotStats.catches . " - recasting")
        HookCatch(shot)
    }
    ClearRecipeNote()                                    ; the only popup that never fades
    if !UseFlick()
        Wait(Timing.catchSettle)
}

WaitBarClear() {
    deadline := Now() + Timing.barClear
    while (Alive() && Now() < deadline) {
        if !FindBar()
            return
        Sleep(30)
    }
}

; Reads "Selected Bait: <name> xN" and syncs the tracked count to what the game shows.
ReadBaitLine(baseline := false) {
    ; One OCR crop reads both the exact recent-death message and selected bait.
    r := SubRect(BotState.win, Regions.diedHud)
    path := TMP_DIR . "\\bait_line.png"
    if !PngSave(r.x, r.y, r.w, r.h, path) {
        if baseline {
            BotState.diedHudVisible := false
            BotState.diedHudReads := 0
            BotState.diedHudMisses := 0
            BotState.diedHudSeen := false
        }
        return
    }
    txt := OcrFile(path)
    compact := StrLower(RegExReplace(txt, "[^a-z]"))
    deathFound := InStr(compact, "diedrecently") && InStr(compact, "pvpdisabled")
    if baseline {
        BotState.diedHudReads := deathFound ? 2 : 0
        BotState.diedHudMisses := 0
        BotState.diedHudVisible := deathFound
        BotState.diedHudSeen := deathFound
    } else {
        if deathFound {
            BotState.diedHudReads += 1
            BotState.diedHudMisses := 0
            BotState.diedHudVisible := BotState.diedHudReads >= 2
        } else {
            BotState.diedHudReads := 0
            BotState.diedHudMisses += 1
        }
        if (BotState.diedHudMisses >= 3) {
            BotState.diedHudVisible := false
            BotState.diedHudSeen := false
        }
    }
    if !RegExMatch(txt, "i)Bait[^\r\n]*?[x" . Chr(0xD7) . "]\s*(\d{1,3})", &m)
        return
    n := Integer(m[1])
    if (n > 999)
        return
    if (n != BotState.bait) {
        LogMsg("[bait] game shows x" . n . " (tracked " . BotState.bait . ")")
        SetBait(n, true)
    }
}

TogglePause(*) {
    if !BotState.running
        return
    BotState.paused := !BotState.paused
    LogMsg(BotState.paused ? "[pause] paused - press Resume or F3" : "[pause] resumed")
    try Ui.btnPause.Text := BotState.paused ? "Resume  (F3)" : "Pause  (F3)"
}
