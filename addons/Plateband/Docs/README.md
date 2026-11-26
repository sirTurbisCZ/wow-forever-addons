# Plateband

Aura row for **World of Warcraft Forever** nameplates: one clean row of the effects that matter, directly above the unit name.

## What you see

One row of small icons **directly above the name**, left-aligned with the health bar (or right after Blizzard's own debuff icons when they are visible). Each icon has a thin coloured border:

| Border | Meaning |
|--------|---------|
| Red | Debuff |
| Green | Helpful effect on a friendly unit (HoT, shield, short buff) |
| Gold | Enemy buff you can dispel or steal |

Icons disappear when the effect expires. Hover an icon for the tooltip of the effect. Clicks pass through, so clicking the plate still targets the unit.

### Rules — what is shown

**Enemy and neutral units** (neutral mobs count as enemies):
- debuffs you cast,
- debuffs cast by other **players or player pets** (party, raid, or strangers fighting next to you),
- buffs of the enemy that you can dispel or steal.

Debuffs cast by NPCs/mobs are not shown.

**Friendly units** (players, party):
- every debuff, whoever cast it (for example Weakened Soul, poisons, diseases),
- helpful effects with a **total duration of 60 seconds or less** (HoTs, shields, short buffs).

Food and drink, and long or permanent buffs (hour-long buffs, auras), are never added.

### What Plateband hides

Blizzard's own nameplate **buff** list, the **crowd-control** list beside the bar and (on friendly units) loose native helpful icons are made invisible, because the row already shows what matters. `/pb off` or `/pb merge off` brings them back. Plateband never moves or re-anchors the name or Blizzard's frames.

## Install

1. Download `Plateband-*.zip` from [Releases](https://github.com/sirTurbisCZ/wow-forever-addons/releases).
2. Extract so the folder is exactly `World of Warcraft/_forever_/Interface/AddOns/Plateband/` (the `.toc` must be inside it).
3. At character select, enable **Plateband** if needed.
4. Log in and `/reload`. Expect `[Plateband] loaded v… · /pb help`.

Optional: install **Forever Error Log** so Lua errors land in `/felog`.

## Commands

| Command | What it does |
|---------|----------------|
| `/pb help` | Help and status |
| `/pb on` / `/pb off` | Enable or disable Plateband. **The setting is saved** — turn it back on after testing. |
| `/pb merge on` / `/pb merge off` | Aura row on/off (off = Blizzard's nameplate auras only) |
| `/pb size <n>` | Icon size hint (12–32); normally the size follows Blizzard's icons |
| `/pb safe` | Turn the module off and restore Blizzard's lists |
| `/pb reset` | Restore default settings |
| `/pb diagnose` | One-line status card of the target plate |
| `/pb tree` | Which frames of the target plate draw aura icons (for bug reports) |
| `/pb dump` | Status, recent errors, last diagnose card |
| `/pb watch on` / `off` | Print the card every ~2 s (off by default) |
| `/pb selftest` | Quick check that the addon is wired correctly |
| `/pb dev on` / `off` | Developer telemetry (off by default) |

Alias: `/plateband`.

## Settings

Stored in `PlatebandDB.profile`:

| Key | Default | Meaning |
|-----|---------|---------|
| `enabled` | true | Module on/off (`/pb on`, `/pb off`) |
| `mergeMissing` | true | Show the aura row |
| `mergeFriendPlates` | true | Also on friendly and party plates |
| `auraWatchPlates` | true | Repaint any plate when its auras change (not only the target). Turn off to save CPU; needs `/reload` |
| `gapTooltip` | true | Tooltip on icon hover. Off = icons ignore the mouse (needs `/reload`) |
| `iconSize` / `maxIcons` | 18 / 12 | Fallback icon size / most icons per row |
| `silentTrace`, `autoDiag` | false | Developer telemetry |

## Sending a bug report

1. Reproduce it with the problem plate **targeted**.
2. Run `/pb diagnose` and `/pb tree` and copy the lines from chat.
3. `/reload` once so SavedVariables are written, then send `World of Warcraft/_forever_/WTF/Account/<Account>/SavedVariables/Plateband.lua` (and `ForeverErrorLog.lua` if installed).

## What it does not do

- No bag UI, party HUD, or full nameplate skin; does not recolor health bars.
- Does not use the combat log.
- Does not move or `ClearAllPoints` the name text or Blizzard's aura frames.

## Troubleshooting

| Symptom | What to try |
|---------|-------------|
| Nothing is shown | `/pb diagnose` → `enabled=true`? If `false`, `/pb on` (an earlier `/pb off` is saved) |
| Addon does not load | Folder name must be exactly `Plateband`; `/reload` |
| A debuff is missing | Check who cast it: debuffs from NPCs are not shown. `/pb diagnose` → `pol=` counts rows kept / no data / unknown type / buff rule / source / error |
| An icon you do not want | `/pb tree` shows which frame draws it; `/pb off` tells you whether it is Plateband's |
| Errors / odd plates | `/pb safe`, then `/felog list` if Forever Error Log is installed |
| Another aura addon on plates | Disable or unlink the other one; Plateband owns the plates' aura row |
