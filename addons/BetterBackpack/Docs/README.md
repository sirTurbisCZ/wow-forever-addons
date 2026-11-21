# BetterBackpack

Category-lane bags for **World of Warcraft Forever** (Interface 16001) with combat-safe RMB.

## Install

1. Put this folder in `Interface/AddOns/BetterBackpack/` (or symlink via `./scripts/link-addon.sh BetterBackpack`).
2. Enable at character select if needed.
3. `/reload` in game — chat should show `loaded v0.5.18` (Toggle* stable; CombinedBags/Baganator chrome; NTH).

Categories open expanded with item icons; click a category header (arrow) to collapse or expand it. The window is sized for the whole bag with every category expanded (as wide as the largest category, never narrower than 6 slots), so collapsing, searching or filtering never resizes it. Categories with no matches are hidden; the freed space stays plain (set `fillEmptyWells` in the profile to show empty slot wells there instead).

## Lanes, custom lanes and drag-to-teach (0.5.17)

- **Drag to teach:** pick an item up in the bag and drop it on another lane — on the lane header or on any item in that lane. The item stays in its bag slot; its itemID is remembered and every stack of it shows in that lane from now on. Dropping it back on the lane it would land in anyway forgets the rule. Works for built-in, custom and Other lanes.
- **Custom lanes are always drawn**, even empty (header with `(0)`), so a new lane is a drop target right away; a search / filter still hides lanes without matches. Custom-lane rows in Settings are drop targets too.
- **+ Lane** (right of the search box): click to name a new empty lane, or drop an item on it to create a lane with that item in it.
- **Settings (gear):** same chrome as the bag. *Lanes* — built-in lanes on/off (unchecked lanes spill into Other, never hidden), with each lane's taught-item count. *Custom lanes* — Rename / Delete per lane, New lane. *Learned items* — count + Forget all. *Features* — visual stack merge, dense layout.
- Rules live in SavedVariables (`profile.itemRules`, `profile.customCategories`). Deleting a lane sends its items back to their default lanes. Drag-teach is out of combat only (bag pickup is disabled in combat).

## Slash

| Command | Action |
|---------|--------|
| `/bb` | Toggle bags |
| `/bb on\|off` | Enable or restore Blizzard bags |
| `/bb sort` / `/bb uklid` | OOC tidy (`SortBags`) |
| `/bb settings` | Lanes, custom lanes, learned items, features (Nastavení) |
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
| `Modules/CustomCategories.lua` | Custom lanes, hide defaults, drag-teach rules, name / rename / delete popups |
| `Modules/Settings.lua` | Settings panel (CombinedBags chrome) |
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

Lanes smoke (OOC): drag a potion onto the Materials header → it moves to Materials and stays there after `/reload` · drop it back on Consumables → rule gone · drop an item on **+ Lane** → name it → new lane with that item · Settings → Rename / Delete the lane.

## Notes

- Never hides CombinedBags (parks alpha / off-screen).
- Optional: ForeverErrorLog for error capture.
- Disable BagShelves if both are present.
