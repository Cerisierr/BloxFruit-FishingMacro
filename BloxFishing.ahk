; ============================================================================
;  Blox Fruits Fishing Macro  -  AutoHotkey v2
;  Port of the "bloxfish" Python macro (vision + reel controller + shop).
;
;  Hotkeys : F2 = start / stop     F4 = quit     F8 = toggle debug log file
;  Requires: AutoHotkey v2.0+, Windows, Roblox (borderless fullscreen or windowed)
;
;  How it works
;    * The screen is read with GDI (BitBlt into a DIB) and scanned in memory,
;      so every colour rule from the Python version can be evaluated exactly.
;    * The reel minigame is a double integrator; the controller is the same
;      time-optimal bang-bang switching law (s = e + 0.5*ev*|ev|/a).
;    * All regions and click points are FRACTIONS of the game window, so the
;      1920x1080 and 2560x1440 profiles use the same calibrated numbers.
; ============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off
Persistent
ProcessSetPriority("High")
SetMouseDelay(-1)
SetKeyDelay(-1, -1)
CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")

; ---- elevation: Roblox drops input from a non-elevated process --------------
if !A_IsAdmin {
    try Run('*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"')
    ExitApp()
}

; ============================================================================
;  INPUT
; ============================================================================
class Mouse {
    static down := false
    static asserted := 0.0
    static trace := false                               ; log every menu click (used during anchor / quest visits)

    ; Drive the left button to `state`; re-assert every 150 ms so a dropped
    ; SendInput event can never leave the reel zone jammed against a wall.
    static Hold(state) {
        t := Now()
        if (state != this.down || t - this.asserted >= 0.15) {
            Click(state ? "Down" : "Up")
            this.down := state
            this.asserted := t
        }
    }

    static Tap(holdSec := 0.08) {
        Click("Down")
        this.down := true
        Sleep(Round(holdSec * 1000))
        Click("Up")
        this.down := false
        this.asserted := Now()
    }

    ; Real injected movement so Roblox's GUI cursor follows (used for menus).
    static ClickAt(x, y, settle := 0.15, holdSec := 0.06) {
        if this.trace
            LogMsg("[click] menu click at " . x . "," . y)
        MouseMove(x - 4, y - 4, 0)
        Sleep(30)
        MouseMove(4, 4, 0, "R")
        Sleep(50)
        MouseMove(1, 0, 0, "R")
        MouseMove(-1, 0, 0, "R")
        Sleep(Round(settle * 1000))
        this.Tap(holdSec)
    }
}

class Keys {
    static SC_W := 0x11
    static SC_S := 0x1F
    static SC_LSHIFT := 0x2A
    static SKILLS := Map("Z", 0x2C, "X", 0x2D, "C", 0x2E, "V", 0x2F, "F", 0x21)   ; fishing-rod skill keys
    static DIGITS := Map("1", 0x02, "2", 0x03, "3", 0x04, "4", 0x05, "5", 0x06
                       , "6", 0x07, "7", 0x08, "8", 0x09, "9", 0x0A, "0", 0x0B)

    ; Scan-code tap: Roblox reads scan codes, not virtual keys.
    static Tap(sc, holdSec := 0.06) {
        code := Format("sc{:03X}", sc)
        Send("{" . code . " down}")
        Sleep(Round(holdSec * 1000))
        Send("{" . code . " up}")
    }

    static Digit(slot) {
        s := Trim(String(slot))
        return this.DIGITS.Has(s) ? this.DIGITS[s] : this.DIGITS["1"]
    }
}

; ============================================================================
;  SCREEN CAPTURE  (GDI BitBlt -> top-down 32-bit DIB, read with NumGet)
; ============================================================================
class ScreenGrab {
    static cache := Map()

    static Get(w, h) {
        key := w "x" h
        if !this.cache.Has(key) {
            if (this.cache.Count > 12)
                this.cache := Map()
            this.cache[key] := ScreenGrab(w, h)
        }
        return this.cache[key]
    }

    static Clear() {
        this.cache := Map()
    }

    __New(w, h) {
        this.w := Max(1, w)
        this.h := Max(1, h)
        this.hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
        this.hdcMem := DllCall("CreateCompatibleDC", "ptr", this.hdcScreen, "ptr")
        bi := Buffer(40, 0)
        NumPut("UInt", 40, bi, 0)
        NumPut("Int", this.w, bi, 4)
        NumPut("Int", -this.h, bi, 8)          ; negative = top-down
        NumPut("UShort", 1, bi, 12)
        NumPut("UShort", 32, bi, 14)
        bitsPtr := 0
        this.hBmp := DllCall("CreateDIBSection", "ptr", this.hdcScreen, "ptr", bi
            , "uint", 0, "ptr*", &bitsPtr, "ptr", 0, "uint", 0, "ptr")
        this.bits := bitsPtr
        this.hOld := DllCall("SelectObject", "ptr", this.hdcMem, "ptr", this.hBmp, "ptr")
    }

    ; Copy the screen rectangle whose top-left is (x, y) into the DIB.
    Capture(x, y) {
        return DllCall("BitBlt", "ptr", this.hdcMem, "int", 0, "int", 0
            , "int", this.w, "int", this.h, "ptr", this.hdcScreen
            , "int", x, "int", y, "uint", Rdp.on ? 0x00CC0020 : 0x40CC0020)   ; SRCCOPY | CAPTUREBLT (RDP: no CAPTUREBLT, it makes the cursor flicker)
    }

    __Delete() {
        try {
            DllCall("SelectObject", "ptr", this.hdcMem, "ptr", this.hOld)
            DllCall("DeleteObject", "ptr", this.hBmp)
            DllCall("DeleteDC", "ptr", this.hdcMem)
            DllCall("ReleaseDC", "ptr", 0, "ptr", this.hdcScreen)
        }
    }
}

; ============================================================================
;  REEL CONTROLLER  (time-optimal bang-bang, identical law to controller.py)
; ============================================================================
class VelEst {
    __New(win := 5) {
        this.win := win
        this.t := []
        this.x := []
    }

    Reset() {
        this.t := []
        this.x := []
    }

    Push(tv, xv) {
        ; A large jump means the target teleported: restart the fit.
        if (this.x.Length && Abs(xv - this.x[this.x.Length]) > 0.25)
            this.Reset()
        this.t.Push(tv)
        this.x.Push(xv)
        if (this.t.Length > this.win) {
            this.t.RemoveAt(1)
            this.x.RemoveAt(1)
        }
    }

    ; Least-squares slope over the sliding window.
    Value() {
        n := this.t.Length
        if (n < 3)
            return 0.0
        t0 := this.t[1]
        tm := 0.0, xm := 0.0
        Loop n {
            tm += this.t[A_Index] - t0
            xm += this.x[A_Index]
        }
        tm /= n
        xm /= n
        num := 0.0, den := 0.0
        Loop n {
            dt := (this.t[A_Index] - t0) - tm
            num += dt * (this.x[A_Index] - xm)
            den += dt * dt
        }
        return den < 1e-12 ? 0.0 : num / den
    }
}

class ReelController {
    __New() {
        this.accel0 := 1.92          ; track widths / s^2
        this.vmax := 0.545           ; track widths / s
        this.win := 5
        this.lat := 0.045            ; capture + input latency (s)
        this.deadband := 0.004
        this.edge := 0.01
        this.vz := VelEst(5)
        this.vf := VelEst(5)
        this.Reset()
    }

    Reset() {
        this.vz.Reset()
        this.vf.Reset()
        this.accel := this.accel0
        this.obs := []
        this.haveLast := false
        this.lastT := 0.0
        this.lastVz := 0.0
        this.lastHold := false
        this.pwm := false
    }

    Retarget() {
        this.vf.Reset()
    }

    ; Learn the rod's real acceleration: median of recent |dv/dt| samples.
    Adapt(tv, vzv) {
        if !this.haveLast {
            this.lastT := tv
            this.lastVz := vzv
            this.haveLast := true
            return
        }
        dt := tv - this.lastT
        if (dt > 0.004 && dt < 0.08) {
            observed := (vzv - this.lastVz) / dt
            expected := this.lastHold ? 1 : -1
            sgn := observed > 0 ? 1 : (observed < 0 ? -1 : 0)
            if (sgn == expected && Abs(vzv) < this.vmax * 0.85) {
                mag := Abs(observed)
                if (mag > 0.2 && mag < 12.0) {
                    this.obs.Push(mag)
                    if (this.obs.Length > this.win * 3)
                        this.obs.RemoveAt(1)
                    if (this.obs.Length >= this.win)
                        this.accel := Median(this.obs)
                }
            }
        }
        this.lastT := tv
        this.lastVz := vzv
    }

    ; One decision. Positions are in track widths (0..1).
    Step(tv, zoneC, fishC, zoneHalf) {
        this.vz.Push(tv, zoneC)
        this.vf.Push(tv, fishC)
        vzv := this.vz.Value()
        vfv := this.vf.Value()
        this.Adapt(tv, vzv)

        a := Max(0.2, this.accel)
        lat := this.lat
        acc := this.lastHold ? a : -a
        zPred := zoneC + vzv * lat + 0.5 * acc * lat * lat
        vzPred := Min(Max(vzv + acc * lat, -this.vmax), this.vmax)
        fPred := fishC + vfv * lat

        lo := zoneHalf + this.edge
        hi := 1.0 - zoneHalf - this.edge
        target := Min(Max(fPred, lo), hi)

        e := target - zPred
        ev := vfv - vzPred
        s := e + 0.5 * ev * Abs(ev) / a

        if (Abs(s) < this.deadband) {
            ; Alternate every tick: mean acceleration ~ 0, the zone coasts.
            this.pwm := !this.pwm
            hold := this.pwm
        } else {
            hold := (s > 0)
        }
        if (hold && vzPred >= this.vmax)
            hold := (s > this.deadband)
        else if (!hold && vzPred <= -this.vmax)
            hold := (s > -this.deadband)

        this.lastHold := hold
        return {hold: hold, err: e, vz: vzv, vf: vfv}
    }
}

; ============================================================================
;  CONFIGURATION
; ============================================================================
APP_NAME    := "Blox Fruits Fishing Macro"
APP_VERSION := "1.28.8"
INI_FILE    := A_ScriptDir "\BloxFishing.ini"
UPDATE_URL  := "https://raw.githubusercontent.com/Cerisierr/BloxFruit-FishingMacro/main/BloxFishing.ahk"
UPDATE_HTML_URL := "https://raw.githubusercontent.com/Cerisierr/BloxFruit-FishingMacro/main/BloxFishing.html"
HTML_FILE := A_ScriptDir . "\BloxFishing.html"
LOG_FILE    := A_ScriptDir "\BloxFishing.log"
ERR_DIR     := A_ScriptDir "\errors"          ; game screenshots taken when something goes wrong
ROBLOX_WIN  := "ahk_exe RobloxPlayerBeta.exe"

; Supported screen resolutions (profile dropdown).
RES_PROFILES := Map("1920x1080", [1920, 1080], "2560x1440", [2560, 1440], "1366x768", [1366, 768])
RES_ORDER    := ["1920x1080", "2560x1440", "1366x768"]

; Regions as fractions of the game window: [left, top, right, bottom].
Regions := {
    bar:   [0.2138, 0.7184, 0.8502, 0.8181],   ; reel bar search band
    baitLine: [0.4200, 0.8050, 0.5800, 0.8600],  ; "Selected Bait: Kelp Bait x80" under the NPC label
    health: [0.0100, 0.8150, 0.2000, 0.8750],  ; HP bar (bottom-left): green fill, empty when dead
    bite:  [0.2800, 0.1600, 0.7200, 0.6000],   ; "!" marker area (excludes the top-right player list)
    meter: [0.2800, 0.6000, 0.3800, 0.9600],   ; cast charge meter: tube sits low on 1366x768 RDP (0.64-0.92)
    meterWide: [0.1800, 0.2200, 0.8200, 0.9600], ; fallback if the camera was moved
    menu:  [0.6700, 0.3600, 0.9500, 0.7800],   ; NPC button stack
    craft: [0.4020, 0.5769, 0.6020, 0.7162],   ; yellow Craft button
    learn: [0.6753, 0.6482, 0.8573, 0.7458],   ; recipe-note "Learn" button
    catchShot: [0.1500, 0.1200, 0.8500, 0.9000],  ; where the Species/Weight card shows (catch screenshot)
    sale:  [0.2200, 0.6200, 0.7800, 0.9200],   ; strip below the centre where the sale text pops up
    npcLabel: [0.3800, 0.5800, 0.6200, 0.8600],  ; where the white "Interact" prompt of a nearby NPC floats
    craftShot: [0.2800, 0.2000, 0.7200, 0.7600], ; the Craft window (bait purchase screenshot)
    money: [0.0220, 0.7000, 0.1450, 0.7620],   ; the $ counter digits (bottom-left HUD), "$" sign excluded
    level: [0.0030, 0.7620, 0.1200, 0.8060],   ; "Lv. 868" under the $ counter
    hud:   [0.0000, 0.6950, 0.2000, 0.8100]    ; $ + level block, attached to the hourly report
  , quest: [0.0000, 0.4000, 0.2600, 0.6400]    ; quest panel (top-left HUD): title, objective n/m, progress bar, reward
  , questText: [0.2000, 0.7400, 0.8000, 0.8800] ; NPC name banner + dialogue line ("Lookin' to do something for me?")
}

; Click points as fractions of the game window: [x, y].
Points := {
    interact:  [0.4965, 0.6552],
    menu1:     [0.7594, 0.4454],   ; legacy ordinal fallbacks (live detection first)
    menu2:     [0.7629, 0.5352],
    menu3:     [0.7711, 0.6106],
    menuLast:  [0.7664, 0.7033],
    craftPlus: [0.6434, 0.5216],
    craftBtn:  [0.5000, 0.6473],
    craftClose:[0.6590, 0.2773],
    learn:     [0.7697, 0.7008]
  , dialogueText: [0.5000, 0.8200]   ; the NPC speech box (click = next line / close)
}

; Timings in seconds (same defaults as the Python build).
Timing := {
    castHold: 5.00, releaseLead: 0.0, castSettle: 1.60, quickHold: 0.30, quickSettle: 1.00, maxCastAttempts: 4, castRetryGap: 0.45
  , biteClickDelay: 0.05, biteToBar: 5.0, maxWaitBite: 30.0, maxReel: 12.0
  , flickGap: 0.08, flickSlowDelay: 0.50, flickSlowGap: 0.50, flickSettle: 0.50
  , catchConfirm: 0.30, popupDelay: 1.60, catchClickGap: 0.35, catchSettle: 0.55
  , barClear: 3.0, barLost: 0.9, errorRecovery: 1.0, responseTimeout: 300.0
  , chestHold: 2.5, chestGrace: 1.5, chestMinProgress: 0.20, chestMaxGrabs: 4
  , shotDelay: 0.50
}

ShopCfg := {
    afterClick: 0.6, afterPlus: 0.25, afterShift: 0.35, afterNevermind: 1.5
  , afterRod: 0.45, walkBackTap: 0.10, stepAwayTap: 0.07, stepAwayAdd: 0.03, stepAwayMax: 0.30, approachWait: 1.2, directTimeout: 0.9
  , dialogTimeout: 6.0, craftTimeout: 6.0, rootTimeout: 2.0, rootSettle: 0.9
  , nevermindRetry: 1.4, beforeLeave: 0.7, pageSettle: 0.65, poll: 0.08
  , maxApproach: 2, afterBack: 0.5, confirmTimeout: 6.0, buyAt: 20, craftStep: 10
}

; ---- baits ------------------------------------------------------------------
; price = money for one pack of 10 bait, item = extra material needed per pack
; (Sea 2 / Sea 3), slot = row of the bait inside the NPC's Bait menu: Basic Bait
; is always first, then the two baits of that sea. If your menu is ordered
; differently, set  baitRow=  (1..3) in the [shop] section of BloxFishing.ini.
BAITS := [
    {name: "Basic Bait",     sea: 1, price: 1000,  item: "",             slot: 1}
  , {name: "Kelp Bait",      sea: 1, price: 12000, item: "",             slot: 2}
  , {name: "Good Bait",      sea: 1, price: 8000,  item: "",             slot: 3}
  , {name: "Abyssal Bait",   sea: 2, price: 25000, item: "Demonic Wisp", slot: 2}
  , {name: "Frozen Bait",    sea: 2, price: 36000, item: "Yeti Fur",     slot: 3}
  , {name: "Epic Bait",      sea: 3, price: 50000, item: "Terror Eyes",  slot: 2}
  , {name: "Carnivore Bait", sea: 3, price: 60000, item: "Dragon Scale", slot: 3}
]
NPC_LIST := ["Fisherman", "Angler"]

; User-adjustable settings (persisted in BloxFishing.ini, edited in the GUI).
Cfg := {
    resolution: "Auto", rodSlot: "4", fastBite: false, slowFlick: false
  , chest: true, anchor: true, flick: true, perfect: true, perfectPct: 97
  , zoomLock: true, zoomOut: 8, zoomEvery: 5, tiltPx: 70, dockWalk: 8, gameFast: true
  , questOn: true, questKey: "Z"
  , npc: "Fisherman", buyBait: true, baitType: "Basic Bait", baitNow: 0, baitPer: 40, baitRow: 0
  , sellOn: true, sellEvery: 100, trackIncome: true, trackLevel: true
  , theme: "Midnight"
  , hkOn: false, hkUrl: "", hkUrlHourly: "", hkName: "Blox Fishing Macro", hkMention: ""
  , hkStart: true, hkStop: true, hkSale: true, hkShot: true, hkBait: true
  , hkErr: true
  , hkBuy: true, hkCast: false, hkCatch: true, hkCatchShot: false, hkChest: true, hkQuest: true, hkQuestDone: true, hkQuestFail: true
}

; Runtime state.
BotState := {
    running: false, debug: false, win: {x: 0, y: 0, w: 1920, h: 1080}
  , resW: 1920, resH: 1080, sc: 1.0
  , shiftLock: false, shiftVerified: false, rodEquipped: true
  , atNpc: true, bait: -1, sinceSell: 0, lastResponse: 0.0, witness: ""
  , flicked: false, lastEscaped: false, buyFailures: 0, lastBought: 0
  , meterFull: 0, biteInfo: "", zoomedAt: -1, biteMisses: 0
  , npcHits: 0, hpNext: 0.0, hpLostSince: 0.0, hpDead: false, hpOcrNext: 0.0, hpZeroReads: 0, paused: false, stopReason: "", moneyLast: -1, lastOcr: "", logBuf: "", levelStart: -1, levelLast: -1, levelRead: 0.0, reportDue: false, hookQ: [], errAt: Map(), stopShot: ""
  , biteBase: 0, biteBaseN: 0, biteFrame: 0, biteFrameW: 0, biteFrameH: 0
  , lastHourlySlot: "", questState: "unknown", questType: "", questRarity: "", questTimed: false, questRead: 0.0, questMiss: 0
  , questNextTry: 0.0, questAcceptedAt: 0.0, questFails: 0, questStreak: 0, questHandFails: 0, questSkillUses: 0, questObjective: "", questEntry: "", questProg: "", questResumed: false, questSig: "", questBlock: 0.0
}
Meter := {x: 0, top: 0, bot: 0}
BotStats := {casts: 0, bites: 0, catches: 0, escapes: 0, missedBar: 0
           , biteTimeouts: 0, sales: 0, purchases: 0, baitBought: 0, spent: 0
           , income: 0, unreadable: 0, levels: 0, chests: 0, quests: 0, questsAcc: 0, questsFail: 0, started: 0.0, lastUp: 0.0}
Hour :={started: 0.0}                                  ; counters since the last hourly report
PrevHour := {valid: false, secs: 0.0, catches: 0, income: 0, levels: 0}   ; the report window before this one (for the comparison)
; Remote Desktop session. Everything added for RDP in v1.18.x is gated by Rdp.on, so
; a normal desktop (1920x1080, 2560x1440, ...) runs exactly the pre-1.18 logic.
Rdp := {on: false, castLead: 0.08, how: ""}
HIST_MAX := 1200
Hist := []                                              ; report-card samples: [elapsed s, income, levels, catches]

CurBait() {
    for b in BAITS {
        if (b.name == Cfg.baitType)
            return b
    }
    return BAITS[1]
}

BaitLabel(b) {
    t := b.name . "   -   Sea " . b.sea . "   -   $" . Fmt(b.price) . " / 10"
    if (b.item != "")
        t .= " + " . b.item
    return t
}

; NPC menu rows: 1-based from the top, -1 = bottom row (Back / Nevermind).
;   Fisherman root : Shop, Fishing Index, Job Stats, Nevermind
;   Fisherman shop : Buy Bait, Sell Fish, Nevermind
;   Angler root    : Rods, Bait, Quest, Nevermind        (cannot buy fish)
;   Bait page      : the baits of the sea ... , Back
MenuRow(page, action) {
    if (action == "nevermind" || action == "back")
        return -1
    switch page {
        case "root":
            if (Cfg.npc == "Angler")
                return (action == "bait") ? 2 : (action == "quest") ? 3 : 1
            return (action == "shop") ? 1 : (action == "fishing_index") ? 2 : 3
        case "shop":
            return (action == "buy_bait") ? 1 : 2
        case "bait":
            return (Cfg.baitRow > 0) ? Cfg.baitRow : CurBait().slot
        case "confirm":
            return 1
        case "quest":                                    ; Angler: "Lookin' to do something for me?"  Yes / No / Back
            return (action == "yes") ? 1 : 2
    }
    return 1
}

; Number of buttons on each page (used to recognise a settled page).
PageRows(page) {
    switch page {
        case "root":
            return 4
        case "shop":
            return 3
        case "confirm":
            return 2
        case "quest":
            return 3
        case "bait":
            if (Cfg.npc == "Angler")
                return 4
            return (CurBait().slot == 1) ? 2 : 4
    }
    return 2
}

QPF := 0
DllCall("QueryPerformanceFrequency", "Int64*", &QPF)
Ui := {}
reelCtl := ReelController()

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
    ; hp = true only inside the fishing loops (the HP bar is hidden during NPC dialogues)
    if (hp && HealthLost()) {
        LogMsg("[death] Health reads 0/x - character is dead, stopping")
        Halt("character dead (Health 0)")
        return false
    }
    return true
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
Halt(reason) {
    BotState.running := false
    first := (BotState.stopReason == "")
    if first
        BotState.stopReason := reason
    LogMsg("[stop] " . reason)
    if first {
        BotState.stopShot := ErrorShot("stop")           ; attached to the "Macro stopped" message
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

; ============================================================================
;  VISION - colour rules (RGB) ported from vision.py
; ============================================================================
; Dark neutral / slightly blue panel. The track is translucent, so it is darker
; over wood (33,30,29) and lighter over bright flat sea or sky (47,53,56).
IsTrackPx(r, g, b) {
    return b >= 18 && b <= 66 && r <= 70 && g <= 70 && Abs(b - g) <= 14 && Abs(g - r) <= 14
}

IsZonePx(r, g, b) {                          ; green zone, normal + alarm look
    if (Abs(b - r) > 16)
        return false
    if (g > b + 10 && g > r + 10 && g > 62)
        return true
    return Abs(g - b) <= 12 && g >= 62 && g <= 170
}

IsFishPx(r, g, b) {
    return b > 110 && b > r + 60 && g > r + 30
}

IsChestPx(r, g, b) {
    return r > 140 && g > 90 && b < 130 && r > b + 60 && g > b + 20
}

; Fraction of sampled pixels on row y (between xl..xr) that belong to the bar.
BandFrac(bits, w, y, xl, xr) {
    n := 0, hit := 0
    base := y * w * 4
    x := xl
    while (x <= xr) {
        v := NumGet(bits, base + x * 4, "UInt")
        rr := (v >> 16) & 255
        gg := (v >> 8) & 255
        bb := v & 255
        n++
        if (IsTrackPx(rr, gg, bb) || IsZonePx(rr, gg, bb) || IsFishPx(rr, gg, bb)
            || IsChestPx(rr, gg, bb))
            hit++
        x += 6
    }
    return n ? hit / n : 0.0
}

; Locate the reel bar. Identified structurally: a long two-tone green progress
; strip with the dark track band directly above it. Returns a geometry object
; or 0.
FindBar() {
    win := BotState.win
    r := SubRect(win, Regions.bar)
    if (r.w < 50 || r.h < 10)
        return 0
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    w := r.w, h := r.h
    minW := Floor(win.w * 0.18)
    maxW := Floor(win.w * 0.99)

    bestW := 0, bTop := -1, bBot := -1, bL := 0, bR := 0
    gTop := -1, gBot := -1, gL := 0, gR := 0

    y := 0
    while (y < h) {
        base := y * w * 4
        runStart := -1, last := -1
        curLen := 0, curL := 0, curR := 0
        x := 0
        while (x < w) {
            v := NumGet(bits, base + x * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            if (gg > bb + 15 && gg > rr + 15 && gg > 40) {       ; progress strip
                if (runStart < 0)
                    runStart := x
                last := x
            } else if (runStart >= 0 && x - last > 6) {
                if (last - runStart > curLen) {
                    curLen := last - runStart
                    curL := runStart
                    curR := last
                }
                runStart := -1
            }
            x += 2
        }
        if (runStart >= 0 && last - runStart > curLen) {
            curLen := last - runStart
            curL := runStart
            curR := last
        }

        if (curLen >= minW && curLen <= maxW) {
            if (gTop >= 0 && Abs(curL - gL) <= 8 && Abs(curR - gR) <= 8) {
                gBot := y
                if (curR - curL > gR - gL) {
                    gL := curL
                    gR := curR
                }
            } else {
                if (gTop >= 0 && gR - gL > bestW) {
                    bestW := gR - gL
                    bTop := gTop
                    bBot := gBot
                    bL := gL
                    bR := gR
                }
                gTop := y
                gBot := y
                gL := curL
                gR := curR
            }
        } else if (gTop >= 0) {
            if (gR - gL > bestW) {
                bestW := gR - gL
                bTop := gTop
                bBot := gBot
                bL := gL
                bR := gR
            }
            gTop := -1
        }
        y++
    }
    if (gTop >= 0 && gR - gL > bestW) {
        bestW := gR - gL
        bTop := gTop
        bBot := gBot
        bL := gL
        bR := gR
    }
    if (bTop < 0)
        return 0

    tw := bR - bL + 2
    progH := bBot - bTop + 1
    if (progH < 3 || progH > Ceil(0.05 * tw))            ; reject scenery blocks
        return 0

    ; Playfield band: rows of dark track / zone / tiles just above the strip.
    bandBotL := -1
    maxGap := Ceil(0.03 * tw)
    k := 0
    while (k <= maxGap && bTop - 1 - k >= 0) {
        if (BandFrac(bits, w, bTop - 1 - k, bL, bR) >= 0.5) {
            bandBotL := bTop - 1 - k
            break
        }
        k++
    }
    if (bandBotL < 0)
        return 0
    bandTopL := bandBotL
    while (bandTopL - 1 >= 0 && BandFrac(bits, w, bandTopL - 1, bL, bR) >= 0.4)
        bandTopL--
    bandH := bandBotL - bandTopL + 1
    if (bandTopL == 0)                                    ; clipped by the search box
        bandH := Max(bandH, Round(0.055 * tw))
    if (bandH < Max(6, Floor(0.02 * tw)))
        return 0

    x0 := r.x + bL
    progTopAbs := r.y + bTop
    progBotAbs := r.y + bBot
    bandBotAbs := r.y + bandBotL
    bandTopAbs := bandBotAbs - bandH + 1
    hh := progBotAbs - bandTopAbs + 1

    geo := {x0: x0, tw: tw, bandTop: bandTopAbs, hh: hh, bandH: bandH
          , grab: ScreenGrab.Get(tw, hh), rows: [], progRows: []}
    Loop 7
        geo.rows.Push(Round((bandH - 1) * (0.15 + 0.70 * (A_Index - 1) / 6)))
    pl0 := progTopAbs - bandTopAbs
    ph := progBotAbs - progTopAbs
    geo.progRows.Push(pl0 + Round(ph * 0.25))
    geo.progRows.Push(pl0 + Round(ph * 0.50))
    geo.progRows.Push(pl0 + Round(ph * 0.75))
    return geo
}

; The track width is measured once per catch: keep the widest of a few reads,
; because a tile over the strip can make a single read come back short.
AcquireWidest(geo) {
    best := geo
    Loop 4 {
        Sleep(20)
        g2 := FindBar()
        if (g2 && g2.tw > best.tw)
            best := g2
    }
    return best
}

; One grab -> zone / fish / chest spans (pixels, relative to the track).
; Returns 0 when the bar is not readable.
ReadBar(geo, zoneWRef, chestMinW) {
    gr := geo.grab
    gr.Capture(geo.x0, geo.bandTop)
    bits := gr.bits
    w := geo.tw
    rows := geo.rows
    nr := rows.Length
    zThr := Ceil(nr * 0.5)
    fThr := Ceil(nr * 0.25)
    cThr := Ceil(nr * 0.30)

    zl := -1, zr := -1, nz := 0
    fs := -1, fe := -1, bfLen := -1, bfS := -1, bfE := -1
    cs := -1, ce := -1, bcLen := -1, bcS := -1, bcE := -1
    trackHits := 0, total := 0

    x := 0
    while (x < w) {
        zc := 0, fc := 0, cc := 0
        for ry in rows {
            v := NumGet(bits, (ry * w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            total++
            if (bb >= 18 && bb <= 66 && rr <= 70 && gg <= 70 && Abs(bb - gg) <= 14 && Abs(gg - rr) <= 14)
                trackHits++
            if (Abs(bb - rr) <= 16
                && ((gg > bb + 10 && gg > rr + 10 && gg > 62)
                    || (Abs(gg - bb) <= 12 && gg >= 62 && gg <= 170)))
                zc++
            if (bb > 110 && bb > rr + 60 && gg > rr + 30)
                fc++
            else if (rr > 140 && gg > 90 && bb < 130 && rr > bb + 60 && gg > bb + 20)
                cc++
        }
        if (zc >= zThr) {
            if (zl < 0)
                zl := x
            zr := x
            nz++
        }
        if (fc >= fThr) {
            if (fs < 0) {
                fs := x
                fe := x
            } else if (x - fe > 4) {
                if (fe - fs > bfLen) {
                    bfLen := fe - fs
                    bfS := fs
                    bfE := fe
                }
                fs := x
                fe := x
            } else {
                fe := x
            }
        }
        if (chestMinW > 0 && cc >= cThr) {
            if (cs < 0) {
                cs := x
                ce := x
            } else if (x - ce > 4) {
                if (ce - cs > bcLen) {
                    bcLen := ce - cs
                    bcS := cs
                    bcE := ce
                }
                cs := x
                ce := x
            } else {
                ce := x
            }
        }
        x += 2
    }
    if (fs >= 0 && fe - fs > bfLen) {
        bfLen := fe - fs
        bfS := fs
        bfE := fe
    }
    if (cs >= 0 && ce - cs > bcLen) {
        bcLen := ce - cs
        bcS := cs
        bcE := ce
    }

    if (nz < 2)
        return 0
    if (total && trackHits / total < 0.10)               ; track background gone
        return 0

    fl := (bfLen >= 2) ? bfS : -1
    fr := (bfLen >= 2) ? bfE + 2 : -1
    cl := -1, cr := -1
    if (chestMinW > 0 && bcLen >= 0 && (bcE - bcS + 2) >= Max(3, chestMinW)) {
        cl := bcS
        cr := bcE + 2
    }
    zr += 2

    ; A tile clipping one end of the zone hides that edge: rebuild it.
    if (zoneWRef > 0 && (zr - zl) < zoneWRef - 8 * BotState.sc) {
        leftHit := (fl >= 0 && fl <= zl + 6) || (cl >= 0 && cl <= zl + 6)
        rightHit := (fr >= 0 && fr >= zr - 6) || (cr >= 0 && cr >= zr - 6)
        if (leftHit && !rightHit)
            zl := zr - zoneWRef
        else if (rightHit && !leftHit)
            zr := zl + zoneWRef
    }
    return {zl: zl, zr: zr, fl: fl, fr: fr, cl: cl, cr: cr}
}

; Fraction (0..1) of the progress bar that is filled, or -1 if unreadable.
ReadProgress(geo) {
    bits := geo.grab.bits
    w := geo.tw
    maxX := -1, cnt := 0
    x := 0
    while (x < w) {
        hit := 0
        for ry in geo.progRows {
            v := NumGet(bits, (ry * w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            if (gg > 150 && bb < 145 && rr < 185)
                hit++
        }
        if (hit >= 1) {
            cnt++
            maxX := x
        }
        x += 2
    }
    if (cnt < 3)
        return -1
    return Min(1.0, (maxX + 2) / w)
}

; The honest "minigame still up" witness: the two-tone strip spans the track.
ProgressPresent(geo) {
    bits := geo.grab.bits
    w := geo.tw
    ry := geo.progRows[2]
    n := 0, hit := 0
    x := 0
    while (x < w) {
        v := NumGet(bits, (ry * w + x) * 4, "UInt")
        rr := (v >> 16) & 255
        gg := (v >> 8) & 255
        bb := v & 255
        n++
        if (gg > bb + 15 && gg > rr + 15 && gg > 40)
            hit++
        x += 4
    }
    return n && (hit / n) >= 0.5
}

; Bite marker: a magenta-pink ring + "!" (hue 316..358 deg, S>=45/255, V>=110).
; Same method as the Python build: colour mask -> connected blobs (small gaps
; closed) -> shape gates on each blob, so stray pink pixels can't spoil it.
; The "!" marker. Measured on a real RDP frame: its body is SALMON (248,117,130);
; only the anti-aliased edge blends towards pink/purple (170,102,143). The old
; rule matched only that edge (114 of ~3,300 marker pixels), so detection depended
; on what was behind the marker. In an RDP session both looks are accepted; on a
; normal desktop the original rule is used unchanged.
IsBitePx(rr, gg, bb) {
    if (rr < 110)
        return false
    if (Rdp.on && rr >= 200 && gg >= 60 && gg <= 165 && bb >= 70 && bb <= 175 && rr - gg >= 70 && Abs(bb - gg) <= 45)
        return true                                        ; salmon body (RDP colour pipeline only)
    if (bb > gg && rr >= bb) {                             ; pink edge (previous rule)
        d := rr - gg
        e := bb - gg
        return (d * 17 >= 3 * rr && e * 100 <= 73 * d && e * 30 >= d && e >= 40)
    }
    return false
}

; Scan the bite zone once. `ign` (or 0) is a mask of cells that were already
; marker-coloured BEFORE any bite (cape, bobber, rod glow...): they are skipped.
BiteScan(ign := 0) {
    r := SubRect(BotState.win, Regions.bite)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    w := r.w, h := r.h
    st := Max(3, Round(3.5 * BotState.sc))
    gw := (w + st - 1) // st
    gh := (h + st - 1) // st
    mask := Buffer(gw * gh, 0)
    cxs := [], cys := []
    gy := 0
    y := 0
    while (y < h) {
        row := y * w * 4
        gx := 0
        x := 0
        while (x < w) {
            v := NumGet(bits, row + x * 4, "UInt")
            if IsBitePx((v >> 16) & 255, (v >> 8) & 255, v & 255) {
                o := gy * gw + gx
                if !(ign && NumGet(ign, o, "UChar")) {
                    NumPut("UChar", 1, mask, o)
                    cxs.Push(gx)
                    cys.Push(gy)
                }
            }
            x += st
            gx++
        }
        y += st
        gy++
    }
    return {mask: mask, gw: gw, gh: gh, cxs: cxs, cys: cys, w: w, h: h, st: st, bits: bits}
}

; Called once per cast, right before waiting for the bite. Two frames 150 ms apart:
; a cell that is marker-coloured in BOTH is scenery, not a bite. Grown by one cell
; so a 1-px shake of the camera does not matter.
BiteBaseline() {
    BotState.biteBase := 0
    BotState.biteBaseN := 0
    a := BiteScan()
    Sleep(150)
    b := BiteScan()
    if (a.gw != b.gw || a.gh != b.gh)
        return
    gw := b.gw, gh := b.gh
    base := Buffer(gw * gh, 0)
    n := 0
    Loop b.cxs.Length {
        i := A_Index
        x := b.cxs[i], y := b.cys[i]
        if !NumGet(a.mask, y * gw + x, "UChar")
            continue
        n++
        ny := Max(0, y - 1)
        while (ny <= Min(gh - 1, y + 1)) {
            nx := Max(0, x - 1)
            while (nx <= Min(gw - 1, x + 1)) {
                NumPut("UChar", 1, base, ny * gw + nx)
                nx++
            }
            ny++
        }
    }
    if n {
        BotState.biteBase := base
        BotState.biteBaseN := n
    }
}

; Keep the frame that fired a bite, so a false hook can be inspected afterwards.
BiteKeep(s) {
    sz := s.w * s.h * 4
    if (!IsObject(BotState.biteFrame) || BotState.biteFrame.Size != sz)
        BotState.biteFrame := Buffer(sz)
    DllCall("RtlMoveMemory", "ptr", BotState.biteFrame, "ptr", s.bits, "uptr", sz)
    BotState.biteFrameW := s.w
    BotState.biteFrameH := s.h
}

; Write the kept frame to a PNG. Returns the path or "".
BiteDumpFrame() {
    f := BotState.biteFrame
    if (!IsObject(f) || !Gp.Start())
        return ""
    bmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", BotState.biteFrameW, "int", BotState.biteFrameH
        , "int", BotState.biteFrameW * 4, "int", 0x22009, "ptr", f, "ptr*", &bmp)
    if !bmp
        return ""
    path := TMP_DIR . "\bite_false_" . FormatTime(, "HHmmss") . ".png"
    ok := (DllCall("gdiplus\GdipSaveImageToFile", "ptr", bmp, "wstr", path, "ptr", Gp.clsid, "ptr", 0) == 0)
    DllCall("gdiplus\GdipDisposeImage", "ptr", bmp)
    return (ok && FileExist(path)) ? path : ""
}

BiteNow() {
    s := BiteScan(BotState.biteBase)
    n := s.cxs.Length
    gw := s.gw, gh := s.gh, mask := s.mask, cxs := s.cxs, cys := s.cys
    w := s.w, h := s.h, st := s.st
    BotState.biteInfo := "marker cells=" . n . (BotState.biteBaseN ? " (" . BotState.biteBaseN . " static ignored)" : "")
    if (n < 4 || n > 12000)
        return false

    seen := Buffer(gw * gh, 0)
    gap := 2                                   ; cells: bridges ~8 px gaps (the "close")
    minDim := w * 0.055
    areaFloor := 6e-4 * w * h
    bestDim := 0
    Loop n {
        i := A_Index
        sx := cxs[i], sy := cys[i]
        if NumGet(seen, sy * gw + sx, "UChar")
            continue
        NumPut("UChar", 1, seen, sy * gw + sx)
        stack := [[sx, sy]]
        cnt := 0
        minX := sx, maxX := sx, minY := sy, maxY := sy
        while stack.Length {
            c := stack.Pop()
            px := c[1], py := c[2]
            cnt++
            if (px < minX)
                minX := px
            if (px > maxX)
                maxX := px
            if (py < minY)
                minY := py
            if (py > maxY)
                maxY := py
            ny := Max(0, py - gap)
            while (ny <= Min(gh - 1, py + gap)) {
                nx := Max(0, px - gap)
                while (nx <= Min(gw - 1, px + gap)) {
                    o := ny * gw + nx
                    if (NumGet(mask, o, "UChar") && !NumGet(seen, o, "UChar")) {
                        NumPut("UChar", 1, seen, o)
                        stack.Push([nx, ny])
                    }
                    nx++
                }
                ny++
            }
        }
        bw := (maxX - minX + 1) * st
        bh := (maxY - minY + 1) * st
        area := cnt * st * st
        bestDim := Max(bestDim, Max(bw, bh))
        if (Max(bw, bh) < minDim || area < areaFloor)
            continue
        aspect := bw / bh
        if (aspect <= 0.40 || aspect >= 2.30)
            continue
        if (area / (bw * bh) < 0.10)
            continue
        BotState.biteInfo := "marker " . bw . "x" . bh . " px at " . (minX * st) . "," . (minY * st)
        BiteKeep(s)
        return true
    }
    BotState.biteInfo := "marker cells=" . n . " largest blob=" . bestDim . " px (need " . Round(minDim) . ")"
    return false
}

; ---- cast charge meter -------------------------------------------------------
; The meter is a dark vertical track with a black outline. Its fill grows upward
; from the bottom and changes colour as it charges: ORANGE (255,151,0) at the
; bottom -> yellow -> green at the top. The bar then bounces back down, so the
; only reliable signal is the fill level measured against the track height.
IsMeterFill(c) {
    rr := (c >> 16) & 255
    gg := (c >> 8) & 255
    bb := c & 255
    mx := Max(rr, gg)
    return bb < 90 && mx > 140 && (mx - bb) > 110
}

IsMeterEdge(c) {                                       ; the black outline (measured 0-15; the track interior is 28-36)
    return Max((c >> 16) & 255, (c >> 8) & 255, c & 255) <= 20
}

IsMeterTrack(c) {                                      ; empty track: dark blue-grey, bluer over bright sky/sea (25,55,69)
    rr := (c >> 16) & 255
    gg := (c >> 8) & 255
    bb := c & 255
    mx := Max(rr, gg, bb)
    return mx > 20 && mx <= 125 && (mx - Min(rr, gg, bb)) <= 64
}

MeterReset() {
    Meter.x := 0
    Meter.top := 0
    Meter.bot := 0
}

; Measure the track around a seed pixel that has a fill colour. Stores the track
; geometry in Meter and returns true, or returns false for look-alikes (yellow
; clothes, a hat ...): a real meter has a black outline on both sides and above.
MeterMeasure(sx, sy) {
    win := BotState.win
    H := win.h
    ys := sy - win.y
    if (ys < 0 || ys >= H)
        return false
    gr := ScreenGrab.Get(1, H)
    gr.Capture(sx, win.y)
    bits := gr.bits

    ; up to the top outline
    y := ys, miss := 0, top := -1
    while (y >= 0) {
        c := NumGet(bits, y * 4, "UInt")
        if IsMeterEdge(c) {
            edgeLow := y
            top := edgeLow + 1                         ; first interior row
            break
        }
        if (IsMeterFill(c) || IsMeterTrack(c)) {
            miss := 0
        } else if (++miss > 2) {
            return false
        }
        y--
    }
    if (top < 0)
        return false

    ; down to the bottom outline (or the last bar-coloured row if it is hidden)
    y := ys, miss := 0
    bot := -1, lastBar := ys
    while (y < H) {
        c := NumGet(bits, y * 4, "UInt")
        if IsMeterEdge(c) {
            bot := y - 1
            break
        }
        if (IsMeterFill(c) || IsMeterTrack(c)) {
            lastBar := y
            miss := 0
        } else if (++miss > 2) {
            bot := lastBar
            break
        }
        y++
    }
    if (bot < 0)
        bot := lastBar
    hgt := bot - top + 1
    if (hgt < Round(H * 0.07) || hgt > Round(H * 0.40))
        return false

    ; width: an outline on both sides of the seed
    half := Round(win.w * 0.025)
    rowW := half * 2 + 1
    gr2 := ScreenGrab.Get(rowW, 1)
    gr2.Capture(sx - half, sy)
    left := -1, right := -1
    i := half
    while (i >= 0) {
        if IsMeterEdge(NumGet(gr2.bits, i * 4, "UInt")) {
            left := i
            break
        }
        i--
    }
    i := half
    while (i < rowW) {
        if IsMeterEdge(NumGet(gr2.bits, i * 4, "UInt")) {
            right := i
            break
        }
        i++
    }
    if (left < 0 || right < 0)
        return false
    wid := right - left
    if (wid < Round(win.w * 0.004) || wid > Round(win.w * 0.022))
        return false

    Meter.x := sx - half + (left + right) // 2
    Meter.top := win.y + top
    Meter.bot := win.y + bot
    return true
}

; Locate the meter inside one region: native PixelSearch for the fill colours
; (orange, dark orange, amber, yellow, yellow-green, green), top-most hit first.
MeterFind(fr) {
    win := BotState.win
    r := SubRect(win, fr)
    x1 := r.x, y1 := r.y
    x2 := r.x + r.w, y2 := r.y + r.h
    cols := [0xFF9700, 0xCA7700, 0xFFCC00, 0xF0FF00, 0xB7C300, 0x1FF910, 0xAAFF00, 0x84C500, 0x6EFF08]
    Loop 60 {
        top := 99999, tx := 0
        for col in cols {
            if PixelSearch(&fx, &fy, x1, y1, x2, y2, col, 30) && fy < top {
                top := fy
                tx := fx
            }
        }
        if (top == 99999)
            return false
        if MeterMeasure(tx, top)
            return true
        y1 := top + 8                                  ; false hit: look below it
        if (y1 >= y2)
            break
    }
    return false
}

; Fill level 0..1 (1 = completely full), or -1 when no meter is on screen.
; Once located, only a 1-px wide column through the track is read per tick.
MeterRead() {
    Loop 2 {
        if (Meter.x > 0) {
            h := Meter.bot - Meter.top + 1
            gr := ScreenGrab.Get(1, h)
            gr.Capture(Meter.x, Meter.top)
            bits := gr.bits
            mid := NumGet(bits, (h // 2) * 4, "UInt")
            if (IsMeterFill(mid) || IsMeterTrack(mid)) {
                fillTop := h, miss := 0, seen := false
                i := h - 1
                while (i >= 0) {
                    if IsMeterFill(NumGet(bits, i * 4, "UInt")) {
                        fillTop := i
                        seen := true
                        miss := 0
                    } else if (++miss > 3) {
                        break
                    }
                    i--
                }
                return seen ? (h - fillTop) / h : 0.0
            }
            MeterReset()                               ; track vanished: search again
        }
        if !(MeterFind(Regions.meter) || MeterFind(Regions.meterWide))
            return -1
    }
    return -1
}

; Recipe note: navy "Learn" button carrying white text.
LearnUp() {
    r := SubRect(BotState.win, Regions.learn)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    n := 0, navy := 0, white := 0
    y := 0
    while (y < r.h) {
        x := 0
        while (x < r.w) {
            v := NumGet(bits, (y * r.w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            n++
            if (bb > 70 && bb < 160 && gg > 30 && gg < 100 && rr < 70 && bb > rr + 45)
                navy++
            else if (bb > 200 && gg > 200 && rr > 200)
                white++
            x += 3
        }
        y += 3
    }
    return n && navy / n >= 0.45 && white / n >= 0.01
}

; Yellow "Craft" action button present? It is a clean solid block, so require
; a stack of consecutive rows that are mostly yellow (clothes and hats are not).
CraftUp() {
    win := BotState.win
    r := SubRect(win, Regions.craft)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    minW := r.w * 0.25
    minRows := Max(16, Round(win.h * 0.022))
    run := 0, bad := 0, runFirst := -1
    y := 0
    while (y < r.h) {
        first := -1, last := -1, cnt := 0
        x := 0
        while (x < r.w) {
            v := NumGet(bits, (y * r.w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            if (rr > 180 && gg > 150 && bb < 110) {
                if (first < 0)
                    first := x
                last := x
                cnt++
            }
            x += 2
        }
        if (first >= 0 && (last - first) >= minW && cnt * 2 >= (last - first) * 0.55
            && (runFirst < 0 || Abs(first - runFirst) <= 8 * BotState.sc)) {
            if (run == 0)
                runFirst := first
            run += 2
            bad := 0
            if (run >= minRows)
                return true
        } else if (++bad > 2) {
            run := 0
            runFirst := -1
        }
        y += 2
    }
    return false
}

; The NPC name banner ("Fisherman") of the dialogue: a long warm-yellow band in
; the lower centre of the screen. Same rule as the Python build.
DialogueHeader() {
    win := BotState.win
    r := SubRect(win, [0.25, 0.52, 0.75, 0.92])
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    minWidth := Round(win.w * 0.18)
    minRows := Max(8, Round(win.h * 0.008))
    run := 0
    y := 0
    while (y < r.h) {
        first := -1, last := -1, cnt := 0
        x := 0
        while (x < r.w) {
            v := NumGet(bits, (y * r.w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            if (rr > 70 && gg > 50 && bb < 130 && rr >= gg && rr > bb + 30 && gg > bb + 20) {
                if (first < 0)
                    first := x
                last := x
                cnt++
            }
            x += 3
        }
        span := last - first
        if (first >= 0 && span >= minWidth && cnt * 3 >= span * 0.45) {
            run += 2
            if (run >= minRows)
                return true
        } else {
            run := 0
        }
        y += 2
    }
    return false
}

; Update 30 NPC menu. The button panels are an opaque, flat slate (~RGB 21..34, 30..40, 37..41)
; whatever the sea or sky looks like, so panels are found by that colour, not by
; "darkness" (a night sea is just as dark). A hovered button changes colour, so a
; panel whose fill is missing is still recovered from its white icon.
; Returns an array of {x, y} click targets (absolute), top to bottom, or [].
IsPanelFill(rr, gg, bb) {
    return Abs(rr - 27) <= 10 && Abs(gg - 35) <= 9 && Abs(bb - 40) <= 8   ; covers 21..37 / 26..44 / 32..48
}

MenuPanelsFill() {
    win := BotState.win
    r := SubRect(win, Regions.menu)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    w := r.w, h := r.h
    colStep := 4
    cols := (w + colStep - 1) // colStep
    nrows := (h + 1) // 2
    need := Max(8, Floor(cols * 0.30))
    minH := Max(18, Floor(h * 0.09))
    maxH := Max(minH + 1, Floor(h * 0.40))

    ; ---- 1. bands of panel-fill colour -------------------------------------
    counts := []
    counts.Length := nrows
    ri := 0
    y := 0
    while (y < h) {
        n := 0
        base := y * w * 4
        x := 0
        while (x < w) {
            v := NumGet(bits, base + x * 4, "UInt")
            if IsPanelFill((v >> 16) & 255, (v >> 8) & 255, v & 255)
                n++
            x += colStep
        }
        ri++
        counts[ri] := n
        y += 2
    }
    panels := []
    start := -1, lastOn := -1
    Loop nrows + 1 {
        i := A_Index
        on := (i <= nrows) && counts[i] >= need
        yy := (i - 1) * 2
        if on {
            if (start < 0)
                start := yy
            lastOn := yy
        } else if (start >= 0 && (i > nrows || yy - lastOn > 4)) {
            hgt := lastOn - start + 1
            if (hgt >= minH && hgt <= maxH) {
                t := PanelTarget(bits, w, colStep, r, start, lastOn)
                t.top := start
                t.bot := lastOn
                panels.Push(t)
            }
            start := -1
        }
    }

    ; ---- 2. hover recovery: white icon blobs without a fill band ------------
    if panels.Length {
        ix0 := Max(0, Round(win.w * 0.696) - (r.x - win.x))
        ix1 := Min(w - 1, Round(win.w * 0.735) - (r.x - win.x))
        iconMin := Max(12, Floor(win.h * 0.030))
        iconMax := Floor(win.h * 0.065)
        bs := -1, bl := -1
        added := []
        y := 0
        while (y <= h) {
            on := false
            if (y < h) {
                wc := 0
                x := ix0
                while (x <= ix1) {
                    v := NumGet(bits, (y * w + x) * 4, "UInt")
                    if (Min((v >> 16) & 255, (v >> 8) & 255, v & 255) >= 225)
                        wc++
                    x += 2
                }
                on := wc >= 5
            }
            if on {
                if (bs < 0)
                    bs := y
                bl := y
            } else if (bs >= 0 && (y >= h || y - bl > 4)) {
                hh := bl - bs + 1
                if (hh >= iconMin && hh <= iconMax) {
                    ym := (bs + bl) // 2
                    covered := false
                    for q in panels {
                        if (ym >= q.top - 6 && ym <= q.bot + 6)
                            covered := true
                    }
                    if !covered
                        added.Push({x: r.x + ix1 + Round(150 * BotState.sc), y: r.y + ym, top: ym - 20, bot: ym + 20})
                }
                bs := -1
            }
            y += 2
        }
        for a in added
            panels.Push(a)
        ; keep top-to-bottom order
        Loop panels.Length - 1 {
            i := A_Index + 1
            key := panels[i]
            j := i - 1
            while (j >= 1 && panels[j].y > key.y) {
                panels[j + 1] := panels[j]
                j--
            }
            panels[j + 1] := key
        }
    }
    return panels.Length >= 2 ? panels : []
}

; Menu buttons, found two ways. The fill colour changes with the scenery behind
; the (translucent) buttons, but the outline does not: 4 px of pure black for
; an active button, neutral grey 72 for a LOCKED one. The better result wins.
MenuPanels() {
    a := MenuPanelsFill()
    b := MenuPanelsBorder()
    if (Cfg.npc == "Angler")
        return (b.Length >= a.Length) ? b : a
    return (a.Length >= b.Length) ? a : b
}

MenuPanelsBorder() {
    win := BotState.win
    r := SubRect(win, Regions.menu)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    w := r.w, h := r.h
    colStep := 4
    cols := (w + colStep - 1) // colStep
    need := Max(8, Floor(cols * 0.30))
    maxThick := Max(6, Round(win.h * 0.009))

    ; ---- 1. horizontal outline lines ---------------------------------------
    groups := []
    gs := -1, gl := -1, gxs := 0, gxe := 0
    y := 0
    while (y <= h) {
        on := false
        xs := -1, xe := -1
        if (y < h) {
            n := 0
            base := y * w * 4
            x := 0
            while (x < w) {
                v := NumGet(bits, base + x * 4, "UInt")
                rr := (v >> 16) & 255
                gg := (v >> 8) & 255
                bb := v & 255
                if (Max(rr, gg, bb) <= 8
                    || (Abs(rr - 72) <= 5 && Abs(gg - 72) <= 5 && Abs(bb - 72) <= 5)) {
                    n++
                    if (xs < 0)
                        xs := x
                    xe := x
                }
                x += colStep
            }
            on := (n >= need)
        }
        if on {
            if (gs < 0) {
                gs := y
                gxs := xs
                gxe := xe
            } else {
                gxs := Min(gxs, xs)
                gxe := Max(gxe, xe)
            }
            gl := y
        } else if (gs >= 0 && (y >= h || y - gl > 3)) {
            if (gl - gs + 1 <= maxThick)                ; thick black areas are not outlines
                groups.Push({s: gs, e: gl, xs: gxs, xe: gxe})
            gs := -1
        }
        y++
    }

    ; ---- 2. top line + bottom line = one button -----------------------------
    panels := []
    pmin := win.h * 0.060
    pmax := win.h * 0.100
    i := 1
    while (i < groups.Length) {
        a := groups[i]
        b := groups[i + 1]
        span := b.e - a.s + 1
        if (span >= pmin && span <= pmax) {
            xs := Min(a.xs, b.xs)
            xe := Max(a.xe, b.xe)
            panels.Push({x: r.x + xs + Round((xe - xs) * 0.40), y: r.y + (a.s + b.e) // 2
                       , top: a.s, bot: b.e})
            i += 2
        } else {
            i++
        }
    }
    return panels.Length >= 2 ? panels : []
}

; Click point: 40 % into the fill span of the panel's middle row.
PanelTarget(bits, w, colStep, r, y0, y1) {
    ym := (y0 + y1) // 2
    xs := -1, xe := -1
    x := 0
    while (x < w) {
        v := NumGet(bits, ym * w * 4 + x * 4, "UInt")
        if IsPanelFill((v >> 16) & 255, (v >> 8) & 255, v & 255) {
            if (xs < 0)
                xs := x
            xe := x
        }
        x += colStep
    }
    if (xs < 0)
        return {x: r.x + w // 2, y: r.y + ym}
    return {x: r.x + xs + Round((xe - xs) * 0.40), y: r.y + ym}
}

PanelSig(panels) {
    s := panels.Length . ":"
    for p in panels
        s .= (p.y // 4) . ","
    return s
}

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
        if (p.Length == expected && PanelSig(p) == BotState.witness.sig)
            return true
        BotState.witness := ""
    }
    stableSig := "", stableSince := 0.0
    while (Now() < deadline) {
        if !Alive()
            return false
        p := MenuPanels()
        sig := PanelSig(p)
        if (p.Length == expected) {
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

; Click a named action (page + role) using the live stack, with the calibrated
; ordinal dots as a last resort.
ClickMenuAction(page, action) {
    BotState.witness := ""
    index := MenuRow(page, action)
    panels := MenuPanels()
    if panels.Length {
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
        if (attempt == 1 && MenuPanels().Length >= 2) {   ; opening but not settled
            if WaitMenuPage("root", ShopCfg.rootTimeout) {
                BotState.atNpc := true
                return true
            }
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
            NevermindClick(A_Index)
            Wait(0.7)
            if !InDialogue()
                break
        }
        Wait(ShopCfg.afterNevermind)
    }
}

EscapeDialogue() {
    if !InDialogue()
        return false
    LogMsg("[cast] a dialogue is open - closing it and stepping away")
    SetShiftLock(false)
    RecoverDialogue()
    SetRod(false)
    SetRod(true)
    BotState.atNpc := true
    EnterFishingStance(true)
    StepAwayFromNpc()
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
ClearNpcRange(why) {
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
    return false
}

; Single place that changes the tracked bait count. Keeps the GUI field and the
; saved setting equal to the real count, so "Bait in inventory now" is always current.
SetBait(n) {
    BotState.bait := n
    Cfg.baitNow := (n > 0) ? Min(100, n) : 0
    try Ui.baitNow.Value := Cfg.baitNow
    SetTimer(SaveSettings, -1500)
}

BuyBait() {
    ok := BuyBaitRoute()
    if ok {
        BotState.buyFailures := 0
        BotState.moneyLast := -1                         ; money was spent: old baseline is stale
        SetBait(Min(100, Max(0, BotState.bait) + BotState.lastBought))
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
    ; The inventory holds 100 bait at most: only buy what still fits.
    room := 100 - Max(0, BotState.bait)
    want := Min(Cfg.baitPer, room)
    packs := want // step
    if (packs < 1) {
        LogMsg("[shop] inventory full (" . Max(0, BotState.bait) . "/100 bait) - nothing to buy")
        BotState.lastBought := 0
        return true
    }
    if (want < Cfg.baitPer)
        LogMsg("[shop] wanted " . Cfg.baitPer . " but only " . want . " fit (" . Max(0, BotState.bait) . "/100 in stock)")
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
            HookCast(perfectMode ? Round(level * 100) : -1)
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
        attempt := A_Index
        Mouse.Tap(Timing.quickHold)
        Wait(0.15)
        if EscapeDialogue()
            continue
        BotState.npcHits := 0
        Tally("casts")
        LogMsg("[cast] #" . BotStats.casts . (attempt == 1 ? "" : " (attempt " . attempt . ")") . " - quick cast")
        HookCast(-1)
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
                HookHooked()
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
        p := BiteDumpFrame()
        if (p != "")
            LogMsg("[bite] possible FALSE HOOK - frame that fired it: " . p)
        return false
    }
    if (spend && BotState.bait > 0) {                    ; bait is only used up once the minigame really starts
        SetBait(BotState.bait - 1)
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

    if QuestSkillWanted()                                ; "use a rod skill 3 times" quest: one skill per reel
        QuestUseSkill()

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
        p := ReadProgress(geo)
        if (p >= 0)
            progress := p
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
ReadBaitLine() {
    r := SubRect(BotState.win, Regions.baitLine)
    path := TMP_DIR . "\\bait_line.png"
    if !PngSave(r.x, r.y, r.w, r.h, path)
        return
    txt := OcrFile(path)
    if !RegExMatch(txt, "i)Bait[^\r\n]*?[x" . Chr(0xD7) . "]\s*(\d{1,3})", &m)
        return
    n := Integer(m[1])
    if (n > 100)
        return
    if (n != BotState.bait) {
        LogMsg("[bait] game shows x" . n . " (tracked " . BotState.bait . ")")
        SetBait(n)
    }
}

TogglePause(*) {
    if !BotState.running
        return
    BotState.paused := !BotState.paused
    LogMsg(BotState.paused ? "[pause] paused - press Resume or F3" : "[pause] resumed")
    try Ui.btnPause.Text := BotState.paused ? "Resume  (F3)" : "Pause  (F3)"
}

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
            SetBait(0)
            LogMsg("[bait] two casts in a row got no bite - assuming the bait ran out")
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
    BotState.bait := (Cfg.baitNow > 0) ? Cfg.baitNow : -1       ; tracked whenever a count is given
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

; ============================================================================
;  SETTINGS  (BloxFishing.ini)
; ============================================================================
; [section, key, default, type]   type: s = text, i = integer, b = on/off
SETTINGS_SPEC := [
    ["display", "resolution", "Auto", "s"]
  , ["display", "theme", "Midnight", "s"]
  , ["fishing", "rodSlot", "4", "s"]
  , ["fishing", "fastBite", "0", "b"]
  , ["fishing", "slowFlick", "0", "b"]
  , ["fishing", "chest", "1", "b"]
  , ["fishing", "anchor", "1", "b"]
  , ["fishing", "perfect", "1", "b"]
  , ["fishing", "perfectPct", "97", "i"]
  , ["fishing", "dockWalk", "8", "i"]
  , ["camera", "zoomLock", "1", "b"]
  , ["camera", "zoomOut", "8", "i"]
  , ["camera", "zoomEvery", "5", "i"]
  , ["camera", "tiltPx", "70", "i"]
  , ["game", "gameFast", "1", "b"]
  , ["quest", "questOn", "1", "b"]
  , ["quest", "questKey", "Z", "s"]
  , ["shop", "npc", "Fisherman", "s"]
  , ["shop", "buyBait", "1", "b"]
  , ["shop", "baitType", "Basic Bait", "s"]
  , ["shop", "baitNow", "0", "i"]
  , ["shop", "baitPer", "40", "i"]
  , ["shop", "baitRow", "0", "i"]
  , ["shop", "sellOn", "1", "b"]
  , ["shop", "sellEvery", "100", "i"]
  , ["shop", "trackIncome", "1", "b"]
  , ["shop", "trackLevel", "1", "b"]
  , ["webhook", "hkOn", "0", "b"]
  , ["webhook", "hkUrl", "", "s"]
  , ["webhook", "hkUrlHourly", "", "s"]
  , ["webhook", "hkName", "Blox Fishing Macro", "s"]
  , ["webhook", "hkMention", "", "s"]
  , ["webhook", "hkStart", "1", "b"]
  , ["webhook", "hkStop", "1", "b"]
  , ["webhook", "hkSale", "1", "b"]
  , ["webhook", "hkShot", "1", "b"]
  , ["webhook", "hkBait", "1", "b"]
  , ["webhook", "hkErr", "1", "b"]
  , ["webhook", "hkBuy", "1", "b"]
  , ["webhook", "hkCast", "0", "b"]
  , ["webhook", "hkCatch", "1", "b"]
  , ["webhook", "hkCatchShot", "0", "b"]
  , ["webhook", "hkChest", "1", "b"]
  , ["webhook", "hkQuest", "1", "b"]
  , ["webhook", "hkQuestDone", "1", "b"]
  , ["webhook", "hkQuestFail", "1", "b"]
]

; [game] rdp=auto|on|off in BloxFishing.ini (auto = Windows reports a remote session).
DetectRdp() {
    mode := StrLower(Trim(IniRead(INI_FILE, "game", "rdp", "auto")))
    sess := DllCall("GetSystemMetrics", "int", 0x1000) != 0          ; SM_REMOTESESSION
    Rdp.on := (mode == "on") || (mode != "off" && sess)
    Rdp.how := (mode == "auto") ? (sess ? "detected" : "not detected") : "forced " . mode
    try Rdp.castLead := Float(IniRead(INI_FILE, "game", "rdpCastLeadMs", "80")) / 1000
}

LoadSettings() {
    for s in SETTINGS_SPEC {
        name := s[2]
        raw := IniRead(INI_FILE, s[1], name, s[3])
        if (s[4] == "b") {
            Cfg.%name% := (raw == "1")
        } else if (s[4] == "i") {
            try {
                Cfg.%name% := Integer(raw)
            } catch {
                Cfg.%name% := Integer(s[3])
            }
        } else {
            Cfg.%name% := raw
        }
    }
    ver := 1
    try ver := Integer(IniRead(INI_FILE, "meta", "ver", "1"))
    if (ver < 2)
        Cfg.zoomOut := 8                                 ; new default camera distance
    Cfg.perfectPct := Min(100, Max(60, Cfg.perfectPct))
    Cfg.dockWalk := Min(40, Max(0, Cfg.dockWalk))
    ; Remove the old optional interval settings; reports now follow the PC clock.
    try IniDelete(INI_FILE, "webhook", "hkHourly")
    try IniDelete(INI_FILE, "webhook", "hkEveryMin")
    if (Cfg.tiltPx == 40)                                ; old v1.16 default was too little
        Cfg.tiltPx := 70
    Cfg.baitPer := Min(100, Max(10, (Cfg.baitPer // 10) * 10))
    if !THEMES.Has(Cfg.theme)
        Cfg.theme := "Midnight"
    if (Cfg.npc != "Angler")
        Cfg.npc := "Fisherman"
    if (Cfg.npc == "Angler")
        Cfg.sellOn := false
    Cfg.questKey := StrUpper(Trim(Cfg.questKey))
    if !Keys.SKILLS.Has(Cfg.questKey)
        Cfg.questKey := "Z"
    ; Early-release lead in ms (0 = release on the frame that shows a full bar).
    try Timing.releaseLead := Float(IniRead(INI_FILE, "fishing", "castLeadMs", "0")) / 1000
    try Timing.shotDelay := Float(IniRead(INI_FILE, "webhook", "shotDelayMs", "500")) / 1000
}

SaveSettings() {
    for s in SETTINGS_SPEC {
        name := s[2]
        v := Cfg.%name%
        if (s[4] == "b")
            v := v ? 1 : 0
        try IniWrite(v, INI_FILE, s[1], name)
    }
    try IniWrite(2, INI_FILE, "meta", "ver")
    try IniWrite(Round(Timing.releaseLead * 1000), INI_FILE, "fishing", "castLeadMs")
}

IntOf(ctrl, fallback) {
    try return Integer(ctrl.Value)
    return fallback
}

; GUI -> Cfg (and to disk). Called when the run starts and whenever a field changes.
SyncSettings(save := true) {
    try {
        Cfg.resolution := Ui.res.Text
        Cfg.rodSlot := Ui.rod.Text
        Cfg.questKey := Ui.questKey.Text
        Cfg.npc := (Ui.npc.Text == "Angler") ? "Angler" : "Fisherman"
        idx := Ui.bait.Value
        if (idx >= 1 && idx <= BAITS.Length)
            Cfg.baitType := BAITS[idx].name
        for key, v in Ui.tog
            Cfg.%key% := v
        Cfg.perfectPct := Min(100, Max(60, IntOf(Ui.perfectPct, 97)))
        Cfg.zoomOut := Min(30, Max(0, IntOf(Ui.zoomOut, 8)))
        Cfg.zoomEvery := Max(0, IntOf(Ui.zoomEvery, 5))
        Cfg.tiltPx := Min(300, Max(0, IntOf(Ui.tiltPx, 70)))
        Cfg.dockWalk := Min(40, Max(0, IntOf(Ui.dockWalk, 8)))
        Cfg.baitNow := Min(100, Max(0, IntOf(Ui.baitNow, 0)))
        Cfg.baitPer := Min(100, Max(10, Integer(Ui.baitPer.Text)))
        Cfg.sellEvery := Max(0, IntOf(Ui.sellEvery, 100))
        Cfg.hkUrl := Trim(Ui.hkUrl.Value)
        Cfg.hkUrlHourly := Trim(Ui.hkUrlHourly.Value)
        nm := Trim(Ui.hkName.Value)
        Cfg.hkName := (nm != "") ? nm : "Blox Fishing Macro"
        Cfg.hkMention := RegExReplace(Ui.hkMention.Value, "\D")
    }
    if (Cfg.npc == "Angler")
        Cfg.sellOn := false
    if save
        SaveSettings()
}

; Any field of the GUI changed.
OnUiChange(*) {
    SyncSettings(false)
    if (BotState.running && Cfg.baitNow != Max(0, BotState.bait) && !(BotState.bait == 0 && Cfg.baitNow == 0))
        BotState.bait := (Cfg.baitNow > 0) ? Cfg.baitNow : -1       ; manual correction while running
    try {
        if (Cfg.npc == "Angler" && Ui.tog["sellOn"])
            SetToggle("sellOn", false)
    }
    RefreshDynamic()
    SetTimer(SaveSettings, -700)
}

; Texts that depend on other settings (price, NPC notes).
RefreshDynamic() {
    try {
        b := CurBait()
        packs := Max(1, Cfg.baitPer // 10)
        t := "= " . packs . (packs == 1 ? " pack" : " packs") . " of 10   -   $" . Fmt(packs * b.price)
        if (b.item != "")
            t .= "  +  " . packs . " x " . b.item
        Ui.costLbl.Text := t
    }
    try {
        if (Cfg.npc == "Angler") {
            Ui.npcNote.Text := "The Angler sells bait only (Bait menu). It cannot buy fish, so auto-sell is switched off."
            Ui.sellNote.Text := "Auto-sell is not available with the Angler."
        } else {
            Ui.npcNote.Text := "The Fisherman sells bait (Shop > Buy Bait) and buys your fish (Shop > Sell Fish)."
            Ui.sellNote.Text := ""
        }
    }
    try {
        Ui.questNote.Text := (Cfg.npc == "Angler")
            ? "Every 15 min the Angler offers one quest: catch a fish of a rarity, catch 3 fish in 2 min, 3 perfect casts + 3 perfect reactions, or use a rod skill 3 times. The macro accepts it (Quest > Yes), keeps fishing, and hands it in when the progress bar is full."
            : "Auto-quest only works when you AFK at the Angler (Shop and Bait page > AFK at)."
    }
    try HtmlSync()
}

; ============================================================================
;  FORMATTING / SCREENSHOT / OCR
; ============================================================================
TMP_DIR := A_Temp . "\BloxFishing"
HOOK_SHOT_NAME := "sale.png"

CleanTmp() {
    try DirCreate(TMP_DIR)
    cutoff := DateAdd(A_Now, -1, "Days")
    Loop Files, TMP_DIR . "\*.*" {
        if (A_LoopFileTimeModified < cutoff && A_LoopFileName != "ocr.ps1")
            try FileDelete(A_LoopFileFullPath)
    }
}

; Save a screen rectangle as a PNG (GDI+). Returns true on success.
PngSave(x, y, w, h, path) {
    static token := 0
    if !token {
        si := Buffer(24, 0)
        NumPut("UInt", 1, si, 0)
        tk := 0
        if (DllCall("gdiplus\GdiplusStartup", "ptr*", &tk, "ptr", si, "ptr", 0) != 0)
            return false
        token := tk
    }
    hdcS := DllCall("GetDC", "ptr", 0, "ptr")
    hdc := DllCall("CreateCompatibleDC", "ptr", hdcS, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcS, "int", w, "int", h, "ptr")
    old := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")
    DllCall("BitBlt", "ptr", hdc, "int", 0, "int", 0, "int", w, "int", h
        , "ptr", hdcS, "int", x, "int", y, "uint", 0x00CC0020)
    DllCall("SelectObject", "ptr", hdc, "ptr", old)
    pBmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "ptr", hbm, "ptr", 0, "ptr*", &pBmp)
    ok := false
    if pBmp {
        clsid := Buffer(16, 0)
        DllCall("ole32\CLSIDFromString", "wstr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "ptr", clsid)
        ok := (DllCall("gdiplus\GdipSaveImageToFile", "ptr", pBmp, "wstr", path, "ptr", clsid, "ptr", 0) == 0)
        DllCall("gdiplus\GdipDisposeImage", "ptr", pBmp)
    }
    DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", hdc)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcS)
    return ok && FileExist(path)
}

; Windows 10/11 built-in OCR, driven through PowerShell (no extra install).
OcrScriptWrite(path) {
    script := "
    (
    param([string]$ImgPath, [string]$OutPath)
    $ErrorActionPreference = 'Stop'
    try {
      Add-Type -AssemblyName System.Runtime.WindowsRuntime
      $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
      $null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
      $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
      $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
      $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
      $null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]
      $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -like 'IAsyncOperation*' })[0]
      function Await($op, $type) { $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op)); $null = $t.Wait(-1); $t.Result }
      Add-Type -AssemblyName System.Drawing
      $src = [System.Drawing.Bitmap]::FromFile($ImgPath)
      $big = New-Object System.Drawing.Bitmap ([int]($src.Width * 3)), ([int]($src.Height * 3))
      $g = [System.Drawing.Graphics]::FromImage($big)
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.DrawImage($src, 0, 0, $big.Width, $big.Height)
      $g.Dispose(); $src.Dispose()
      $ImgPath = $ImgPath + '.x3.png'
      $big.Save($ImgPath, [System.Drawing.Imaging.ImageFormat]::Png); $big.Dispose()
      $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($ImgPath)) ([Windows.Storage.StorageFile])
      $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
      $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
      $bmp = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
      $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
      if ($engine -eq $null) { Set-Content -Path $OutPath -Value 'ERR:no-ocr-engine'; exit }
      $res = Await ($engine.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])
      Set-Content -Path $OutPath -Value $res.Text
    } catch { Set-Content -Path $OutPath -Value ('ERR:' + $_.Exception.Message) }
    )"
    try {
        f := FileOpen(path, "w", "UTF-8-RAW")
        f.Write(script)
        f.Close()
        return true
    }
    return false
}

OcrFile(png) {
    ps := TMP_DIR . "\ocr.ps1"
    out := TMP_DIR . "\ocr_out.txt"
    try FileDelete(out)
    OcrScriptWrite(ps)
    try {
        RunWait('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' . ps
            . '" "' . png . '" "' . out . '"', , "Hide")
    } catch {
        return ""
    }
    try return Trim(FileRead(out))
    return ""
}

; Largest number in a piece of OCR text ("$ 483,112" -> 483112), or -1.
ParseMoney(text) {
    best := -1
    pos := 1
    while RegExMatch(text, "(\d[\d,. ]*)", &m, pos) {
        digits := RegExReplace(m[1], "\D")
        if (digits != "" && StrLen(digits) <= 12) {
            v := Integer(digits)
            if (v > best)
                best := v
        }
        pos := m.Pos + Max(1, m.Len)
    }
    return best
}

; "Lv. 868" -> 868, or -1.
ParseLevel(text) {
    if RegExMatch(text, "i)L[vV]\.?\s*(\d{1,4})", &m)
        return Integer(m[1])
    v := ParseMoney(text)
    return (v >= 1 && v <= 9999) ? v : -1
}

ReadLevel() {
    r := SubRect(BotState.win, Regions.level)
    path := TMP_DIR . "\level.png"
    if !PngSave(r.x, r.y, r.w, r.h, path)
        return -1
    lv := ParseLevel(OcrFile(path))
    return (lv >= 1 && lv <= 3000) ? lv : -1
}

; Read the level from the HUD and count the levels gained. Only valid while the
; HUD is visible (not in a dialogue). Jumps of more than 25 are treated as OCR noise.
UpdateLevel() {
    if !Cfg.trackLevel
        return
    lv := ReadLevel()
    BotState.levelRead := Now()
    if (lv < 0)
        return
    if (BotState.levelStart < 0) {
        BotState.levelStart := lv
        BotState.levelLast := lv
        LogMsg("[level] starting level " . lv)
        return
    }
    if (lv >= BotState.levelLast && lv - BotState.levelLast <= 25) {
        if (lv > BotState.levelLast) {
            Tally("levels", lv - BotState.levelLast)
            LogMsg("[level] now " . lv . " (+" . BotStats.levels . " this session)")
        }
        BotState.levelLast := lv
    }
}

LevelText() {
    if (BotState.levelStart < 0)
        return "n/a"
    return BotState.levelStart . " > " . BotState.levelLast . "  (+" . BotStats.levels . ")"
}

; Read the $ counter (bottom-left of the HUD). -1 if unreadable.
ReadMoney() {
    r := SubRect(BotState.win, Regions.money)
    path := TMP_DIR . "\money.png"
    if !PngSave(r.x, r.y, r.w, r.h, path)
        return -1
    BotState.lastOcr := RegExReplace(OcrFile(path), "\s+", " ")
    v := ParseMoney(BotState.lastOcr)
    if (v >= 0 && v < 100000000000) {
        BotState.moneyLast := v
        return v
    }
    return -1
}

; Poll the $ counter until it is readable, has changed from `before` and shows the
; same value twice in a row (the counter animates after a sale). Returns the last
; good value (or -1). If nothing changes it gives up after `timeout` seconds.
ReadMoneyWait(before, timeout := 10) {
    t0 := A_TickCount
    last := -1
    same := 0
    while ((A_TickCount - t0) / 1000 < timeout && Alive()) {
        v := ReadMoney()
        if (v >= 0) {
            same := (v == last) ? same + 1 : 1
            last := v
            if (same >= 2 && (before < 0 || v != before))
                return v
            if (same >= 4)                                ; steady and unchanged: nothing was paid out
                return v
        } else {
            same := 0
        }
        Wait(0.3)
    }
    return last
}

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
    f := [["NPC", Cfg.npc], ["Bait", bait.name . " x" . Cfg.baitPer]
        , ["Auto-buy bait", Cfg.buyBait ? "on" : "off"]
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
    f.Push(["Bait in inventory", BotState.bait >= 0 ? Min(100, Max(0, BotState.bait) + qty) . " / 100" : "n/a"])
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

HookCast(pct) {
    if !(HookReady() && Cfg.hkCast)
        return
    HookPost(EmbedJson("Casting", "Cast #" . BotStats.casts . (pct >= 0 ? "  -  released at " . pct . "%" : "")
        , 0x94A3B8), , , "cast", , true)
}

HookHooked() {
    if !(HookReady() && Cfg.hkCast)
        return
    HookPost(EmbedJson("Hooked", "Bite #" . BotStats.bites . "  -  reeling now", 0xFBBF24), , , "hooked", , true)
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
    if HookPost(EmbedJson("Webhook connected", "Test message from the Blox Fishing Macro.", 0x4ADE80, f)
            , , , "test message")
        SetHookStatus("Test sent - waiting for Discord...")
    if (UrlIsHook(Cfg.hkUrlHourly) && Cfg.hkUrlHourly != Cfg.hkUrl)
        HookPost(EmbedJson("Hourly channel connected", "Hourly reports will be posted here.", 0x6C8CFF, f)
            , , , "hourly test", , false, Cfg.hkUrlHourly)
}

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

; ============================================================================
;  THEMES
; ============================================================================
THEME_ORDER := ["Midnight", "Obsidian", "Ocean", "Emerald", "Sunset", "Rose", "Daylight"]
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
        if (String(element.value) != String(value))
            element.value := String(value)
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
        doc.getElementById("log").innerText := BotState.logBuf
        logo := doc.querySelector(".logo")
        logo.style.backgroundColor := accent
        logo.style.color := accentText
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
            for key in ["perfectPct", "zoomOut", "zoomEvery", "tiltPx", "dockWalk", "baitNow", "sellEvery", "hkUrl", "hkUrlHourly", "hkName", "hkMention"]
                HtmlField(doc, key, Ui.%key%.Value)
            for key in ["npc", "res", "rod", "baitPer", "questKey"]
                HtmlField(doc, key, Ui.%key%.Text)
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
        if (StrLen(latest) < 50000 || !InStr(latest, "class ReelController"))
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
        InstallUpdate(latest, latestHtml, remoteVersion)
    } catch as err {
        if manual
            MsgBox("Could not check GitHub for updates.`n`n" . err.Message, APP_NAME, "Icon!")
    }
}

InstallUpdate(source, htmlSource, version) {
    target := A_ScriptFullPath
    htmlTarget := A_ScriptDir . "\BloxFishing.html"
    temp := A_Temp . "\BloxFishing-update-" . version . ".ahk"
    htmlTemp := A_Temp . "\BloxFishing-update-" . version . ".html"
    backup := target . ".bak"
    htmlBackup := htmlTarget . ".bak"
    htmlBackedUp := false
    htmlInstalled := false
    try {
        if FileExist(temp)
            FileDelete(temp)
        if FileExist(htmlTemp)
            FileDelete(htmlTemp)
        FileAppend(source, temp, "UTF-8-RAW")
        FileAppend(htmlSource, htmlTemp, "UTF-8-RAW")
        if (FileGetSize(temp) < 50000)
            throw Error("The downloaded file is incomplete")
        if (FileGetSize(htmlTemp) < 5000)
            throw Error("The downloaded interface file is incomplete")
        try {
            Ui.browser.Navigate("about:blank")
            while (Ui.browser.ReadyState != 4)
                Sleep(10)
        }
        if FileExist(htmlTarget) {
            FileCopy(htmlTarget, htmlBackup, true)
            htmlBackedUp := true
        }
        FileCopy(target, backup, true)
        FileMove(htmlTemp, htmlTarget, true)
        htmlInstalled := true
        FileMove(temp, target, true)
        Run('"' . A_AhkPath . '" "' . target . '"')
        ExitApp()
    } catch as err {
        if htmlBackedUp {
            try FileCopy(htmlBackup, htmlTarget, true)
        } else if htmlInstalled {
            try {
                if FileExist(htmlTarget)
                    FileDelete(htmlTarget)
            }
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
            Ui.browser.Navigate(HtmlFileURL(htmlTarget))
        }
        MsgBox("The update was downloaded but could not be installed.`nYour current macro is unchanged.`n`n"
            . err.Message, APP_NAME, "Icon!")
    }
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
    if !FileExist(HTML_FILE) {
        MsgBox("The interface file is missing:`n" . HTML_FILE . "`n`nKeep BloxFishing.html next to BloxFishing.ahk.", APP_NAME, "Iconx")
        ExitApp()
    }
    th := THEMES.Has(Cfg.theme) ? THEMES[Cfg.theme] : THEMES["Midnight"]
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
    Lbl(g, "", 18, 21, 36, "BF", th.onAccent, 12, 700, 32)
    Lbl(g, "", 64, 20, 132, "Blox Fruits", th.txt, 11, 700)
    Lbl(g, "", 64, 42, 132, "Fishing Macro", th.accent, 9, 600)
    Box(g, "", 16, 70, 178, 1, th.line)
    navDefs := [["dash", "Dashboard", "⌂"], ["fish", "Fishing", "⚓"], ["shop", "NPC + Bait", "▣"]
              , ["quest", "Quests", "✓"], ["hook", "Alerts", "✉"], ["look", "Appearance", "⚙"]
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
    PageHeader(g, "dash", "Fishing Macro Control Panel", "Your fishing setup, session status and quick links.")
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
    HomeCard(g, 514, 480, "Alerts", "Choose which updates are sent to Discord.", "hook")

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
    Panel(g, "fish", 213, 256, 592, 124)
    Panel(g, "fish", 213, 390, 592, 142)
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
    Lbl(g, "fish", 214, 355, 210, "Extra walk (0.1 s per step)", th.muted)
    AddEdit(g, "fish", "dockWalk", 430, 351, 54, Cfg.dockWalk, true)
    Lbl(g, "fish", 494, 355, 150, "8 = 0.8 seconds", th.muted)
    Section(g, "fish", 214, 390, "GAME")
    Lbl(g, "fish", 214, 418, 120, "Roblox resolution", th.muted)
    AddDdl(g, "fish", "res", 340, 414, 130, ["Auto", "1920x1080", "2560x1440", "1366x768"]
        , IdxOf(["Auto", "1920x1080", "2560x1440", "1366x768"], Cfg.resolution))
    Lbl(g, "fish", 500, 418, 120, "Rod slot", th.muted)
    slots := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    AddDdl(g, "fish", "rod", 624, 414, 60, slots, IdxOf(slots, Cfg.rodSlot, 4))
    AddToggle(g, "fish", "gameFast", 214, 454, "Enable Roblox Fast Mode and Reduce Motion at startup", Cfg.gameFast, 480)
    Lbl(g, "fish", 214, 470, 590, "Perfect cast reads the whole charge bar (orange > yellow > green) and releases when it reaches the"
        . " chosen percentage. With zoom-out 8 the bar is small, so 96-98 % is a good value.", th.muted, 9, 400, 44)

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
    Lbl(g, "shop", 470, 312, 330, "Enter 0 to let the macro track bait itself (max 100).", th.muted)
    Lbl(g, "shop", 214, 352, 170, "Buy up to", th.muted)
    AddDdl(g, "shop", "baitPer", 390, 348, 70, ["10", "20", "30", "40", "50", "60", "70", "80", "90", "100"]
        , Min(10, Max(1, Cfg.baitPer // 10)))
    Ui.costLbl := Lbl(g, "shop", 470, 352, 340, "", th.txt)
    Lbl(g, "shop", 214, 384, 590, "The inventory holds 100 bait at most: the macro only buys what fits (50 in stock + 100 wanted = 50 bought).", th.muted)
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
    PageHeader(g, "hook", "Alerts", "Choose what the macro reports to Discord. Leave this page off if unused.")
    Panel(g, "hook", 213, 98, 592, 162)
    Panel(g, "hook", 213, 276, 592, 154)
    Panel(g, "hook", 213, 444, 592, 206)
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
    AddToggle(g, "hook", "hkCast", 500, 468, "Casting and hooked", Cfg.hkCast, 230)
    AddToggle(g, "hook", "hkCatch", 214, 502, "Fish caught + progress", Cfg.hkCatch, 200)
    AddToggle(g, "hook", "hkCatchShot", 500, 502, "Catch screenshot (slower)", Cfg.hkCatchShot, 230)
    AddToggle(g, "hook", "hkChest", 214, 536, "Chest collected", Cfg.hkChest, 200)
    Lbl(g, "hook", 214, 566, 400, "Hourly report webhook URL (optional - empty = same channel)", th.muted)
    AddEdit(g, "hook", "hkUrlHourly", 214, 588, 400, Cfg.hkUrlHourly, false, true)
    Ui.hookStatus := Lbl(g, "hook", 214, 616, 590, "", th.muted, 9)

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
    Ui.browserCtl := g.Add("ActiveX", "x0 y0 w1160 h758", "Shell.Explorer")
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
    g.Show("w1160 h758")
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

; ============================================================================
;  STARTUP
; ============================================================================
DllCall("winmm\timeBeginPeriod", "UInt", 1)          ; 1 ms timer resolution
OnExit(Cleanup)
CleanTmp()
LoadSettings()
DetectRdp()
ResetHour()
BuildGui()
Hotkey("F2", ToggleRun)
Hotkey("F3", TogglePause)
Hotkey("F4", (*) => ExitApp())
Hotkey("F8", ToggleDebug)
SetTimer(UpdateStats, 1000)
SetTimer(HourlyTick, 15000)
SetTimer(HookPump, 2200)
SetTimer(HistPush, 20000)
SetTimer(CheckForUpdates.Bind(false), -5000)
LogMsg("[env] remote desktop session: " . (Rdp.on ? "ON" : "off") . " (" . Rdp.how . ")"
    . (Rdp.on ? " - RDP-only bite filter, plain screen capture and cast lead " . Round(Rdp.castLead * 1000) . " ms are active" : ""))
LogMsg(APP_NAME . " ready. Stand at the " . Cfg.npc . " (Interact prompt visible), rod equipped, "
    . "Shift Lock OFF, then press F2.")
