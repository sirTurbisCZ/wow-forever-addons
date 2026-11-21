# Playtest brief — BetterBackpack 0.5.72

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