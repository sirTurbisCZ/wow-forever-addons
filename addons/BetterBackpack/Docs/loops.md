# BetterBackpack — workflows and diagrams

**Code:** `Core.lua`, `Modules/{Slots,Layout,Context,BulkTransfer,VendorJunk,OpenClose,Tidy,Settings,Search,Filter,CustomCategories,Trash,StackMerge,Pins,LayoutModes}.lua`  
**Version reference:** 1.0.0 (combat keep-shown shell · sync vendor lane bulk · auto-sell grey · OpenAllBags→OpenOurs)  
**CS-RMB:** path **B** — `SecureActionButtonTemplate` attrs OOC (never harvest CombinedBags items).

---

## 1. Open / close (B → BetterBackpack)

```mermaid
flowchart TD
  B[ToggleAllBags + ToggleBackpack + Open/CloseBackpack<br/>reassert · bagKeyHook SV · debug-only onBagKey trace]
  Bar[ToggleBag / ToggleKeyRing → Blizzard]
  B --> Rep[Replace global — skip Blizzard body]
  Rep --> Black[BlackoutAllBlizzard alpha=0 first]
  Black --> Lock{t < toggleLockUntil or debounce?}
  Lock -->|yes| Pulse[Park only]
  Lock -->|no| Vis{SessionOpen?}
  Vis -->|no| Open[OpenOurs + Layout.Show]
  Open --> ParkMode{InCombatLockdown?}
  ParkMode -->|yes| AlphaOnly[ParkBlizzardForOverlay — alpha/mouse only]
  ParkMode -->|no| OffPark[off-screen Park + PulsePark]
  Vis -->|yes| Close[CloseOurs + ClearBagFocus]
  Close --> Keep0[Keep alpha=0 + CloseAllBags<br/>NEVER RestoreBlizzard alpha=1]
  OpenOnly[OpenAllBags / OpenBag] --> OpenOrPark[Open if closed else park+focus]
  CloseAPI[CloseBag / CloseAllBags] --> Close
```

**Rules**

- Never `SetOverrideBindingClick` or `SetFrameStrata` / `SetToplevel` on our frame.
- Toggle globals are **replaced**, not post-hooked.
- Combat (**1.0**): `_bbKeepShown` — main frame stays shown at alpha 0; open = alpha 1 only (no `Show()` in lockdown). **ESC:** strip from `UISpecialFrames` when alpha &lt; 0.05; `CloseSpecialWindows` guard.
- `OpenAllBags` / `OpenBag` → `OpenOurs` when replace is on (vendor keeps BB, not native CombinedBags).
- Window size is computed from the full unfiltered bag with all lanes expanded (sticky while open).

---

## 2. Layout

```mermaid
flowchart TD
  L[Layout Relayout]
  L --> Class[ClassifyBagSlot + CustomCategories.Resolve]
  Class --> Buckets[CollectBuckets]
  Buckets --> SF[Search.Passes + Filter.Passes]
  SF --> Merge[StackMerge.Collapse per lane]
  Merge --> Place[Slots.Acquire + Place]
  Place --> Attrs{OOC?}
  Attrs -->|yes| Sync[SyncAttrs type2=item]
  Attrs -->|combat| Keep[visual sync only]
```

Optional feature modules: `Feat("Name")` lookups — Layout does not crash if a module is omitted from TOC.

---

## 3. Combat RMB (CS-RMB)

```mermaid
sequenceDiagram
  participant P as Player
  participant C as Core
  participant S as Slots

  Note over S: LOGIN OOC PreCreate · SecureActionButton type2=item
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
  Show[MERCHANT/MAIL SHOW] --> Clear[Clear type2 use attrs]
  Clear --> RMB[RMB slot Pickup + Sell / ClickSendMail]
  BankShow[BANKFRAME_OPENED] --> Keep[Keep type2=item]
  Keep --> Deposit[Secure UseContainerItem deposits]
  Close[CLOSED] --> Restore[ForceRestore type2=item]
```

### 4b. Lane header bulk (Shift+RMB, OOC)

```mermaid
flowchart TD
  Down[RMB down capture Shift] --> Up[MouseUp / OnClick]
  Up --> Shift{Shift held?}
  Shift -->|no| Collapse[RMB collapse only]
  Shift -->|yes| RMB[TransferLane bulk]
  RMB --> Ctx{Context open?}
  Ctx -->|merchant| Sell[sync in click · Pickup+SellCursor / UseContainerItem]
  Ctx -->|mail| Mail[sync Pickup+ClickSendMail]
  Ctx -->|bank| Bank[UseContainerItem per slot async]
```

- **RMB** without Shift = lane collapse only.
- **Shift+RMB** at vendor: full lane via `Layout.ListLaneSlots(unfiltered)`; sells run **synchronously** in the header click (Forever blocks deferred Pickup/Sell).
- **Auto-sell:** `MERCHANT_SHOW` + Settings — greys only; optional Junk lane non-grey (`VendorJunk`).

---

## 5. Sort OOC

```mermaid
flowchart TD
  Sort[/bb sort]
  Sort --> Combat{InCombatLockdown?}
  Combat -->|yes| Defer[message · bail]
  Combat -->|no| Native[C_Container.SortBags]
  Native --> Settle[suppress refresh · one Layout ~0.55s]
```

---

## 6. Drag-teach lanes

Drop an item on a lane header (or an item in another lane) to teach `profile.itemRules`. Drop back on its natural lane to forget. Out of combat only.

---

## 7. Trash lane

Click-only destroy on Forever (no timer delete). See `Docs/README.md` and `/bb trashtest`.