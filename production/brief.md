# Playtest brief — BetterBackpack 0.5.7

**0.5.6 (fixed):** helpers called before `local` decl → DoLayout aborted (empty lanes, all `[+]`, stuck 456×360). Confirmed in SV: `Slots.lua:894` / `Layout.lua:941` nil-call errors from the 0.5.5 session.

**0.5.7 (iteration 2 — look + stable size)**
- Stack counts: `NumberFontNormal` white, BOTTOMRIGHT −5,2 (StackMerge cyan removed)
- Headers: Baganator Forever `bag-arrow` (rotated) + `GameFontNormalMed2` label + grey `(n)`; no `[+]/[-]` text
- Slots: ItemButtonTemplate Normal/Pushed/Highlight/IconBorder read at runtime; full-texcoord icon in BORDER; `bags-item-slot64` well
- Frame size pinned to the unfiltered bag: search / filter / "No matches" never shrink the window

**Keep:** Toggle* replace (B stable) — OpenClose untouched.

**Done when:** `/reload` → `v0.5.7` → B: arrows + gold headers, white counts, Blizzard-like slots · type a no-match search → window size unchanged · clear search → same layout · B closes.
