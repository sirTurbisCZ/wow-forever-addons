# Plateband changelog

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