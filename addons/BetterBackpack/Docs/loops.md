# BetterBackpack — smyčky a grafy

**Kód:** `Core.lua`, `Modules/{Slots,Layout,Context,OpenClose,Tidy}.lua`  
**Verze reference:** 0.3.9  
**Stabilita:** Project `docs/bag-addon-brief.md` + Scenario Maps `docs/scenarios/BetterBackpack/`  
**CS-RMB:** path **B** — `SecureActionButtonTemplate` attrs OOC (never path C harvest).

---

## 1. Open / close (B → BetterBackpack)

```mermaid
flowchart TD
  B[ToggleAllBags / ToggleBackpack / ToggleBag / bag-bar OnClick]
  B --> Black[BlackoutAllBlizzard alpha=0 first]
  Black --> Lock{t < toggleLockUntil or debounce?}
  Lock -->|ano| Pulse[Park only]
  Lock -->|ne| Vis{SessionOpen?}
  Vis -->|ne| Open[OpenOurs + SetBagFocus + park]
  Vis -->|ano| Close[CloseOurs + ClearBagFocus]
  Close --> Keep0[Keep alpha=0 + CloseAllBags<br/>NEVER RestoreBlizzard alpha=1]
  OpenOnly[OpenAllBags / OpenBag] --> OpenOrPark[Open if closed else park+focus]
  CloseAPI[CloseBag / CloseAllBags] --> Close
  OnShow[CombinedBags Show/OnShow] --> BO[Blackout first line]
  BO --> Park[Park; OpenOurs only if still closed]
```

**Pravidla**

- Nikdy `SetOverrideBindingClick`.
- Anti-flash: `Show`/`OnShow`/`onToggle` → **Blackout alpha=0 first**; CloseOurs never `RestoreBlizzardBags`.
- CombinedBags stays `IsShown`+parked while ours open — **ne** `:Hide()` mid-session.
- `SuppressReplace`; OnShow nesmí ClearSuppress→OpenOurs.
- **ToggleBag + bag-bar OnClick = XOR** (same as B). OpenBag/OpenAllBags = open-only. CloseBag/CloseAllBags close ours.
- HookScript OnClick only on frames with `HasScript("OnClick")` / Button — never throw on BagsBar chrome kids.
- Bag focus: `Layout.SetBagFocus(id)` highlights that bag’s slots after open.
- Title chrome: reparent native `BagItemAutoSortButton`; settings twin sized to AutoSort (PortraitButton stays on CombinedBags).
- Footer N/M: player bags `0..NUM_BAG_SLOTS` + **reagent bag** (Materials lane). Never keyring invent (102=70+32).
- Slots: `Normalize` 37×37 on every `Place` and after `SetItemButtonQuality`.
- CombinedBags/Container OnShow: park now; **defer** open to next tick so Toggle* XOR runs first.

---

## 2. Layout — own SAB only

```mermaid
flowchart TD
  L[Layout Relayout]
  L --> Buckets[CollectBuckets ClassifyBagSlot]
  Buckets --> Place[Slots.Acquire + Place into lanes]
  Place --> Attrs{OOC?}
  Attrs -->|ano| Sync[SyncAttrs type2=item]
  Attrs -->|ne combat| Keep[Keep prior attrs · visual sync]
  Place --> Unused[ParkUnused off-screen]
```

Žádný harvest / `SetParent` CombinedBags.Items.

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
