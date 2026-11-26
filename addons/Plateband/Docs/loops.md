# Plateband — aura / layout loops

Version: **0.3.31** (SV-primary telemetry; reload = TOC only)

## Version / config truth (agent feed)

```mermaid
flowchart TD
  reload["/reload or PLAYER_LOGIN"] --> chat[chat Config.VERSION line]
  reload --> platesStart[ApplyModuleState Plates.Start]
  reload --> sv[BumpChatTruthSV CHAT_LOADED once]
  sv --> syncSv[agentLive runtimeVer export L1 truth]
  syncSv --> once[LoginDiskExportOnce one io attempt]
  once -->|ok| disk[agent-live-export L1 optional]
  once -->|fail| svonly[ioAllowName sv_only]
  paint[UNIT_AURA PAINT events] --> ring[paintTrace + sessionLog SV]
  host[host restamp watch] -->|rejected| x[never PASS prove/gate]
  prove[prove/gate scripts] --> sv
  prove --> chat
  prove -.->|bonus only| disk
```

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
  paint --> layout[LayoutMergeBesideNative + LayoutGapIconsInFallback + MergeRowIconSize]
```

## Hostile target harvest (`useTargetSrc`)

```mermaid
flowchart TD
  paint[PaintMergeMissing] --> gate{ShouldUseTargetAuraSource}
  gate -->|PlateMatchesTarget OR IsTargetPlate| tf[CollectTargetHarmfulRows tgtSrc=1]
  gate -->|other plate while HasTarget| unit[nameplate unit mirror tgtSrc=0]
  tf --> parity[ReconcileTfHarmfulCoverage + ForceFill]
  paint --> friend[nameTop on UnitFrame parent friend Show]
  friend --> offy[MergeRowOffY hostile bar-flush only]
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
