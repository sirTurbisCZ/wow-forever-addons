# ForeverErrorLog changelog

## Release 0.1.3 — agentExport for sv_only watch

- **`sessionLog.agentExport`** — rolling `AGENT[*]` lines in SV (host `felog_bridge_sv` without `session.log`).
- **`ProbeSessionFileAppend`** fix in `AppendSessionFile` (was calling undefined `ProbeSessionFile`).
- **`AgentFeedReady()`** for bridge probes.

## Release 0.1.2 — Plateband agent bridge

- **`ForeverErrorLog.AgentFeed(source, line)`** — append `AGENT[source] …` to live `session.log` (append-only io probe).
- **`/felog session`** — live session tail (not the 80-error historical ring).
- Login text clarifies **errors stored (historical)** vs **session LIVE**.