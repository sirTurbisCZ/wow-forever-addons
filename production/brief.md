# Playtest brief — BetterBackpack 0.5.68-stable-062-base

**0.5.68-stable-062-base**
- **Full tree** = git **9277c4f** (0.5.63) = **56da553** (0.5.62) OpenClose/Layout/Core + **BulkTransfer + VendorJunk** only.
- **Discarded:** 0.5.64–0.5.67 (combat ColdPreload, CombatShow/Hide paths, comment experiments).
- **OpenClose load fix only:** strip all `--[[` block comments + safe bag-bar `_G[frameName]` (logic still 0.5.62).
- Expect chat **`loaded v0.5.68`** and **B** BetterBackpack XOR. FrameXML must have **no** OpenClose parse error after `/reload`.

**0.5.62 reference**
- OpenClose = `a6367fd` body. ToggleAllBags + ToggleBackpack replaced; ToggleBag / ToggleKeyRing native.

**0.5.63 kept**
- Lane header RMB bulk (OOC). Vendor auto-sell at merchant (opt-in). No OpenClose edits in that commit.

**Do not ship until**
- `/reload` → `loaded v0.5.68`
- B open/close XOR ×3 OOC
- FrameXML.log no `OpenClose.lua` syntax line (fresh timestamp)