# Plateband

Companion for Forever nameplate auras. Looks and feels like Blizzard’s native DebuffList.

- **Your** personal DoTs stay 100% native (Plateband does not paint them).
- On **enemy** plates (especially the current target), Plateband appends **only** harmful icons Blizzard omitted — same band, LEFT→RIGHT of native DebuffList (party/nearby foreign DoTs, including Forever-secret FileIDs).
- **Friend/party** plates are left alone (no name reanchor). On enemies with merge paint, name tucks under the aura band. Never parks or hides native DebuffList.

## Install

1. Download `Plateband-*.zip` from [Releases](https://github.com/sirTurbisCZ/wow-forever-addons/releases).
2. Extract so the folder is exactly:

   `World of Warcraft/_forever_/Interface/AddOns/Plateband/`

   (the `.toc` must sit inside that `Plateband` folder).
3. At character select, enable **Plateband** if needed.
4. Log in and `/reload`.

Optional: also install **Forever Error Log** so Lua errors land in `/felog` / its SavedVariables file.

Developers (monorepo): `./scripts/link-addon.sh Plateband` then `/reload`.

## Commands

| Command | What it does |
|---------|----------------|
| `/pb help` | Help and status |
| `/pb on` / `/pb off` | Enable or disable merge painting |
| `/pb diagnose` | Compact status card (also auto-saved) |
| `/pb dump` | Status, recent errors, session log tail |
| `/pb watch on` / `/pb watch off` | Print one-line card every ~2s (off by default; SV still logs) |
| `/pb safe` | Turn merge off and clear overlays |
| `/pb reset` | Restore default settings |
| `/pb size <n>` | Icon size hint (12–32) |

Alias: `/plateband`.

## Sending a bug report

Plateband keeps a **session log** automatically (no slash required). After a pull:

1. `/reload` once (or log out) so SavedVariables flush to disk.
2. Send this file:

`World of Warcraft/_forever_/WTF/Account/<YourAccount>/SavedVariables/Plateband.lua`

Look inside for `sessionLog`, `lastDiagnose`, and `export`.

If Forever Error Log is installed, also send:

`…/SavedVariables/ForeverErrorLog.lua`

## What it does

- Leaves Blizzard DebuffList fully visible for personal / native auras.
- On enemy plates, diffs TargetFrame (target) + unit harmful auras against native icons and paints **only missing** others’ DoTs to the **right** of the native band. Friend plates are never rewritten.
- Click-through overlays — plate click still selects the unit.
- Auto-saves throttled diagnose cards into SavedVariables during play.
- Degrades gracefully when aura APIs are empty (no combat-log core).

## What it does not do

- No bag UI, party HUD, or full plate skin rewrite.
- Does not recolor nameplate health bars.
- Does not use the combat log as a DoT source.
- Does not replace or hide native DebuffList.

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| Addon does not load | Folder name must be exactly `Plateband`; `/reload` |
| No extra icons | Expected solo — native shows your DoTs. With party DoTs on target, check `/pb diagnose` (`fb` > 0 when merge paints) |
| Icons cover the name | `/pb safe` and send `Plateband.lua` after `/reload` |
| Errors / weird plates | `/pb safe`, then `/felog list` if Forever Error Log is installed |
| Dual aura rows with an old Retinue install | Disable or unlink Retinue; Plateband owns plates only |
