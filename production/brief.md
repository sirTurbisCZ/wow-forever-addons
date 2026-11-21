# Playtest brief — BetterBackpack 0.5.79

**0.5.79**
- Fix load: `CaptureBlizzardOpens` before `RestoreBlizzardToggles` (B XOR works again).
- Merchant hook: deferred + only when BB already open (OpenAllBags still routes vendor).

**0.5.78**
- Vendor **MERCHANT_SHOW**: park CombinedBags; keep BB if open.
- **OpenAllBags** / **OpenBag** → `OpenOurs` (not native Spojený batoh after first B).
- Shift+RMB lane bulk unchanged.

**0.5.77**
- Shift captured on header **MouseDown**; bulk on **MouseUp** + OnClick via `TransferLane`.
- One chat line: `Bulk header trace: lane=… ctx=…` on first bulk attempt.
- Shift+RMB never collapses (plain RMB still toggles lane).

**0.5.76**
- Lane header **RMB** = collapse/expand (unchanged).
- **Shift+RMB** header at vendor/mail/bank = bulk sell/attach/deposit (tooltip when context open).

**0.5.75**
- After `EnsureCombatShell`: `_bbKeepShown` - frame stays `Show()`; close = alpha 0 only.
- Combat `CombatPresentFrame`: **no `Show()`** in lockdown (alpha 1 + mouse). Metrics add `keep=`.

**0.5.74**
- Combat open: force CENTER (not saved offscreen pos); fix w/h<100; one chat `combat B · metrics · w=…`.

**0.5.73**
- Shell warmup runs **one OOC DoLayout** (`_bbLayoutWarm`) so combat has slots.
- `CombatPresentFrame`: UIParent, PlaceOnScreen, size, alpha 1, Raise, content Show, chrome refresh.
- No SetFrameStrata (Forever blocked).

**0.5.72**
- Combat visibility: `IsBagFrameVisible` uses alpha+`_bbBuilt` in lockdown (not `IsShown`).
- Shell `Show` at alpha 0; `ShowCombatMinimal` no longer recurses into `CombatShow`.
- XOR: `OursVisible` -> `IsBagFrameVisible`; combat open syncs `shown` from visible.

**0.5.71**
- **Combat shell OOC:** `EnsureCombatShell` = PreCreate + EnsureMain only (no DoLayout). Runs on LOGIN (deferred 0) and PLAYER_REGEN_ENABLED.
- **Combat B:** `CombatShow` alpha; missing `_bbBuilt` falls back `ShowCombatMinimal`. No "open OOC first" chat.
- No ENTERING_WORLD, no ColdPreload.

**0.5.70** (0.5.68-stable base + combat alpha, no ColdPreload)
- **Load:** same as 0.5.68. No `ENTERING_WORLD`. No login `DoLayout` preload.
- **Combat B:** open bags **once OOC** first (`_bbBuilt`). Then in combat: B toggles alpha (`CombatShow`/`CombatHide`); close never `Hide()` in lockdown.
- OpenClose: combat branch calls `Layout.CombatShow` only. Toggle* unchanged.
- Expect `loaded v0.5.70`, B XOR OOC, then combat B after one OOC open.

**0.5.69** (reverted — do not ship)
- Broke on `RegisterEvent("ENTERING_WORLD")` on Forever. See internal `betterbackpack-069-felog-cause.md`.

**0.5.68-stable-062-base**
- git `9277c4f` tree. OpenClose lexer fix (`--[[` stripped). BulkTransfer + VendorJunk.

**Gate**
- `/reload` -> `loaded v0.5.70`
- OOC B open/close x3
- Combat: after one OOC open, B x3 (no `BetterBackpackFrame:Hide()` in lastBlocked)
- FrameXML: no OpenClose parse line (fresh timestamp)