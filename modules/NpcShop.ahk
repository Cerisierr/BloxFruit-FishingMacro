; ============================================================================
;  SHOP  (NPC dialogue, bait, sell)
; ============================================================================
; A real NPC dialogue = dark button stack AND the yellow name banner. Dark
; scenery alone (night sea, sky) or yellow clothes alone can never satisfy both.
; Fixed click pixels of the Craft window, measured on real screenshots, per resolution
; profile (offset from the top-left of the game area). No fractions, no image comparison.
CRAFT_PX := Map(
    "2560x1440", {plus: [1642, 738], craft: [1280, 917], close: [1702, 386]}
  , "1920x1080", {plus: [1232, 554], craft: [960, 688],  close: [1277, 290]}
  ; 1366x768: NOT measured - scaled from 1920x1080 by 0.711. Check with a screenshot.
  , "1366x768", {plus: [877, 394], craft: [683, 489], close: [909, 206]}
)

; Absolute screen position of a Craft-window pixel for the active profile.
CraftPx(name) {
    key := BotState.resW . "x" . BotState.resH
    t := CRAFT_PX.Has(key) ? CRAFT_PX[key] : CRAFT_PX["1920x1080"]
    return {x: BotState.win.x + t.%name%[1], y: BotState.win.y + t.%name%[2]}
}

; Click a fixed pixel and report where the cursor really ended up.
ClickPx(name, holdSec := 0.12) {
    p := CraftPx(name)
    MouseMove(p.x, p.y, 0)                               ; first jump, then the normal nudged move + click
    Sleep(80)
    Mouse.ClickAt(p.x, p.y, 0.30, holdSec)
    MouseGetPos(&mx, &my)
    off := (Abs(mx - p.x) > 3 || Abs(my - p.y) > 3)
    LogMsg("[click] " . name . " target " . p.x . "," . p.y . " cursor " . mx . "," . my
        . (off ? "  <-- CURSOR MISSED THE TARGET" : ""))
    return p
}

; The Craft window is checked explicitly where it is expected (BuyBait,
; RecoverDialogue), never used to guess that a dialogue is open.
DialogueState() {
    p := MenuPanels().Length
    h := p >= 2 ? DialogueHeader() : false
    return {panels: p, header: h, on: (p >= 2 && h)}
}

InDialogue() {
    return DialogueState().on
}

SetRod(equipped) {
    if (BotState.rodEquipped == equipped)
        return
    Keys.Tap(Keys.Digit(Cfg.rodSlot))
    BotState.rodEquipped := equipped
    Wait(ShopCfg.afterRod)
}

; Unequip + re-equip right after a catch: the Species/Weight card never shows.
FlickRod() {
    sc := Keys.Digit(Cfg.rodSlot)
    if Cfg.slowFlick {
        Wait(Timing.flickSlowDelay)
        Keys.Tap(sc)
        Wait(Timing.flickSlowGap)
        Keys.Tap(sc)
    } else {
        Keys.Tap(sc)
        Sleep(Round(Timing.flickGap * 1000))
        Keys.Tap(sc)
    }
    Wait(Timing.flickSettle)
}

ShiftCentered(x, y) {
    win := BotState.win
    cx := win.x + win.w // 2
    cy := win.y + win.h // 2
    tol := Max(24, Round(Min(win.w, win.h) * 0.03))
    return Abs(x - cx) <= tol && Abs(y - cy) <= tol
}

; Shift lock is a toggle, so drive it to a known state and PROVE it: the OS
; cursor must snap from away-from-centre to centre.
SetShiftLock(on) {
    if (BotState.shiftLock == on)
        return (!on || BotState.shiftVerified)
    win := BotState.win
    cx := win.x + win.w // 2
    cy := win.y + win.h // 2
    bx := 0, by := 0
    if on {
        MouseGetPos(&bx, &by)
        if ShiftCentered(bx, by) {                       ; make the snap observable
            MouseMove(cx + Round(220 * BotState.sc), cy + Round(160 * BotState.sc), 0)
            Sleep(120)
            MouseGetPos(&bx, &by)
        }
    }
    Keys.Tap(Keys.SC_LSHIFT, 0.10)
    BotState.shiftLock := on
    Wait(ShopCfg.afterShift)
    if !on {
        BotState.shiftVerified := true
        return true
    }
    ax := 0, ay := 0
    MouseGetPos(&ax, &ay)
    verified := ShiftCentered(ax, ay) && !ShiftCentered(bx, by)
    BotState.shiftVerified := verified
    if verified {
        LogMsg("[input] Shift Lock ON - centre cursor confirmed")
        return true
    }
    BotState.shiftLock := false
    LogMsg("[input] Could not verify Shift Lock (before=" . bx . "," . by
        . " after=" . ax . "," . ay . " centre=" . cx . "," . cy
        . ") - refusing to fish. Check Roblox focus, the Shift Lock Switch setting, "
        . "and leave Shift Lock OFF before pressing F2.")
    return false
}

FishingShiftReady() {
    if !(BotState.shiftLock && BotState.shiftVerified)
        return false
    MouseGetPos(&mx, &my)
    still := ShiftCentered(mx, my)
    BotState.shiftVerified := still
    if !still
        BotState.shiftLock := false
    return still
}

; During an accidental NPC dialogue the cached Shift Lock state can be stale.
; Disable the remembered state, then use a tiny mouse move to verify that the
; dialogue cursor is free before any menu click (large probes rotate the camera).
EnsureShiftLockOff() {
    win := BotState.win
    cx := win.x + win.w // 2
    cy := win.y + win.h // 2
    probeX := cx + 8
    if BotState.shiftLock
        SetShiftLock(false)
    MouseGetPos(&mx, &my)
    if !ShiftCentered(mx, my) {
        BotState.shiftLock := false
        BotState.shiftVerified := false
        LogMsg("[input] cursor is free for NPC dialogue controls; Shift Lock is already off")
        return true
    }
    Loop 2 {
        MouseMove(probeX, cy, 0)
        Sleep(50)
        MouseGetPos(&mx, &my)
        if (Abs(mx - cx) >= 4) {
            BotState.shiftLock := false
            BotState.shiftVerified := false
            LogMsg("[input] mouse cursor released for NPC dialogue controls")
            return true
        }
        LogMsg("[input] cursor still locked during NPC dialogue; toggling Shift Lock off (" . A_Index . "/2)")
        Keys.Tap(Keys.SC_LSHIFT, 0.10)
        Wait(ShopCfg.afterShift)
        MouseMove(probeX, cy, 0)
        Sleep(50)
        MouseGetPos(&mx, &my)
        if (Abs(mx - cx) >= 4) {
            BotState.shiftLock := false
            BotState.shiftVerified := false
            LogMsg("[input] mouse cursor released for NPC dialogue controls")
            return true
        }
    }
    BotState.shiftLock := true
    BotState.shiftVerified := false
    LogMsg("[input] could not release the Shift Lock cursor for NPC dialogue controls")
    return false
}

; Same camera distance every time = same meter size = repeatable perfect casts:
; wheel all the way in (first-person limit), then out by a fixed notch count.
ZoomReset() {
    if (!Cfg.zoomLock || !BotState.running)
        return
    MouseGetPos(&mx, &my)
    if !ShiftCentered(mx, my) {
        win := BotState.win
        MouseMove(win.x + win.w // 2, win.y + win.h // 2, 0)
        Sleep(40)
    }
    Loop 40 {
        Click("WheelUp")
        Sleep(18)
    }
    Wait(0.15)
    Loop Max(0, Cfg.zoomOut) {
        Click("WheelDown")
        Sleep(60)
    }
    Wait(0.35)
    MeterReset()
    LogMsg("[camera] zoom locked: all the way in, then out " . Cfg.zoomOut . " notches")
}

; afterNpc = true when we have just talked to the NPC. The dialogue leaves the
; camera at a known pitch, so tilting down once here is repeatable; tilting at any
; other time would add up and end with the camera looking at the ground.
EnterFishingStance(afterNpc := false) {
    if !SetShiftLock(true)
        return false
    BotState.atNpc := false
    ZoomReset()
    if afterNpc
        TiltCameraDown()
    if afterNpc
        DebugShot("camera-after-npc", "NPC dialogue closed; Shift Lock and zoom restored")
    return true
}

; Real relative mouse movement (Shift Lock turns it into camera rotation), in small steps.
TiltCameraDown() {
    n := Cfg.tiltPx
    if (n <= 0 || !BotState.running || !BotState.shiftLock)
        return
    left := n
    while (left > 0 && Alive()) {
        step := Min(8, left)
        DllCall("mouse_event", "UInt", 0x0001, "Int", 0, "Int", step, "UInt", 0, "UPtr", 0)
        left -= step
        Sleep(14)
    }
    Wait(0.25)
    LogMsg("[camera] tilted down " . n . " px (after the NPC)")
}

; Wait until a complete, settled menu page is showing.
WaitMenuPage(page, timeout) {
    expected := PageRows(page)
    poll := Max(0.03, ShopCfg.poll)
    deadline := Now() + timeout
    if (BotState.witness != "" && BotState.witness.page == page) {
        p := MenuPanels()
        if (MenuPageVisible(page, p) && PanelSig(p) == BotState.witness.sig)
            return true
        BotState.witness := ""
    }
    stableSig := "", stableSince := 0.0
    while (Now() < deadline) {
        if !Alive()
            return false
        p := MenuPanels()
        sig := PanelSig(p)
        if MenuPageVisible(page, p) {
            tn := Now()
            if (sig != stableSig) {
                stableSig := sig
                stableSince := tn
            } else if (tn - stableSince >= ShopCfg.pageSettle) {
                BotState.witness := {page: page, sig: sig}
                return true
            }
        } else {
            stableSig := ""
            stableSince := 0.0
        }
        Wait(poll)
    }
    return false
}

; A partial outline scan is common over the translucent NPC menu. For the root
; page, the gold dialogue banner plus at least two stable menu rows is enough
; to establish that the interaction opened; clicks still use calibrated row
; coordinates unless the entire expected stack was detected.
MenuPageVisible(page, panels) {
    if (panels.Length == PageRows(page))
        return true
    return (page == "root" && panels.Length >= 2 && DialogueHeader())
}

; Click a named action (page + role) using the live stack, with the calibrated
; ordinal dots as a last resort.
ClickMenuAction(page, action) {
    BotState.witness := ""
    index := MenuRow(page, action)
    panels := MenuPanels()
    if (panels.Length == PageRows(page)) {
        chosen := index < 0 ? panels.Length + index + 1 : index
        if (chosen >= 1 && chosen <= panels.Length) {
            Mouse.ClickAt(panels[chosen].x, panels[chosen].y)
            return
        }
    }
    fr := (index == 1) ? Points.menu1 : (index == 2) ? Points.menu2
        : (index == 3) ? Points.menu3 : Points.menuLast
    p := PtAbs(fr)
    Mouse.ClickAt(p.x, p.y)
}

WaitUntil(pred, timeout) {
    deadline := Now() + timeout
    while (Now() < deadline) {
        if !Alive()
            return false
        if pred()
            return true
        Wait(ShopCfg.poll)
    }
    return false
}

; Retry one named action only from a stable page, observing its result.
ClickActionUntil(page, action, done, tries, waitSec, nextPage := "") {
    if !WaitMenuPage(page, waitSec)
        return false
    Loop tries {
        if !Alive()
            return false
        if (nextPage == "" && done())
            return true
        ClickMenuAction(page, action)
        if (nextPage != "") {
            if WaitMenuPage(nextPage, waitSec)
                return true
        } else if WaitUntil(done, waitSec) {
            return true
        }
    }
    return (nextPage != "") ? false : done()
}

ClearRecipeNote() {
    if !LearnUp()
        return false
    LogMsg("[catch] new-recipe note - clicking Learn")
    was := BotState.shiftLock
    SetShiftLock(false)
    p := PtAbs(Points.learn)
    Mouse.ClickAt(p.x, p.y)
    Wait(0.6)
    if was
        SetShiftLock(true)
    return true
}

OpenNpcDialogue() {
    ClearRecipeNote()
    ds := DialogueState()
    if ds.on {
        SetShiftLock(false)
        LogMsg("[shop] dialogue already visible (panels=" . ds.panels . " banner=" . (ds.header ? 1 : 0)
            . ") - no Interact click")
        if WaitMenuPage("root", ShopCfg.rootTimeout) {
            BotState.atNpc := true
            return true
        }
        LogMsg("[shop] dialogue visible but root rows not confirmed")
        return false
    }
    SetRod(false)
    DebugShot("camera-before-npc", "about to open NPC dialogue")
    ip := PtAbs(Points.interact)

    Loop ShopCfg.maxApproach + 1 {
        attempt := A_Index
        if (attempt > 1) {
            LogMsg("[shop] no dialogue - S range probe " . (attempt - 1) . "/" . ShopCfg.maxApproach)
            Keys.Tap(Keys.SC_S, ShopCfg.walkBackTap)
            Wait(ShopCfg.approachWait)
        }
        if !Alive()
            return false
        SetShiftLock(false)
        MouseMove(ip.x, ip.y, 0)
        Wait(0.25)
        BotState.witness := ""
        Mouse.ClickAt(ip.x, ip.y)
        timeout := (attempt == 1) ? ShopCfg.directTimeout : ShopCfg.dialogTimeout
        if WaitMenuPage("root", timeout) {
            BotState.atNpc := true
            return true
        }
        ds := DialogueState()
        if ds.on {                                        ; dialogue opened; do not walk/click Interact again
            LogMsg("[shop] NPC dialogue is open (" . ds.panels . " rows detected); waiting for a stable root menu")
            if WaitMenuPage("root", ShopCfg.rootTimeout) {
                BotState.atNpc := true
                return true
            }
            LogMsg("[shop] dialogue banner is visible but menu rows are incomplete")
            return false
        }
    }
    BotState.atNpc := false
    return false
}

; Click the bottom row (Back / Nevermind) of the NPC stack. The button under the
; cursor changes colour on hover and can drop out of the panel detection, which
; used to make "the last detected panel" a different row (e.g. Job Stats). Now:
;   * if the stack is complete, or the lowest detected panel is where the bottom
;     row should be, that panel is clicked;
;   * otherwise (a row is missing) the calibrated bottom-row point is clicked;
;   * every retry waits longer over the button and holds the press longer, and
;     attempts 3 and 5 always use the fixed point, so one wrong reading cannot
;     repeat forever. From attempt 2 the cursor is first moved away to wake the
;     game's hover state (remote desktop drops small mouse moves).
NevermindClick(attempt := 1) {
    if (!Rdp.on && attempt == 1) {                     ; normal desktop: first try is the original click
        ClickMenuAction("root", "nevermind")
        return
    }
    win := BotState.win
    expected := PageRows("root")
    settle := Min(0.50, 0.15 + 0.15 * (attempt - 1))
    hold := Min(0.20, 0.06 + 0.06 * (attempt - 1))
    panels := MenuPanels()
    n := panels.Length
    fixed := PtAbs(Points.menuLast)
    pt := fixed
    how := "fixed point"
    if (n >= 2 && !(attempt >= 3 && Mod(attempt, 2) == 1)) {
        low := panels[n]
        if (n >= expected || Abs(low.y - fixed.y) <= win.h * 0.04) {
            pt := {x: low.x, y: low.y}
            how := "bottom row of " . n . " panels"
        } else {
            how := "fixed point (only " . n . "/" . expected . " panels, lowest one too high)"
        }
    }
    if (attempt >= 2) {
        MouseMove(win.x + win.w // 2, win.y + win.h // 2, 0)
        Sleep(80)
    }
    BotState.witness := ""
    LogMsg("[shop] nevermind/back attempt " . attempt . ": " . how . " at " . pt.x . "," . pt.y)
    Mouse.ClickAt(pt.x, pt.y, settle, hold)
}

; Leave the dialogue. Fisherman: Back -> Nevermind, waiting for each page.
; Angler (or any layout where the bait page and the root page look alike): the
; bottom row is "Back" on the bait page and "Nevermind" on the root page, so
; clicking it repeatedly walks out either way.
LeaveDialogue(tries := 4) {
    Wait(ShopCfg.beforeLeave)
    if !WaitUntil(() => MenuPanels().Length >= 2, ShopCfg.rootTimeout)
        return !InDialogue()
    if (PageRows("bait") == PageRows("root"))
        return LeaveByBottomRow()
    if (MenuPanels().Length < PageRows("root")) {
        ClickMenuAction("bait", "back")
        if !WaitMenuPage("root", ShopCfg.rootTimeout)
            return false
    }
    Wait(ShopCfg.rootSettle)
    Loop tries {
        if !Alive()
            return true
        if (!InDialogue() && StaysClosed())
            return true
        NevermindClick(A_Index)
        if (WaitUntil(() => !InDialogue(), ShopCfg.nevermindRetry) && StaysClosed())
            return true
        if (MenuPanels().Length >= PageRows("root"))
            Wait(ShopCfg.afterBack)
    }
    if InDialogue()
        LogMsg("[shop] could not close the dialogue - stopping this shop route")
    return !InDialogue()
}

; The menu is "gone" only if it stays gone: between Back and the root page the button stack
; vanishes for a moment, which used to look like a closed dialogue (no Nevermind, the macro
; went fishing with the menu still coming up).
StaysClosed(secs := 0.9) {
    end := Now() + secs
    while (Now() < end) {
        if InDialogue() {
            LogMsg("[shop] the menu is still there (page change) - clicking again")
            return false
        }
        Wait(0.15)
    }
    return true
}

LeaveByBottomRow() {
    Loop 5 {
        if !Alive()
            return true
        if (!InDialogue() && StaysClosed())
            return true
        Wait(ShopCfg.pageSettle)
        NevermindClick(A_Index)
        if (WaitUntil(() => !InDialogue(), ShopCfg.nevermindRetry) && StaysClosed())
            return true
        Wait(ShopCfg.afterBack)
    }
    if InDialogue()
        LogMsg("[shop] could not close the dialogue - stopping this shop route")
    return !InDialogue()
}

; Best-effort exit from whatever dialogue page we are stuck on.
RecoverDialogue() {
    try {
        if CraftUp() {
            p := CraftPx("close")
            Mouse.ClickAt(p.x, p.y)
            Wait(0.5)
        }
        Loop 4 {
            if !Alive()
                break
            ; Shift Lock can recapture the pointer between menu retries. Never
            ; send a Nevermind click until the cursor has been released again.
            if !EnsureShiftLockOff() {
                LogMsg("[input] cursor was captured again before Nevermind attempt " . A_Index)
                break
            }
            NevermindClick(A_Index)
            Wait(0.7)
            if !InDialogue()
                break
        }
        Wait(ShopCfg.afterNevermind)
    }
    return !InDialogue()
}

EscapeDialogue() {
    if !InDialogue()
        return false
    LogMsg("[cast] accidental NPC dialogue after cast - ensuring the cursor is free before Nevermind")
    DebugShot("npc-accidental-open", "cast input opened an NPC dialogue; beginning recovery")
    if !EnsureShiftLockOff() {
        Halt("could not free the cursor to close the accidental NPC dialogue; no recast attempted", false)
        return true
    }
    if !RecoverDialogue() {
        Halt("accidental NPC dialogue stayed open; move farther from the NPC and restart", false)
        return true
    }
    SetRod(false)
    SetRod(true)
    BotState.atNpc := true
    EnterFishingStance(false)
    StepAwayFromNpc()
    ClearNpcRange("after accidental NPC dialogue", false)
    WalkToFishingEdge("after accidental NPC dialogue")
    if NpcLabelVisible() {
        DebugShot("npc-still-close", "Interact prompt remained after moving; stopping before another cast")
        Halt("still within NPC interaction range after dialogue recovery", false)
        return true
    }
    DebugShot("npc-accidental-closed", "dialogue closed, cursor free, and NPC range cleared")
    return true
}

; The cast click talked to the NPC again: we are standing too close. Each time
; this happens in a row, walk forward (W, away from the NPC) a little further:
; 0.07 s, 0.10 s, 0.13 s ... up to 0.30 s. The streak resets on a good cast.
StepAwayFromNpc() {
    BotState.npcHits += 1
    hold := Min(ShopCfg.stepAwayMax, ShopCfg.stepAwayTap + (BotState.npcHits - 1) * ShopCfg.stepAwayAdd)
    LogMsg("[cast] the cast talked to the NPC again (" . BotState.npcHits . "x) - stepping forward "
        . Round(hold * 1000) . " ms to get out of range")
    Keys.Tap(Keys.SC_W, hold)
    Wait(0.5)
}

; The NPC shows a floating "Interact" prompt whenever we are inside its range. Standing
; that close the NPC overlaps the character and the meter / bite / bar detection
; read the NPC's yellow coat and red bobber instead of the real ones.
NpcLabelVisible() {
    r := SubRect(BotState.win, Regions.npcLabel)
    path := TMP_DIR . "\interact.png"
    if !PngSave(r.x, r.y, r.w, r.h, path)
        return false
    txt := OcrFile(path)
    BotState.lastOcr := RegExReplace(txt, "\s+", " ")
    return RegExMatch(txt, "i)nter\s?a\s?c\s?t|intera") ? true : false
}

; If the "Interact" prompt is on screen, walk forward in small, growing steps until it is
; gone. Returns true when it had to move.
ClearNpcRange(why, walkEdge := true) {
    if !NpcLabelVisible()
        return false
    LogMsg("[npc] too close to the NPC (" . why . ") - the Interact prompt is showing, stepping forward")
    Loop 6 {
        if !Alive()
            return true
        hold := Min(0.40, 0.10 + (A_Index - 1) * 0.06)
        Keys.Tap(Keys.SC_W, hold)
        Wait(0.6)
        if !NpcLabelVisible() {
            LogMsg("[npc] out of range after " . A_Index . " step" . (A_Index == 1 ? "" : "s"))
            if walkEdge
                WalkToFishingEdge(why)
            return true
        }
    }
    LogMsg("[npc] still in range after 6 steps - move the character away from the NPC by hand")
    return true
}

; Walk a short, configurable distance from the NPC interaction circle toward the dock edge.
WalkToFishingEdge(why) {
    ticks := Min(40, Max(0, Cfg.dockWalk))
    if (ticks <= 0 || !BotState.running)
        return
    seconds := ticks / 10
    LogMsg("[position] walking " . Format("{:.1f}", seconds) . " s from the NPC circle toward the dock edge (" . why . ")")
    Keys.Tap(Keys.SC_W, seconds)
    Wait(0.25)
}

; One confirmed NPC dialogue is the position reset on F2.
EstablishAnchor() {
    Mouse.trace := true
    try ok := EstablishAnchorCore()
    catch as err {
        Mouse.trace := false
        throw err
    }
    Mouse.trace := false
    return ok
}

EstablishAnchorCore() {
    LogMsg("[start] opening NPC dialogue to establish fishing position")
    if !OpenNpcDialogue() {
        LogMsg("[start] NPC anchor failed - stand at the NPC on the edge of interaction range")
        return false
    }
    if !LeaveDialogue() {
        LogMsg("[start] NPC dialogue did not close")
        return false
    }
    Wait(ShopCfg.afterNevermind)
    SetRod(true)
    if !EnterFishingStance(true) {
        LogMsg("[start] Shift Lock did not engage")
        return false
    }
    ClearNpcRange("after the anchor")
    LogMsg("[start] NPC anchor confirmed")
    return Alive()
}

ShopFail(why, what) {
    ReportError(what . "-fail", "Problem: " . what . " failed", why, 20)   ; screenshot BEFORE the recovery moves the screen
    ds := DialogueState()
    LogMsg("[" . what . "] FAILED: " . why . " (screen: panels=" . ds.panels . " banner=" . (ds.header ? 1 : 0)
        . " craft=" . (CraftUp() ? 1 : 0) . ")")
    RecoverDialogue()
    SetRod(true)
    EnterFishingStance(true)
    ClearNpcRange("after failed " . what)
    return false
}

; Single place that changes the tracked bait count. Keeps the GUI field and the
; saved setting equal to the real count, so "Bait in inventory now" is always current.
SetBait(n, fromHud := false) {
    BotState.bait := fromHud ? Min(999, Max(0, n)) : Min(90, Max(0, n))
    Cfg.baitNow := (BotState.bait > 0) ? Min(90, BotState.bait) : 0
    try Ui.baitNow.Value := Cfg.baitNow
    SetTimer(SaveSettings, -1500)
}

BuyBait() {
    ok := BuyBaitRoute()
    if ok {
        BotState.buyFailures := 0
        BotState.moneyLast := -1                         ; money was spent: old baseline is stale
        SetBait(Min(90, Max(0, BotState.bait) + BotState.lastBought))
        LogMsg("[bait] topped up to " . BotState.bait)
        return
    }
    BotState.buyFailures += 1
    if (BotState.buyFailures >= 3)
        Halt("could not restock bait after 3 attempts")
}

; Buy Cfg.baitPer bait of the selected type. The craft window starts at one
; pack (10 bait) and each "+" adds another pack, so 40 bait = 3 "+" clicks.
BuyBaitRoute() {
    bait := CurBait()
    step := Max(1, ShopCfg.craftStep)
    ; The inventory holds 90 bait at most: only buy what still fits.
    room := 90 - Max(0, BotState.bait)
    want := Min(Cfg.baitPer, room)
    packs := want // step
    if (packs < 1) {
        LogMsg("[shop] inventory full (" . Max(0, BotState.bait) . "/90 bait) - nothing to buy")
        BotState.lastBought := 0
        return true
    }
    if (want < Cfg.baitPer)
        LogMsg("[shop] wanted " . Cfg.baitPer . " but only " . want . " fit (" . Max(0, BotState.bait) . "/90 in stock)")
    nPlus := packs - 1
    bought := step * packs
    cost := packs * bait.price
    LogMsg("[shop] buying x" . bought . " " . bait.name . " at the " . Cfg.npc
        . " (" . packs . " pack" . (packs == 1 ? "" : "s") . ", $" . Fmt(cost)
        . (bait.item != "" ? " + " . packs . " " . bait.item : "") . ")")

    HookBuying(bait, bought, cost)
    if !OpenNpcDialogue()
        return ShopFail("NPC dialogue never opened", "shop")
    if (Cfg.npc == "Angler") {
        if !ClickActionUntil("root", "bait", () => MenuPanels().Length == PageRows("bait")
                , 4, ShopCfg.afterClick + 0.6, "bait")
            return ShopFail("Bait page never appeared", "shop")
    } else {
        if !ClickActionUntil("root", "shop", () => MenuPanels().Length == PageRows("shop")
                , 4, ShopCfg.afterClick + 0.6, "shop")
            return ShopFail("Shop page never appeared", "shop")
        if !ClickActionUntil("shop", "buy_bait", () => MenuPanels().Length == PageRows("bait")
                , 4, ShopCfg.afterClick + 0.6, "bait")
            return ShopFail("Buy Bait page never appeared", "shop")
    }
    if !ClickActionUntil("bait", "bait_item", () => CraftUp()
            , 4, ShopCfg.afterClick + 0.6)
        return ShopFail("CRAFT window never opened for " . bait.name
            . " (is it unlocked? is the bait row right?)", "shop")

    LogMsg("[shop] craft window up - profile " . BotState.resW . "x" . BotState.resH . ", game area "
        . BotState.win.x . "," . BotState.win.y . " " . BotState.win.w . "x" . BotState.win.h
        . " (" . nPlus . " + clicks needed)")
    Wait(0.4)                                            ; let the window finish its pop-up animation
    Loop nPlus {
        if !Alive()
            return false
        ClickPx("plus")
        Wait(ShopCfg.afterPlus + 0.15)
    }
    shot := BaitShot()                                   ; the Craft window with the final quantity
    closed := false
    Loop 4 {
        if !Alive()
            return false
        ClickPx("craft")
        if WaitUntil(() => !CraftUp(), 3.0) {
            closed := true
            break
        }
    }
    if !closed
        return ShopFail("CRAFT window did not close - purchase unconfirmed (missing "
            . (bait.item != "" ? bait.item . " or " : "") . "money?)", "shop")

    ; From here the bait IS bought: credit it however messy the exit is.
    BotState.lastBought := bought
    Tally("purchases")
    Tally("baitBought", bought)
    Tally("spent", cost)
    NoteResponse()
    HookBait(bait, bought, cost, shot)
    if !LeaveDialogue() {
        LogMsg("[shop] bait bought, but the dialogue did not close - stopping safely")
        Halt("the NPC dialogue would not close after buying bait")
        return true
    }
    Wait(ShopCfg.afterNevermind)
    SetRod(true)
    EnterFishingStance(true)
    LogMsg("[shop] done - " . bought . " " . bait.name . " bought")
    return true
}

; Screenshot of the Craft window just before Craft is pressed (quantity + price visible).
BaitShot() {
    if !(HookReady() && Cfg.hkBait && Cfg.hkShot)
        return ""
    Wait(0.3)
    r := SubRect(BotState.win, Regions.craftShot)
    path := TMP_DIR . "\bait_" . FormatTime(, "yyyyMMdd_HHmmss") . ".png"
    return PngSave(r.x, r.y, r.w, r.h, path) ? path : ""
}

; The Angler cannot buy fish; only the Fisherman's Shop has "Sell Fish".
SellFish(stayAtNpc := false) {
    if (Cfg.npc == "Angler") {
        LogMsg("[sell] the Angler cannot buy fish - skipped")
        return false
    }
    LogMsg("[sell] selling the fish stock")
    HookSelling(BotState.sinceSell)
    moneyBefore := -1
    if Cfg.trackIncome {                                  ; HUD is visible now: read the $ before opening the NPC
        Loop 3 {
            moneyBefore := ReadMoney()
            if (moneyBefore >= 0)
                break
            Wait(0.3)
        }
        if (moneyBefore < 0)
            moneyBefore := BotState.moneyLast
        LogMsg("[money] before the sale: " . (moneyBefore >= 0 ? "$" . Fmt(moneyBefore) : "unreadable (OCR: '" . BotState.lastOcr . "')"))
    }
    if !OpenNpcDialogue()
        return ShopFail("NPC dialogue never opened", "sell")
    if !ClickActionUntil("root", "shop", () => MenuPanels().Length == PageRows("shop")
            , 4, ShopCfg.afterClick + 0.6, "shop")
        return ShopFail("Shop page never appeared", "sell")
    if !ClickActionUntil("shop", "sell_fish", () => MenuPanels().Length == PageRows("confirm")
            , 4, ShopCfg.confirmTimeout, "confirm")
        return ShopFail("sell confirmation never appeared", "sell")
    Wait(0.7)

    sold := false
    shot := ""
    Loop 3 {
        if (!Alive() || !WaitMenuPage("confirm", ShopCfg.confirmTimeout))
            break
        ClickMenuAction("confirm", "confirm")
        if WaitUntil(() => MenuPanels().Length < 2, ShopCfg.confirmTimeout) {
            sold := true
            break
        }
    }
    if !sold
        return ShopFail("sell confirmation did not close", "sell")

    Wait(ShopCfg.afterNevermind)
    fishSold := BotState.sinceSell
    gained := -1
    after := -1
    if Cfg.trackIncome {
        ; The HUD ($) is hidden while the NPC dialogue is up, so make sure it is gone,
        ; then wait for the counter to settle on its new value.
        if InDialogue()
            LeaveDialogue()
        after := ReadMoneyWait(moneyBefore, 10)
        if (moneyBefore >= 0 && after >= moneyBefore)
            gained := after - moneyBefore
        LogMsg("[money] after the sale: " . (after >= 0 ? "$" . Fmt(after) : "unreadable (OCR: '" . BotState.lastOcr . "')"))
    }
    shot := SaleShot()                                   ; the $ / level block AFTER the sale
    Tally("sales")
    if (gained >= 0)
        Tally("income", gained)
    else if Cfg.trackIncome
        Tally("unreadable")
    BotState.sinceSell := 0
    NoteResponse()
    LogMsg("[sell] sold " . fishSold . " fish"
        . (gained >= 0 ? " for $" . Fmt(gained) : (Cfg.trackIncome ? " (amount unreadable)" : "")))
    HookSale(gained, fishSold, shot, moneyBefore, after)
    if stayAtNpc {
        BotState.atNpc := false
        LogMsg("[sell] done - reopening the NPC for bait")
        return true
    }
    SetRod(true)
    EnterFishingStance(true)
    LogMsg("[sell] done")
    return true
}

; Screenshot of the bottom-left HUD ($ + level) right after the sale, so the new
; balance is visible in the Discord message.
SaleShot() {
    if !(Cfg.hkOn && Cfg.hkShot)
        return ""
    Wait(Timing.shotDelay)
    r := SubRect(BotState.win, Regions.hud)
    path := TMP_DIR . "\sale_" . FormatTime(, "yyyyMMdd_HHmmss") . ".png"
    return PngSave(r.x, r.y, r.w, r.h, path) ? path : ""
}
