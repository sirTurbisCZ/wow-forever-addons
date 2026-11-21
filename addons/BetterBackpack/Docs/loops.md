# BetterBackpack — smyčky a grafy

**Kód:** `Core.lua`, `Modules/{Slots,Layout,Context,OpenClose,Tidy,Settings,Search,Filter,CustomCategories,StackMerge,Pins,LayoutModes}.lua`  
**Verze reference:** 0.5.6 (chrome skutečně aplikovaný v DoLayout · hug-width grid · kategorie default rozbalené)  
**Stabilita:** Project `docs/bag-addon-brief.md` + Scenario Maps `docs/scenarios/BetterBackpack/`  
**CS-RMB:** path **B** — `SecureActionButtonTemplate` attrs OOC (never path C harvest).

---

## 1. Open / close (B → BetterBackpack)

```mermaid
flowchart TD
  B[ToggleAllBags / ToggleBackpack / ToggleBag / ToggleKeyRing]
  B --> Rep[Replace global — skip Blizzard body]
  Rep --> Black[BlackoutAllBlizzard alpha=0 first]
  Black --> Lock{t < toggleLockUntil or debounce?}
  Lock -->|ano| Pulse[Park only]
  Lock -->|ne| Vis{SessionOpen?}
  Vis -->|ne| Open[OpenOurs + SetBagFocus + park]
  Vis -->|ano| Close[CloseOurs + ClearBagFocus]
  Close --> Keep0[Keep alpha=0 + CloseAllBags<br/>NEVER RestoreBlizzard alpha=1]
  OpenOnly[OpenAllBags / OpenBag — non-Toggle API] --> OpenOrPark[Open if closed else park+focus]
  CloseAPI[CloseBag / CloseAllBags] --> Close
  OnShow[CombinedBags Show/OnShow] --> BO[Blackout first line]
  BO --> Park[Park; deferred OpenOurs only if still closed]
```

**Pravidla**

- Nikdy `SetOverrideBindingClick`.
- Forever: never call `SetFrameStrata` / `SetToplevel` in Lua. **0.5.5+:** `ButtonFrameTemplate` + CombinedBags NineSlice/TopTile/Bg at Baganator Forever offsets (6,-21); **Inset:Hide**; empty `SlotBackground` on slots; footer inside bottom border.
- **0.5.3+:** `Toggle*` are **replaced**, not `hooksecurefunc`. Post-hooks ran after Blizzard `Open*`/`Close*` → open/close thrash that froze on B.
- Anti-flash: `Show`/`OnShow`/`onToggle` → **Blackout alpha=0 first**; CloseOurs never `RestoreBlizzardBags`. OpenOurs fail → `ForceCloseBlizzard` (not Unblackout).
- CombinedBags stays `IsShown`+parked while ours open — **ne** `:Hide()` mid-session.
- `SuppressReplace`; OnShow nesmí ClearSuppress→OpenOurs.
- **ToggleBag + bag-bar OnClick = XOR** (same as B; `toggleLockUntil` after replaced ToggleBag). OpenBag/OpenAllBags = open-only. CloseBag/CloseAllBags close ours.
- HookScript OnClick only on frames with `HasScript("OnClick")` / Button — never throw on BagsBar chrome kids.
- Bag focus: `Layout.SetBagFocus(id)` highlights that bag’s slots after open.
- Frame size (**0.5.6 hug**): `cols = clamp(nejširší rozbalená lane, MIN_COLS=6, Columns())` (Columns = profile 10, dense ≥12). Grid = `cols*37 + (cols-1)*4`; outer = `INSET_X + grid + INSET_X` (symetricky, INSET_X=14); výška = TOP_CHROME 54 + obsah + BOT_CHROME 30. Žádný prázdný pruh vpravo.
- Kategorie jsou **default rozbalené**; `[+]/[-]` header = per-profile toggle. Schema 3 (0.5.6) jednorázově maže `collapsed` zaseknutý z 0.5.4/0.5.5 (prázdné lanes → hráč zavřel všechny headery).
- Lua 5.1: helper volaný z `DoLayout` / `SyncVisual` / `Acquire` musí být deklarovaný **nad** volajícím (nebo forward `local X` + `X = function`). 0.5.4/0.5.5 volaly `ApplyCombinedBagsChrome` / `EnsureSlotBackground` jako nil global → DoLayout abort na prvním itemu (žádné ikony, frame se nezmenšil).
- Title chrome: AutoSort **twins** (same native size, atlas art, no ADD glow); broom | gear | X. No native reparent.
- Footer N/M: player bags `0..NUM_BAG_SLOTS` + **reagent bag** (Materials lane). Never keyring invent (102=70+32).
- Slots: `Normalize` 37×37 on every `Place` and after `SetItemButtonQuality`.
- CombinedBags/Container OnShow: park now; **defer** open to next tick (non-Toggle Open* only).

---

## 2. Layout — own SAB only (+ NTH Feat hooks)

```mermaid
flowchart TD
  L[Layout Relayout]
  L --> Class[ClassifyBagSlot + CustomCategories.Resolve]
  Class --> Buckets[CollectBuckets]
  Buckets --> SF[Search.Passes + Filter.Passes]
  SF --> Merge[StackMerge.Collapse per lane]
  Merge --> Hug[cols = clamp widest expanded lane, 6, Columns]
  Hug --> Col{lane collapsed?}
  Col -->|ano| Hdr[header only · '+']
  Col -->|ne default| Place[Slots.Acquire + Place on main · SlotBackground well · ApplyDisplayCount]
  Hdr --> Pins
  Place --> Pins[Pins.Layout ghosts for missing · same cols]
  Pins --> Size[main:SetSize INSET+grid+INSET × TOP+content+BOT]
  Size --> Chrome[ApplyCombinedBagsChrome NineSlice/Bg/TopTile · EnsureTitleChrome · Search.EnsureChrome]
  Chrome --> Foot[UpdateFreeSpace N/M + money]
  Place --> Attrs{OOC?}
  Attrs -->|ano| Sync[SyncAttrs type2=item]
  Attrs -->|ne combat| Keep[Keep prior attrs · visual sync]
  Place --> Unused[ParkUnused off-screen]
```

Žádný harvest / `SetParent` CombinedBags.Items.  
Feature modules are optional `Feat("Name")` lookups — TOC can omit a file without Layout crash.  
`LayoutModes.Columns` densifies grid; stack merge is visual-only (first real bag:slot keeps clicks).  
Title chrome / AutoSort twins remain the 0.4.x path — NTH does not own OpenClose.

---

## 3. Combat RMB (CS-RMB)

```mermaid
sequenceDiagram
  participant P as Player
  participant C as Core
  participant S as Slots

  Note over S: LOGIN OOC PreCreate 0–4+reagent ×36<br/>SecureActionButton type2=item
  P->>C: B / open
  C->>S: Layout + SyncAttrs
  P->>C: enter combat
  Note over C,S: Freeze protected mutates · mouse on secure
  P->>P: RMB potion → secure use
  P->>C: leave combat
  C->>S: Flush attrs + full Layout
```

---

## 4. Vendor / mail / bank

```mermaid
flowchart LR
  Show[MERCHANT/MAIL/BANK SHOW] --> Clear[Clear type2 use attrs]
  Clear --> RMB[RMB Pickup + Sell / ClickSendMail / PutItemInBag]
  Close[CLOSED] --> Restore[ForceRestore type2=item]
```

Mail: `MailFrame:IsVisible()` — ne stuck SendMailFrame alone.

---

## 5. Sort OOC

```mermaid
flowchart TD
  Sort[/bb sort]
  Sort --> Combat{InCombatLockdown?}
  Combat -->|ano| Defer[message · bail]
  Combat -->|ne| Native[C_Container.SortBags]
  Native --> Settle[suppress refresh · one Layout ~0.55s]
```
