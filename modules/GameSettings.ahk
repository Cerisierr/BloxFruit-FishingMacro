; ============================================================================
;  GAME SETTINGS  (Fast Mode + Reduce Motion)
; ============================================================================
; Positions are fractions of the game window, measured on a 1280x720 recording
; of the Settings window. The window slides while it opens, so the yellow title
; bar is located first and the rows are measured from it.
GEAR_FR := [0.0086, 0.4306]    ; gear icon above the compass
SET_TITLE_X := 0.33            ; column that only crosses the title bar
SET_ON_X := 0.5992             ; centre of the "On" buttons
SET_SAMPLE_X := 0.5664         ; left padding of the "On" button (no text there)
SET_CLOSE_X := 0.7398          ; red X
SET_FAST_DY := 0.3931          ; from the title-bar centre, list scrolled to the bottom
SET_MOTION_DY := 0.4819

PxAt(x, y) {
    g := ScreenGrab.Get(1, 1)
    g.Capture(x, y)
    v := NumGet(g.bits, 0, "UInt")
    return {r: (v >> 16) & 255, g: (v >> 8) & 255, b: v & 255}
}

IsGreenBtn(p) {
    return p.g >= 120 && p.g > p.r + 50 && p.g > p.b + 50
}

; Screen Y of the centre of the yellow "Settings" title bar, or -1.
FindSettingsTitle() {
    win := BotState.win
    gr := ScreenGrab.Get(1, win.h)
    gr.Capture(win.x + Round(win.w * SET_TITLE_X), win.y)
    bits := gr.bits
    minH := Round(win.h * 0.04)
    maxH := Round(win.h * 0.09)
    best := -1, bestLen := 0, runStart := -1
    y := 0
    while (y <= win.h) {
        yellow := false
        if (y < win.h) {
            v := NumGet(bits, y * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            yellow := (rr > 225 && gg > 195 && gg < 240 && bb < 80)
        }
        if yellow {
            if (runStart < 0)
                runStart := y
        } else if (runStart >= 0) {
            len := y - runStart
            if (len >= minH && len <= maxH && len > bestLen) {
                bestLen := len
                best := win.y + runStart + len // 2
            }
            runStart := -1
        }
        y++
    }
    return best
}

; Wait for the title bar to stop moving (the window slides while it opens).
WaitSettingsTitle(timeout) {
    deadline := Now() + timeout
    last := -2
    while (Now() < deadline && Alive()) {
        y := FindSettingsTitle()
        if (y >= 0 && y == last)
            return y
        last := y
        Sleep(120)
    }
    return -1
}

ApplyGameSettings() {
    if !Cfg.gameFast
        return true
    win := BotState.win
    LogMsg("[settings] turning on Fast Mode and Reduce Motion in the game settings")
    if !FocusGame()
        return false
    if (FindSettingsTitle() < 0) {
        Mouse.ClickAt(win.x + Round(win.w * GEAR_FR[1]), win.y + Round(win.h * GEAR_FR[2]), 0.30, 0.10)
    }
    ty := WaitSettingsTitle(3.0)
    if (ty < 0) {
        LogMsg("[settings] the Settings window did not open - skipped (the gear is above the compass)")
        return false
    }

    ; scroll the list to the bottom with the cursor over it
    px := win.x + win.w // 2
    py := ty + Round(win.h * 0.25)
    MouseMove(px - 3, py - 3, 0)
    Sleep(40)
    MouseMove(3, 3, 0, "R")
    Sleep(80)
    Loop 14 {
        Click("WheelDown")
        Sleep(70)
    }
    Wait(0.5)
    ty2 := WaitSettingsTitle(2.0)
    if (ty2 >= 0)
        ty := ty2

    ok := true
    sx := win.x + Round(win.w * SET_SAMPLE_X)
    bx := win.x + Round(win.w * SET_ON_X)
    for item in [["Fast Mode", SET_FAST_DY], ["Reduce Motion", SET_MOTION_DY]] {
        y := ty + Round(win.h * item[2])
        if IsGreenBtn(PxAt(sx, y)) {
            LogMsg("[settings] " . item[1] . " is already on")
            continue
        }
        Mouse.ClickAt(bx, y, 0.25, 0.10)
        Wait(0.5)
        if IsGreenBtn(PxAt(sx, y)) {
            LogMsg("[settings] " . item[1] . " switched on")
        } else {
            LogMsg("[settings] " . item[1] . " could NOT be switched on - check the Settings window")
            ok := false
        }
    }

    cx := win.x + Round(win.w * SET_CLOSE_X)
    Loop 2 {
        cy := FindSettingsTitle()
        if (cy < 0)
            break
        Mouse.ClickAt(cx, cy, 0.25, 0.10)
        Wait(0.6)
    }
    if (FindSettingsTitle() >= 0) {
        LogMsg("[settings] could not close the Settings window")
        ok := false
    }
    Wait(0.8)                                            ; let the textures switch off
    return ok
}
