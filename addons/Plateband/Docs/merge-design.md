# Plateband — safe merge design (no name mutation)

**Status:** v0.2.7 P0+P1 (`pb-old-vs-peers-dots.md` §5) · **default ON** (`mergeMissing=true`, schema 7+)  
**Baseline:** `plateband-v0.1.15` data contract + **0.2** beside-native layout · HUD gate before main merge

## Product rule (0.2.7)

**One native-looking harmful row** on enemy **target** nameplates (e.g. Rake + timer left of health): Blizzard `DebuffList` / `auraPools` kids first; Plateband paints **personal gaps** (player DoTs missing from native) then **foreign gaps**. Dedupe via **`GapAuraKey`** (instance → spell → tex); `EnsureTargetHarmfulParity` tops up TF/API vs native plate. **`NativeKeySet`** for on-plate only; `CollectPlayerOwnedKeys` applies to **foreign** skip set only. Gaps use **fixed** merge size (`iconSize` / `/pb size`, health-bar cap) — independent of native personal vs buff chrome. `paint_hold` still **refreshes cooldowns** on sticky foreign slots. Appended **RIGHT of rightmost native** with **BOTTOM** band align. Gap icons use **native debuff button chrome** (`CreateGapAuraButton`); `ApplyGapAuraVisual` sets icon + stack + **`Cooldown:SetCooldown`** from aura API/TF harvest. **No** AuraContainer overlay row.

## Hard rules (non-negotiable)

| Rule | Why |
|------|-----|
| **Never** `ClearAllPoints` / `SetPoint` on `UnitFrame.name` | 0.1.8–0.1.11 broke Forever plates |
| **Never** `ClearAllPoints` / `SetPoint` / `Hide` / `SetAlpha(0)` on DebuffList | Forever FORBIDDEN |
| **Never** parent plate band to `UIParent` / HUD | UI vanish incident |
| **Never** mutate TargetFrame / TF buttons (read-only scrape OK) | Incident + taint |
| **No CLEU** | Forever policy |

## Data flow (`mergeMissing=true`)

```mermaid
flowchart TD
  tick[UpdateOverlay] --> gate{mergeMissing?}
  gate -->|false| nativeOnly[EnsureNativeVisible + clear chrome]
  gate -->|true| kind{Target / party / other enemy?}
  kind -->|target heavy| tfPath[TF harvest + Reconcile when native lt TF]
  kind -->|target lean| leanT[Foreign API gaps only]
  kind -->|party| unitParity[Unit API + EnsureUnitHarmfulParity]
  kind -->|other enemy| leanE[Foreign API gaps only]
  tfPath --> paint[Fallback beside native]
  leanT --> paint
  unitParity --> paint
  leanE --> paint
```

## Layout

1. Native DebuffList untouched.
2. Fallback parents to `DebuffList` / `AurasFrame` (`FallbackParent`), not `UIParent`.
3. Anchor: rightmost native aura from **pools** or `DebuffListFrame`; health-bar fallback only if no kid.
4. `pcall` on paint + layout; debounce `UNIT_AURA` on target; **gap sticky 3s** on flicker (no preemptive `ClearFallback` in `UpdateOverlay`).

## Sources

| Plate | Source |
|-------|--------|
| Target enemy | `NativeKeySet` → `C_UnitAuras` foreign (`owned~=true`, skip native keys) → **`CollectTargetFrameMissing`** → `nameplateN` token |
| Other enemy | `C_UnitAuras` on `nameplateN` only (no TF) |
| Party / raid / player NP | **`mergeFriendPlates`** (default on): same harmful gap merge via unit `C_UnitAuras` + `EnsureUnitHarmfulParity` — **not** ambient friendly stranger plates (0.2.30) |

`CollectPlayerOwnedKeys` → `skipKeys` (secret dedupe only; **not** personal fallback paint).

## `/pb merge off`

Native only; Plateband chrome cleared.