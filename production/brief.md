# Playtest brief — BetterBackpack 0.5.15 (search chrome + bank RMB)

One build with both lines (UI branch `cursor/bb-056-layout-expand-hug-9374`, includes `cursor/bb-bank-rmb-secure-c19a`).

**UI chrome (0.5.10–0.5.11)**
- Search = `SearchBoxTemplate` (same as CombinedBags `BagItemSearchBox`: rounded border, magnifier, clear X, "Search")
- 0.5.15: broom | gear | X all exactly Close size, 2px gap. Both built from Close's own art (plate, press, highlight), X covered by its own plate, gold broom / gear glyph. No BagItemAutoSortButton reparent
- 0.5.15: window size sticky while open (only grows); collapse / search / using items never shrink it; refits on reopen
- Search box OK (0.5.11)
- 1px hairline above footer (OK)

**Bank RMB (0.5.12, sibling)**
- At bank keep secure `type2=item` (UseContainerItem deposits). Do not clear attrs / Pickup+PutItemInBag. Merchant/mail still insecure Pickup.

**Keep:** Toggle* replace (B stable) — OpenClose untouched.

**Done when:** `/reload` → `v0.5.15` → B · broom/gear look like the X (red-gold plate), same size, even gaps · collapse a lane / type a search / eat food → window does not change size · open bank → RMB bag item deposits · B ×5 stable.
