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

Green when `SESSION_START ver` matches disk, `PLATES_LOAD ok=1`, no hostile `target=yes tf>0 painted=0`, no `session_zero_paint_streak` (`plateband-sv-anomaly.sh`).

## Live vs flushed version

WoW only flushes `Plateband.lua` on logout/reload — **do not treat `SESSION_START` in SV as live truth** while you play.

- **`plateband-sv-lib.sh`:** `live_ver` = `PLATEBAND_LIVE_VER` or runtime `Interface/AddOns/Plateband/Config.lua`, not stale flush.
- **`agent-live.log`:** CARD/PAINT append each event (when client `io` works).
- Gate/matrix **do not fail** on flush lag alone; paint rules still run on `agent-live.log` + SV.

```bash
PLATEBAND_LIVE_VER=0.2.51 ./scripts/plateband-sv-gate.sh
./scripts/plateband-sv-session-report.sh   # SESSION_REPORT → coordinator on new reload
```

- **`plateband-sv-session-watch.sh`:** polls every **2s**, writes `session-report-latest.txt` on new `t|flushed` key (spawned by main watch).
- Agent **timer 5s** + every turn: `session-report` exit 0 → **immediate** `SendToAgent` parent (not 15s paint watch).

## Background watch (CARD + PAINT + party)

`plateband-sv-watch.sh` every 15s: **gate → tail PAINT/CARD → anomaly → matrix** → `Logs/sv-watch.log`.

**`plateband-sv-anomaly.sh`** watches reactions to **your + party** actions:

| Signal | Source | Anomaly |
|--------|--------|---------|
| Own DoT (HARMFUL) | CARD `painted` / PAINT `painted` `tgtSrc=1` | `tf>0 painted=0` |
| Foreign/party DoT | CARD `harv` `miss` / PAINT `harv` `miss` `tfRows` | `harv=0` when `tf≥2` |
| Weakened Soul | PAINT/CARD `friend=1` | `tf>0 painted=0` |
| Helpful bleed (PW:S on mob) | CARD `punit` vs plate, `friend=0` | unit mismatch + paint |
| Sticky / expire | PAINT `paint_hold`, `paint_stale_cleared` | logged; stale = OK |
| FElog paint nil | ForeverErrorLog | only if SESSION = disk version |

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