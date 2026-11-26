# Plateband testing (agent + CI)

## Offline selftest (no client)

```bash
./scripts/plateband-selftest.sh
```

Checks: `luac` on `Plates.lua` + `PlatesPaint.lua`, version sync, **chunk locals ≤195**, `PlatesPaintDeps` wire, invariant grep (friendly filter, `AuraUnitForPlate`, no mob-bleed bind).

## Live SV gate (before asking player)

```bash
./scripts/plateband-sv-gate.sh
```

Green when `SESSION_START ver` matches disk, `PLATES_LOAD ok=1`, no hostile `target=yes tf>0 painted=0`, no `session_zero_paint_streak` (`plateband-sv-anomaly.sh`).

## Live vs flushed version

**Live feed:** `Interface/AddOns/Plateband/Logs/agent-live.log` + `agent-live-export.log` update during play (0.2.56+). **Reload only for addon updates.**

WoW flushes `Plateband.lua` on logout/reload — treat WTF as archive; **watch reads Logs/ first**.

- **Live during play (0.2.78+):** primary head = `Plateband/Logs/agent-live-head.log` (`WriteAgentLiveHead` / `PublishChatTruthHead`; Forever io allowlist). Gate: `felog-live-gate.sh --max-age 2`. Older: `ForeverErrorLog/Logs/live-head.log` / `felog-live-head.log` when allowed; else **`felog_bridge_sv`** → repo `felog-plateband-live.log`; else Plateband SV mirror + `live-head.txt`.
- **Never:** client `agent-live-export` or old PAINT lines for `live_ver`; never treat head lag as `reload_pending`.
- **Live ver order:** `Plateband/Logs/agent-live-head.log` (≤2s on load) → `ForeverErrorLog/Logs/live-head.log` / bridge → `agent-live-export.log` → SV stamps. `interface_ver` = TOC on disk; `live_ver` / `felog_ver` on L1 = runtime **`Config.VERSION`** (same string as chat **`loaded v…`**).
- **Export age (0.3.00+):** prove/gate uses **mtime** for `feed=pb_bridge` + `src=EXPORT_PULSE|CHAT_LOADED`; host may promote **`export-pulse.log`** tail when L1 `w=` stalls.
- **Reload:** expect `CHAT_LOADED ver=… src=reload` in export/logs without logout; `SESSION_REPORT` within ~2s of session-watch.
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
| Weakened Soul | PAINT/CARD `friend=1` | `tf>0 painted=0` (matrix uses **last 3** friend cards + PAINT tail — stale OK blocked) |
| Party WS no paint | PAINT `party=1` `tfRows>0` | `friendly_party_WS_no_paint` (anomaly) |
| DoT overlap | PAINT `native=0` `nativeVis≥1` `painted≥2` | `OVERLAP_nativeVis_multi_paint` + matrix `native_overlap_risk` |
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