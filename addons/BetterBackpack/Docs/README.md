# BetterBackpack

Category-lane bags for **World of Warcraft Forever** (Interface 16001) with combat-safe RMB.

## Install

1. Put this folder in `Interface/AddOns/BetterBackpack/` (or symlink via `./scripts/link-addon.sh BetterBackpack`).
2. Enable at character select if needed.
3. `/reload` in game — chat should show `loaded v0.5.7` (Toggle* stable; CombinedBags/Baganator chrome; NTH).

Categories open expanded with item icons; click a category header (arrow) to collapse or expand it. The window is as wide as its widest expanded category (never narrower than 6 slots). Searching or filtering never resizes the window — non-matching items are just hidden.

## Slash

| Command | Action |
|---------|--------|
| `/bb` | Toggle bags |
| `/bb on\|off` | Enable or restore Blizzard bags |
| `/bb sort` / `/bb uklid` | OOC tidy (`SortBags`) |
| `/bb settings` | Categories + feature toggles (Nastavení) |
| `/bb search <text>` | Filter icons by name / itemID |
| `/bb filter <cat\|all>` | Show one category lane |
| `/bb pin <itemID>` | Toggle red ghost pin (missing items) |
| `/bb custom add <name>` | New custom category |
| `/bb custom del <id>` | Remove custom category |
| `/bb assign <itemID> <cat\|clear>` | Item → category rule |
| `/bb layout [lanes\|dense]` | Layout mode |
| `/bb merge [on\|off]` | Visual stack merge |
| `/bb dump` | Status + error ring |
| `/bb safe` | Safe mode → Blizzard |
| `/bb reset` | Defaults |
| `/bb selftest` | Wiring check (still need 1× manual combat RMB) |
| `/bb bags` | Reagent / free-space probe |

Also `/betterbackpack`. Úklid / Nastavení stay Czech on chrome.

## Nice-to-have modules (0.5.x)

| File | Job |
|------|-----|
| `Modules/Search.lua` | Search box + match |
| `Modules/Filter.lua` | Category filter |
| `Modules/CustomCategories.lua` | Custom lanes + hide defaults |
| `Modules/StackMerge.lua` | Visual same-itemID merge |
| `Modules/Pins.lua` | Red ghost for unowned pins |
| `Modules/LayoutModes.lua` | lanes vs dense columns |

Layout talks to them only through optional `Feat("Name")` lookups. OpenClose / AutoSort-twin chrome stays on the main 0.4.x path — NTH does not rewrite it.

## Playtest (T0–T3)

1. `/reload` → version print; B opens lanes; CombinedBags not visible.
2. Enter combat with bags open → RMB potion/Q-item works.
3. Open B mid-combat → lanes usable; no CombinedBags ghost.
4. Spam B 5× in combat → leave combat OK without `/reload`.

NTH smoke (OOC): search box → filter → merge toggle → pin a missing itemID → layout dense.

## Notes

- Never hides CombinedBags (parks alpha / off-screen).
- Optional: ForeverErrorLog for error capture.
- Disable BagShelves if both are present.
