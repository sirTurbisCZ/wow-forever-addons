# Plateband changelog

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