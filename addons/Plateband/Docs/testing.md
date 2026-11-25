# Plateband testing (agent + CI)

## Offline selftest (no client)

```bash
./scripts/plateband-selftest.sh
```

Checks: `luac`, version sync, **chunk locals ≤195**, invariant grep (friendly filter, `AuraUnitForPlate`, no mob-bleed bind).

## Live SV gate (before asking player)

```bash
./scripts/plateband-sv-gate.sh
```

Green when `SESSION_START ver` matches disk, `PLATES_LOAD ok=1`, no hostile `target=yes tf>0 painted=0`.

## Background watch

```bash
./scripts/plateband-sv-watch.sh   # logs to addons/Plateband/Logs/sv-watch.log
```

## In-client

`/pb selftest` → `SELFTEST` lines in SavedVariables.

Playtest matrix (manual, agent reads SV):

| Scenario | SV signal |
|----------|-----------|
| Own DoTs on mob | `tgtSrc=1` `painted>0` |
| Party DoTs on mob | `harv>0` `miss≥2` |
| Friend WS | `friend=1` `painted>0` |
| Party PW:S, mob targeted | no WS spell on mob (`painted` without friend bleed) |
| WS expired | `paint_stale_cleared` / `painted=0` after timer |