# Playtest brief — BetterBackpack 0.5.3

**Freeze fix**
- B froze: `hooksecurefunc(Toggle*)` ran *after* Blizzard `Open*`/`Close*` (and our Open*/Close* hooks) → open-then-close / close-then-reopen thrash.
- Fix: **replace** `ToggleAllBags` / `ToggleBackpack` / `ToggleBag` / `ToggleKeyRing`; skip Blizzard body when replace enabled.
- Plain `BetterBackpackFrame` (no ButtonFrameTemplate `SetFrameStrata` BLOCKED).
- OpenOurs fail → `ForceCloseBlizzard` (no Unblackout re-entry).

**Keep:** footer ~/70 · AutoSort-twin gear/broom · bag-bar XOR · keyring→Keys · search left.

**Done when:** `/reload` → `v0.5.3` → B opens and stays open · B closes · no freeze · bag-bar XOR.
