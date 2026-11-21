# BetterBackpack — smyčky a grafy

**Kód:** `Core.lua`, `Modules/{Slots,Layout,Context,OpenClose,Tidy,Settings,Search,Filter,CustomCategories,StackMerge,Pins,LayoutModes}.lua`  
**Verze reference:** 0.3.0-nth (feature branch `betterbackpack/features-nth`)  
**Stabilita:** Project `docs/bag-addon-brief.md` + Scenario Maps `docs/scenarios/BetterBackpack/`  
**CS-RMB:** path **B** — `SecureActionButtonTemplate` attrs OOC (never path C harvest).

---

## 1. Open / close (B → BetterBackpack)

```mermaid
flowchart TD
  B[ToggleAllBags / ToggleBackpack]
  B --> Black[BlackoutAllBlizzard alpha=0 first]
  Black --> Lock{t < toggleLockUntil?}
  Lock -->|ano| Pulse[PulseHide only]
  Lock -->|ne| Vis{SessionOpen?}
  Vis -->|ne| Open[OpenOurs + park IsShown]
  Vis -->|ano| Grace{openedAt grace?}
  Grace -->|ano same press| Pulse
  Grace -->|ne| Close[CloseOurs]
  Close --> Keep0[Keep alpha=0 + CloseAllBags<br/>NEVER RestoreBlizzard alpha=1]
  OnShow[CombinedBags Show/OnShow] --> BO[Blackout first line]
  BO --> Park[Park if session/replace]
```

**Pravidla**

- Nikdy `SetOverrideBindingClick`.
- Anti-flash: `Show`/`OnShow`/`onToggle` → **Blackout alpha=0 first**; CloseOurs never `RestoreBlizzardBags`.
- CombinedBags stays `IsShown`+parked while ours open — **ne** `:Hide()` mid-session.
- `SuppressReplace`; OnShow nesmí ClearSuppress→OpenOurs.
- Grace ≠ `toggleLockUntil`; OpenAllBags while open must not extend lock.
- Open: Toggle* XOR; **OpenAllBags/OpenBag/ToggleBag/bag-bar** open intent. Keys/keyring lane. N/M centered. Hug-content height.

---

## 2. Layout — own SAB only (+ NTH feature hooks)

```mermaid
flowchart TD
  L[Layout Relayout]
  L --> Class[ClassifyBagSlot + CustomCategories.Resolve]
  Class --> Buckets[CollectBuckets]
  Buckets --> SF[Search.Passes + Filter.Passes]
  SF --> Merge[StackMerge.Collapse per lane]
  Merge --> Place[Slots.Acquire + Place · ApplyDisplayCount]
  Place --> Pins[Pins.Layout ghosts for missing]
  Pins --> Chrome[Search.EnsureChrome]
  Place --> Attrs{OOC?}
  Attrs -->|ano| Sync[SyncAttrs type2=item]
  Attrs -->|ne combat| Keep[Keep prior attrs · visual sync]
  Place --> Unused[ParkUnused off-screen]
```

Žádný harvest / `SetParent` CombinedBags.Items.  
Feature modules are optional `Feat("Name")` lookups — TOC can omit a file without Layout crash.  
`LayoutModes.Columns` densifies grid; stack merge is visual-only (first real bag:slot keeps clicks).

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
