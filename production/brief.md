# Playtest brief — BetterBackpack 0.5.49 (session reset)

**0.5.49**
- Stuck after 1st close: **`SessionOpen` = frame `IsShown` only** (not `bagsOpen`). **`ResetOverlaySessionState`** after every `CloseOurs` / `NotifyHidden`. `Layout.ForceHidden`. Unpark native ContainerFrames if left off-screen. B close suppress 0.1s.

**0.5.48**
- **Close:** X wired every layout (`WireCloseButton`); **B XOR close** uses `closeBlizzard=true` like `/bb`. `CloseOurs` clears flags, `Layout.Hide`, **`RestoreCombinedBagsUI`** (no stuck alpha-0 Combined). `NotifyHidden` syncs `bagsOpen`.

**0.5.47**
- **B** back to **0.5.45**: both `ToggleAllBags` + `ToggleBackpack` → **`onBagKey`**. Fix 0.5.46 regression: no `RestoreNativeBagFrames` during park (un-blackout Combined). Keep unpark ContainerFrames on **CloseOurs**.

**0.5.46**
- Broke B (restore Combined during park / combat-only path). Bag unpark kept in 0.5.47.

**0.5.45**
- **B** binds often hit **`ToggleBackpack`** — replace **Both** `ToggleAllBags` + `ToggleBackpack` (re-apply 0s/1s after login). `OpenOurs` / `onBagKey` call **`CloseNativeCombinedBags`** (park + Hide). Chat: `2/2 toggles`.
- Bag bar = native `ToggleBag` only (no bar OnClick hooks). `/bb` XOR.

**0.5.44**
- ToggleAllBags only — insufficient when B = ToggleBackpack.

**0.5.43**
- WTF top error was `OpenClose.lua:1398 unexpected symbol near 'if'` (0.5.42 trims InstallHooks). Harden: `EnsureMain` / `DoLayout` chrome in pcall; Settings `notes` nil; hooks install pcall.
- **`/reload`** → `loaded v0.5.43`, `/bb` opens without `EnsureMain failed` / layout abort.

**0.5.42**
- Fix: `OpenClose.lua` failed to load (`unexpected symbol near 'if'` after bare `return`). `InstallHooks` trimmed; keyring helper renamed `BBKeyringBagIndex` (no Blizzard global clash). **`/reload`** → `loaded v0.5.42`, no `OpenClose` nil in FELog.

**0.5.41**
- No global Toggle* replace. All Blizzard bag keys native. **`/bb`** toggles BetterBackpack. Login should not crash.

**0.5.40**
- Crash stop: **only ToggleAllBags** hooked; all frame/Open/Close/bag-bar hooks off (`SOFT_BAG_HOOKS`). pcall on replace handler + onBagKey path.

**0.5.39**
- 0.5.38 crash/loop: snapshot Blizzard toggles at install; no CombinedBags→onOpenIntent; reentrancy guards on B path.

**0.5.38**
- Only **ToggleAllBags** → BetterBackpack. Bag bar + keyring = vanilla Blizzard (globals restored, no bar hooks).

**0.5.37**
- OpenClose reset: B = overlay XOR only; bag bar = orig Blizzard toggles (raw bag id, secrets OK); no ContainerFrame park when `bagBarNativeBag`.

**0.5.36**
- Bag bar: backpack 0, bags 1–4, reagent, keyring — `ToggleBag` secret indices pass through to Blizzard (fix post-0.5.35 early return).

**0.5.35**
- FElog `OpenClose.lua:191`: forward-decl `NormalizeBagID`; `ToggleBag -1` → keyring path; `CallOrigToggle` guards missing Blizzard orig.

**0.5.34**
- Combat **B**: `ForceCombatShow` when `BetterBackpackFrame` exists; chat lines `combat B · …` once per branch (busy/replace/xor/no frame/show fail). Paste traces if still dead.

**0.5.33**
- **B in combat:** `ShowCombatMinimal` — only if `BetterBackpackFrame` was built OOC; else one chat line. No DoLayout/create/SetAttribute in lockdown.
- **Keyring:** native XOR; probes KeyRingFrame + ContainerFrame + KEYRING id; no triple ToggleKeyRing+ToggleBag+OpenKeyRing.

**0.5.32**
- **B in combat:** combined opens with prebuilt frame; Blizzard CombinedBags hidden alpha-only (no reparent). No new SecureActionButton/SetAttribute in combat.

**0.5.31**
- Keyring: `ToggleKeyRing` + `ToggleBag(KEYRING_CONTAINER)` + `OpenKeyRing`; bar/mixin routes to `onKeyRingToggle`; KEYRING frame restore.

**0.5.30**
- Native bag-bar: orig `ToggleBag` / `ToggleKeyRing`, no toggleLock on bar, OnShow restore while opening. B unchanged (combined).

**0.5.29**
- B: `ToggleAllBags` and `ToggleBackpack` → combined XOR (Forever often binds B to ToggleBackpack). Backpack **icon** still native bag 0 (mouse-down arm).
- Native visibility ignores parked off-screen frames; `OpenBag` + anchor refresh.
- `/bb dump` prints open-state line — paste if still broken.

**0.5.28**
- **B / ToggleAllBags** opens/closes BetterBackpack combined again; not blocked after bag-bar click; with native bag open, B switches to combined.

**0.5.27**
- Every bag-bar icon (`0`–`NUM_BAG_SLOTS`, reagent, keyring) opens native `ContainerFrame`. Backpack icon uses `ToggleBackpack` → bag 0 (not combined). **B** = combined only (`ToggleAllBags`).
- Broom/gear/X: same Close `GetWidth/Height` every layout (`StyleCloseTwin` + glyph crop).

**0.5.26**
- **B** = BetterBackpack combined overlay (all lanes). **Bag-bar / per-bag icon** = native Blizzard `ContainerFrame` (or keyring) — not overlay. Toggle same icon closes; another icon switches native bag. Settings → Features → *Bag bar opens native Blizzard bag* (default on; off = overlay + slot highlight).
- Broom: gold AutoSort art stretched to **exact Close button size**.

**0.5.25** (superseded open-mode)
- Overlay single-bag collect — replaced by native frames in 0.5.26.

**0.5.24**
- Settings rebuilt: left categories (Lanes, Custom lanes, Trash, Learned, Features), right panel — like Interface Options.
- Removed "+ Lane" from bag search row; new custom lanes only via Settings → Custom lanes → New lane.

Branch `cursor/bb-056-layout-expand-hug-9374` (includes bank RMB 0.5.12, search 0.5.11, Close-chrome title buttons 0.5.16, sticky size 0.5.15, drag-teach lanes 0.5.17–0.5.18).

**0.5.21**
- Trash drop fix: Forever secret item IDs on cursor no longer block `DropOnLane` — itemID captured before pickup. Dropping on Trash header works (OnMouseUp/OnReceiveDrag); header won't collapse while holding an item. Junk ≠ Trash (tooltip + header `(destroy)`).
- No false "locked" while the stack is on your cursor; waiting-destroy flush only when cursor is empty.

**0.5.20**
- Trash is click-only on Forever (Ondřej's trashtest: click=OK, timer and event blocked). No more timer / event destroy attempts → no "Interface action failed". New loot of a Trash item waits red in Trash and goes on the next click in the bag.
- `/bb trashtest go` now only checks click destroy (1 grey stack).

**0.5.19**
- Fix: Shift+LMB on a bag item links it into the open chat / whisper box again (Ctrl = dress-up, Shift with no chat = split stack).
- Trash lane (off by default — gear → Lanes → Trash). Drop a grey/white stack on it → destroyed now (first time per item asks), future loot of that item destroyed too. A grey ghost icon stays in Trash (no bag slot). Drag the ghost to another lane, or click it → Keep, to stop destroying it. Settings → Trash lists every item with Keep.
- Never destroyed: quest items, green or better, locked items, hearthstone. Never in combat.

**0.5.18**
- Empty custom lanes are drawn (header `(0)`) so they are drop targets; custom-lane rows in Settings accept drops too.

**0.5.17**
- Drag an item onto another lane (header or any item in it) → item stays in its slot, its itemID is taught to that lane (SavedVariables `itemRules`). Drop back on its natural lane = forget.
- **+ Lane** next to search: click = name a new lane; drop an item = new lane with that item.
- Settings (gear) rebuilt in bag chrome: Lanes on/off (unchecked → Other) with taught counts · Custom lanes Rename / Delete / New lane · Learned items count + Forget all · Trash · Features (stack merge, dense).

**Keep:** Toggle* replace (B stable) · bank RMB deposit · fixed window size.

**Done when:** `/reload` → `v0.5.21` · open a whisper, Shift+LMB an item in the bag → link appears in the box · gear → check Trash → Trash header `(0)` in bag · drop a grey item on it → popup → Destroy → gone, grey ghost with `x3` in Trash · drop a green item → refused message, item back · loot the same grey item again → red in Trash, no "Interface action failed" → click anything in the bag → destroyed · drag the ghost onto Junk/Other → "kept again", ghost gone · next loot stays · B ×5 stable.
