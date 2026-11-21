# Plateband

Shared harmful / DoT icons grouped with native nameplate debuffs **above** the health bar. Feels like Blizzard forgot one native row — not a plate replacement.

## Install

1. Download `Plateband-*.zip` from [Releases](https://github.com/sirTurbisCZ/wow-forever-addons/releases) when published, **or** symlink from the monorepo: `./scripts/link-addon.sh Plateband`.
2. Ensure the folder `Plateband` sits in `World of Warcraft/_forever_/Interface/AddOns/`.
3. Enable at character select if needed, then `/reload`.

Optional: keep **Forever Error Log** installed so Lua errors land in `/felog`.

## Commands

| Command | What it does |
|---------|----------------|
| `/pb help` | Help and status |
| `/pb on` / `/pb off` | Enable or disable the aura band |
| `/pb diagnose` | Compact status card (also auto-saved) |
| `/pb dump` | Status, recent errors, session log tail |
| `/pb watch on` / `/pb watch off` | Print one-line card every ~2s (off by default; SV still logs) |
| `/pb safe` | Turn the band off and clear overlays |
| `/pb reset` | Restore default settings |
| `/pb size <n>` | Icon size hint (12–32) |

Alias: `/plateband`.

## Sending a bug report (friends)

Plateband keeps a **session log** automatically (no slash required). After you finish a pull:

1. `/reload` once (or log out) so the client flushes SavedVariables to disk.
2. Send this file:

`World of Warcraft/_forever_/WTF/Account/<YourAccount>/SavedVariables/Plateband.lua`

Look inside for `sessionLog` / `lastDiagnose` / `export`.

If the game build allows addon file IO (rare on Forever), a plain text copy may also exist at:

`Interface/AddOns/Plateband/Logs/session.log`

Prefer the SavedVariables file — it is the reliable path.

## What it does

- Builds an AuraContainer band aligned with the native debuff area **above** the plate.
- On your current target, binds the richer `"target"` unit so shared harmful auras the client can surface show up.
- Click-through overlays — plate click still selects the unit.
- Auto-saves throttled diagnose cards into SavedVariables during play.
- Degrades gracefully when aura APIs are empty (no combat-log core).

## What it does not do

- No bag UI, party HUD, or full plate skin rewrite.
- Does not recolor nameplate health bars.
- Does not use the combat log as a DoT source.

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| Addon does not load | Folder name must be exactly `Plateband`; `/reload` |
| No icons | Nameplates on; `/pb on`; target a mob with a DoT; `/pb diagnose` |
| Errors / weird plates | `/pb safe`, then `/felog list` if Forever Error Log is installed |
| Dual aura rows with an old Retinue install | Disable or unlink Retinue; Plateband owns plates only |
