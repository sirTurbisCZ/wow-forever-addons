# Plateband

Companion for Forever nameplate auras. Looks and feels like Blizzard’s native DebuffList.

- **Default (0.1.15+):** merge **on** — foreign DoTs beside native on enemy plates (`/pb merge off` for native-only).
- Personal DoTs stay 100% Blizzard. Never parks or hides native DebuffList.
- **Never** `ClearAllPoints` the plate name (three-addon refactor hard rule).
- Merge design (`Docs/merge-design.md`): beside native only; on by default (`mergeMissing=true`).

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
| `/pb merge on` / `/pb merge off` | Foreign DoT merge beside native (default **on** since 0.1.15) |
| `/pb selftest` | Log `SELFTEST` cases to SavedVariables (agent gate) |

Alias: `/plateband`.

## Silent trace (default on since 0.2.10)

No chat spam while playing. Plateband appends **PAINT** lines to SavedVariables continuously (target + visible nameplates, ~0.5s sweep + each paint). Wiped each game session at login.

**Friend / agent path** (one `/reload` after repro, or send file occasionally):

`World of Warcraft/_forever_/WTF/Account/<YourAccount>/SavedVariables/Plateband.lua`

Grep `PAINT`, `paintTrace`, `lastPaintTrace`, or `sessionLog.export`.

**Developer on Mac** (while Ondřej tests — no screenshots needed):

```bash
./scripts/plateband-selftest.sh             # offline: locals, luac, invariants
./scripts/plateband-sv-gate.sh              # live SV green before asking /reload
./scripts/plateband-sv-watch.sh             # background agent watch → Plateband/Logs/sv-watch.log
./scripts/watch-forever-traces.sh watch 3   # FElog LIVE + Plateband SV alerts every 3s (agent default)
./scripts/watch-plateband-sv.sh             # PAINT tail only
```

See `Docs/testing.md`.

Alerts append to `/tmp/forever-trace-coordinator-inbox.txt`. Agents fix/ship on regression signals (size jump, `cdN=0`, missing foreign, FElog nil) **before** asking for screenshots.

Optional: `WOW_FOREVER_ROOT=/path/to/_forever_ ./scripts/watch-plateband-sv.sh 80`

## Sending a bug report

1. Reproduce with DoTs on a nameplate (or leave combat).
2. `/reload` once (or log out) so SavedVariables flush to disk.
3. Send **Plateband.lua** (see path above). Include `paintTrace` / `lastDiagnose`.

Look inside for `sessionLog`, `paintTrace.export`, `lastDiagnose`, and `lastPaintTrace`.

If Forever Error Log is installed, also send:

`…/SavedVariables/ForeverErrorLog.lua`

## What it does

- Leaves Blizzard DebuffList fully visible.
- Click-through — plate click still selects the unit.
- Auto-saves throttled diagnose cards into SavedVariables during play.
- Merge of omitted foreign DoTs is **on by default** and does not reanchor the name.

## What it does not do

- No bag UI, party HUD, or full plate skin rewrite.
- Does not recolor nameplate health bars.
- Does not use the combat log as a DoT source.
- Does not replace, hide, or `ClearAllPoints` native DebuffList / name text (safe default).

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| Addon does not load | Folder name must be exactly `Plateband`; `/reload` |
| Weird / broken plates after older Plateband | `/reload` on **0.1.12+** (undoes prior name pins) |
| Native-only debuffs | `/pb merge off`; `/pb diagnose` → `merge=0` |
| Party DoTs missing on plate | default merge on; `/pb diagnose` → `merge=1`, `fb>0` when icons painted |
| Own DoT shown twice (e.g. Flame Shock ×2) | update to **0.2.40+**; `/reload` — personal stays native-only when DebuffList already has it |
| Errors / weird plates | `/pb safe`, then `/felog list` if Forever Error Log is installed |
| Dual aura rows with an old Retinue install | Disable or unlink Retinue; Plateband owns plates only |
