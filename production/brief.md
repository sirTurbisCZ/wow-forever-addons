# Playtest brief — BetterBackpack 0.3.2 hotfix

**Bug:** B crash — CombinedBags OnShow opened BB before ToggleBackpack hooksecurefunc XOR, so B immediately closed; OpenOurs false left bags blacked out.

**Fix:** defer OnShow open one tick; OpenOurs retry + unblackout on fail; chrome sizes from Close GetWidth/Height (no button recreate).

**Done when:** `/reload` → `loaded v0.3.2` · B opens and stays open · second B closes.
