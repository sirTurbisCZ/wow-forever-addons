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

- **Version truth (0.3.05+):** chat **`loaded v…`** = Interface `Config.VERSION`. Gate/prove: `./scripts/felog-live-gate.sh` / `./scripts/felog-prove-export-l1-toc.sh` — PASS when **SV `chatTruthLine`** matches TOC after **`/reload`** (WTF flush lag OK; no ≤2s SV age requirement).
- **Disk L1:** optional bonus only — one **`LoginDiskExportOnce`** at CHAT_LOADED when io allowlist permits. **Host `watch_sync` / restamp never PASS.**
- **Paint:** PAINT/CARD in SV ring + optional `agent-live.log` append; matrix/anomaly accept flush lag until logout/`/reload`.
- **Reload:** one `/reload` after deploy; expect `src=CHAT_LOADED load=login|reload` in SV `chatTruthLine`.
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
| DoT overlap | PAINT `nativeVis=0` `painted≥2` `miss=painted` + `gapW` | OK = spread gap row; FAIL = `painted≥2 miss=1` |
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