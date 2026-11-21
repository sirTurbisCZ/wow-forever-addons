# Playtest brief — BetterBackpack 0.5.9

**History:** 0.5.6 fixed empty lanes (helpers called before `local` decl). 0.5.7 bag-arrow headers + ItemButtonTemplate slot art. 0.5.8 fixed full-bag window size (collapse/search never resize), dense grid, small counts.

**0.5.9**
- No empty fill wells: `fillEmptyWells` default false; schema 4 turns off the `true` saved by 0.5.8
- Broom = 1:1 copy of the live `BagItemAutoSortButton` art (normal/pushed/highlight) + size
- Gear = same size, flat gear icon from a verified atlas (`C_Texture.GetAtlasInfo`), same square highlight, 1px press offset. Old code never fell back because `SetNormalAtlas` doesn't error on unknown atlases
- Footer N/M uses the money text's font (copper button) and sits on its baseline

**Keep:** Toggle* replace (B stable) — OpenClose untouched.

**Done when:** `/reload` → `v0.5.9` → B · no wells after collapse/search · broom/gear/X look like CombinedBags · "43/70" matches money font/size · B closes.
