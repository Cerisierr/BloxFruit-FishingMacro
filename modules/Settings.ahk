; ============================================================================
;  SETTINGS  (BloxFishing.ini)
; ============================================================================
; [section, key, default, type]   type: s = text, i = integer, b = on/off
SETTINGS_SPEC := [
    ["display", "resolution", "Auto", "s"]
  , ["display", "theme", "Obsidian", "s"]
  , ["fishing", "rodSlot", "4", "s"]
  , ["fishing", "fastBite", "0", "b"]
  , ["fishing", "slowFlick", "0", "b"]
  , ["fishing", "rodSkill", "1", "b"]
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
  , ["webhook", "hkName", "CeriFish Macro", "s"]
  , ["webhook", "hkMention", "", "s"]
  , ["webhook", "hkStart", "1", "b"]
  , ["webhook", "hkStop", "1", "b"]
  , ["webhook", "hkSale", "1", "b"]
  , ["webhook", "hkShot", "1", "b"]
  , ["webhook", "hkBait", "1", "b"]
  , ["webhook", "hkErr", "1", "b"]
  , ["webhook", "hkActions", "1", "b"]
  , ["webhook", "hkBarMiss", "1", "b"]
  , ["webhook", "hkBuy", "1", "b"]
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
    if (Cfg.hkName == "Blox Fishing Macro") {
        Cfg.hkName := "CeriFish Macro"
        try IniWrite(Cfg.hkName, INI_FILE, "webhook", "hkName")
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
    if (Cfg.resolution != "Auto" && !RES_PROFILES.Has(Cfg.resolution))
        Cfg.resolution := "Auto"
    if !RegExMatch(String(Cfg.rodSlot), "^(?:[1-9]|0)$")
        Cfg.rodSlot := "4"
    baitValid := false
    for baitOption in BAITS {
        if (baitOption.name == Cfg.baitType) {
            baitValid := true
            break
        }
    }
    if !baitValid
        Cfg.baitType := BAITS[1].name
    if (Cfg.npc == "Angler")
        Cfg.sellOn := false
    Cfg.questKey := StrUpper(Trim(Cfg.questKey))
    if !Keys.SKILLS.Has(Cfg.questKey)
        Cfg.questKey := "Z"
    ; Early-release lead in ms (0 = release on the frame that shows a full bar).
    try Timing.releaseLead := Float(IniRead(INI_FILE, "fishing", "castLeadMs", "0")) / 1000
    try Timing.shotDelay := Float(IniRead(INI_FILE, "webhook", "shotDelayMs", "500")) / 1000
    SaveSettings()                                         ; persist repaired/default values (avoids blank/invalid controls next launch)
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
        Cfg.baitNow := Min(90, Max(0, IntOf(Ui.baitNow, 0)))
        Cfg.baitPer := Min(100, Max(10, Integer(Ui.baitPer.Text)))
        Cfg.sellEvery := Max(0, IntOf(Ui.sellEvery, 100))
        Cfg.hkUrl := Trim(Ui.hkUrl.Value)
        Cfg.hkUrlHourly := Trim(Ui.hkUrlHourly.Value)
        nm := Trim(Ui.hkName.Value)
        Cfg.hkName := (nm != "") ? nm : "CeriFish Macro"
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
            Ui.npcNote.Text := "Auto-sell only works with the Fisherman. It is unavailable with the Angler, which sells bait only."
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
