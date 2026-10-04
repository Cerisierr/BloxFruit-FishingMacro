# Changelog: CeriFish — Fishing Macro (AutoHotkey v2)

Current delivered files: `BloxFishing.ahk`, `BloxFishing.html`, and CeriFish logo assets (v1.29.3 below).
Nothing is pending from the earlier "not delivered" list except the open points at the bottom.

---

## v1.29.3: Fit the control panel to the available screen

- Size and center the app window within the primary monitor's work area.
- Let the HTML interface reflow on narrow RDP displays instead of forcing a 980 px minimum width.

---

## v1.29.2: Add the CeriFish CF logo

- Create a geometric CF monogram based on the supplied reference for the app header and Windows icon.
- Use a multi-size Windows icon for the app window and taskbar.
- Include the logo files in GitHub updates so the interface and icon remain in sync.

---

## v1.29.1: Rename the app to CeriFish

- Replace the Blox Fruits app branding with CeriFish and update the logo initials to CF.
- Update the default Discord display name and migrate the old default name while preserving custom names.

---

## v1.29.0: Rename Alerts to Webhook

- Rename the Webhook page and dashboard shortcut so their purpose is clear.

---

## v1.28.9: Make Obsidian the default theme

- Set Obsidian as the default for new settings while keeping an existing saved theme choice.

---

## v1.28.8: Schedule hourly reports on the PC clock

- Send automatic reports at the start of each local PC clock hour while the macro and webhook are active.
- Removed the configurable interval and enable/disable controls; the hourly schedule is now fixed. Manual **Send report now** is still available.
- Show the next full-hour report time in the status line and explain the schedule in the interface and README.

---

## v1.28.7: Theme help panels, branding and tab hover

- Apply the selected theme to the BF logo, Fishing Macro label and callouts used for NPC, quest and dashboard guidance.
- Make hovered navigation tabs use the current theme accent, and clear the temporary hover state on mouseout.
- Added a dashboard screenshot preview to the README.

---

## v1.28.6: Color every action button with the active theme

- Apply the selected theme's accent background, border and readable text color to all `.btn` controls, including header, footer and dashboard actions.

---

## v1.28.5: Clear stale selected colors

- Clear inline highlight colors from navigation tabs as soon as they become inactive.
- Clear the previous theme's selected border so only the current theme stays highlighted.

---

## v1.28.4: Apply theme accents consistently and align switches

- Apply the selected accent to active navigation, selected theme, primary actions and button borders.
- Position setting switches at the right edge of every row in the embedded browser.

---

## v1.28.3: Match active controls to the selected theme

- Apply the selected theme's accent color directly to enabled switches and primary action buttons in the embedded interface.

---

## v1.28.2: Fix hosted panel layering and switches

- Keep the embedded HTML panel above the legacy AHK controls when the window is shown.
- Use explicit switch-knob elements so enabled switches align their knobs to the right in the embedded browser.

---

## v1.28.1: Fix updater rollback syntax

- Fixed the AutoHotkey v2 `if`/`else` structure in the updater's recovery path so the script parses correctly.
- Kept cleanup and interface restoration inside explicit `try` blocks.

---

## v1.28.0: External HTML interface loaded by AHK

- Moved the dashboard markup and styling into `BloxFishing.html` beside the AHK script.
- AutoHotkey v2 now loads that local file inside its GUI using the built-in `Shell.Explorer` ActiveX control; no separate browser window is opened.
- Removed the AHK-generated HTML strings that caused the startup syntax error shown in the report.
- Updated the GitHub updater to download, back up and install the AHK and HTML files together.
- Not launched in AutoHotkey or Roblox; visual rendering and button interaction remain unverified.

---

## v1.27.0: Embedded HTML control panel

- Replaced the native AHK dashboard display with a responsive HTML/CSS control panel hosted inside the macro window; it does not open an external browser.
- Grouped the existing fishing, camera, dock, NPC, bait, quest, Discord, appearance and log settings into dedicated sections.
- Wired the HTML switches and fields to the existing AHK settings, validation, persistence, actions and live session status.
- Kept the interface in the single AHK file so the existing GitHub updater can update the UI and macro together.
- Not launched in AutoHotkey or Roblox; in-window rendering and interaction remain to be visually verified.

---

## v1.26.0: Dashboard redesign

- Replaced the top tabs with a left navigation bar, a persistent macro status panel and a wide footer.
- Added a dashboard with live session totals and direct links to the functional Fishing, NPC + Bait, Quests and Alerts settings.
- Added clear card panels to every settings page and moved the activity stream to its own Logs page.
- Updated the default Midnight palette to the blue/navy style of the requested reference.
- Kept one AHK file so the GitHub updater can install a complete, self-contained update.
- Not tested in AutoHotkey or Roblox.

---

## v1.25.1: Fix startup error in the update checker

- Renamed the update-comparison parameters that used AutoHotkey's reserved word `local`. The script now starts normally, and GitHub version checks can run.
- No other behavior changed.
- Not tested in AutoHotkey or Roblox.

---

## v1.25.0: Simpler navigation and GitHub updates

- **Navigation:** renamed the pages by task (Fishing, NPC + Bait, Quests, Alerts, Display) and reduced the blank area under the tabs.
- **Home:** separates the two positioning cues: use the lower white circle below the green ring for NPC visits; return to the dock edge to fish.
- **Footer:** added an Updates button; an idle startup check looks for the latest version on the repository's main branch. The macro asks before replacing the current script, saves a `.bak` backup, then restarts.
- **Settings:** clarified the camera/casting, bait/stock and selling/stats groups. Kept the macro as one AHK file so the updater can replace it as a single download.
- **Not tested in AutoHotkey or Roblox.**

---

## v1.24.6: Clearer navigation and persistent controls

- **Window layout:** replaced the side navigation with a compact top tab strip and kept Start / Stop, Pause, Check setup, Quit and running status together in a fixed footer.
- **Settings pages:** aligned the existing controls under the tabs and removed the large sidebar so more space goes to the active page.
- **Setup guidance:** kept the lower white NPC circle instruction on Home and clarified the fishing page description.
- **Inspired by NatroMacro's native tabs and persistent controls; no code was copied.**
- **Not tested in the game** (I cannot run AutoHotkey here).

---

## v1.24.5: Cleaner GUI and clearer setup

- **Home:** replaced the cramped three-card strip with one short setup panel: use the lower white NPC circle, choose the NPC and bait, then press F2.
- **All settings pages:** replaced full-width divider rules with small accent markers so sections read clearly without adding more boxes. Kept larger field and toggle text for legibility.
- **Fishing settings:** clarified the extra walk input and its units; the movement remains time-based and adjustable.
- **Not tested in the game** (I cannot run AutoHotkey here).

---

## v1.24.4: False chest + false "character dead"

- **What you saw:** a chest was "grabbed" that was not there, the zone left the fish, the reel gave up after 12 s, and then the macro stopped with `[death] HP bar gone for 3 s`.
- **False chest:** a chest now has to be seen on 4 reads in a row at the same spot and be at most 14 % of the track wide (single orange pixels from the fish or the scenery no longer count). While the zone is still travelling to a chest, if the chest is no longer on the track for 0.8 s it is dropped: `[chest] it is not on the track any more (false chest) - back to the fish`. The 2.5 s hold once the zone sits on a chest is unchanged.
- **False death:** the HUD (HP bar) is hidden while a gold-banner card is up, such as the catch card "Species / Weight" (your screenshot) or an NPC speech, and the old check took "no green bar for 3 s" as dead. Now death means the Health text reads **0/x**: when the bar has no green fill, the Health text is read with OCR once a second, and two reads in a row of 0/x stop the macro (`[death] Health reads 0/x - character is dead, stopping`). A hidden HUD has no text, so it is never a death.
- Not tested in the game (I cannot run AutoHotkey here).
---

## v1.24.3: Bait purchase - Craft -> Back, then no Nevermind

- **What you saw:** after Craft the macro clicked Back and then went straight back to fishing without clicking Nevermind.
- **Cause:** between Back and the root menu the button stack disappears for a moment. The macro read that as "dialogue closed" and stopped clicking. This hits most when the bait page and the root page have the same number of rows (Angler: it leaves by clicking the bottom row repeatedly).
- **Now:** the dialogue counts as closed only if it stays closed for about 0.9 s (new `StaysClosed()`). If the menu comes back, the macro clicks the bottom row again (Nevermind) and logs `[shop] the menu is still there (page change) - clicking again`. Used by both leave routines (`LeaveDialogue`, `LeaveByBottomRow`), so it also covers sales and quest visits.
- Not tested in the game (I cannot run AutoHotkey here).
---

## v1.24.2: Still "finished" on the 2-bar quest + "Still waitin'" from the Angler

- **What you saw:** log `active quest: 3 perfect casts + 3 reactions (3/3)` then `objective complete (3/3)`, and the Angler answered "Still waitin' on you to get that task done." OCR had read only one counter (`3/3`), missed `0/3`, and the macro took that for "all done".
- **Perfect quest:** it has two objectives, so it is now done only when OCR reads at least two counters and all are n/n. One counter read is treated as an OCR miss.
- **Angler says "Still waitin'..." at the hand-in:** the macro now takes this as "NOT done". The quest goes back to active, the hand-in is not counted as failed or done, and every finished signal (bar or OCR) is ignored for 2 min. For a 2-counter quest the block is lifted early once OCR really reads every counter as n/n. Log: `the Angler says the task is NOT done yet`.
- Not tested in the game (I cannot run AutoHotkey here).
---

## v1.24.1: "Quest finished" fired too early on the 2-bar quest

- **What you saw (screenshot):** "Perform 3 Perfect Casts 0/3" + "Perform 3 Perfect Reactions 3/3". The reactions bar was full, so the macro logged "the progress bar is full - handing the quest in" while the casts were still 0/3.
- **Cause:** the pixel scan (`QuestBarDone`) returns true as soon as ANY bar in the quest panel is full.
- **Now:** for the perfect-casts quest (or any panel with several counters, `a/b + c/d`) the bar scan is skipped. The quest is done only when OCR reads every counter as n/n. For that quest the panel is read every 10 s instead of 45 s.
- Single-bar quests are unchanged.
- Not tested in the game (I cannot run AutoHotkey here).
---

## v1.24.0: Stop / error messages no longer carry the hourly report

- **What you saw:** stopping the macro (or an error stop) posted "Macro stopped / Stopped manually. Session summary:" with the same image card as the hourly report, in the normal webhook channel.
- **Now:** the stop and error messages are plain text embeds (run time, fish, money, bait, net profit, casts, levels, quests) and go to the normal webhook only. The hourly report image card is sent only when the hour is up (or with "Send report now"), and only to the **hourly report webhook URL** (the normal one if that field is empty).
- **Error stops:** one message "Macro stopped - needs attention" with the reason, the summary, the last 8 log lines and the game screenshot attached (before, the screenshot came as a second message and the card as a third). Start-up failures work the same way.
- Not tested on Discord (I cannot run AutoHotkey here).

---

## v1.23.0: The quest survives a restart + the quest objectives are really done

- **Stop / restart during a quest:** the quest state is now saved in `BloxFishing.ini` (`[quest]`: state, type, rarity, timed, progress, panel text, accept time, next-ask time). On start the macro reads it back (`[quest] resuming the quest from the last session: ...`), keeps fishing for it and does NOT ask the Angler for a new one. The quest panel is checked at the first tick: if it is still there the quest continues; if it is gone (two empty reads in a row) the macro logs that the quest ended while it was stopped (no "failed" message, not counted) and goes on. A saved quest older than 12 h is ignored.
- **The 15 min cooldown also survives a restart:** the next-ask time is saved, so a restart does not ask the Angler again right away.
- **First read at start:** an empty first read of the quest panel is repeated once after 2 s before the macro decides there is no quest (it used to trust one OCR miss).
- **Quest progress:** all counters of the panel are read (`1/3 + 0/3`), written to the log as `[quest] progress: ...` when they change, and shown on the Dashboard / Quest tab.
- **"3 perfect casts + 3 perfect reactions" is now really done:** while this quest is active the macro forces Perfect cast ON (whatever the switch says), releases at least at 97 % (or your setting if higher), and forces the fast bite reaction. The cast log line ends with `[perfect-cast quest]`. The fast bite reaction is also forced during the "3 fish within 2:05" quest.
- Not tested in the game (I cannot run AutoHotkey here).

---

## v1.22.0: Angler cooldown message + game screenshot on every error

- **"I don't have any tasks for you right now, come back in a little bit." (your screenshot):** this is the Angler telling us the 15 min cooldown is still running (the previous quest was already done). It is a text-only box (no buttons), so before this version the macro clicked it away *before* reading it and then treated it as "nothing to accept". Now the text is read first (OCR, after a 0.7 s wait for the typing), logged as `[quest] the Angler says (no buttons): '...'`, then clicked away. If it matches (any tasks / come back / little bit / right now), the macro asks again when the cooldown ends: 15 min after the last accept, never later than 15 min from now, never sooner than 60 s (5 min if the accept time is unknown, e.g. a restart). This is not counted as a failed visit and does not grow the 60/120/... s retry delay.
- **Game screenshot on every problem:** the whole game window is saved in the new `errors` folder next to the script (`err_<date>_<time>_<tag>.png`, the newest 40 are kept) and sent to Discord with the error message, the run time, and the last 8 log lines. It uses the **Errors + game screenshot** toggle (Webhook page). The log prints `[error] game screenshot saved: <path>`. Triggers:
  - every safety stop (`Halt`), taken at the moment of the stop;
  - a failed shop / bait / quest visit (taken BEFORE the recovery moves the screen);
  - a cycle error (at most one per 60 s);
  - start-up failure (anchor / Shift Lock);
  - a quest that failed (attached to the "Quest failed" message too);
  - an unknown quest text, a quest page that is not the offer, "Yes" answered but no quest panel (at most one per 60-120 s each).
- Not tested in the game or on Discord (I cannot run AutoHotkey here).

---

## v1.21.0: Quest webhooks + quests in the hourly report

- **Three quest webhooks** (toggles on the **Quest** tab, "DISCORD" section; the old "Quest accepted / done" toggle on the Webhook page moved there):
  - **Quest accepted:** the quest to do (label, the quest-panel text as read by OCR, normal/timed, next quest in ~15 min, session counts).
  - **Quest finished:** quest, time taken, session counts.
  - **Quest failed:** the quest panel vanished before the objective was complete (timed out or abandoned), the hand-in did not register after 3 tries, or auto-quest was switched off after 3 failed visits. Shows the reason and how long it was open.
- **Hourly report:** the text report has a "Quests" field (accepted / done / failed) and a "Quests this hour" list (`[done]`, `[failed]`, `[ongoing]` + label). The image card has a new full-width **QUESTS** panel (accepted / done / failed counts + the last 3 quests) and is now 1000x830. The stop summary also has the Quests line.
- New counters: `questsAcc`, `questsFail` (session + hourly window). New ini keys `[webhook] hkQuestDone`, `hkQuestFail` (default on).
- A quest that is already open when the macro starts is also tracked and reported when it ends.
- Not tested in the game or on Discord (I cannot run AutoHotkey here).

---

## v1.20.0: Quest tab, quest dialogue click, quick cast

- **New "Quest" tab** (sidebar, after Fishing). The Auto-quest switch and the Rod skill key moved there from the Fishing page. It also shows the live quest state, the four quests the macro handles, and a note on the Fisherman quests. The Fisherman has other quests whose dialogue pages the macro does not know yet: send a screenshot of each one. Any quest text the macro cannot match is now logged as `[quest] UNKNOWN quest text ...`.
- **Stuck after accepting a quest (your screenshot):** after **Yes**, the Angler shows a text-only box (gold banner + "Use your fishing rod's skill 3 times.", no buttons) that stays until it is clicked. The macro thought the dialogue was closed because no buttons were showing. New `AdvanceDialogueText()`: while the gold banner is up and there is no button stack, it clicks the speech box (up to 6 times, 0.7 s apart) until the banner is gone or the buttons come back. It is used after **Yes** and also during the hand-in wait. New click point `Points.dialogueText` (0.50, 0.82).
- **Quick cast when Perfect cast is OFF:** the old classic path still searched for the charge meter (full-region pixel search) before releasing, which is what made every cast slow. Now it is press, hold `Timing.quickHold` (0.30 s), release, then check only that no NPC dialogue opened. Wait after the cast is `Timing.quickSettle` (1.0 s instead of 1.6 s). Perfect cast ON is unchanged.
- **Inventory opening at the anchor:** I found no key or click in the code that opens the inventory (the macro only presses the rod slot digit, Shift, W/S and Z/X/C/V/F). So I could not fix it blind. During the anchor and every quest visit the log now prints `[click] menu click at x,y` for each click, and the `[input]` / `[start]` lines show the order. Send the log lines around `[start] opening NPC dialogue` the next time the inventory opens, and say which key or button you see it with. A stuck text-only dialogue (see above) is a possible cause, since the macro went on pressing the rod slot while the dialogue was still open.
- Not tested in the game (I cannot run AutoHotkey here).

---

## v1.19.0: Auto-quest at the Angler

- **What it does (only with "AFK at" = Angler):** every 15 min the Angler offers one quest. The macro opens the Angler, clicks **Quest**, and when the page "Lookin' to do something for me?  Yes / No / Back" shows, answers **Yes**. It keeps fishing, and when the quest is finished it talks to the Angler again, clicks **Quest** once to hand it in, then leaves with **Nevermind**.
- **Cooldown (from the wiki):** 15 min counted from *accepting* a quest, and an unfinished quest must be finished or abandoned before a new one is offered. So the macro only asks for a new quest when the quest panel (top-left HUD) is empty, and the next try is 15 min after the last accept. If nothing is on offer it asks again after 60 s, 120 s ... up to 300 s.
- **How it sees the quest:** the quest panel is read with Windows OCR (title, objective, `n/m` counters, "within / remaining" for the timed one) every 20 s (timed quest) or 45 s, and the progress bar is checked every cycle by a cheap pixel scan (a long, thin, bright-yellow bar = full). Finished = bar full or every counter n/n. One empty read does not end a quest, two in a row do.
- **Per quest type:**
  - *Catch a Common..Mythical fish:* nothing special, normal fishing. An Epic or Mythical quest can take a long time and blocks the next one.
  - *Catch 3 fish within 2:05:* sales and bait trips are postponed while it runs (bait trips still happen if 5 bait or fewer are left), and the hand-in has priority at the start of the next cycle.
  - *3 perfect casts + 3 perfect reactions:* the bite reaction is forced to Fast-bite speed while this quest is active. Turn **Perfect cast** on for it.
  - *Use a rod skill 3 times:* one rod skill key is pressed at the start of each reel until the quest is done. Key: **Rod skill key** (default Z, Reel Boost), Fishing page.
- **Safety:** the macro never answers Yes unless the page text says "Lookin' / do something for me" (a different Yes/No page, like an abandon prompt, is backed out of). If OCR returns nothing at all it trusts the empty quest panel. Three failed visits in a row switch auto-quest off until the next start. A hand-in that does not register is retried 3 times, then dropped.
- **New settings:** *Fishing* page > ANGLER QUEST: **Auto-quest** switch (on by default, only active with the Angler) and **Rod skill key**. *Webhook* page: **Quest accepted / done**. The hourly report has a "Quests done" field and the Dashboard line shows the quest state.
- **Log lines:** `[quest] ...` for every step, including `[quest] the Angler says: '<text>'` after each Quest click.
- Not tested in the game. The quest panel region, the bar colour and the hand-in page are from your screenshots only. If something is off, send the `[quest]` lines (and a screenshot of the quest panel / dialogue if the text looks wrong).

---

## v1.18.5: Report card never drew (wrong GDI+ function name)

- **What your log showed:** `[card] could not draw the report image: Call to nonexistent function.` The hourly report went out as the plain text embed, with no image.
- **Cause:** `Gp.Text` called `GdipSetStringFormatLineAlignment`, which does not exist in gdiplus.dll. The real export is `GdipSetStringFormatLineAlign`. The first text drawn on the card threw, so the card never rendered (in v1.18.0 to v1.18.4). The picture shown earlier was a mock-up of the layout, not output of the macro.
- **Fix:** the function name. Checked: every other `gdiplus\` function name used by the card and screenshot code is a real export, and no undefined AHK function is called anywhere in the script.
- **Log:** the `[card]` line now also prints the failing function and line, so if another problem shows up it is named.
- The "hourly advantage" panel from v1.18.4 is drawn on the same card, so it appears now too.
- Not tested in the game or on Discord (I cannot run AutoHotkey here).

---

## v1.18.4: Hourly advantage (this hour vs previous hour)

- **New panel on the report card:** fish per hour, money per hour and levels per hour of the current window, each compared with the previous hour (arrow, % change, previous value). Green = better, red = worse.
- **First report:** there is no previous hour yet, so the panel shows the current rates and says the comparison starts with the next report. A previous window shorter than 5 min is not used as a baseline.
- **Stop summary:** compares the window since the last report; if that is under 5 min, the whole session is used instead.
- **Text fallback / embed:** the same comparison is added as a line ("Vs previous hour") so it is also there if the image cannot be drawn.
- **Log:** if the card cannot be drawn, the log now says the text version was sent instead.
- Card canvas is now 1000x700.
- Not tested in the game or on Discord.

---

## v1.18.3: Cast meter on a dark background (released late and weak)

- **What your screenshot (1363x770, meter at x 452) showed:** the empty track inside the meter is (28-36, 26-31, 26-28), very dark. The outline is black (0-15). The code treated every pixel with max <= 32 as "outline", so the dark track interior counted as the outline and `IsMeterTrack` (which required > 32) did not accept it either.
- **Effect (simulated on that screenshot):** the meter was measured from the top of the fill instead of the real top, so its height was just the fill height (99 px of a 213 px track) and the level read 0.99 instead of 0.46. The meter was also rejected while the fill was shorter than 7% of the window height, so nothing was seen for the first seconds of the hold, and the cast then released at once at a mid level.
- **Fix:** outline = max <= 20 (`IsMeterEdge`), empty track = max > 20 (`IsMeterTrack`). On the same screenshot the track is now 213 px (top 495, bottom 707) and the level reads 0.46 (yellow = mid, as expected).
- Applies to every resolution and to non-RDP too (an earlier normal-texture track was 33, only 1 above the old limit). Brighter tracks (25,55,69) are unaffected.
- Not tested in the game.

---

## v1.18.2: RDP-only changes (normal desktops unchanged)

- **New `Rdp.on` flag:** set automatically when Windows reports a remote session (`GetSystemMetrics(SM_REMOTESESSION)`). Override in `BloxFishing.ini`: `[game]` `rdp=auto|on|off`. The log prints `[env] remote desktop session: ON/off` at start.
- **Gated behind it (so 1920x1080 and 2560x1440 on a normal desktop run the pre-1.18 logic):**
  - the plain screen capture (the original `CAPTUREBLT` capture is back on a normal desktop);
  - the salmon marker colour and the 150 ms scenery baseline of the bite detector (the original colour rule is used otherwise);
  - the first Nevermind/Back click (original `ClickMenuAction`); only retries after a failure use the new slower, fixed-point clicks.
- **RDP cast lead (new):** over RDP the charge bar is seen late, so the cast looks ahead by `[game]` `rdpCastLeadMs` (default 80 ms) when `castLeadMs` is 0. If casts release too early over RDP, lower it; too late, raise it. Not measured, it is a starting value.
- **Not touched:** resolution profiles, click points, the report card (it draws its own image and does not read the screen).
- Not tested in the game.

---

## v1.18.1: Stuck on Nevermind / Back

- **Likely cause (from the code, no log yet):** the bottom-row click used "the last panel the detector found". The button under the cursor changes colour on hover and can drop out of the detection, so the last detected panel was a different row (for example Job Stats), and every retry repeated the same wrong click. Clicks over remote desktop could also be dropped (same effect as the Craft window in v1.11).
- **Fix (`NevermindClick`):** the detected bottom row is used only if the stack is complete or the lowest panel is where the bottom row should be (within 4% of the window height); otherwise the calibrated bottom-row point is clicked. Each retry waits longer over the button (0.15 s up to 0.50 s) and holds the press longer (0.06 s up to 0.20 s). Attempts 3 and 5 always use the fixed point. From attempt 2 the cursor is first moved to the window centre to wake the hover state.
- **Retries:** `LeaveDialogue` now tries 4 times (was 3); `RecoverDialogue` 4 (was 3).
- **Log:** `[shop] nevermind/back attempt N: <how> at X,Y` on every click. If it still sticks, send those lines.
- Not tested in the game.

---

## v1.18.0: Bite detection rebuilt for RDP, image report card

- **Why "hooked" was wrong (measured on your 1363x766 RDP screenshot):** the real "!" marker body is salmon, about (248,117,130). The old rule only matched the anti-aliased edge of the marker (114 of about 3,300 pixels), so detection depended on what was behind the marker and could fire on other pink/red shapes.
- **Marker colour:** both the salmon body and the old pink edge are accepted (`IsBitePx`). On your two screenshots: the frame with "!" gives a 130x118 px blob, the frame without gives nothing.
- **Baseline:** right before waiting for a bite, two frames 150 ms apart are compared; marker-coloured cells present in both are scenery (cape, bobber, rod glow, anything static) and are ignored for that cast. Log: `[bite] N marker-coloured cells already on screen - ignored`.
- **False-hook evidence:** the frame that fired a bite is kept in memory; if the reel bar then never appears, it is saved as `%TEMP%\BloxFishing\bite_false_HHmmss.png` and the log prints the path (`possible FALSE HOOK`). The `[bite] hooked (...)` line now also shows the blob position.
- **Screen capture:** `CAPTUREBLT` removed (plain `SRCCOPY`), because it makes the cursor flicker over RDP. `PngSave` already used plain `SRCCOPY`.
- **Report card (new):** the hourly report and the stop summary now attach a StatMonitor-style PNG drawn with GDI+: money-earned chart, levels-gained chart, panels for the last period and the session (money gained, levels gained, time), plus fish caught, fish per hour, level and bait spent. History is sampled every 20 s and at each sale. If the image cannot be drawn, the old text embed is sent instead (`[card]` line in the log).
- Not tested in the game or on Discord. If hooks are still wrong, send the `[bite]` log lines and the `bite_false_*.png` file.

---

## v1.0: Python to AHK conversion

- Ported the Python macro (`Fishing-Macro-master`) into a single AHK v2 file.
- Added a screen resolution profile: Auto, 1920x1080 or 2560x1440.
- All regions and click points are fractions of the game window, so both resolutions share the same calibration.
- Ported the cast, bite, reel and shop logic.
- Reel controller: same time-optimal switching law as the Python version. In a simulation it kept the fish inside the zone 100% of the time.
- Added a settings window, saved to `BloxFishing.ini`.
- Hotkeys: F2 start/stop, F4 quit, F8 debug log.
- The script restarts itself as administrator.
- Checked: syntax validation, and a rendered reel bar was found at the right position.

## v1.1: Detection fixes (first screenshots)

- **Dialogue not seen:** the "dark panel" test merged the four buttons into one block, so it never matched. It now splits them correctly. On your screenshot it finds the 4 buttons at the right positions.
- **Bite marker:** it now finds each pink blob separately instead of merging every pink pixel on screen.
- **Perfect cast (first attempt):** added a "Perfect cast" checkbox that releases at full charge.

## v1.2: Zoom, bait, sell, dialogue

- **Camera zoom lock:** zooms all the way in, then out by a set number of notches. It runs at start, after each shop trip, and every 5 casts.
- **Cast meter:**
  - The meter reading was capped at 20% of the screen height, which clipped every reading and made casts release early. The cap is now 50%.
  - Yellow fill is now accepted as well as green.
- **Dialogue detection:** it now needs both the button stack and the yellow NPC name banner, so dark scenery alone no longer counts.
- **Craft window detection:** it now needs a solid yellow block, so yellow clothes no longer match.
- **Bait and sell:**
  - "Bait now" is tracked on its own, without needing "Buy bait".
  - "Sell every" works on its own.
  - The macro stops at zero bait when "Buy bait" is off.
  - This logic was tested in a simulation.

## v1.3: Robustness

- **Menu panels:** found by their flat slate colour instead of "darkness", so the sea colour no longer matters.
- **Hover recovery:** a panel whose colour changes under the mouse is recovered from its white icon.
- **Missed bites:** two casts in a row with no bite are treated as "out of bait".
- **Logs:**
  - The start of the log echoes the settings that were read.
  - The status line shows `catches | bait | sale in N`.
  - A failed shop trip logs what the screen looked like.

## v1.4

- Label change only: "Bait per purchase (x10)" became "Bait per purchase".
  Enter the real number: 10 for 10 bait, 20 for 20 bait.
- **Known bug in this version:** values from 1 to 9 are rounded up to 10, so a value of 2 buys 10 bait, not 20 (fixed in v1.7).

---

## v1.5: Cast fix, bait, NPCs, webhook, new window

Built from the screenshots you sent. Not yet tested in the game: the script was only checked statically (brackets, duplicate or missing functions).

- **Perfect cast (fixed at the root):**
  - The meter fill is orange at the bottom, then yellow, then green. The old reader only accepted green and yellow, so it never saw the bar fill or drain.
  - The meter is now found by its fill colours and measured against its own track (black outline, dark inside), so the camera distance no longer matters.
  - The macro reads the fill level every tick and releases when it reaches the chosen percentage (default 97%). The bar bounces, so a missed rise is not a problem: it waits for the next one.
  - If the bar stops just under the threshold, it releases after it has stayed still for 0.12 s.
  - Maximum hold is 5 s. Default zoom-out is now 8 notches.
- **Bait counting:** bait is now used up only when the reel bar really appears. "bar never appeared" no longer costs bait.
- **Choice of bait:** Basic, Kelp, Good (Sea 1), Abyssal, Frozen (Sea 2), Epic, Carnivore (Sea 3), with the price per 10 and the extra item (Demonic Wisp, Yeti Fur, Terror Eyes, Dragon Scale). The window shows the pack count and total cost.
- **Choice of NPC:**
  - The **Fisherman** buys bait and fish.
  - The **Angler** sells bait only. Auto-sell is switched off when the Angler is selected.
  - Angler path: Bait, then the bait row, then the craft window. The way out clicks the bottom row (Back, then Nevermind).
- **Menu detection:** buttons are now also found by their outline (4 px of pure black for an active button, grey 72 for a LOCKED one), because the fill colour changes with the scenery behind the buttons. The better of the two results is used.
- **Discord webhook (new page):**
  - Settings: on/off, URL (hidden by default), display name, optional user ID to mention on errors, "Send test".
  - Events: started, stopped with a session summary, fish sold, bait purchased, errors and safety stops, hourly report.
  - A screenshot of the strip below the screen centre is taken right after each sale and attached to the "Fish sold" message.
  - Sending uses `curl.exe`. The window shows "delivered (HTTP 204)" or "FAILED" about 5 s after each send.
- **Hourly Report:** money generated, bait bought and money spent, fish caught, net profit, casts and escapes, fish per hour, session totals. The interval is adjustable. "Send report now" sends it immediately.
- **Income:** read from the $ counter (bottom-left) with the Windows built-in OCR, before and after each sale. If that fails, the macro tries to read the sale screenshot instead.
- **New window:** sidebar with Dashboard, Fishing, Shop and Bait, Webhook and Appearance; stat tiles; 7 themes (Midnight, Obsidian, Ocean, Emerald, Sunset, Rose, Daylight); switches instead of checkboxes; settings saved automatically.
- The window is no longer "always on top", so it cannot hide the game area the macro reads.

## v1.6: Levels, report screenshot, title fix

- **Level tracking:** the level ("Lv. 868", under the $ counter) is read with OCR at start, every 5 minutes between casts, and just before each hourly report. Levels gained are counted and shown on a new Dashboard tile, in the start message, the stop summary and the hourly report. A jump of more than 25 is treated as an OCR error. A "Track levels" switch is on the Shop and Bait page.
- **Hourly report screenshot:** the report now also attaches a screenshot of the bottom-left block (money and level).
- **Window:** the large titles, the sidebar name and the tile numbers were cut off because their text boxes were too short. They are taller now.
- The version number shown in the window is now 1.6.0.

## v1.7: Bait per purchase list, 100-bait cap

- **Bait per purchase** is now a drop-down from 10 to 100 (steps of 10). The rounding bug (1 to 9 becoming 10) is gone because the field no longer takes free numbers.
- **Inventory cap:** the inventory holds at most 100 bait, so the macro buys only what fits: `min(wanted, 100 - bait in stock)`. Example: 50 in stock and 100 wanted buys 50; 1 in stock and 100 wanted buys 90. If the inventory is already full it skips the purchase and says so in the log.
- The tracked bait count is capped at 100 as well, and "Bait in inventory now" accepts 0 to 100.
- This relies on the bait count: enter your real stock in "Bait in inventory now" (0 = not counted, then the cap cannot be applied before the first purchase).
- Not tested in the game.

## v1.8: Live webhook messages

- **New "Live activity" group** on the Webhook page:
  - **Buying bait / selling fish:** a message when the macro starts a purchase (type, quantity, cost) or a sale (fish in stock).
  - **Casting and hooked:** a message for each cast (with the release percentage) and each bite. Off by default because it is chatty.
  - **Fish caught + progress:** catch number, catches until the next sale, bait left, level, fish per hour, chests.
  - **Catch screenshot:** attaches a screenshot of the Species/Weight card. The fast "flick" trick hides that card, so while this option is on the macro waits for the card instead, which makes each catch about 2 s slower. Off by default. The screenshot area (`catchShot` in the code) is a guess, check the first one.
  - **Chest collected:** a message when the zone reaches a chest and holds it. Chests are also counted in the hourly report and the catch message.
- **Message queue:** messages are sent one every 2.2 s so Discord's rate limit is not hit. If the queue is full, the live "casting/hooked/buying/selling" messages are dropped first.
- The window is a little taller (640) to fit the new switches.
- Not tested in the game or on a real Discord channel.

## v1.9: Income read fix, bait screenshot, live bait counter

- **Income "unreadable" (fixed):**
  - Cause: the $ was read while the Fisherman dialogue was still open, and the dialogue hides the bottom-left HUD. The counter also updates a moment after Confirm, and it was only read once.
  - Now: the $ is read before opening the NPC (3 tries), then after the sale the macro leaves the dialogue if it is still open and polls the counter until it has changed and shows the same value twice. Gain = after - before.
  - The region now skips the "$" sign, which OCR often misreads as a digit.
  - The log shows `[money] before/after` and the raw OCR text when a read fails.
  - The unreliable fallback (reading numbers from the sale text) is removed.
  - The "Fish sold" message now shows `Balance: $before > $after` and attaches the HUD ($ + level) after the sale instead of the dialogue text.
- **Bait purchase screenshot:** the Craft window is captured just before Craft is pressed (quantity and price visible) and attached to "Bait purchased", which also shows the inventory total. The `hkShot` switch is now labelled "Screenshots (sale, bait, report)". Region: `craftShot` in the code.
- **"Bait in inventory now" is live:** every bait used or bought updates the field and the saved setting, so the next start resumes from the real count. Editing the field during a run corrects the tracked count.
- Not tested in the game.

## v1.10: Step away when the cast talks to the NPC

- If the cast click opens the NPC dialogue again (standing too close after the anchor), the macro now closes it and taps W (forward, away from the NPC) for a short time before retrying: 70 ms the first time, +30 ms for each repeat in a row, up to 300 ms. The streak resets after a cast that charges. Tune with `stepAwayTap`, `stepAwayAdd` and `stepAwayMax` in `ShopCfg`.
- Not tested in the game. If W moves you toward the NPC in your layout, swap `SC_W` for `SC_S` in `StepAwayFromNpc`.

## v1.11: Craft window clicks (+ and Craft not registering)

- **What the video showed:** the Craft window was detected correctly, the money never changed, the quantity stayed at 10 and neither + nor Craft showed any reaction. Only the final Close click (from the error recovery) registered, so the fixed click positions are right but the earlier clicks were not accepted by the game.
- **Fixes:**
  - Waits 0.4 s after the Craft window appears, so its pop-up animation has finished.
  - Craft-window clicks now settle 0.30 s over the button and hold the press 0.12 s (was 0.15 s and 0.06 s), so a low game frame rate cannot miss the click.
  - Every `+` click is verified: the "10" on the bait icon (`craftQty` region) is compared before and after. If nothing changed, the click is repeated (up to 3 times); if it still does nothing the shop trip stops with a clear error.
  - The Craft button is pressed up to 4 times, each time waiting 3 s for the window to close (was 6 s).
- **Log:** new lines show the game area, the exact click positions and whether each `+` click changed the quantity.
- Not tested in the game.

## v1.12: Too close to the NPC (Interact prompt)

- **What the video showed:** the character stood right behind the Fisherman, so the NPC filled the screen. The meter reader took the NPC's yellow coat for a full cast meter ("released at 99%", no real cast), the bite reader took its red bobber for a "!" ("hooked"), and the bar never appeared. No dialogue opened, so the v1.10 step-away never triggered.
- **New detection:** a nearby NPC shows a floating white "Interact" prompt. The macro now reads that area (`npcLabel` region) with the Windows OCR and, if it sees the word, walks forward (W) in growing steps (0.10 s, +0.06 s each, up to 6 steps) until the prompt is gone.
- **When it runs:** after the start-up anchor, after every shop trip (sale or bait), and every time a bite is followed by "bar never appeared".
- **Log:** `[npc] too close ...`, `[npc] out of range after N steps`.
- Not tested in the game: the OCR match for "Interact" is the weak point. If it never triggers, send the log line `[npc]` (or a screenshot of the prompt) and I will tune the region.

## v1.13: Fixed pixels for the Craft window

- **What the video showed:** the Craft window was up from 3.2 s to 7.8 s. In that time the macro clicked three times, 1.6 s apart (the verify-and-retry `+` clicks of v1.11), and the quantity never changed. The cursor stayed on the water on the right, where the bait row had been clicked, so the `+` clicks did not land on the button.
- **Change:** the quantity comparison is removed. The Craft window now uses fixed pixels per resolution profile (`CRAFT_PX` table near `Points`):
  - 2560x1440: `+` (1642, 738), Craft (1280, 917), Close (1702, 386), measured on your screenshot.
  - 1920x1080: `+` (1232, 554), Craft (960, 688), Close (1277, 290), scaled from the 2560x1440 values (x0.75), not measured.
  - The profile is the one chosen in the window (Auto = nearest to your screen size). Pixels are offsets from the top-left of the game area.
- **Click diagnostics:** every click logs `[click] plus target X,Y cursor X,Y` and flags `CURSOR MISSED THE TARGET` if Windows did not move the mouse there. The cursor is first jumped to the target, then the usual nudged move and click follow.
- The Close click used by the error recovery uses the same table.
- Not tested in the game.

---

## v1.17.2: RDP 1366x768 fixes (cast meter, bait line, false hooks)

- **Cast meter:** the orange fill is lower on a 1366x768 screen (about 0.64 to 0.92 of the game height). The read zone stopped at 0.82, so the macro did not see the top of the charge and released late. The zone now covers down to 0.96.
- **Bait line:** moved up to about 0.81 to 0.86 of the game height, where the RDP shows `Selected Bait: ... xN`.
- **False "hooked":** the dark red cape of the character passed the pink test. The bite marker now also needs blue at least 40 above green, which rejects the cape.
- Checked against your screenshot (1362x798 window, title bar removed). The real "!" marker was not in that screenshot, so it is still untested.
- Not tested in the game.

---

## v1.17.1: 1366x768 profile (RDP) and better OCR

- **1366x768 profile added** (also in the Resolution dropdown). Before, that screen was matched to the 1920x1080 profile, so the fixed click points of the shop/craft window landed in the wrong place.
- **The 1366x768 click points are not measured yet.** They are the 1920x1080 values scaled by 0.711. If the shop or craft clicks miss, send me a screenshot of the craft window at 1366x768 and I will measure the points.
- **OCR upscale x3** before reading text (bait line, level). The OCR helper is now always rewritten, so the new version is used even if an old copy exists.
- Not tested in the game.

---

## v1.17: Pause button, bait read from the screen, never 0 bait

- **Pause:** new **Pause (F3)** button on the Dashboard (same place as Check setup while running). The pause takes effect at the start of the next cycle, so the mouse is always released first. The pause does not trip the response timeout. Stop (F2) clears the pause.
- **Bait count read from the game:** each cycle reads `Selected Bait: <name> xN` under the NPC label (Windows OCR) and updates the tracked bait count. The log shows `[bait] game shows xN`.
- **Never 0:** the auto-restock threshold went from 1 to 20 bait, so the macro restocks well before it runs out.
- Not tested in the game. The OCR of `xN` is the weak point: if the log shows wrong numbers, send me the `[bait]` lines.

---

## v1.16.5: Re-anchor after a missed bite (boss event / teleport)

- **What the video showed:** the camera tilts up to the sea, the character is teleported to an arena, then comes back on the dock facing sideways instead of straight ahead. Casts then miss, and the old logic only counted the misses.
- **Fix:** after the first missed bite, the macro re-runs the NPC anchor (camera and position reset, same routine as at start). The second missed bite in a row still triggers the bait-out logic, as before.
- Log line: `[reanchor] no bite - re-establishing the NPC anchor`.
- Limit: this only works if the character is back near the NPC after the event. If the teleport leaves it too far away, the anchor fails and the macro stops.
- Not tested in the game.

---

## v1.16.4: Death detection (HP bar)

- **Problem:** the macro never noticed the character had died. A boss knocked the character into the water, and the macro kept waiting for a bite until the 5-minute response timeout.
- **Fix:** while fishing (waiting for a bite and during the reel), the macro reads the green HP bar at the bottom-left. If it stays empty for 3 s, the macro stops, logs `[death]`, and reports the stop reason (`character dead (HP bar gone)`) in the webhook summary.
- The check is not run during NPC dialogues, because the dialogue hides the HP bar.
- The macro does not respawn or walk back to the NPC. Restart it with F2 after you respawn and stand at the NPC again.
- Not tested in the game.

---

## v1.16.3: Fausses morsures (faux "hooked")

- **Cause:** la confirmation de morsure reposait sur 2 lectures consécutives espacées de 8 ms (environ une frame de jeu). Un flash rose/magenta dans la zone `bite` (effets du lancer, personnage, canne) suffisait donc à déclencher un clic.
- **Correctif:** le "!" doit maintenant rester visible au moins 0.15 s (0.04 s en Fast bite) avant le clic. La confirmation ne dépend plus de la vitesse de la boucle.
- **Journal:** `[bite] hooked` affiche désormais les détails de la détection (`biteInfo`).
- Pas encore testé en jeu. Pistes restantes : réduire la zone `bite` pour exclure le personnage, et ne lancer la recherche de morsure qu'après le relâchement du lancer.

---

## v1.16.2: Cast meter not found over bright sky (Fast Mode)

- **What your screenshot showed:** the fill is lime (170,255,0 in the middle, 132,197,0 at the sides) and the empty part of the track is (25,55,69) over the bright blue sky.
- **Two causes, both fixed:**
  - The fill search only knew orange, amber, yellow, one yellow-green and one pure green. The lime tones were not in the list, so the meter was never found. Added `0xAAFF00`, `0x84C500` and `0x6EFF08` (same tolerance).
  - The empty-track test allowed a colour spread of 40; this track has 44-47, so the search stopped at the first empty row above the fill. The limit is now 64 (still capped at brightness 125, so sky and bright sea are rejected).
- Checked on your screenshot: the old rules find no fill and fail at the first empty track row; the new ones find the fill top and the full track height.
- Not tested in the game.

---

## v1.16.1: Tilt a bit further

- Default "Tilt down (px)" raised from 40 to 70. A saved value of exactly 40 (the old default) is moved to 70 on load. Any other value you typed is kept.

---

## v1.16: Camera tilt after the NPC, Fast Mode + Reduce Motion on start

- **Camera tilt (new setting "Tilt down (px)", default 40, 0 = off):** after every conversation with the NPC (start-up anchor, sale, bait purchase, recovery) the macro moves the mouse down by that many pixels under Shift Lock, so the camera looks a little further down. It is done only right after the NPC dialogue, never at other times, because the movement would add up and end with the camera on the ground. Raise the number to look further down.
- **Game settings on start (new switch on the Fishing page, on by default):** before the NPC anchor the macro clicks the gear above the compass, scrolls the Settings list to the bottom, switches **Fast Mode** and **Reduce Motion** to On if they are not already (it reads the green button first), then closes the window. Positions come from your 1280x720 recording and scale with the game window; the yellow title bar is located first because the window slides while it opens.
- **Log:** `[settings]` lines say what was found and done, and `[camera] tilted down ...` after each tilt.
- Not tested in the game.

---

## v1.15: Reel bar lost over flat / bright scenery (Fast mode)

- **What the video showed:** with the "Fast" texture-less mode the bar's translucent track is lighter and bluer over the sky/sea (about 47,53,56) than the old rule accepted (blue 34 +/-14). Only the part over dark wood matched. When the zone turned grey against the left edge the match fell below 25%, the macro decided the bar was gone and released the mouse for about 2 s while the fish escaped.
- **Track colour:** widened to any dark neutral/blue-grey (blue 18-66, red and green <= 70, channels within 14 of each other). Your normal-texture screenshot (33,30,29) and the Fast-mode video (47,53,56) both match.
- **Track threshold:** the "track background gone" test now needs 10% instead of 25%.
- **Zone hidden but progress strip still up:** the macro now keeps the last mouse state instead of releasing it.
- Not tested in the game.

---

## v1.14: Separate channel for the hourly report

- New field on the Webhook page: **Hourly report webhook URL (optional)**. Create a webhook in the other Discord channel and paste its URL there. Empty = hourly reports stay in the main channel.
- "Send test" and "Send report now" also use it. The Show/Hide button reveals both URLs.
- The main webhook still has to be enabled and valid; everything except the hourly report keeps going to it.
- Window is a little taller (656).
- Not tested in the game or on a real Discord channel.

---

## Findings from your screenshots

- **Cast meter colour shows the charge:** orange is low, yellow is mid, green is full. (Used in v1.5.)
- **Meter position:** zoomed out, the bar sits low on screen. Fixed in v1.5 by measuring the track instead of using a fixed size.
- **Two NPCs:** the Fisherman sells fish and Basic Bait. The Angler sells the other baits and cannot buy fish. Its menu is Rods (locked), Bait, Quest, Nevermind; its bait page is Basic Bait, LOCKED, LOCKED, Back.

## Open points (to check in the game)

- **OCR:** money and level reading depend on Windows OCR reading the game font. If a sale says "unreadable", send me a screenshot of the bottom-left HUD.
- **Webhook screenshots:** the attachments have not been seen arriving on a real Discord channel yet.
- **Bait menu order:** I assumed Basic first, then the two baits of that sea in the order you listed. Override with `baitRow=` (1 to 3) in the `[shop]` section of `BloxFishing.ini`.
- **Craft window for baits that need an item:** only the Basic Bait layout is known, so the "+" and Craft button positions may need adjusting.
- **Selected bait:** if the game does not select a newly bought bait by itself, it has to be selected by hand.
