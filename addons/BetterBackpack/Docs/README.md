# BetterBackpack

Category-lane bags for **World of Warcraft Forever** (Interface 16001) with combat-safe RMB.

## Install

1. Copy or symlink this folder to `Interface/AddOns/BetterBackpack/`.
2. Enable on the character select screen.
3. `/reload` — expect `loaded v1.0.0`. **B** opens BetterBackpack (replaces `ToggleAllBags` / `OpenAllBags` when enabled). Bag-bar single bags stay native `ToggleBag`.

Categories start expanded; click a lane header to collapse. Window size is based on the full bag with every lane expanded (search/filter/collapse do not shrink it).

## 1.0.0 highlights

| Feature | How |
|---------|-----|
| Combat **B** | Keep-shown frame shell; toggle visibility with alpha (no `Show()` in lockdown). |
| Vendor bags | Merchant `OpenAllBags` opens BetterBackpack, not native CombinedBags. |
| Lane bulk sell | **Shift+RMB** lane header at vendor — sells the lane synchronously in the click. |
| Auto-sell grey | Settings → Features → vendor grey junk (optional Junk lane). |
| Chrome | **Tidy** (broom) and **Settings** (gear) on the title bar — English tooltips. |

Workflow graphs: `Docs/loops.md`. History: `Docs/CHANGELOG.md`.

## Lanes and drag-to-teach

Pick up an item and drop it on another lane header or on an item in that lane. The item stays in its bag slot; its itemID is taught to that lane. Drop on the natural lane again to forget.

## Trash lane

Off by default (Settings → Lanes → Trash). Click-only destroy on Forever — see `/bb trashtest`.

## Slash commands

| Command | Action |
|---------|--------|
| `/bb` | Toggle bags |
| `/bb on\|off` | Enable or restore Blizzard bags |
| `/bb sort` / `/bb tidy` | OOC tidy (`SortBags` + stack merge) |
| `/bb settings` | Categories, custom lanes, features |
| `/bb search <text>` | Filter by name / itemID |
| `/bb filter <cat\|all>` | Show one category lane |
| `/bb dump` | Status + error ring |
| `/bb safe` | Safe mode → Blizzard only |
| `/bb help` | Full command list |

Also `/betterbackpack`.

## Module layout

| File | Role |
|------|------|
| `Core.lua` | Events, slash, hooks install |
| `Modules/OpenClose.lua` | B toggle, CombinedBags park |
| `Modules/Layout.lua` | Lanes UI |
| `Modules/Slots.lua` | Secure item buttons |
| `Modules/BulkTransfer.lua` | Shift+RMB lane bulk |
| `Modules/VendorJunk.lua` | Auto-sell greys |
| `Modules/Context.lua` | Vendor/mail/bank RMB |
| Optional `Feat()` modules | Search, Filter, Trash, Settings, … |

## Release smoke (1.0.0)

1. `/reload` → `loaded v1.0.0` · `BulkTransfer ok`.
2. **B** out of combat and in combat — bag visible both times.
3. Vendor: **Shift+RMB** Bags header → chat `sold N/M` and items sell.
4. Vendor open with bags up — still BetterBackpack, not native CombinedBags.
5. Grey auto-sell if enabled in Settings.

## Notes

- Optional: **ForeverErrorLog** for errors.
- Do not run alongside **BagShelves** (or **CombinedBags**) if both replace bags — disable at character login. Live check: **`/bb bagkey`** (`ToggleBackpack ours=true` expected). Stale `BagShelves.lua` SV without the addon installed is harmless.