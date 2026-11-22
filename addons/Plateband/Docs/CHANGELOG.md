# Plateband changelog

## 0.1.19 (urgent — UI safe)

- Fallback parent **nameplate UnitFrame only** — never `UIParent` / HUD frames.
- Personal gap: `C_UnitAuras` when `playerHarmful > nativeKids` (no TF personal walk).
- `pcall(PaintMergeMissing)`; TF brute skips global chrome; `UNIT_AURA` debounce.

## 0.1.18

- **Partial native row:** paint personal harmful beside native when Blizzard only shows some of your DoTs (`native=1`, TF=3). Removed `nativeN==0` gate; dedupe stays `NativeKeySet`.
- **TF personal scrape:** `ButtonAuraIcon(..., wantPersonal)` so TargetFrame buttons contribute personal icons missing from the plate.

## 0.1.17

- **Personal DoTs on plate:** when native `DebuffList` shows no aura kids (`native=0`) but TargetFrame has your harmful (Corruption/Agony etc.), paint them on the fallback band — SV had `tf>0` on frame vs `native=0`/`fb=0` on plate.

## 0.1.16

- **Merge layout:** anchor fallback band to native `DebuffListFrame` (not health-bar `TOP`) so adding a personal DoT does not jump the foreign row.
- **Merge collect:** `allowSecretUnknown` only when native debuff row is empty — avoids duplicate personal icons on fallback after your DoT lands on native.

## 0.1.15

- **Default merge on:** `mergeMissing=true` (schema 7 migrates older saves from schema 6 off).
- **`/pb merge off`** — native DebuffList only (same safe path as 0.1.12–0.1.14 default).
- Docs: README, merge-design, loops, playtest brief updated.

## 0.1.14

- Merge beside native on enemy plates (opt-in `mergeMissing=false` default).
- TargetFrame auraPools / `C_UnitAuras` collection; no name `SetPoint`.

## 0.1.12

- Native-only safe default; strips legacy name mutation paths.