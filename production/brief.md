# Playtest brief — BetterBackpack 0.5.20 (Trash click-only + Shift-click links)

Branch `cursor/bb-056-layout-expand-hug-9374` (includes bank RMB 0.5.12, search 0.5.11, Close-chrome title buttons 0.5.16, sticky size 0.5.15, drag-teach lanes 0.5.17–0.5.18).

**0.5.20**
- Trash is click-only on Forever (Ondřej's trashtest: click=OK, timer and event blocked). No more timer / event destroy attempts → no "Interface action failed". New loot of a Trash item waits red in Trash and goes on the next click in the bag.
- `/bb trashtest go` now only checks click destroy (1 grey stack).

**0.5.19**
- Fix: Shift+LMB on a bag item links it into the open chat / whisper box again (Ctrl = dress-up, Shift with no chat = split stack).
- Trash lane (off by default — gear → Lanes → Trash). Drop a grey/white stack on it → destroyed now (first time per item asks), future loot of that item destroyed too. A grey ghost icon stays in Trash (no bag slot). Drag the ghost to another lane, or click it → Keep, to stop destroying it. Settings → Trash lists every item with Keep.
- Never destroyed: quest items, green or better, locked items, hearthstone. Never in combat.

**0.5.18**
- Empty custom lanes are drawn (header `(0)`) so they are drop targets; custom-lane rows in Settings accept drops too.

**0.5.17**
- Drag an item onto another lane (header or any item in it) → item stays in its slot, its itemID is taught to that lane (SavedVariables `itemRules`). Drop back on its natural lane = forget.
- **+ Lane** next to search: click = name a new lane; drop an item = new lane with that item.
- Settings (gear) rebuilt in bag chrome: Lanes on/off (unchecked → Other) with taught counts · Custom lanes Rename / Delete / New lane · Learned items count + Forget all · Trash · Features (stack merge, dense).

**Keep:** Toggle* replace (B stable) · bank RMB deposit · fixed window size.

**Done when:** `/reload` → `v0.5.20` · open a whisper, Shift+LMB an item in the bag → link appears in the box · gear → check Trash → Trash header `(0)` in bag · drop a grey item on it → popup → Destroy → gone, grey ghost with `x3` in Trash · drop a green item → refused message, item back · loot the same grey item again → red in Trash, no "Interface action failed" → click anything in the bag → destroyed · drag the ghost onto Junk/Other → "kept again", ghost gone · next loot stays · B ×5 stable.
