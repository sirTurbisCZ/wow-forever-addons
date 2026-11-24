# BetterBackpack changelog

## 1.2.8 — bag-key / combat / esc trace → SV only

- **No chat** for `onBagKey`, `combat-diag`, `combat B ·`, or `esc ·` (even with `/bb debug on`).
- **`BAGKEY`** lines in `actionTrace` / `sessionLog` (default silent trace on).
- **`/bb bagkey`** still prints diagnose to chat on demand.

### Playtest (1.2.8)

1. `/reload` → `v1.2.8`; press **B** — no `onBagKey` in chat.
2. `/bb debug on` + **B** — still no chat; `/bb dump` or SV shows `BAGKEY` tail.

## 1.2.7 — silent ACTION trace (agent-readable)

- **Silent by default:** `silentTrace` + `actionTraceOn` (schema **10**) — bulk/vendor diagnostics → SV, not chat.
- **ACTION lines:** lane bulk sell (`queued`/`sold`/`MISMATCH=1`), vendor auto-sell, esc debug when `profile.debug`.
- **Stores:** `sessionLog.export`, `actionTrace.export`, `lastActionTrace`; wiped each login.
- **Agent:** `./scripts/watch-forever-traces.sh` (shared with Plateband / FElog).

### Playtest (1.2.7)

1. `/reload` → `loaded v1.2.7` (no BulkTransfer spam).
2. Vendor → Ctrl+Shift+RMB lane or auto-sell → `/bb dump` shows `lastAction`.
3. Mac agent: `watch-forever-traces.sh watch 8` after one `/reload`.

## GitHub release 1.2.6 (PR merge `cursor/bb-shift-stack-recipe-9374`)

Tag `betterbackpack-v1.2.6` · includes **1.2.2–1.2.6**:

| Version | Highlights |
|---------|------------|
| **1.2.2** | Shift+RMB merged stack sell/mail; Recipes lane; Ctrl+Shift+RMB lane bulk |
| **1.2.3** | Recipe detection; stable merge anchors; merge-group transfer scan fix |
| **1.2.4** | Vendor auto-sell queue; per-char auto-sell + Settings preview (schema 8) |
| **1.2.5** | Mail subject from first attach when empty |
| **1.2.6** | Custom lanes + rules per character (schema 9) |

## 1.2.6 — custom lanes per character

- **Custom lanes** (`custom_*`), their **item assignments**, and drag-teach rules targeting those lanes live in `BetterBackpackDB.chars["Name-Realm"]` (schema **9**). Built-in lane toggles (`categories`, `hiddenDefaults`) and teachings to **default** lanes stay on account `profile`.
- **Upgrade:** first login after 1.2.6 copies `profile.customCategories` + `profile.itemRules` (custom_* only) into the **current** character, then clears account-wide custom storage.

### Playtest (1.2.6)

1. `/reload` → `loaded v1.2.6`.
2. Char A: Settings → Custom lanes → create lane + assign item → lane visible in bag.
3. Log to Char B → **no** Char A custom lane header.
4. Back to Char A → custom lane and assignments still there.
5. Built-in lane toggles (Recipes on/off) still shared unless you change them (expected).

## 1.2.5 — mail subject from first attach

- **Send mail:** when the subject field is **empty**, attaching an item (RMB, Shift merged stack, Ctrl+Shift lane bulk) sets the subject to that item’s **display name**. First successful attach wins; existing subject text is never overwritten.

### Playtest (1.2.5)

1. `/reload` → `loaded v1.2.5`.
2. Mailbox → Send; leave subject blank → **RMB** an item in BB → subject = item name.
3. Clear subject → **Shift+RMB** merged stack → subject = first stack’s item name.
4. New mail, blank subject → **Ctrl+Shift+RMB** lane header → subject = first attached item name.
5. Type a custom subject first → attach items → subject unchanged.

## 1.2.4 — vendor auto-sell (WFA-36)

- **Auto-sell reliability:** `MERCHANT_SHOW` uses the same `BulkTransfer` merchant **queue** as lane/merge sells (sync pump), re-scanning bag slots at sell time instead of one-off `TransferSlot` timer steps.
- **Per character:** grey toggle, Junk-lane toggle, and **marked itemIDs** live in `BetterBackpackDB.chars["Name-Realm"]` (schema **8** migrates the logged-in character from account `profile`).
- **Settings → Features:** lists **marked** items (drag row to teach, Remove) and **in bags now** preview with icons, names, stack count, and reason (grey / junk lane / marked). Chat summary names up to 6 items.

### Playtest (1.2.4)

1. `/reload` → `loaded v1.2.4`.
2. **Char A:** Settings → Features → enable **Auto-sell grey**; open Features — see grey junk in **In bags now** with icons.
3. Vendor → greys sell; chat `Bulk sold N / N · auto-sell` and item names (not count only).
4. **Char B:** disable grey, mark one item (drag to auto-sell row) → preview shows marked; vendor sells marked only.
5. Char A vs B toggles/marked lists differ after `/reload` (per character).

## 1.2.3 — playtest fixes (WFA-33/34/35)

- **Recipes (WFA-34):** broader detection — `C_Item.IsRecipeItem`, `GetItemClassAndSubClass`, trade-goods recipe subtype, `Recipe:` / `Pattern:` name prefixes; still respects taught rules and Settings lane toggle.
- **Merge layout (WFA-35):** lane lists sorted by bag/slot; merge **stable anchor** per merge key so opening one stack does not jump siblings; representative stays put until that slot empties.
- **Vendor/mail merge (WFA-33):** `CollectMergeGroup` scanned wrong bag ranges (`from`/`to` vs `bag`/`slots`) → always found 1 slot. Fixed inventory scan; shift latched on RMB down; merged icons transfer **whole group** on RMB at vendor/mail.

### Playtest (1.2.3)

1. `/reload` → `loaded v1.2.3`.
2. **Recipe** in bag → **Recipes** lane (disable lane in Settings → **Other**).
3. **3× same item** (stack merge): open/use one → other merged icons **same grid cells**.
4. Vendor: **RMB** merged icon → chat `moved N / N` or `sold N / N` for **all** stacks; mail same.
5. **Ctrl+Shift+RMB** lane header still bulk lane only.

## 1.2.2 — merged stack sell + Recipes lane

- **Vendor/mail:** **Shift+RMB** on a **stack-merged** slot sells/attaches **every physical stack** in that merge group (`StackMerge.CollectMergeGroup` → `BulkTransfer.TransferMergeGroup`). Plain **RMB** still moves one stack.
- **Lane bulk:** moved to **Ctrl+Shift+RMB** on the lane header (Shift+RMB alone no longer sells the whole lane).
- **Recipes lane:** built-in lane **Recipes** (`recipe` category); class **Recipe**, type/subtype heuristics, and **Learn** use-spell detection. Toggle in Settings → Lanes like other categories. Schema **7** adds `categories.recipe=true` for existing profiles.

### Playtest (1.2.2)

1. `/reload` → chat `loaded v1.2.2` · bulk hint mentions Ctrl+Shift header + Shift merged stack.
2. Duplicate stacks of one item (stack merge on) → vendor → **Shift+RMB** icon → all copies sell; **RMB** → one stack only.
3. **Ctrl+Shift+RMB** Materials (or other) header → whole lane sells; **Shift+RMB** header without Ctrl → collapse only (no lane sell).
4. Carry a recipe / pattern item → appears under **Recipes**; disable lane in Settings → item goes to **Other** (or next classifier).

## 1.2.1 — stack merge + lock state

- **StackMerge:** merge key is **`itemID` + `isLocked`** — locked and unlocked copies of the same item (e.g. lockboxes) show as **separate** visual stacks instead of one misleading icon.

## 1.2.0 — quest starter bang

- **Slots:** yellow **!** on bag slots when `C_Container.GetContainerItemQuestInfo` reports **`questID` and not `isActive`** (item begins a quest; not yet accepted). Uses Blizzard bang texture / `QuestBang` atlas; not shown for plain `isQuestItem` objectives.
- **Core:** `QUEST_ACCEPTED`, `QUEST_REMOVED`, `UNIT_QUEST_LOG_CHANGED` refresh open bag slot visuals (`RefreshCooldowns` → `SyncVisual` / `SyncQuestBang`).

## 1.1.9 — ship (combat B + ESC)

- **Combat B:** OOC **`EnsureCombatShell`** keeps **`Show`+alpha0** warm shell (`_bbKeepShown`); in combat toggle = alpha 1/0 on prebuilt frame (no `Hide` in lockdown). **`CloseOurs`** reparks shell OOC after close.
- **ESC (parked closed):** user-visible ⇔ `UISpecialFrames` via **`SyncBagUISpecialFrame`**. Parked keep-shown still counted as shown by Forever → **transient `Hide` only inside `CloseSpecialWindows`**, then **re-arm** (`_bbEscRearm`); no permanent `Hide` on warm shell.
- **ESC (user open):** listed in `UISpecialFrames`; one ESC closes bags; second ESC → game menu. **`CloseFromEsc`** fallback if needed.
- **ESC bugfix:** Blizzard **`CloseBackpack`** during close stack must not call **`onBagKey` open path** when `vis=false` — close-only no-op + skip during `_bbEscRearm`/`_bbEscPass`. **`BagKeyTrace`** order fix (nil in `BagCombatDiag`).
- **Debug:** `/bb debug on` → `bagEscTrace`, `combatBagTrace`, chat `esc ·` / `combat-diag`.

## 1.1.8

- **ESC (arch):** keep-shown `Show`+alpha0 on `ButtonFrameTemplate` still participates in ESC/CloseSpecialWindows on Forever even when **not** in `UISpecialFrames` (1.1.3 worked because shell was **Hidden**). Parked OOC: **transient `Hide` during `CloseSpecialWindows` only**, then re-arm keep-shown (combat B preserved). User-open: sync + normal UISpecial close. `_bbEscRearm` suppresses OnHide side effects.

## 1.1.7

- **ESC:** sync `UISpecialFrames` immediately before every `CloseSpecialWindows` (visible = listed, parked = not). Fallback `CloseFromEsc` if visible after orig. `NotifyHidden` ESC path + `OnHide` repark keep-shown shell after Blizzard `Hide`. `/bb debug on` → `bagEscTrace` + chat `esc ·` lines.

## 1.1.6

- **ESC:** `CloseSpecialWindows` guard no longer strips `UISpecialFrames` while bags are user-visible (1.1.x bug: first ESC opened game menu + left bags open). Parked keep-shown: strip only, no `Hide()` on ESC. `NotifyHidden` ignores OnHide from parked shell.

## 1.1.5

- **Combat B (fix):** restore **1.1.2 keep-shown** warm shell (`EnsureCombatShell` → `Show`+alpha 0). 1.1.4 parked with **`Hide()`** so combat could not `Show()` under lockdown → B dead. ESC: still strip `UISpecialFrames` when alpha 0 / `combatVisuallyHidden`; full `Hide()` only when `_bbKeepShown` is off (user had real open). **`CloseOurs`** reparks shell OOC. Removed ineffective `OnCombatEnter`/`OnCombatExit`. Debug: `/bb debug on` → `combat-diag` + `combatBagTrace` SV.

## 1.1.4

- **Combat B + ESC (failed live):** OOC `Hide()` after warm; `OnCombatEnter` on `PLAYER_REGEN_DISABLED` — combat B still broken (frame not `IsShown` in lockdown).

## 1.1.3

- **ESC:** disable OOC keep-shown (`Show`+alpha 0 after `EnsureCombatShell`); parked shell is **`Hide()`**. In-combat close still alpha-only; OOC `Hide()`. `CloseSpecialWindows` may `Hide()` invisible frame. LIVE had no `bagEsc` in SV until logout — use `/bb bagkey` after `/reload`.

## 1.1.2

- **ESC:** hard-strip `BetterBackpackFrame` from `UISpecialFrames` when alpha under 0.05 or parked; `CloseSpecialWindows` pre-hook; `bagEsc` SV snapshot; login sync retries. Combat `IsBagFrameVisible` requires alpha at least 0.05.

## 1.1.1

- **ESC:** `UISpecialFrames` for `BetterBackpackFrame` only while bags are user-visible — keep-shown combat shell (alpha 0, `Show()`) no longer blocks UIParent ESC.

## 1.1.0

- **B key (ship):** `ToggleBackpack` / `ToggleAllBags` / `OpenBackpack` / `CloseBackpack` replace + reassert; hook retries to +20s; `PLAYER_ENTERING_WORLD` + late `ADDON_LOADED`. BagShelves conflict warning.
- **Cleanup:** onBagKey chat + `bagKeyTrace` only when **`/bb debug on`**; no wrapper spam. **`/bb bagkey`** + silent `bagKeyHook` in SV for hook ownership.

## 1.0.13

- **B key:** hook `OpenBackpack` / `CloseBackpack`; retry toggles to +20s; `bagKeyHook` snapshot in SV; `wrap` bagKeyTrace lines; `PLAYER_ENTERING_WORLD` reassert; EnsureDB for trace persist.

## 1.0.12

- **BagShelves:** login conflict warn when loaded; `RestoreNativeBagFrames` guard fixed (was inverted). **`/bb bagkey`** — ToggleBackpack hook ownership + `bagKeyTrace`. If BagShelves is enabled at login, disable it (both replace bags).

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