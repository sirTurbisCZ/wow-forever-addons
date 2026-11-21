# Playtest brief — BetterBackpack 0.3.8

**Bug:** footer 51/62 missing reagents; Materials empty. 62+8 reagent = 70.

**Fix:** `InventoryBagRanges` = bags 0..NUM_BAG_SLOTS + reagent (API or free+occupied probe). Footer + CollectBuckets both use it. Chat: `… R=8 → used/total=N/70`.

**Done when:** `/reload` → footer **/70** · Materials shows reagent-bag items.
