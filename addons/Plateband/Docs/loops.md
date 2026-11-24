# Plateband — aura / layout loops

Version: **0.2.22** (GapAuraLive sticky purge + target API harvest)

See also: [merge-design.md](merge-design.md) (default merge on 0.1.15+, no name mutation).

## Safe default (native DebuffList only)

```mermaid
flowchart TD
  ev[NAME_PLATE / TARGET / UNIT_AURA / ticker] --> upd[UpdateOverlay]
  upd --> native[EnsureNativeVisible DebuffList alpha=1]
  upd --> clear[ClearFallback only]
  upd --> mergeFlag{mergeMissing?}
  mergeFlag -->|false /pb merge off| stop[Stop — Blizzard name+DebuffList untouched]
  mergeFlag -->|true opt-in| paint[PaintMergeMissing foreign+TF]
  paint --> layout[LayoutMergeBesideNative + MergeRowIconSize TF lock]
```

## Hard rules (three-addon refactor)

- Never park/hide native DebuffList.
- Never SetPoint DebuffList (Forever FORBIDDEN).
- **Never ClearAllPoints / SetPoint UnitFrame.name** (preference + 0.1.8–0.1.11 postmortem).
- No CLEU · no plate HP recolor · no bags (BetterBackpack owns bags).
