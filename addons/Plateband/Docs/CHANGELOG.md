# Plateband changelog

## 0.2.7 (HUD gate — Retinue TF harvest)

- **Root fix:** replace thin `CollectTargetFrameButtons` / `ButtonAuraIconAny` scrape with **Retinue parity** harvest: `debuffAuraGroup:GetFramesByIndex`, **`GetAuras():Iterate`**, `auraPools`, **`C_UnitAuras.GetAuraSlots`**, numeric **`activeDebuffs` → GetAuraDataByAuraInstanceID**, live-button brute with secret icon support.
- **TF gaps:** mirror full TF harmful row, subtract `paintKeys` (native + personal) — party warlock DoTs paint when TF shows them.
- **Paint:** `SetIconTexture` accepts `{ iconTex }` wrapper for secret/atlas TF buttons.
- **Diagnose:** `tf=` uses `CollectTargetHarmfulRows` count (falls back to legacy counter if 0).

### Playtest (0.2.7)

1. `/reload` → `/pb diagnose` → **`ver=0.2.7`** · **`tf≥2`** when TF shows personal + warlock.
2. Target mob: your DoT + **party warlock DoT** on TF → nameplate row shows **both** (`fb` includes warlock).
3. Solo target → no junk icons; UI intact after `/reload`.

## 0.2.6 (HUD gate — foreign / party DoTs)

- **TF supplement:** `CollectTargetFrameMissing` uses `ButtonAuraIconAny` — dedupe via `skipKeys` only, not ownership skip (party warlock DoTs were dropped when `isFromPlayerOrPlayerPet` mis-tagged).
- **API foreign:** `AuraCountsAsForeignGaps` — party-sourced harmful with `owned==true` still counts as foreign (`AuraLooksForeign`).
- **TF dedupe:** `tfDedupe` = painted keys + API foreign keys; personal already in `paintKeys` prevents duplicate Rake.

### Playtest (0.2.6)

1. `/reload` → `ver=0.2.6`.
2. Target mob with **your Rake + party warlock DoT** on TF → plate row shows **both** (`fb≥2` or native+rake + fb foreign).
3. Solo pull (no foreign) → no duplicate personal icons.

## 0.2.5 (HUD gate — P1 personal gaps)

- **Personal gaps (§5.2 Phase B):** when native `DebuffList` / pools show **0** harmful (Forever omits player DoTs on plate), paint player-owned HARMFUL from `C_UnitAuras` + TF buttons **only if ∉ NativeKeySet** — no `CollectPlayerOwnedKeys` on the same set used for personal eligibility.
- **Foreign path unchanged:** `CollectForeignAuraGaps` + `CollectTargetFrameMissing` with separate `foreignSkip` after personal pass.
- **Diagnose:** `native=` counts pool-enumerated harmful buttons (`CountPlateHarmfulShown`).

### Playtest (0.2.5)

1. `/reload` → `/pb diagnose` → `ver=0.2.5`.
2. Hunter pet DoT / Mark on **Ashenvale Bear** (or any `native=0` target) → plate shows **≥1** icon (`fb≥1`); TF parity for personal.
3. Party warlock DoT on same target → `fb` includes foreign; no duplicate if native already shows spell.
4. `/reload` UI intact (no name/DebuffList SetPoint).

## 0.2.4 (HUD gate — P0 §5)

- **0.1.15 data contract:** `CollectForeignAuraGaps` skips `owned==true` (no personal fallback); `CollectPlayerOwnedKeys` → `skipKeys`; target always `CollectTargetFrameMissing` after API + `nameplateN`.
- **0.2 layout retained:** `NativeAuraMetrics`, pools anchor, `FallbackParent`, beside-native only.
- **Gap sticky** ~0.4s on target when API flickers empty (no CLEU).

## 0.2.3 (HUD gate)

- **Paint path:** TF read-only gap supplement on target (`CollectTargetFrameMissing`) always after API gaps.
- **Gate:** `FallbackParent` (DebuffList/AurasFrame) — not `SafeFallbackParent`-only early exit.
- **Native detect:** nameplate `auraPools` + `CollectPlateDebuffButtons` for `NativeKeySet`, metrics, anchor.
- **Dedupe:** `CollectPlayerOwnedKeys` → `playerOnly` (foreign path only); personal gaps use native keys only.
- **Visibility:** fallback parent `DebuffList`/`AurasFrame`; higher frame level; layout health-bar fallback.

## 0.2.2 (HUD gate)

- **Fix foreign DoTs missing:** `CollectHarmfulGaps` restored 0.1.15 eligibility — skip only `owned==true` in foreign path; `allowSecretUnknown` on target/nameplate; re-added `CollectPlayerOwnedKeys` before paint.
- Removed `GapAuraEligible` `nativeN` gate that dropped secret-ownership party DoTs when any native kid showed.
- `NativeDebuffAnchorList` — layout when `AurasFrame` exists without `DebuffListFrame`.

## 0.2.1 (HUD gate)

- Gap icons **match native debuff metrics** (`NativeAuraMetrics`) — same size/row as Rake-style chrome left of health.
- Layout: `LEFT` of rightmost native + **BOTTOM** align; strata/level from `DebuffListFrame`.

## 0.2.0 (HUD gate — branch zip, not main)

- **Native-row gap:** personal + foreign harmful via `C_UnitAuras` only; dedupe `NativeKeySet`.
- **Safety:** `SafeFallbackParent`, debounce `UNIT_AURA`, `pcall` paint; no TF scrape in paint path; no health-TOP merge anchor.
- **Requires** `DebuffListFrame` on plate to paint gaps.

## 0.1.15

- **Default merge on:** `mergeMissing=true` (schema 7 migrates older saves from schema 6 off).
- **`/pb merge off`** — native DebuffList only (same safe path as 0.1.12–0.1.14 default).
- Docs: README, merge-design, loops, playtest brief updated.

## 0.1.14

- Merge beside native on enemy plates (opt-in `mergeMissing=false` default).
- TargetFrame auraPools / `C_UnitAuras` collection; no name `SetPoint`.

## 0.1.12

- Native-only safe default; strips legacy name mutation paths.