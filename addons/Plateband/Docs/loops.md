# Plateband — aura / layout loops

Version: **0.2.54** (combat pending first paint; hostile always heavy TF harvest)

See also: [merge-design.md](merge-design.md) (default merge on 0.1.15+, no name mutation).

## Safe default (native DebuffList only)

```mermaid
flowchart TD
  ev[NAME_PLATE / TARGET / UNIT_AURA] --> upd[UpdateOverlay]
  tick[3.5s gap CD tick] --> upd
  upd --> native[EnsureNativeVisible DebuffList alpha=1]
  upd --> clear[ClearFallback only]
  upd --> mergeFlag{mergeMissing?}
  mergeFlag -->|false /pb merge off| stop[Stop — Blizzard name+DebuffList untouched]
  mergeFlag -->|true opt-in| paint[PaintMergeMissing foreign+TF]
  paint --> layout[LayoutMergeBesideNative + MergeRowIconSize TF lock]
```

## Combat lockdown

```mermaid
flowchart TD
  upd[UpdateOverlay] --> lock{InCombatLockdown?}
  lock -->|yes painted>0| cd[RefreshGapCooldownsOnly]
  lock -->|yes painted=0| q[combatPendingPaint queue]
  lock -->|no| paint[PaintMergeMissing]
  regen[PLAYER_REGEN_ENABLED] --> flush[FlushCombatPendingPaint]
  flush --> full[RefreshAll full]
```

## Hard rules (three-addon refactor)

- Never park/hide native DebuffList.
- Never SetPoint DebuffList (Forever FORBIDDEN).
- **Never ClearAllPoints / SetPoint UnitFrame.name** (preference + 0.1.8–0.1.11 postmortem).
- No CLEU · no plate HP recolor · no bags (BetterBackpack owns bags).
