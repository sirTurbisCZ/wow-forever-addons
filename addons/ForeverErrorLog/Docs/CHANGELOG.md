# ForeverErrorLog changelog

## Release 0.1.2 — Plateband agent bridge

- **`ForeverErrorLog.AgentFeed(source, line)`** — append `AGENT[source] …` to live `session.log` (append-only io probe).
- **`/felog session`** — live session tail (not the 80-error historical ring).
- Login text clarifies **errors stored (historical)** vs **session LIVE**.