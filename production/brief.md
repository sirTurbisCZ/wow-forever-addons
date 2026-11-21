# Playtest brief — BetterBackpack 0.5.11

**History:** 0.5.6 empty-lanes fix · 0.5.7 headers/slot art · 0.5.8 fixed window size · 0.5.9 no wells, money-font footer (footer OK per Ondřej).

**0.5.11**
- Search = `SearchBoxTemplate` (same as CombinedBags `BagItemSearchBox`: rounded border, magnifier, clear X, "Search")
- Gear sits on the native broom plate (`bags-button-autosort-up/down`), broom glyph covered by the atlas' own fill

**0.5.10** (hairline OK)
- Broom = the real `BagItemAutoSortButton`, reparented into our title bar (Blizzard art/size/tooltip). Click → Tidy (OOC guard). Re-grabbed next frame if CombinedBags takes it back; released to CombinedBags on `/bb off` / safe mode
- Gear = AutoSort size + native highlight geometry + verified gear atlas (CombinedBags has no native gear)
- 1px hairline above the footer

**Keep:** Toggle* replace (B stable) — OpenClose untouched.

**Done when:** `/reload` → `v0.5.11` → search looks like Blizzard's, clear X empties it · gear plate = broom plate → B · broom is Blizzard's own (hover tooltip "Clean Up Bags") · click sorts · hairline above 43/70 · B ×5 stable · broom never vanishes after open/close.
