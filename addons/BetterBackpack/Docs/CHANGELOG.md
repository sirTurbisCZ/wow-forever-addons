# BetterBackpack changelog

## 1.0.11

- **B key:** `ReplaceToggle` / `ReplaceOpen` re-assert BB wrapper when `_G.ToggleBackpack` stolen (e.g. BagShelves in FELog); late `ADDON_LOADED` → `EnsureBagKeyReplace`. `bagKeyTrace` (last 16) in `BetterBackpackDB` mirrors chat onBagKey lines.

## 1.0.10

- **B key:** stop calling `RestoreBlizzardToggles` inside `ApplyBagKeyReplace` — `InstallHooks` runs it again at +0s/+1s; restore stripped the BB wrapper while `_replaced_ToggleBackpack` blocked re-hook (post-reload B dead, no new FELog after `1795291991`).

## 1.0.9

- **B / CloseOurs:** skip `RestoreNativeBagFrames` when `bagBarNativeBag` (default) — nothing to restore; live FELog nil @ `:153` / `:108` on `ToggleBackpack` → `CloseOurs`. `OpenOurs` → `local function`.

## 1.0.8

- **B / CloseOurs:** move `KeyRingFrameNames`, `ClearFocusBag`, `FocusBagsMatch`, … to `local function` before first use (live FELog nil @ ~108–153 on `ToggleBackpack` → `CloseOurs`); `pcall` on `ClearFocusBag` + `RestoreNativeBagFrames`.

## 1.0.7

- **B / CloseOurs:** `RestoreNativeBagFrames` restores keyring via static frame names (live FELog nil @ `OpenClose.lua:153`–`154` on `KeyRingFrameNames()` after 1.0.6 forward-decl). `NormalizeBagID` → proper `local function` + `SafeNum` type guard.

## 1.0.6

- **B / CloseOurs:** forward-decl `KeyRingFrameNames` — `RestoreNativeBagFrames` called it before `local function` binding (nil @ line 153; same Lua scope bug as 1.0.5 `NormalizeBagID`).

## 1.0.5

- **B / CloseOurs:** hoist `NormalizeBagID` + `BBKeyringBagIndex` before `KeyRingFrameNames` (main 1.0.0 scope bug; live FELog `ToggleBackpack` → nil @ ~153). No bag-bar hook changes.

## 1.0.4

- **Revert** 1.0.1–1.0.3 bag-bar work: restore `OpenClose.lua` from **1.0.0** (`ToggleBag` untouched). Bag-bar fix deferred.

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