# ForeverErrorLog changelog

## Release 0.1.29 — pairs with Plateband 0.3.00 export defer

- FElog **`PulseLiveHeadFile`** still delegates; host pulse promote unchanged.

## Release 0.1.28 — FElog pulse delegates `ExportDiskPulse` only

## Release 0.1.27 — relies on Plateband `DoExportDiskPulse` idle tick

## Release 0.1.26 — export pulse from events

- Felog driver calls **`PulseExportDiskTick(true)`**.

## Release 0.1.25 — sustained export via Plateband OnUpdate driver

- FElog OnUpdate still nudges **`PulseExportDiskTick`**; primary **`PlatebandExportDriver`** frame.

## Release 0.1.24 — FElog driver → `PulseExportDiskTick`

- Ongoing export uses Plateband deferred 2s tick (fresh L1 mtime).

## Release 0.1.23 — FlushChatLoadedExport on reload/login

- **`StampFelogReload` / `PLAYER_LOGIN`** call Plateband **`FlushChatLoadedExport`** (not raw export line).

## Release 0.1.23 — HOTFIX: delegate export to Plateband throttle

- One **2s** driver; no WorldFrame/io ticker stack; no write retry loop.

## Release 0.1.22 — export L1 = chat `Config.VERSION`

- **`FelogChatLoadedVersions`** — matches **`loaded v%s`** / **`reloaded v%s`**; dropped stamp/toc/metadata **`FelogBestVersion`** for L1.

## Release 0.1.21 — disk L1 = Plateband chatTruthLine

- **`PulseLiveHeadFile`** prefers **`PlatebandDB.chatTruthLine`**; **`WritePlatebandExportL1`** + deferred **`C_Timer`** io.

## Release 0.1.20 — FelogExportDriver + BestVersion chat FE

- **`FelogExportDriver`** 1.95s; **`FelogBestVersion`** — chat `Config.VERSION` beats stale stamp.

## Release 0.1.19 — FelogResolveExportVersions (stamp/toc, no lastKnown)

- Matches Plateband **`ResolveExportVersions`**; stamp-first for **0.2.90 / 0.1.19** interface truth.

## Release 0.1.18 — fix export L1 live_ver=?

- **`FelogLiveInterfaceVersions`** standalone (no Plateband delegate); **`Config.VERSION`** + metadata; never **`?`**.

## Release 0.1.17 — FElog chat TOC + LoadAddOn Plateband for pb ver

- **`FelogLiveInterfaceVersions`** — **`Config.VERSION`** (chat) first; **`C_AddOns.LoadAddOn("Plateband")`** so pb matches deployed toc without separate `/reload`; stamp + immediate export on FElog reload.

## Release 0.1.16 — FElog TOC file read + metadata each WritePlatebandExportLine

- Same **`FelogLiveInterfaceVersions`** as Plateband (disk .toc first, then **`GetAddOnMetadata`**); delegates to **`SessionLog.LiveInterfaceVersions`** when loaded.

## Release 0.1.15 — FElog always writes export L1 from TOC each tick

- **`PulseLiveHeadFile`** always **`WritePlatebandExportLine`** (GetAddOnMetadata) then Plateband **`PulseExportDisk`**; burst on reload; WorldFrame OnUpdate.

## Release 0.1.14 — direct Plateband export write + GetTime OnUpdate

- **`WritePlatebandExportLine`** when **`PulseExportDisk`** fails; **`FelogPlatebandExportLine`** from TOC metadata.
- OnUpdate uses **`GetTime`** on **UIParent** child frame.

## Release 0.1.13 — live pulse OnUpdate + PulseExportTruth bridge

- **`ArmLivePulse`** OnUpdate 2s fallback; re-arm on `PLAYER_ENTERING_WORLD`; **`PulseLiveHeadFile`** → **`Plateband.SessionLog.PulseExportTruth`** when loaded.

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