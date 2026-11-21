# BetterBackpack — smyčky a grafy

**Kód:** `Core.lua`, `Modules/{Slots,Layout,Context,OpenClose,Tidy}.lua`  
**Verze reference:** 0.1.0  
**Stabilita:** Project `docs/bag-addon-brief.md` + Scenario Maps `docs/scenarios/BetterBackpack/`  
**CS-RMB:** path **B** — `SecureActionButtonTemplate` attrs OOC (never path C harvest).

---

## 1. Open / close (B → BetterBackpack)

```mermaid
flowchart TD
  B[ToggleAllBags / ToggleBackpack]
  B --> Lock{t < toggleLockUntil?}
  Lock -->|ano| Pulse[PulseHide only]
  Lock -->|ne| Vis{OursVisible?}
  Vis -->|ne| Open[OpenOurs]
  Vis -->|ano| Grace{openedAt < 0.6s?<br/>InOpenGrace = jen openedAt}
  Grace -->|ano same press| Pulse
  Grace -->|ne| Close[CloseOurs + SuppressReplace]
  Close --> Rest[RestoreBlizzardBags + CloseAllBags]
  OnShow[CombinedBags OnShow] --> Supp{IsReplaceSuppressed?}
  Supp -->|ano| Skip[return — ne OpenOurs]
  Supp -->|ne + own| Stash[StashFrame alpha/park]
  Supp -->|ne + free| Open
```

**Pravidla**

- Nikdy `SetOverrideBindingClick`.
- CombinedBags `:Show()` + `SetAlpha(0)` + park — **ne** `:Hide()`.
- `SuppressReplace`; OnShow nesmí ClearSuppress→OpenOurs.
- Grace ≠ `toggleLockUntil`.
- Watchdog restash; heal ≤1×/s.

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
