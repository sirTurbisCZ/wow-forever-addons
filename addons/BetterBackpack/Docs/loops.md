# BetterBackpack — smyčky a grafy

**Kód:** `Core.lua`, `Modules/{Slots,Layout,Context,OpenClose,Tidy}.lua`  
**Verze reference:** 0.2.3  
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
- Title chrome: compact equal **Úklid**|**Nastavení** left of X (`EnsureTitleChrome` forward-assigned). Disabled cat → **Other**. White Count when stack>1 (blank if 1).

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
