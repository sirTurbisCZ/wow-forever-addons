# Wayfarer changelog

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
