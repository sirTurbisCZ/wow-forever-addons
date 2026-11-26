# Plateband brief — 0.3.01 (auras)

**Goal:** Weakened Soul on friendly plates + hostile DoT overlap/missing — prove via live PAINT/CARD, not guess.

**Keep:** native DebuffList safe default; merge on for enemy foreign gaps; silentTrace PAINT feed; host export watch.

**Avoid:** taint on name/DebuffList; claiming matrix OK without hostile multi-paint samples.

**Done when:**
- Matrix `friendly_ws` + `friendly_ws_paint` OK with live `friend=1 painted>0 tfRows>0`
- Matrix `own_foreign_paint` + overlap rows OK after mob pull with party DoTs
- `plateband-sv-anomaly.sh` clean; no new `ADDON_ACTION_BLOCKED`

**Live check (no reload if already 0.3.01):** `./scripts/plateband-sv-matrix.sh` + anomaly after priest PW:S on friend + mob pull.