# BetterBackpack changelog

## 1.0.2

- **Bag bar:** forward-declare `BagIdFromButton` (nil call in `IsKeyringBarButton` when hooks run).

## 1.0.1

- **Bag bar:** install `EnsureBagBarHooks` (was never called); hook clicks in native + overlay modes; replace `ToggleBag` / `ToggleKeyRing` through `onBagToggle` (B unchanged).

## 1.0.0 (release)

- **Combat:** keep-shown bag shell; B toggles alpha without blocked `Show()` in lockdown.
- **Vendor:** `OpenAllBags` routes to BetterBackpack; CombinedBags parked while ours is open.
- **Bulk sell:** Shift+RMB lane header at merchant — sync sell in click (`BulkTransfer` + `ContainerAPI` bag indices).
- **Auto-sell:** grey junk at vendor (`VendorJunk`) — settings toggles.
- **English-only** UI strings and documentation cleanup; dropped legacy `/bb uklid` alias and Czech debug field names.

### 0.5.84 → 0.5.82 (bulk path)

- TOC load order: `BulkTransfer` after `Layout`; runtime `LayoutMod()`.
- Sync vendor pump (no `C_Timer` Pickup/Sell).
- Header Shift capture; `ListLaneSlots(unfiltered)` fix.