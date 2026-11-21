# Playtest brief — BetterBackpack 0.5.8

**History:** 0.5.6 fixed empty lanes (helpers called before `local` decl). 0.5.7 added bag-arrow headers, ItemButtonTemplate slot art, white counts. Ondřej rejected the 0.5.7 result (little visible change; window resized on collapse/search).

**0.5.8**
- Window size fixed = full bag, unfiltered, every lane expanded → collapse / search / filter / "No matches" never resize
- Space freed by collapse / search → empty `bags-item-slot64` wells (`profile.fillEmptyWells`, default on)
- Lanes with no matches hide with their header
- Dense grid: PAD 2, HEADER_H 18, SECTION_GAP 4 (Pins grid PAD 2 to match)
- Stack counts `NumberFontNormalSmall` white, BOTTOMRIGHT −3,2

**Keep:** Toggle* replace (B stable) — OpenClose untouched.

**Done when:** `/reload` → `v0.5.8` → B · collapse a lane → size unchanged, wells fill gap · search no-match → size unchanged, wells · clear → same layout · B closes.
