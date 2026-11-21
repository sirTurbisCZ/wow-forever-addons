# Plateband

Companion for Forever nameplate auras. Looks and feels like Blizzard’s native DebuffList.

- **Default (0.1.12+):** native DebuffList only — Plateband does not move names or paint merge icons.
- Personal DoTs stay 100% Blizzard. Never parks or hides native DebuffList.
- Optional merge (`mergeMissing`) can append omitted party/nearby DoTs beside native — off by default after layout breakage in 0.1.8–0.1.11.

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
| `/pb on` / `/pb off` | Enable or disable the module |
| `/pb diagnose` | Compact status card (also auto-saved) |
| `/pb dump` | Status, recent errors, session log tail |
| `/pb watch on` / `/pb watch off` | Print one-line card every ~2s (off by default; SV still logs) |
| `/pb safe` | Turn module off and clear overlays |
| `/pb reset` | Restore default settings (native-only) |
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

- Leaves Blizzard DebuffList fully visible.
- Click-through — plate click still selects the unit.
- Auto-saves throttled diagnose cards into SavedVariables during play.
- Merge of omitted foreign DoTs is **opt-in** (`mergeMissing`) and does not reanchor the name.

## What it does not do

- No bag UI, party HUD, or full plate skin rewrite.
- Does not recolor nameplate health bars.
- Does not use the combat log as a DoT source.
- Does not replace, hide, or `ClearAllPoints` native DebuffList / name text (safe default).

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| Addon does not load | Folder name must be exactly `Plateband`; `/reload` |
| Weird / broken plates after older Plateband | `/reload` on **0.1.12+** (native-only; undoes prior name pins) |
| Want party DoT merge again | Advanced: set `PlatebandDB.profile.mergeMissing = true` then `/reload` (experimental) |
| Errors / weird plates | `/pb safe`, then `/felog list` if Forever Error Log is installed |
| Dual aura rows with an old Retinue install | Disable or unlink Retinue; Plateband owns plates only |
