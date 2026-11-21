# Playtest brief — BetterBackpack 0.5.18 (lanes: drag-teach + custom lanes + settings)

Branch `cursor/bb-056-layout-expand-hug-9374` (includes bank RMB 0.5.12, search 0.5.11, Close-chrome title buttons 0.5.16, sticky size 0.5.15).

**0.5.18**
- Empty custom lanes are drawn (header `(0)`) so they are drop targets; custom-lane rows in Settings accept drops too.

**0.5.17**
- Drag an item onto another lane (header or any item in it) → item stays in its slot, its itemID is taught to that lane (SavedVariables `itemRules`). Drop back on its natural lane = forget.
- **+ Lane** next to search: click = name a new lane; drop an item = new lane with that item.
- Settings (gear) rebuilt in bag chrome: Lanes on/off (unchecked → Other) with taught counts · Custom lanes Rename / Delete / New lane · Learned items count + Forget all · Features (stack merge, dense).
- Fix: unchecking a built-in lane no longer removes its row from settings.

**Keep:** Toggle* replace (B stable) · bank RMB deposit · fixed window size.

**Done when:** `/reload` → `v0.5.18` → empty lane "test" shows as a header in the bag · drop an item on it (or on its Settings row) → item moves there → B · drag a potion onto Materials header → moves, survives `/reload` · drop back on Consumables → back to default · drop item on + Lane → name → new lane · gear → Rename / Delete it · uncheck Junk → items in Other, row still there to re-check · B ×5 stable.
