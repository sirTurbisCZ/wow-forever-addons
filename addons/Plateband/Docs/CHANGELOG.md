# Plateband changelog

## Release 0.8.2 — help text and small fixes (#54)

- **#58:** the gap policy call no longer names an undefined variable (`auraUnit`, always nil); behaviour unchanged, found by luacheck.
- Help and usage lines use a slash instead of a pipe between words: the client reads `|r`, `|t`, `|n`, `|k` and similar as escape codes and swallowed part of the text (for example `on|off|reset`).
- `/pb reset` moves the minimap button back to its default (shown, default angle) at once.

## Release 0.8.1 — audit fixes (#43), polish (#46)

- **#43 CPU:** a nameplate `UNIT_AURA` no longer repaints a plate the AuraContainer row already follows (the container updates itself). Only the rate-limited learning of food/drink ids and, on friendly plates, a native-buff mute at most once a second remain.
- **#43 Friendly plates off:** the plate's side is remembered before the row is hidden, so a secret reaction check in combat cannot bind the enemy container to a friendly plate.
- **#43 Settings changes:** `Plates.Refresh` resets the full-refresh debounce, so a change within 0.75 s of another refresh is no longer swallowed. Hover tooltips changed in combat are applied when combat ends.
- **#43 Enemy buffs row off** now also hides the dispellable enemy buffs of the older Lua-drawn row (it only affected the AuraContainer row).
- **#43 Reload note corrected:** enemy buffs and icon count apply to plates created after `/reload` (nameplate frames are recycled and a built row is not rebuilt), so a `/reload` is needed. The baseline is captured at load, not when the window is first opened.
- **#43 Small:** `GetProfile` keeps its fast path for any schema from the current one up; error logging no longer runs the full database check each time; container buttons are initialised only once (guard against duplicate Cooldown/Frame objects).
- **#46 Polish:** `.toc` gets `X-Website`, `X-License`, `IconTexture`; login line `[Plateband] vX.Y.Z · /pb`; `/pb settings` opens the window; minimap tooltip "Left-click: settings window / Drag: move"; `/pb reset` prints "settings reset"; README: Install first, Issues link, button angle 230.

## Release 0.8.0 — settings window (#33)

- **Minimap button position (#37):** the radius follows the real minimap width (the Forever minimap is larger, the button used to float outside the ring) and the default angles differ per addon so the buttons do not overlap.
- **Settings window**: `/pb` (no arguments) or the new **minimap button** (left-click, drag to move; `/pb minimap` hides or shows it). Checkboxes: Enable, Friendly plates, Enemy buffs row, Hover tooltips, and the most icons per row. Built on first open; nothing runs per frame. All `/pb` subcommands still work (`/pb help`).
- **Enemy buffs row** off (`enemyBuffs`) hides the dispellable/stealable buff icons.
- Enemy buffs and the icon count are fixed when a plate's row is built: after changing them the window says "/reload needed" (plates that appear later use the new value at once). Hover tooltips apply at once out of combat. "Friendly plates" now also applies to the AuraContainer row.
- Schema 20: new profile keys `enemyBuffs`, `minimap`.

## Release 0.7.3 — less garbage and fewer scans per nameplate

- `Config.GetProfile()` returns the saved profile directly instead of building and merging the 17-key default table on every call (it is called dozens of times per nameplate update).
- `HasTarget()` answers at once when the game says there is no target (the normal state in cities) instead of scanning all nameplates (about 160 protected calls per call).
- Old row mode no longer leaks a 12-button frame on every loading screen: the hidden frame is kept per plate token and reused.
- Clearing our row no longer calls `ClearAllPoints` in combat (deferred until combat ends).
- `UNIT_SPELLCAST_SENT` targets of Power Word: Shield are dropped on every success and at the end of combat (the table no longer grows all session).
- The in-combat `UNIT_AURA` diagnostic probe runs only after `/pb tree` has been used.

## Release 0.7.2 — AuraContainer row is the default

- The row is now drawn by Blizzard's managed **AuraContainer** (`/pb ac`, default **on**). The client tracks the auras itself, so friendly units (party, players) work **in combat** and other casters' debuffs, countdown numbers and stacks are shown reliably. Verified in game on enemy and friendly plates in combat. `/pb ac off` returns to the previous Lua-drawn row; if the client has no AuraContainer the previous row is used automatically.

## Release 0.7.1 — friendly debuffs up to 5 minutes

- Debuffs on friendly units are shown only up to a total duration of **5 minutes** (was 10): Resurrection Sickness (10 min) and hour-long bonuses are no longer shown. Applies to the legacy row and the AuraContainer mode.

## Release 0.7.0 — EXPERIMENTAL AuraContainer row (off by default)

- **New experimental mode** `/pb ac on|off|status` (setting `useAuraContainer`, default **off**; schema 18). When on, each plate's row is drawn by Blizzard's managed **AuraContainer** instead of Plateband's own aura reading. The container tracks the unit's auras inside the client, so it is expected to keep working **in combat on friendly units** (party Weakened Soul, HoTs, shields), for other casters' debuffs and with a client-driven countdown. Not yet verified in game.
- One row per plate, directly above the name, left-aligned with the health bar (same offset as the normal row; anchored out of combat only). Friendly plates: debuffs up to 10 min + helpful effects up to 60 s, food/drink and permanent buffs excluded by spell id (ids are learned out of combat). Enemy plates: debuffs from players/pets + dispellable/stealable buffs. Red / green / gold borders as before; the tooltip is the container's own.
- While the mode owns a plate, Plateband's normal row on that plate is hidden and Blizzard's native debuff list is muted too (the container shows those debuffs); buff and crowd-control lists stay muted as before. `/pb ac off` brings everything back.
- If the client has no AuraContainer (or refuses every filter), the normal row is used silently; `/pb ac status` says why. `/pb tree` lists the container of the target plate (bound unit, shown, number of buttons).

## Release 0.6.15 — countdown from the end time

- An icon whose aura reports no (or zero) total duration but a public end time now counts down the remaining time (Weakened Soul showed no number).

## Release 0.6.14 — other casters in combat

- In combat the client hides the fields of other casters' auras (secret), so the "is it from a player?" rule dropped every debuff but yours. A debuff on an enemy whose caster is **unknown** is now shown; only a debuff known to come from an NPC stays hidden. Rows built by the direct aura read keep their own aura data for the rules.

## Release 0.6.13 — no icon on top of icon, Weakened Soul row re-anchored

- **Overlap:** our row is anchored through a small spacer frame of our own. When native debuffs grow into the row (your own DoT added in combat, when the row cannot be re-anchored), the spacer widens and the row moves right of the last visible native icon. A row left on a recycled plate is hidden at once (also in combat), and only one row per plate is painted.
- **Expired icons:** an icon whose aura is no longer on a readable unit disappears even when its stored time was unusable or still in the future (dispelled, shield absorbed). A reused slot no longer keeps the previous timer; when the times are secret the client duration object drives the swipe if available. The Weakened Soul placeholder never survives combat.
- **Weakened Soul in combat:** the row is anchored again before combat after it was cleared (before, a cleared row kept the "anchored" flag without points and showed nothing). Target names with a realm suffix are matched; with no usable name the friendly target / mouseover is used. `/pb tree` shows each step of the last own cast, the last blocked action and our row's state.
- Nameplate aura events inside the debounce window get one trailing repaint.

## Release 0.6.12 — every caster, Weakened Soul in combat

- **All auras of a unit are read directly** (one icon per aura instance) whenever the client returns them, so debuffs from several casters stay separate: your DoT no longer hides other players' DoTs, and the other way round. The older collectors remain as a fallback.
- **Friendly units in combat:** the client does not let addons read their auras. Icons painted out of combat stay and expire from their stored times; your own **Power Word: Shield** cast puts **Weakened Soul** (15 s) on that unit's row (party/raid plates). The row is anchored out of combat so it can be shown in combat without touching the plate. The placeholder is dropped when combat ends and real data takes over.
- `/pb tree` shows the last own cast (`last own cast:`).

## Release 0.6.10 — no hour-long debuffs on friendly plates

- Debuffs on friendly units are shown only when their total duration is 10 minutes or less: the client files the hour-long "Boosted Rest" bonus as a debuff and it was shown next to Weakened Soul.
- `/pb tree` lists every aura of the target (name, duration, flags, kept/dropped), tries the party token first and reports read errors. On this client aura data of **friendly** units cannot be read while in combat ("Auras cannot be accessed when secret while tainted"); out of combat it works.

## Release 0.6.3 — debuffs from any player

- Enemy plates show debuffs cast by **any player or player pet** (yours, party, strangers); NPC debuffs stay hidden. (`isFromPlayerOrPlayerPet` means "a player", not "me".)

## Release 0.6.2 — border colours

- Thin coloured border per icon: red debuff, green helpful, gold dispellable enemy buff.

## Release 0.6.1 — no duplicate crowd control

- Blizzard's `CrowdControlListFrame` is muted (Frost Nova etc. appeared twice).

## Release 0.6.0 — tooltips

- Hover an added icon for the effect tooltip (`GameTooltip` only; clicks still pass to the plate). `gapTooltip` setting.

## Release 0.5.3 — rules also for remembered icons

- The rules are applied to the remembered ("sticky") icons too. Before, an emptied list re-painted old icons that the rules reject (long buffs, foreign debuffs).

## Release 0.5.2 — row height

- Row offset above the name uses the height of the name text.

## Release 0.5.1 — anchor fix

- The row anchors only to **visible** native debuffs. Native buffs (muted but still "shown", centred on the plate) acted as the anchor and pushed the row to the middle.

## Release 0.5.0 — one layout

- One layout for every plate: after the last visible native debuff, otherwise directly above the name, left-aligned with the bar. The separate friendly layouts (`friendLeft`/`friendAbove`) are gone.

Earlier versions (0.1.x to 0.4.x): internal development builds, see the repository history.
