# Plateband — aura / layout loops

Version: **0.1.9**

## Merge-missing (enemy plates)

```mermaid
flowchart TD
  ev[NAME_PLATE / TARGET / UNIT_AURA / ticker 0.25s] --> refresh[RefreshAll / UpdateOverlay]
  refresh --> friend{Friend or party plate?}
  friend -->|yes| restore[RestoreNameShift + no paint]
  friend -->|no| merge{mergeMissing?}
  merge -->|no| restore2[RestoreNameShift]
  merge -->|yes| paint[PaintMergeMissing]
  paint --> target{Is target plate?}
  target -->|yes| src[TF auraPools + C_UnitAuras HARMFUL<br/>allowSecretUnknown]
  target -->|no| unitOnly[C_UnitAuras HARMFUL<br/>allowSecretUnknown]
  src --> skip[skipKeys = native + player-owned]
  unitOnly --> skip
  skip --> missing{missing icons?}
  missing -->|no| clear[ClearFallback + RestoreNameShift]
  missing -->|yes| fb[Paint fallback textures]
  fb --> layout[LayoutAuraRowAboveName]
  layout --> beside[Merge LEFT of native rightmost]
  layout --> name[Enemy name BOTTOM of health TOP +2]
```

## Friend / party plates (Pichy)

- **No** `ClearAllPoints` on name or DebuffList.
- Any shift left from ≤0.1.8 is restored on refresh.
- `CountShownAuraKids` requires `Icon` / `icon` / `GetAuraInstance` (no bare Frame false positives).

## Hard rules

- Never park/hide native DebuffList.
- Never SetPoint DebuffList (Forever FORBIDDEN).
- No CLEU core · no plate HP recolor.
