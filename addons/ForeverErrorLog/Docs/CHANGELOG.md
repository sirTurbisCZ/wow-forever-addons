# ForeverErrorLog changelog

## Release 0.3.0 — error window, minimap button, taint capture (#32)

- **Minimap button position (#37):** the radius follows the real minimap width (the Forever minimap is larger, the button used to float outside the ring) and the default angles differ per addon so the buttons do not overlap.
- **Window:** `/felog` (no argument) or the minimap button opens a draggable window with a copyable report (header with FElog version, client build, locale and loaded Forever addon versions, then the errors with stacks). Buttons: This session / Previous, page back/forward (20 entries per page), Clear, Close; Esc closes. Built on first open; nothing is created at login except the minimap button. Position is saved.
- **Minimap button:** left-click toggles the window, hover shows the error count and the last 5 errors, drag to move; `/felog minimap` hides or shows it (`minimapHide`).
- **Taint capture:** `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` are recorded as `[blocked] <addon> tried <function>` (repeats counted). `/felog taint on|off` (`captureTaint`, default on).
- Existing subcommands are unchanged; `/felog help` still lists them.

## Release 0.2.1 — survive handler replacement, less work per error

- **Handler re-check:** if another addon calls `seterrorhandler` later, FElog (on `PLAYER_LOGIN` and `PLAYER_ENTERING_WORLD`) forwards to that handler as its original and installs itself again; a re-entrancy guard prevents forwarding loops.
- **Chat:** at most one `[FElog]` line per 2 s, with a "(+N more)" counter for the errors held back.
- **Repeats:** the same message within 1 s is only counted, before `debugstack` is taken. Messages are capped at 1500 characters (was 4000) and stacks at 1500; the archive of a previous session keeps its top 20 entries by count. The visible error list is unchanged.

## Release 0.2.0 — rewrite: working capture, persistent popup setting, dev telemetry opt-in

- **Fix (critical):** every session-log write threw (`AppendLiveStream` was called before it was declared), so the error handler was installed late, the `[FElog]` chat line never appeared and nothing was recorded after the first error. `Core.lua` is rewritten without the dead export/pulse/version code (about 40 % of the old file); the handler is installed on `ADDON_LOADED`.
- **`/felog ui on` persists** across `/reload` and relog (the saved preference is applied; the `scriptErrors` CVar is only written when it differs).
- **`/felog off` hands errors to the default handler** instead of swallowing them; the same happens if capture itself fails.
- **Error list:** reset once per load (previous list archived, last 8 kept, each message/stack trimmed to 1000 characters). FElog no longer wipes other addons' error lists. Repeated errors write to the session log sparsely.
- **Developer telemetry** (`AgentFeed`, `NotifyRuntime`, `ApplyLiveHeadSnapshot`, live head, export strings) runs only after **`/felog dev on`** (default off). All file-writing code is gone: the Forever client has no `io`.
- **SavedVariables schema 5:** `errorWipeTok` removed; session `export` strings are emptied unless dev telemetry is on.
- TOC: `OptionalDeps: !BugGrabber` (stable load order). README rewritten.

## Release 0.1.31 — session-clean error ring

- **`ResetErrorRingOnChatLoaded(load)`** on `BeginSession`, `/reload` ADDON_LOADED, and **`PLAYER_LOGIN`** (idempotent via `errorWipeTok`).
- Prior ring archived to **`errorArchive.sessions`** (max 8); **`PlatebandDB.errors`** cleared too.
- Chat load line: **0 errors this session** (not historical 80-count).
- **`/felog archive [dump]`** — inspect archived rings; **`/felog clear`** archives then wipes.

## Release 0.1.30 — stop FelogExportDriver disk heartbeat

- **`ArmLivePulse`** stops drivers only; no OnUpdate L1 writes when Plateband loaded (login export via **`LoginDiskExportOnce`**).
- Pairs with Plateband **0.3.05** live-telemetry-options architecture.

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