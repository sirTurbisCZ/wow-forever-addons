# Plateband — aura / layout loops

Version: **0.1.12**

## Safe default (native DebuffList only)

```mermaid
flowchart TD
  ev[NAME_PLATE / TARGET / UNIT_AURA / ticker] --> upd[UpdateOverlay]
  upd --> native[EnsureNativeVisible DebuffList alpha=1]
  upd --> clear[ClearFallback + RestoreNameShift]
  upd --> mergeFlag{mergeMissing?}
  mergeFlag -->|false default| stop[Stop — Blizzard layout untouched]
  mergeFlag -->|true opt-in| paint[PaintMergeMissing beside native]
  paint --> anchor[LayoutMergeBesideNative — no name SetPoint]
```

## Hard rules

- Never park/hide native DebuffList.
- Never SetPoint DebuffList (Forever FORBIDDEN).
- Never ClearAllPoints / SetPoint UnitFrame.name (0.1.8–0.1.11 broke plates).
- No CLEU core · no plate HP recolor.
