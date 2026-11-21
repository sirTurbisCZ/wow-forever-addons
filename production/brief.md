# Playtest brief — BetterBackpack 0.5.6

**Regression fixed (0.5.4/0.5.5):** `ApplyCombinedBagsChrome` (Layout) and `EnsureSlotBackground` (Slots) were called before their `local` declaration → nil global → DoLayout aborted on the first item. Result: empty lanes, players collapsed every header `[+]`, frame stuck at 456×360 (empty right side), chrome refresh skipped.

**0.5.6**
- Both helpers declared before use; chrome (NineSlice / Bg / TopTile @ 6,-21, Inset hidden) actually runs each layout
- Slot wells: `SlotBackground` (bags-item-slot64) under every icon
- Categories default expanded; schema 3 wipes stuck `collapsed` once
- Hug width: cols = clamp(widest expanded lane, 6, Columns()); symmetric INSET_X 14

**Keep:** Toggle* replace (B stable) — OpenClose untouched.

**Done when:** `/reload` → `v0.5.6` → B opens with all lanes `[-]` + icons · window hugs grid (no empty right strip) · B closes · no new `layout` error in `/bb dump`.
