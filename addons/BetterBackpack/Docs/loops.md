# BetterBackpack — smyčky a grafy

**Kód:** `Core.lua`, `Modules/{Slots,Layout,Context,OpenClose,Tidy,Settings,Search,Filter,CustomCategories,Trash,StackMerge,Pins,LayoutModes}.lua`  
**Verze reference:** 0.5.21 (Trash drop: itemID před pickup · header drop bez collapse · Junk≠Trash · 0.5.20 Trash jen click-only destroy · 0.5.19 Trash lane auto-destroy + ghosts + `/bb trashtest` · Shift/Ctrl+LMB = nativní link / dress-up / split · prázdné custom lanes kreslené jako drop target · drag-teach lanes · custom lanes v Settings · Settings v chrome bagu · broom = stejná plate jako gear/X · sticky velikost okna · broom/gear v chrome Close · bank RMB secure type2=item · SearchBoxTemplate search · gear na nativní broom plate · nativní AutoSort reparent · footer hairline · pevná velikost = plný rozbalený bag · dense grid PAD 2 · NumberFontNormalSmall counts · broom/gear jako CombinedBags · footer N/M = font peněz · fill wells default off)  
**Stabilita:** Project `docs/bag-addon-brief.md` + Scenario Maps `docs/scenarios/BetterBackpack/`  
**CS-RMB:** path **B** — `SecureActionButtonTemplate` attrs OOC (never path C harvest).

---

## 1. Open / close (B → BetterBackpack)

```mermaid
flowchart TD
  B[ToggleAllBags only replaced]
  Bar[ToggleBag / ToggleBackpack / ToggleKeyRing → Blizzard]
  B --> Rep[Replace global — skip Blizzard body]
  Rep --> Black[BlackoutAllBlizzard alpha=0 first]
  Black --> Lock{t < toggleLockUntil or debounce?}
  Lock -->|ano| Pulse[Park only]
  Lock -->|ne| Vis{SessionOpen?}
  Vis -->|ne| Open[OpenOurs + Layout.Show]
  Open --> ParkMode{InCombatLockdown?}
  ParkMode -->|ano| AlphaOnly[ParkBlizzardForOverlay — alpha/mouse only]
  ParkMode -->|ne| OffPark[off-screen Park + PulsePark]
  Vis -->|ano| Close[CloseOurs + ClearBagFocus]
  Close --> Keep0[Keep alpha=0 + CloseAllBags<br/>NEVER RestoreBlizzard alpha=1]
  OpenOnly[OpenAllBags / OpenBag — non-Toggle API] --> OpenOrPark[Open if closed else park+focus]
  CloseAPI[CloseBag / CloseAllBags] --> Close
  OnShow[CombinedBags Show/OnShow] --> BO[Blackout first line]
  BO --> Park[ParkBlizzardForOverlay; defer OpenOurs if still closed]
```

**Pravidla**

- Nikdy `SetOverrideBindingClick`.
- Forever: never call `SetFrameStrata` / `SetToplevel` in Lua. **0.5.5+:** `ButtonFrameTemplate` + CombinedBags NineSlice/TopTile/Bg at Baganator Forever offsets (6,-21); **Inset:Hide**; empty `SlotBackground` on slots; footer inside bottom border.
- **0.5.3+:** `Toggle*` are **replaced**, not `hooksecurefunc`. Post-hooks ran after Blizzard `Open*`/`Close*` → open/close thrash that froze on B.
- Anti-flash: `Show`/`OnShow`/`onToggle` → **Blackout alpha=0 first**; CloseOurs never `RestoreBlizzardBags`. OpenOurs fail OOC → `ForceCloseBlizzard`; v combatu jen `ParkBlizzardForOverlay` (not Unblackout).
- CombinedBags stays `IsShown`+parked while ours open — **ne** `:Hide()` mid-session.
- `SuppressReplace`; OnShow nesmí ClearSuppress→OpenOurs.
- **Open (0.5.44):** Jen **`ReplaceToggle("ToggleAllBags", onBagKey)`** (XOR OpenOurs/CloseOurs, handler v `pcall`). ToggleBag/Backpack/KeyRing = Blizzard. Žádné bag-bar OnClick hooks. `/bb` = `OpenClose.Toggle`. Chrome v pcall (0.5.43).
- **Keyring (0.5.33):** `KeyRingFrameNames` (KeyRingFrame / ContainerFrameKeyRing / `ContainerFrame-{KEYRING}`); `InvokeNativeKeyRing` jeden API krok; container OnShow restore pro `IsKeyringBag`; XOR přes `KeyRingNativeOpen`.
- HookScript OnClick only on frames with `HasScript("OnClick")` / Button — never throw on BagsBar chrome kids.
- Frame size (**0.5.8 fixed**): počítá se vždy z **plného bagu — nefiltrovaný, všechny lanes rozbalené** (`CollectBuckets(true)`, collapse ignorován). `cols = clamp(nejširší lane, MIN_COLS=6, Columns())` (Columns = profile 10, dense ≥12). Grid = `cols*37 + (cols-1)*2` (PAD 2, dense); outer = `INSET_X + grid + INSET_X` (INSET_X=14); výška = TOP_CHROME 54 + lanesH + BOT_CHROME 30. HEADER_H 18, SECTION_GAP 4.
- Collapse / Search / Filter / „No matches“ **nikdy nemění velikost okna**; během otevření ho nezmenší ani úbytek itemů (sticky 0.5.15), roste jen při novém lootu. Lanes bez shody se skryjí i s headerem. Uvolněné místo zůstane prázdné (Bg). Opt-in: `profile.fillEmptyWells = true` → prázdné wells `bags-item-slot64` (0.5.9 default **false**, schema 4 vypne i uložené true).
- Header (0.5.7) = Baganator Forever: atlas `bag-arrow` 14×14 (rozbaleno rotace π/2, sbaleno −π; fallback UI-Minus/PlusButton), label `GameFontNormalMed2`, počet `(n)` `GameFontDisableSmall`, hover = bílý label.
- Slot art (0.5.7) = ContainerFrameItemButton: Normal/Pushed/Highlight + IconBorder čtené z hidden `ItemButtonTemplate` (fallback UI-Quickslot2 64×64 CENTER 0,-1 / Quickslot-Depress / ButtonHilight-Square ADD / WhiteIconFrame), ikona full texcoord v `BORDER`, well `bags-item-slot64`. Count (0.5.8) `NumberFontNormalSmall` bílý BOTTOMRIGHT −3,2 (i StackMerge — žádný cyan).
- Kategorie jsou **default rozbalené**; klik na header = per-profile toggle. Schema 3 (0.5.6) jednorázově maže `collapsed` zaseknutý z 0.5.4/0.5.5 (prázdné lanes → hráč zavřel všechny headery).
- Lua 5.1: helper volaný z `DoLayout` / `SyncVisual` / `Acquire` musí být deklarovaný **nad** volajícím (nebo forward `local X` + `X = function`). 0.5.4/0.5.5 volaly `ApplyCombinedBagsChrome` / `EnsureSlotBackground` jako nil global → DoLayout abort na prvním itemu (žádné ikony, frame se nezmenšil).
- Title chrome (0.5.27): broom | gear | X — live Close size každý layout; broom = `StyleCloseTwin` + gold autosort glyph (crop 0.28–0.72, 62% jako gear).
- Search (0.5.11): EditBox z `SearchBoxTemplate` (= vzhled `BagItemSearchBox`: common-search-border, lupa, clear X, "Search"). Nikdy `BagSearchBoxTemplate` (SetItemSearch → druhý CombinedBags). Query = `profile.searchQuery`, OnTextChanged hook (i clear X), Esc vymaže. Fallback plochý box, když template chybí.
- Velikost okna (0.5.15): grid = nejširší **nefiltrovaná** lane, výška = všechny lane rozbalené + nefiltrované. Navíc **sticky** během otevření (`stickyCols`, `stickyH`): okno jen roste (nový loot), collapse / search / spotřeba itemů / pins ho nikdy nezmenší. `Layout.Hide` (zavření) reset → další otevření se znovu napasuje na plný layout.
- Footer N/M (0.5.9): hairline 1px (bílá α0.14, PixelUtil) nad footerem (0.5.10); font = font peněz (`<money>CopperButton:GetFontString()`), baseline zarovnaný na text peněz; barva dle zaplnění. Počítá player bags `0..NUM_BAG_SLOTS` + **reagent bag** (Materials lane). Never keyring invent (102=70+32).
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
  Merge --> Filt{Search / Filter active?}
  Filt -->|ano| Full[sizing = CollectBuckets unfiltered]
  Filt -->|ne| Same[sizing = rendered lists]
  Full --> Hug[cols + lanesH from sizing · every lane EXPANDED · clamp widest lane, 6, Columns · cols ≥ stickyCols]
  Same --> Hug
  Hug --> Col{lane has matches?}
  Col -->|ne| HideH[hide header]
  Col -->|ano| Coll{collapsed?}
  Coll -->|ano| Hdr[header only · bag-arrow −π]
  Coll -->|ne default| Place[Slots.Acquire + Place on main · SlotBackground well · ApplyDisplayCount · Trash lane: red veil + ghosts]
  Hdr --> Pins
  HideH --> Pins
  Place --> Pins[Pins.Layout ghosts for missing · same cols]
  Pins --> Size[main:SetSize: INSET+grid+INSET × max(TOP+lanesH+BOT, stickyH) · store sticky]
  Close2[Layout.Hide on close] -.->|reset stickyCols/H| Hug
  Size --> Wells{fillEmptyWells? default off}
  Wells -->|on| WellsOn[empty bags-item-slot64 in freed space]
  WellsOn --> Chrome
  Wells -->|off| Chrome[ApplyCombinedBagsChrome NineSlice/Bg/TopTile · EnsureTitleChrome · Search.EnsureChrome]
  Chrome --> Sort[EnsureTitleChrome: broom + gear in Close chrome · X (Close size, gap 2) · SearchBoxTemplate]
  Sort --> Foot[footer hairline · UpdateFreeSpace N/M in money font + money]
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
  Show[MERCHANT/MAIL SHOW] --> Clear[Clear type2 use attrs]
  Clear --> RMB[RMB Pickup + Sell / ClickSendMail]
  BankShow[BANKFRAME_OPENED] --> Keep[Keep type2=item]
  Keep --> Deposit[Secure UseContainerItem deposits]
  Close[CLOSED] --> Restore[ForceRestore type2=item]
```

- **Bank:** never clear `type2` / never Pickup+`PutItemInBag` from OnClick — secure SAB `type2=item` = native CombinedBags deposit (OOC). Detect `BankFrame` / `BankPanel`.
- **Merchant/mail:** `NeedsInsecureSpecialRmb` → clear type2 + Pickup path.
- Mail: `MailFrame:IsVisible()` — ne stuck SendMailFrame alone.

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

---

## 6. Lanes: drag-teach + custom lanes (0.5.17)

```mermaid
flowchart TD
  Click[LMB up on bag item OOC] --> Mod{Shift / Ctrl / Alt and cursor empty?}
  Mod -->|ano| Native[chat box open → ChatEdit_InsertLink · else HandleModifiedItemClick · Shift → StackSplitFrame]
  Native -->|handled| Done[no pickup]
  Native -->|not handled| P
  Mod -->|ne| P
  Pick[drag item in bag OOC] --> P[Slots pickup: PickupContainerItem]
  P --> Src[dragSrc = bag, slot, lane, itemID · SetDropHints on]
  Src --> Where{drop target?}
  Where -->|Trash header / item / ghost| TR[Trash.HandleDrop — see §7]
  Where -->|item in another lane| T[Layout.DropOnLane lane]
  Where -->|lane header click / OnReceiveDrag| T
  Where -->|custom lane row in Settings| T
  Where -->|Settings Custom → New lane| N[CustomCategories.PromptNew]
  N --> Create[CC.CreateLane name + AssignItem itemID]
  Where -->|item in same lane| Swap[normal PickupContainerItem swap]
  Where -->|elsewhere / cursor cleared| Clear[CURSOR_CHANGED/UPDATE → dragSrc nil · hints off]
  T --> End[ClearCursor · item stays in slot · hints off]
  End --> Nat{lane == NaturalLane?}
  Nat -->|ano| Forget[itemRules id = nil]
  Nat -->|ne| Rule[itemRules id = lane]
  Forget --> Re[Relayout + Settings.Refresh]
  Rule --> Re
  Create --> Re
```

- `ClassifyBagSlot` pořadí: `CC.Resolve` (itemRules → custom itemIDs) → `itemRules` → `ClassifyNatural` (třída itemu). `Layout.NaturalLane` = jen `ClassifyNatural`, vypnutý built-in → `other`.
- Pravidlo na vypnutý built-in → položka v Other (CategoryEnabled). Smazání custom lane maže i jeho pravidla.
- **Custom lane se kreslí vždy** (0.5.18), i prázdná: jen header `(0)`, počítá se do pevné velikosti okna (`HEADER_H + HEADER_PAD + SECTION_GAP`). Výjimka: při search / filter se lanes bez shody skryjí jako ostatní. Řádky custom lanes v Settings jsou také drop target (`OnReceiveDrag` / `OnMouseUp` → `DropOnLane`, zlatý `dropHl` přes `Settings.SetDropHints`).
- Každé tlačítko v lane nese `btn._bbLane` (DoLayout). Header má `dropHl` (zlatý pruh) během tažení; `+ Lane` `LockHighlight`.
- V boji pickup z bagu nefunguje (`pickup` bail) → drag-teach jen mimo boj; nic secure se nemění.
- Settings: `Layout.CreateChromedPanel` (ButtonFrameTemplate + CombinedBags NineSlice jako bag). Sekce Lanes (z `CATEGORY_ORDER`, ne z `ExtendOrder` — skrytý lane musí zůstat v seznamu, jinak nejde znovu zapnout), Custom lanes (Rename / Delete / New lane přes StaticPopup), Learned items (počet + Forget all), Trash (stav loot režimu, confirm checkbox, řádek na item + Keep), Features. Žádné `SetFrameStrata`.
- **Modified LMB (0.5.19):** `OnMouseUp` LMB s Shift/Ctrl/Alt a prázdným kurzorem nejdřív zkusí nativní cestu (otevřený chat / whisper → `ChatEdit_InsertLink` / `ChatFrameUtil.InsertLink`; jinak `HandleModifiedItemClick` = link, dress-up; Shift bez chatu → `StackSplitFrame`). Pickup jen když nic z toho neproběhlo. S itemem na kurzoru = normální drop / swap.

---

## 7. Trash lane — auto-destroy (0.5.19)

Design: Project store `docs/auto-destroy-lane.md` (v2). Lane `trash` je built-in, **default vypnutý** (`categories.trash = false`, `CategoryEnabled` chce `== true`); vypnutý = pravidla spí, itemy v Other, nic se neničí. Pořadí: … custom lanes · Trash · Other.

```mermaid
flowchart TD
  Drop[item z bagu puštěn na Trash header / item / ghost] --> DOL[Layout.DropOnLane trash · dragSrc.itemID z slotu před pickup · header OnMouseUp/OnReceiveDrag · bez collapse když kurzor drží item]
  DOL --> Cmb{InCombatLockdown?}
  Cmb -->|ano| No1[ClearCursor · zpráva]
  Cmb -->|ne| Ref{Trash.Refuse: quest · green+ · locked · hearthstone · neznámá kvalita}
  Ref -->|ano| No2[ClearCursor · item zpět · důvod do chatu]
  Ref -->|ne| Conf{confirm zapnutý a item ještě nepotvrzený?}
  Conf -->|ano| Pop[ClearCursor · StaticPopup Destroy link xN]
  Pop -->|Accept = klik| Re[confirmed id · najdi stack · Pickup v témže kliku]
  Re --> Del
  Conf -->|ne| Del[DeleteCursorItem · ověř prázdný kurzor]
  Del --> Teach[itemRules id = trash · destroyed id += N · log 20]
  Teach --> Ghost[Relayout: šedý ghost id v Trash lane · 0 slotů · xN]

  Loot[BAG_UPDATE_DELAYED / REGEN_ENABLED / změna pravidel] --> Scan[Recount: stacky s pravidlem trash, prošlé Refuse · NIKDY delete]
  Scan --> Wait[stack v Trash lane s červeným veilem]
  Wait --> Next[další klik v bagu: slot OnMouseDown · header · ghost → FlushOnClick]
  Next --> Flush[Pickup + DeleteCursorItem pro každý · nikdy když kurzor drží jiný item]

  GhostDrag[OnDragStart ghost] --> Fake[fake drag: plovoucí ikona sleduje GetCursorPosition · drop hints · NIC na kurzoru]
  Fake --> Stop[OnDragStop: Layout.LaneUnderMouse · + Lane · header · item · Settings řádek]
  Stop --> Move[Trash.MoveOut: natural lane = forget · jiná lane = Teach · + Lane = nová lane]
  GhostClick[klik na ghost] --> Menu[menu Keep · Keep in lane · Keep in a new lane · Cancel]
  Menu --> Move
```

- **Forever = click-only (0.5.20, natrvalo).** Ondřejův trashtest 0.5.19: `click=OK · timer=blocked · event=blocked` → `DeleteCursorItem` mimo hardware event = „Interface action failed“. Timer / event delete cesty jsou z kódu pryč; eventy jen přepočítají čekající stacky. Delete běží výhradně v: drop na Trash, Accept popupu, další klik v bagu (slot / header / ghost), `/bb trashtest go` (Enter).
- `/bb trashtest` (bez argumentu = co by zničil + poslední výsledek; `go` = 1 šedý stack z klávesy Enter; `<itemID>` = bílý/šedý item) = jen kontrola, že click destroy pořád jde. Uloženo v `BetterBackpackDB.trashTest`. `click = false` → Trash na klientu nejde.
- V boji nikdy (`PLAYER_REGEN_ENABLED` → přepočet). Jedno pravidlo = celý itemID: další stacky téhož itemu čekají červeně do dalšího kliku.
- Ghost: `Button` mimo SAB, `RegisterForDrag`, ikona desaturovaná α0.45 + pass X; Shift-klik s otevřeným chatem = link itemu. Ghosty se počítají do pevné velikosti okna jako sloty (sizing lists); při search / filter se nekreslí.
- Destroy proběhne jen uvnitř kliku / klávesy hráče; žádné `SetFrameStrata`, menu + plovoucí ikona jen přes frame level.

