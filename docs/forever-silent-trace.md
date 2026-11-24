# Forever addons — silent trace contract

**Chat:** real errors + intentional player feedback only.  
**Diagnostics:** per-addon session SavedVariables (wiped each login). Agent reads on Mac — no screenshots.

| Addon | Version gate | SV file | Trace keys | Slash optional |
|-------|--------------|---------|------------|----------------|
| **Plateband** | 0.2.10+ (`cursor/pb-native-dot-row-9374`) | `Plateband.lua` | `PAINT`, `paintTrace`, `lastPaintTrace` | `/pb diagnose`, `/pb dump` |
| **BetterBackpack** | 1.2.7+ | `BetterBackpack.lua` | `ACTION`, `actionTrace`, `lastActionTrace` | `/bb dump` |
| **ForeverErrorLog** | 0.1.2+ | `ForeverErrorLog.lua` | `ERROR`, `sessionLog` (errors ring kept) | `/felog list`, `/felog dump` |

Path prefix: `World of Warcraft/_forever_/WTF/Account/<Account>/SavedVariables/`

## Agent scripts (repo)

```bash
cd git/wow.addons
./scripts/watch-forever-traces.sh          # tail + alerts
./scripts/watch-forever-traces.sh watch 8  # poll
./scripts/watch-plateband-sv.sh            # PB-only tail
```

## Alert heuristics (`watch-forever-traces.sh`)

- **Plateband:** `PAINT` with `tf>0` or `harv>0` and `painted=0`
- **BetterBackpack:** `ACTION` with `MISMATCH=1` or `sold=0` with `queued>0`
- **FElog:** new `ERROR` lines in session export

Flush SV with one `/reload` after repro (Forever does not write mid-session reliably).