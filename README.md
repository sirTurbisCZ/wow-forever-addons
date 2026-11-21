# wow-forever-addons

Addons for **World of Warcraft Forever**, shipped as a monorepo.

Install from [Releases](https://github.com/sirTurbisCZ/wow-forever-addons/releases) — download the zip for the addon you want, extract so you get `Interface/AddOns/<AddonName>/`, then `/reload` in game.

## Addons

| Addon | Slash | What it does |
|-------|-------|----------------|
| [ForeverErrorLog](addons/ForeverErrorLog/) | `/felog` | Captures Lua errors from all addons into SavedVariables (Blizzard error popup off by default) |
| [Plateband](addons/Plateband/) | `/pb` | Native DebuffList companion — merges omitted party DoTs beside Blizzard’s band |

Player docs live next to each addon (`Docs/README.md`). Development notes and Scenario Maps stay in the Cursor project store, not in this repo.

## Local development

```bash
./scripts/link-addon.sh ForeverErrorLog   # symlink into Forever Interface/AddOns
./scripts/link-addon.sh Plateband
./scripts/package-addon.sh ForeverErrorLog  # zip → dist/
./scripts/package-addon.sh Plateband
```

Release tags look like `felog-v0.1.0` / `plateband-v0.1.0` and produce a zip whose root is the addon folder.

## License

[MIT](LICENSE)
