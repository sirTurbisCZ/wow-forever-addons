# ForeverErrorLog changelog

## Release 0.1.12 — ship with Plateband 0.2.83 export pulse

- Version bump only; 2s **`EXPORT_PULSE`** disk + `t=` refresh lives in **`Plateband.SessionLog.PulseExportTruth`**.

## Release 0.1.7 — watch reads agent-live-head.log

- Forever blocks `*live-head*` filenames; chat truth now **`Plateband/Logs/agent-live-head.log`** (same io allowlist as `agent-live-export`).

## Release 0.1.6 — chat-truth head on CHAT_LOADED

- No early head write before Plateband loads; **`PublishChatTruthHead`** on reload/login + 2s pulse (both TOC versions).
- **`ApplyLiveHeadSnapshot`**; pulse defers to Plateband publish when loaded.

## Release 0.1.5 — Plateband disk bridge + chat version

- **Forever io:** direct `ForeverErrorLog/Logs/*` writes stay `sv_only`; **`Plateband.SessionLog.MirrorFelogLogs`** writes `live-head` / export / stream from Plateband context (`feed=pb_bridge`).
- **Chat:** `loaded v0.1.5` on login; **`reloaded v… · live feed`** on `/reload` (was version-less).
- **Watch:** `felog_pick_live_head_file` — `ForeverErrorLog/Logs/live-head.log` or `Plateband/Logs/felog-live-head.log`.

## Release 0.1.4 — live-head + sub-2s agent stream

- **`Logs/live-head.log`** — sync on SESSION_START, CHAT_LOADED, `AgentFeed`, 2s pulse (mtime stays fresh in play).
- **`Logs/agent-live-export.log`** + **`live-stream.log`** — append/mirror on every agent line (no WTF flush).
- **`ForeverErrorLog.NotifyRuntime`** — Plateband `CHAT_LOADED` stamps plateband ver immediately.
- **Watch:** `scripts/felog-live-gate.sh` (`age_sec` ≤5) + `felog-sv-lib.sh`; Plateband `pb_client_ver` reads FElog head first.

## Release 0.1.3 — agentExport for sv_only watch

- **`sessionLog.agentExport`** — rolling `AGENT[*]` lines in SV (host `felog_bridge_sv` without `session.log`).
- **`ProbeSessionFileAppend`** fix in `AppendSessionFile` (was calling undefined `ProbeSessionFile`).
- **`AgentFeedReady()`** for bridge probes.

## Release 0.1.2 — Plateband agent bridge

- **`ForeverErrorLog.AgentFeed(source, line)`** — append `AGENT[source] …` to live `session.log` (append-only io probe).
- **`/felog session`** — live session tail (not the 80-error historical ring).
- Login text clarifies **errors stored (historical)** vs **session LIVE**.