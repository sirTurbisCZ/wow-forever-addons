# Wayfarer changelog

## Release 0.3.1 — audit fixes and polish

- **Proc icons in combat (#47):** in combat the player's auras are secret on this client, so aura-based proc icons did not show while fighting. Procs that make a spell glow are now also read from the proc glow (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW / HIDE and C_SpellActivationOverlay.IsSpellOverlayed), which is readable in combat: Missile Barrage (glow on Arcane Missiles) and Shadow Trance (glow on Shadow Bolt). `/wf proc status` shows the number of glow events. Procs without a glow (Clearcasting / Arcane Concentration, Flurry, ...) can only be shown when the client lets addons read auras.
- **Proc icons in combat, second part (#47):** the proc icons are now drawn by a Blizzard-managed aura container (`Modules/ProcContainer.lua`), which shows icon, duration swipe and stack count from C code, so the addon never has to read the secret aura. It follows the aura ids of your class's procs plus ids learned automatically whenever a proc is readable out of combat (saved, at most 40, `procHUD.learnedIds`). It is built out of combat only; if this client has no such container or refuses it, the old icons are used as before (test mode always uses them). New: `/wf proc add <spellId>`, `/wf proc ids`, `/wf proc container on|off|refresh`; `/wf proc diag` and `/wf proc status` show the container state. NOT verified in the game yet: whether the container shows the player's own auras in combat on this client (see README, "Procs in combat"). `/wf proc auras` no longer fails (its filter list was undefined).
- **#44 Procs:** one aura pass per update, shared by all entries (reusable maps by spell id and by name, no new tables per tick; the by-name fallback is repeated at most once a second while nothing is found, buffs only unless the Arcane Blast stack aura is looked up); the 10 Hz ticker no longer scans the aura list for every missing proc.
- **#44** The "incoming" pip is only cleared by the stop, failure or interrupt of the cast that set it (cast GUID or spell id; when unreadable it stays unless nothing is being cast).
- **#44** A successful Arcane Blast whose spell id is secret (combat) now counts its stack when its START was recognised (assumes the successful cast is the one that started).
- **#44** Saved data with a wrong type for a settings block (for example `procHUD = true`) is repaired with the defaults; `GetProfile` checks the blocks too.
- **#44** Party marks: roster changes are coalesced into one refresh 0.2 s later. The Party marks section shows a hint while friendly nameplates are off.
- **#46 Polish:** shorter addon notes, `X-Website`, `X-License` and `IconTexture` in the .toc; login line `[Wayfarer] vX.Y.Z · /wf`; `/wf settings`; `/wf reset` prints "settings reset"; minimap tooltip "Drag: move"; README: install first, Issues link, fishing overlap note, no version in the heading, no "Coming next".

## Release 0.3.0 — procs for shaman, druid, priest and warlock

- **Upcoming stack (#36):** while an Arcane Blast is being cast the next pip is shown dimmed (the stack is only applied when the cast finishes); it lights up on success and disappears on interrupt, failure or stop. Setting `procHUD.upcoming` (default on), checkbox in the Procs section.
- **#34:** proc icons for more classes (icon only, no stack meter, shown while the buff is up): shaman (Clearcasting from Elemental Focus, Flurry, Nature's Swiftness), druid (Clearcasting from Omen of Clarity, Nature's Grace, Nature's Swiftness), priest (Inner Focus, Spirit Tap, Power Infusion) and warlock (Shadow Trance). Buffs are found by id or by name (English and Czech client text). The ids are unverified; use `/wf proc auras` in the game to check them. Dropped for lack of evidence on Forever: Elemental Mastery (not a spell there) and Tiger's Fury.
- Test mode lights up all proc icons one by one, however many a class has. The settings window lists which classes have procs.
- (#31) Missile Barrage icon, from the former 0.2.14:
- The free-cast buff of the Arcane Concentration talent (Clearcasting icon) is also found by the names Clearcasting / Arcane Concentration (and the Czech texts), not only by id 12536.
- **Fix (#31):** the Missile Barrage proc icon was not shown on Forever. A proc entry was dropped when the game gave no spell info for its aura id (the stack meter had a fallback, procs had none) and a proc was only searched by id. Proc entries are now kept, the aura is found by id or by name (English and Czech client text) and the icon is taken from the aura itself when the spell lookup has none. The icon does not depend on Arcane Blast stacks.

## Release 0.2.13 — less garbage per tick

- `Config.GetProfile()` returns the saved profile directly instead of merging the default table on every call (timer ticks, nameplate updates).
- **Fishing key picker:** the full-screen key capture closes when combat starts (it could swallow the next key).
- **Procs:** `SPELLS_CHANGED` is always listened to, so a module switched off while spell data was still loading re-checks; the player `UNIT_AURA` event no longer runs a full update while the 0.1 s ticker is active; the Arcane Blast aura is read once per update.

## Release 0.2.12 — procs and one-key fishing

- **Procs and timers (mage):** Arcane Blast stack meter (4 pips and the 18 s countdown from the first cast, not refreshed by later casts), shown with the first Blast and gone when the stacks run out. The count is predicted from your casts and corrected from the real aura whenever it is readable (a missing aura never clears the meter). At 4/4 the meter pulses gold and shows what is usable: Arcane Wrath when off cooldown, Arcane Missiles while Missile Barrage is up. Clearcasting, Missile Barrage and Presence of Mind icons. Movable HUD (unlock locks itself after 90 s, test mode ends after 30 s), scale, optional glow over action buttons. Settings section "Procs", `/wf proc` (`debug` and `auras` help find spell ids). Priest, shaman and druid have an empty trigger table, ready for later.
- **One-key fishing** (Settings → Fishing, `/wf fish`): one press loots an open fishing loot window, reels in the bobber when it is the soft-interact target, or casts Fishing (not in combat, swimming, mounted or in a vehicle). Never hooks on its own. The key is an override binding on Wayfarer's own frame, changed only out of combat and released when the module is off or the key is cleared; your own bindings are untouched. By default only while a fishing pole is equipped. While a cast runs: raised interact reach to the bobber and an optional louder splash, put back when the cast ends. A warning when another addon with its own one-key fishing is active.
- Settings window in the BetterBackpack layout: section list on the left (General, Party marks, Procs, Fishing), scrollable content, scrollbar only when needed. The party and raid colour swatches are disabled while "Use the class colour" is on.

## Release 0.1.2

- Settings window uses the same layout as BetterBackpack: section list on the left (General, Party marks, Procs, Fishing), scrollable content on the right, scrollbar only when needed.

## Release 0.1.1

- Settings: the party and raid colour swatches are disabled (greyed out) while "Use the class colour" is on.

## Release 0.1.0 — first version

- Minimap button (left-click settings, right-click marks on/off, drag to move) and one settings window (`/wf`).
- Party and raid marks on nameplates: coloured outline around the health bar and a P / R tag; class colour or one custom colour per group. The Blizzard health bar is not touched.
