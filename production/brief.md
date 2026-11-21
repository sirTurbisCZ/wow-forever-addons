# Playtest brief — BetterBackpack 0.5.14 (search chrome + bank RMB)

One build with both lines (UI branch `cursor/bb-056-layout-expand-hug-9374`, includes `cursor/bb-bank-rmb-secure-c19a`).

**UI chrome (0.5.10–0.5.11)**
- Search = `SearchBoxTemplate` (same as CombinedBags `BagItemSearchBox`: rounded border, magnifier, clear X, "Search")
- 0.5.14: broom | gear | X all exactly Close size, flush left of X. Broom = real `BagItemAutoSortButton` (click → Tidy, OOC); gear = flat options gear, no plate
- Search box OK (0.5.11)
- 1px hairline above footer (OK)

**Bank RMB (0.5.12, sibling)**
- At bank keep secure `type2=item` (UseContainerItem deposits). Do not clear attrs / Pickup+PutItemInBag. Merchant/mail still insecure Pickup.

**Keep:** Toggle* replace (B stable) — OpenClose untouched.

**Done when:** `/reload` → `v0.5.14` → B · broom/gear same size as X, touching it, centred on it · open bank → RMB bag item deposits · B ×5 stable.
