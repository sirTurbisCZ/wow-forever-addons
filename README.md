# wow-forever-addons

Addons for **World of Warcraft Forever** (Interface 16001), shipped as a monorepo.

Install from [Releases](https://github.com/sirTurbisCZ/wow-forever-addons/releases): download the zip of the addon you want, extract so you get `Interface/AddOns/<AddonName>/`, then `/reload` in game.

## Addons

| Addon | Slash | What it does |
|-------|-------|--------------|
| [ForeverErrorLog](addons/ForeverErrorLog/Docs/README.md) | `/felog` | Collects Lua errors from all addons into SavedVariables. The Blizzard error popup is off by default (`/felog ui on` brings it back). |
| [Plateband](addons/Plateband/Docs/README.md) | `/pb` | One aura row above each nameplate's name: your debuffs and other players' debuffs on enemies, debuffs and short buffs on friendly units, dispellable enemy buffs. Colour-coded, with tooltips. |
| [BetterBackpack](addons/BetterBackpack/Docs/README.md) | `/bb` | Category-lane bags with combat-safe item use, a Junk lane that sells everything in it, per-character rules and an auto-destroy Trash lane. |
| [Seekwell](addons/Seekwell/Docs/README.md) | `/sw` | Find items and mobs: drop tables of your target (hotkey), a browser with search and a zone map, silver map pins, wishlist with alerts, learning from your loot. Reads Tnny's Mob Loot and, optionally, the forever-db data. |
| [Seekwell_Locations](addons/Seekwell_Locations/Docs/README.md) | — | Optional data for Seekwell: original Classic mob spawn points (GPL-3.0), loaded on demand. |
| [Wayfarer](addons/Wayfarer/Docs/README.md) | `/wf` | One minimap button and one settings window: party / raid nameplate marks, procs and timers (mage Arcane Blast meter), one-key fishing. |

Each addon has its player documentation in `Docs/README.md` and its history in `Docs/CHANGELOG.md`.

## Issues and contributing

Found a bug or have an idea? Open an [issue](https://github.com/sirTurbisCZ/wow-forever-addons/issues); see [CONTRIBUTING.md](CONTRIBUTING.md) for what to include.

## Release tags

`felog-v<version>`, `plateband-v<version>`, `betterbackpack-v<version>`, `wayfarer-v<version>`, `seekwell-v<version>`, `seekwell-locations-v<version>` — for example `plateband-v0.8.1`. The version must equal the `## Version` in the addon's `.toc`. A tag builds a zip whose root is the addon folder and publishes it as a GitHub Release with the newest changelog section as its notes (the workflow also syntax-checks every Lua file first, and only accepts tags on commits that are on `main`).

## License

[MIT](LICENSE). Exception: `addons/Seekwell_Locations` carries third-party spawn data under GPL-3.0 (see its `LICENSE.txt` and `DATA-CREDITS.txt`).
