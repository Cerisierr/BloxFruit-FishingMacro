; ============================================================================
;  CeriFish - Fishing Macro  -  AutoHotkey v2
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

#Include "modules\Input.ahk"

; ============================================================================
;  CONFIGURATION
; ============================================================================
APP_NAME    := "CeriFish"
APP_VERSION := "1.33.0"
INI_FILE    := A_ScriptDir "\BloxFishing.ini"
UPDATE_URL  := "https://raw.githubusercontent.com/Cerisierr/BloxFruit-FishingMacro/main/BloxFishing.ahk"
UPDATE_HTML_URL := "https://raw.githubusercontent.com/Cerisierr/BloxFruit-FishingMacro/main/BloxFishing.html"
UPDATE_LOGO_URL := "https://raw.githubusercontent.com/Cerisierr/BloxFruit-FishingMacro/main/images/cerifish-mark.png"
UPDATE_ICON_URL := "https://raw.githubusercontent.com/Cerisierr/BloxFruit-FishingMacro/main/images/cerifish.ico"
UPDATE_MODULE_URL := "https://raw.githubusercontent.com/Cerisierr/BloxFruit-FishingMacro/main/modules/"
UPDATE_MODULES := ["Input.ahk", "Core.ahk", "Vision.ahk", "NpcShop.ahk", "Fishing.ahk"
    , "Quests.ahk", "Settings.ahk", "ScreenIO.ahk", "Webhooks.ahk", "Reports.ahk"
    , "GameSettings.ahk", "Gui.ahk"]
HTML_FILE := A_ScriptDir . "\BloxFishing.html"
ICON_FILE := A_ScriptDir . "\images\cerifish.ico"
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
    diedHud: [0.3000, 0.7800, 0.7000, 0.8650], ; OCR crop for death status and selected-bait line
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
    castHold: 5.00, releaseLead: 0.0, castSettle: 1.20, quickHold: 0.30, quickSettle: 0.80, maxCastAttempts: 4, castRetryGap: 0.45
  , biteClickDelay: 0.05, hookedDelay: 0.05, biteToBar: 5.0, maxWaitBite: 30.0, maxReel: 12.0
  , flickGap: 0.08, flickSlowDelay: 0.50, flickSlowGap: 0.50, flickSettle: 0.35
  , catchConfirm: 0.30, popupDelay: 1.60, catchClickGap: 0.35, catchSettle: 0.30, recastDelay: 0.20
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
    resolution: "Auto", rodSlot: "4", fastBite: false, slowFlick: false, rodSkill: true
  , chest: true, anchor: true, flick: true, perfect: true, perfectPct: 97
  , zoomLock: true, zoomOut: 8, zoomEvery: 5, tiltPx: 70, dockWalk: 8, gameFast: true
  , questOn: true, questKey: "Z"
  , npc: "Fisherman", buyBait: true, baitType: "Basic Bait", baitNow: 0, baitPer: 40, baitRow: 0
  , sellOn: true, sellEvery: 100, trackIncome: true, trackLevel: true
  , theme: "Obsidian"
  , hkOn: false, hkUrl: "", hkUrlHourly: "", hkName: "CeriFish Macro", hkMention: ""
  , hkStart: true, hkStop: true, hkSale: true, hkShot: true, hkBait: true
  , hkErr: true, hkActions: true
  , hkBuy: true, hkCatch: true, hkCatchShot: false, hkBarMiss: true, hkChest: true, hkQuest: true, hkQuestDone: true, hkQuestFail: true
}

; Runtime state.
BotState := {
    running: false, debug: false, win: {x: 0, y: 0, w: 1920, h: 1080}
  , resW: 1920, resH: 1080, sc: 1.0
  , shiftLock: false, shiftVerified: false, rodEquipped: true
  , atNpc: true, bait: -1, sinceSell: 0, lastResponse: 0.0, witness: ""
  , flicked: false, lastEscaped: false, buyFailures: 0, lastBought: 0
  , meterFull: 0, biteInfo: "", zoomedAt: -1, biteMisses: 0
  , npcHits: 0, hpNext: 0.0, hpLostSince: 0.0, hpDead: false, hpOcrNext: 0.0, hpZeroReads: 0
  , diedHudVisible: false, diedHudReads: 0, diedHudMisses: 0, diedHudSeen: false, diedHudArmed: false
  , paused: false, stopReason: "", moneyLast: -1, lastOcr: "", logBuf: "", levelStart: -1, levelLast: -1, levelRead: 0.0, reportDue: false, hookQ: [], errAt: Map(), debugAt: Map(), stopShot: ""
  , biteBase: 0, biteBaseN: 0, biteFrame: 0, biteFrameW: 0, biteFrameH: 0, biteBox: 0
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

#Include "modules\Core.ahk"

#Include "modules\Vision.ahk"

#Include "modules\NpcShop.ahk"

#Include "modules\Fishing.ahk"

#Include "modules\Quests.ahk"

#Include "modules\Settings.ahk"

#Include "modules\ScreenIO.ahk"

#Include "modules\Webhooks.ahk"

#Include "modules\Reports.ahk"

#Include "modules\GameSettings.ahk"

#Include "modules\Gui.ahk"

; ============================================================================
;  STARTUP
; ============================================================================
DllCall("winmm\timeBeginPeriod", "UInt", 1)          ; 1 ms timer resolution
OnExit(Cleanup)
CleanTmp()
LoadSettings()
DetectRdp()
ResetHour()
if FileExist(ICON_FILE)
    try TraySetIcon(ICON_FILE)
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
