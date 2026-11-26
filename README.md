# wow-forever-addons

Addons for **World of Warcraft Forever** (Interface 16001), shipped as a monorepo.

Install from [Releases](https://github.com/sirTurbisCZ/wow-forever-addons/releases): download the zip of the addon you want, extract so you get `Interface/AddOns/<AddonName>/`, then `/reload` in game.

## Addons

| Addon | Slash | What it does |
|-------|-------|--------------|
| [ForeverErrorLog](addons/ForeverErrorLog/Docs/README.md) | `/felog` | Collects Lua errors from all addons into SavedVariables. The Blizzard error popup is off by default (`/felog ui on` brings it back). |
| [Plateband](addons/Plateband/Docs/README.md) | `/pb` | One aura row above each nameplate's name: your debuffs and other players' debuffs on enemies, debuffs and short buffs on friendly units, dispellable enemy buffs. Colour-coded, with tooltips. |
| [BetterBackpack](addons/BetterBackpack/Docs/README.md) | `/bb` | Category-lane bags with combat-safe item use, a Junk lane that sells everything in it, per-character rules and an auto-destroy Trash lane. |

Each addon has its player documentation in `Docs/README.md` and its history in `Docs/CHANGELOG.md`.

## Release tags

`felog-v<version>`, `plateband-v<version>`, `betterbackpack-v<version>` — for example `plateband-v0.6.3`. The version must equal the `## Version` in the addon's `.toc`. A tag builds a zip whose root is the addon folder and publishes it as a GitHub Release (the workflow also syntax-checks every Lua file first).

## License

[MIT](LICENSE)
