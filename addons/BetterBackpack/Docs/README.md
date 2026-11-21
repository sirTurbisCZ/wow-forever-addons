# BetterBackpack

Category-lane bags for **World of Warcraft Forever** (Interface 16001) with combat-safe RMB.

## Install

1. Put this folder in `Interface/AddOns/BetterBackpack/` (or symlink via `./scripts/link-addon.sh BetterBackpack`).
2. Enable at character select if needed.
3. `/reload` in game — chat should show `loaded v0.5.29`. `/bb dump` includes open-state line.

Categories open expanded with item icons; click a category header (arrow) to collapse or expand it. The window is sized for the whole bag with every category expanded (as wide as the largest category, never narrower than 6 slots), so collapsing, searching or filtering never resizes it. Categories with no matches are hidden; the freed space stays plain (set `fillEmptyWells` in the profile to show empty slot wells there instead).

## Lanes, custom lanes and drag-to-teach (0.5.17)

- **Drag to teach:** pick an item up in the bag and drop it on another lane — on the lane header or on any item in that lane. The item stays in its bag slot; its itemID is remembered and every stack of it shows in that lane from now on. Dropping it back on the lane it would land in anyway forgets the rule. Works for built-in, custom and Other lanes.
- **Custom lanes are always drawn**, even empty (header with `(0)`), so a new lane is a drop target right away; a search / filter still hides lanes without matches. Custom-lane rows in Settings are drop targets too.
- **Settings (gear):** Interface Options layout — category list on the left (Lanes, Custom lanes, Trash, Learned, Features), detail on the right. Custom lanes: **New lane** only here (no button in the bag header). Teach items by dropping on lane headers in the bag or on custom-lane rows in Settings.
- Rules live in SavedVariables (`profile.itemRules`, `profile.customCategories`). Deleting a lane sends its items back to their default lanes. Drag-teach is out of combat only (bag pickup is disabled in combat).
- **Shift / Ctrl + LMB** on a bag item works like the Blizzard bag: Shift links it into the open chat or whisper box (Shift with no chat box = split stack), Ctrl = dress-up.

## Trash lane — auto-destroy (0.5.19)

- Off by default: Settings → Lanes → check **Trash**. Unchecked = nothing is ever destroyed, Trash rules wait.
- Drop a grey or white stack on the Trash header (or on an item / ghost in Trash): it is destroyed **immediately** (no confirm by default). To get first-time-per-item popups back: Settings → Trash and **uncheck** \"Don't ask again (skip all destroy confirms)\".
- From then on every stack of that item you loot is destroyed too. A grey **ghost** icon of it stays in the Trash lane (no bag slot) with how many were destroyed.
- **To keep it again:** drag the ghost onto another lane (header, an item in it, + Lane, or a lane row in Settings), or click the ghost → *Keep* / *Keep in …*. Settings → Trash lists every Trash item with **Keep**.
- Never destroyed: quest items, green or better, locked items, the hearthstone. Nothing happens in combat.
- New loot of a Trash item waits in Trash with a red veil and is destroyed on your next click in the bag. Forever only allows destroying inside a click or key press (0.5.20: timer / event destroy removed).
- `/bb trashtest go` destroys 1 grey stack from the key press to check click destroy still works (`/bb trashtest` alone shows which).

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
| `/bb trashtest [go\|<itemID>]` | Check click destroy still works (destroys 1 grey stack) |
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
| `Modules/Trash.lua` | Trash lane: destroy on drop, ghosts, keep menu / fake drag, loot auto-destroy, `/bb trashtest` |
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
