# ForeverErrorLog changelog

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