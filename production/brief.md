# Playtest brief — BetterBackpack 0.3.7

**Where 102 came from:** footer used BagRanges + invented keyring 32 when API secret/failed → 70 + 32 = 102.

**Fix:** `CountPlayerSlots` = only `GetContainerNumSlots(0..NUM_BAG_SLOTS)`; never invent; chat once `slots 0=… 1=… → used/total=N/70`.

**Done when:** `/reload` → footer **/70** · chat breakdown sums to 70.
