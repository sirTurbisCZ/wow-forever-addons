# Plateband changelog

## Release 0.2.82 — SV chatTruth gate + disk write retry

- **`SyncLiveExportFile`** — export write every pulse (no sv_only skip); **`felog-live-gate`** reads **`PlatebandDB.chatTruthLine`** (rejects `host_toc_pulse` as PASS).

## Release 0.2.80 — SyncLiveExportFile (line1 live_ver + 2s pulse)

- **`SyncLiveExportFile` / `BuildChatTruthLine`** — every publish/flush: line 1 `live_ver=` in export + SV `chatTruthLine`; **`EnsureExportTruthTicker`** 2s refresh.
- **Watch:** `pb_mirror_sv_export` + `pb_write_wow_export_with_chat_truth` prepend `chatTruthLine` when io=sv_only.

## Release 0.2.79 — exact io allowlist: agent-live-export.log

- **`DiscoverIoAllowlist`** — only `agent-live-export.log` is writable on Forever; chat truth = **line 1** of export; host `felog_materialize_agent_live_head_from_export` for gate path.

## Release 0.2.78 — agent-live-head.log (Forever io allowlist)

- **`WriteAgentLiveHead`** — `PublishChatTruthHead` writes `Logs/agent-live-head.log` first; export prepends `chatTruthLine`. Blocked paths: `live-head.log`, `felog-live-head.log`.

## Release 0.2.77 — PublishChatTruthHead (reload ≤2s)

- **`PublishChatTruthHead`** on SESSION_START, CHAT_LOADED, AGENT_LIVE (2s) — unified `live_ver` + `felog_ver` from loaded Config (matches chat).

## Release 0.2.76 — FElog disk bridge (Forever io sandbox)

- **`SessionLog.MirrorFelogLogs`** — writes `ForeverErrorLog/Logs/live-head.log`, export, stream, and `Plateband/Logs/felog-live-head.log` when FElog’s own `io.open` is `sv_only`.

## Release 0.2.75 — live-head feed + reload stamp ≤2s

- **Reload:** `RecordChatLoaded("reload")` only when `IsLoggedIn()` on `ADDON_LOADED`; cold login stamps once on `PLAYER_LOGIN` (no double reload+login).
- **Feed:** `Logs/live-head.log` written sync on `SESSION_START` / `CHAT_LOADED` / `AGENT_LIVE`; watch prefers it over stale SV `agentLive`.
- **Watch:** `pb_client_ver` = `live-head.log` → export → SV; export adds `interface_ver` + `session_load`.

## Release 0.2.74 — hostile skip keys + WS/full harmful parity

- **Root (0.2.72 screenshot):** hostile `NativeShownKeySet` always API-augmented skip keys on `nativeVis=0` → player DoTs treated as native → `miss`/`painted` in PAINT but icons missing / partial (Tarantula, Condor).
- **Fix:** API augment **only when visible harmful buttons exist** (friend + hostile).
- **Paint:** `EnsureUnitHarmfulParity` + `CollectUnitHarmfulMirror` on all nameplate unit paths; gap parent = `DebuffList` row first; unclip parent; layout fallback if unanchored.

## Release 0.2.73 — live feed + reload runtime truth

- **Runtime:** `CHAT_LOADED` + `RUNTIME_VER` on **ADDON_LOADED** (`src=reload`), not only `PLAYER_LOGIN` — fixes stale `0.2.71` after `/reload` on deployed `0.2.72+`.
- **Session:** `BeginSession` writes `runtimeVer` + `liveHead` + `runtime-ver.log` with `SESSION_START`.
- **Watch:** `pb_client_ver` prefers fresh `Logs/agent-live-export.log` / `runtime-ver.log`; SV unified picks **newest stamp** across `runtimeVer`, `CHAT_LOADED`, `RUNTIME_VER`, `SESSION_START`, `liveHead`, `agentLive` (no stale `liveHead_chat` lock-in).

## Release 0.2.72 — paint deps wire + friend gap layout

- **Root (live 0.2.71):** `PlatesPaint.lua` called `LayoutMergeBesideNative`, `InitAuraButton`, `EnsureUnitHarmfulParity`, `GapAuraLive`, `RefreshHeldGapFallback` as globals (nil in split chunk) — PAINT logged `painted>0` but gap row never positioned / friend parity skipped → no visible DoT/WS on plates.
- **Fix:** all paint-side calls via `Plateband.PlatesPaintDeps` (`D.*`); expose `GapAuraLive` + `RefreshHeldGapFallback` on deps table.
- **Layout:** friend/party merge anchors to `AurasFrame` debuff row (not health TOP) — fixes `painted=2 nativeVis=0` overlap with cast/chrome on party plates.
- **Layout:** horizontal offset from **visible** native buttons only on friends (no API inflate in spacing).
- **Matrix:** `multi_icon_overlap` hostile-only FAIL; friend `nativeVis=0` multi-gap = expected merge band.

## Release 0.2.71 — friend WS paint + watch truth

- **Friend:** stop inflating `nativeN` via unit API; `NativeShownKeySet` skips API augment when harmful buttons visible — fixes tf>0 painted=0 (phantom native skip).
- **Friend target:** heavy TF harvest when `tfHarm > nativeVis`; lean path runs `EnsureUnitHarmfulParity`; fix `D.ForceFillTargetFrameGaps` in PlatesPaint.
- **Matrix:** `tgt_bind` counts friend `PAINT tgtSrc=1`.
- **Watch:** `liveHead_chat` wins; newer stamped `CHAT_LOADED` can supersede; no felog/agent override; `reload_pending` = live vs Interface TOC only (`chat_primary`).

## Release 0.2.70 — PaintMergeMissing chunk split (60 upvalues)

- **Root (live 0.2.69):** `PaintMergeMissing` exceeded Lua **60 upvalues** → compile/paint failure; `PLATES_LOAD` missing from export; auras invisible despite CHAT `0.2.69`.
- **Fix:** `Modules/PlatesPaint.lua` owns paint merge; `Plates.lua` injects `Plateband.PlatesPaintDeps` + thin delegate.
- **Paint:** `AurasFrame` parent, `PlateMatchesTarget` / party GUID resolve (from 0.2.69 WIP).
- **Watch:** gate/anomaly flag missing `PLATES_LOAD`, `paint=false`, FElog `more than 60 upvalues`.

## Release 0.2.69 — gap parent + party WS + overlap watch

- **Layout:** `FallbackPaintParent` always parents gap row to health/UF (never `DebuffList`) — fixes Tarantula-class DoT stack when pool lies `native=0` but icons show (`nativeVis>0`).
- **Layout:** `LayoutMergeBesideNative` pixel offset from live native buttons; `PickRightmostAuraFrame` last-button fallback; PAINT trace adds `nativeVis`.
- **Friend party:** drop `PlateFor(party*)==plate` hard bail — use `PlateUnitBindingMatches` / `SameUnit` so Renia-class plates still run `EnsureUnitHarmfulParity` (WS).
- **Watch:** matrix `native_overlap_risk` + `multi_icon_overlap` use `nativeVis`; anomaly flags `nativeVis` overlap + `friendly_party_WS_no_paint`.

## Release 0.2.68 — hotfix paint nil (forward decl)

- **`PlateUsesFriendlyHarmfulFilter`** forward-declare — fixes `paint` nil at line 790 on 0.2.67 (native augment path).

## Release 0.2.67 — plate binding + watcher chat truth

- **Plates:** `CanonicalPlateUnit` / `PlateMatchesTarget` — TF harvest only on real target plate; drop party paint on wrong plate; CARD `punit`/fb from target unit only (no bleed).
- **Watch:** `pb_unified_runtime_from_sv` priority `liveHead_chat` → `CHAT_LOADED` → `RUNTIME_VER` (not SESSION max); `chat_override` clears false `reload_pending`.

## Release 0.2.66 — native API fallback (overlap / false gaps)

- **Root (live 0.2.64):** `native=0` on every PAINT while `painted>0` — Forever pool buttons fail `SafeShown` → empty `NativeShownKeySet` → full-gap repaint on top of Blizzard row.
- **Fix:** `NativeAuraButtonLive`, `AugmentNativeKeysFromUnitApi` (personal harmful / friend all harmful), relaxed `CountPlateHarmfulShown`.
- **CARD:** `punit` = plate token (not stale `lastPaintDebug.unit`).
- **Matrix:** `native_overlap_risk` + recent-only friend PAINT.

## Release 0.2.65 — WS sticky + merge overlap + matrix strict

- **Sticky:** `GAP_STICKY_FRIEND_SEC=18` (hostile stays 3s); refresh `sticky.at` on hold/paint; friend re-inject sticky rows after budget; parity retry before friendly clear.
- **GapAuraLive:** instance lookup miss no longer instant-dead (index/spell fallback).
- **Layout:** merge row offset by `nativeN*(sz+pad)` when anchoring aura row (no DoT overlap).
- **Watch:** matrix recent-tail rules for `friendly_ws` / `tgt_bind` (no stale OK).

## Release 0.2.64 — FElog bridge always + pending queue

- **SessionLog:** always `MirrorToFelog` (not only when `agentIoOk`); flush pending on `ADDON_LOADED` ForeverErrorLog.
- **Watch:** host reads `ForeverErrorLogDB.sessionLog.agentExport` when `session.log` missing (`felog_bridge_sv`).

## Release 0.2.63 — FElog live bridge (io sv_only fallback)

- **SessionLog:** agent lines → `ForeverErrorLog.AgentFeed` when `agent-live.log` append fails.
- **Watch:** `felog-plateband-live.log` sync + `pb_felog_plateband_ver` in unified client ver (`feed=felog_bridge`).
- Requires **ForeverErrorLog 0.1.2+** loaded.

## Release 0.2.62 — unified runtime detection + sv live mirror

- **Lua:** `PlatebandDB.liveHead` (ver/seq/at) updated every pulse — regex-fast for agents.
- **Watch:** single `pb_unified_runtime_from_sv` (chat → agentLive → export); **never** stale `agent-live-export` for version.
- **Feed:** `pb_sync_live_feed` mirrors SV export + writes `Logs/live-head.txt` every 2s when SV mtime moves (in-play flush path).

## Release 0.2.61 — in-play agent-live file feed (no SV wait)

- **Io:** `ProbeAgentIo` append-only (`agent-live.log`) — decoupled from `session.log` truncate; pulse + PAINT flush `agent-live-export.log` every 2s when io works.
- **Host:** `pb_sync_live_feed` copies client `agent-live*.log` to repo `Logs/` each 2s poll; watch **skips SV mirror** when live file is fresh (`feed=agent_live_file`).
- **Forever:** `file=file` in `SESSION_START` when append io works; SV flush remains reload-only — live path is **disk logs**, not `Plateband.lua`.

## Release 0.2.60 — chat-first runtime ver (no SV lag)

- **PLAYER_LOGIN:** `RecordChatLoaded` → `CHAT_LOADED` + `RUNTIME_VER` + `PlatebandDB.runtimeVer` + `Logs/runtime-ver.log` (prefer over stale `SESSION_START` until WTF flush).
- **Watch:** `pb_client_ver` order runtime file → `runtimeVer` → `CHAT_LOADED` → export `RUNTIME_VER` → `agentLive` → `SESSION`.
- **Pulse:** `AGENT_LIVE` also refreshes `runtime-ver.log` when io works.

## Release 0.2.59 — agent live_ver detection + SV feed mirror

- **Agent pulse:** `AGENT_LIVE` every 2s → `PlatebandDB.agentLive` + rolling export line (`io=file|sv_only`); `live_ver` never inferred from TOC.
- **SessionLog:** `EnsureAgentPulseTicker` on session start; CARD appended on silent `start`/`regen`/`target` (`forceSession`).
- **Watch scripts:** `pb_client_ver` reads `agentLive` / export before stale `agent-live.log`; `pb_mirror_sv_export` → `Logs/agent-live-export.log` when io blocked.
- **SESSION_REPORT:** key includes `agent_seq` + `reload_pending`; fires on reload transition; never treats `PLATEBAND_LIVE_VER` as runtime truth.

## Release 0.2.58 — merge row anchor fix (below-health overlap)

- **Layout:** `LayoutMergeBesideNative` health-bar fallback only when fallback parents to **health bar**; otherwise anchor to `AurasFrame` / debuff row — fixes merge strip sitting under health overlapping cast/name chrome (Blackrock Grunt screenshot).
- **Anchor:** `NativeBandRightAnchor` scans hostile buff row when debuff anchor missing; never use bare `DebuffListFrame` as spatial anchor.
- **Parent:** `FallbackPaintParent` keeps aura-row parent when native buffs show but harmful count is zero.

## Release 0.2.57 — friend WS backfill + watch parse fix

- **Friend:** `EnsureUnitHarmfulParity` backfill before clear when `miss=0`; sticky stale retries unit harmful before `paint_stale_cleared`; `tfRows` on all unit paints.
- **Watch:** anomaly parses per-line PAINT/CARD (not `export` blobs); ignore `paint_stale_cleared` for foreign/WS rules; `session_paint_tail_streak` vs whole-session zero.

## Release 0.2.56 — live agent feed (no reload for watch data)

- **SessionLog:** append **agent-live.log** + rolling **agent-live-export.log** (~120 lines, 2s debounce, 5s ticker); re-probe `io` every 30s when `sv_only`.
- **Watch:** `plateband-sv-lib` prefers newest `agent-live.log` / `agent-live-export.log` / `session.log` over stale WTF flush.
- **Reload** = TOC/code only; CARD/PAINT/SESSION visible on disk as you play (when client allows `io`).

## Release 0.2.55 — PAINT telemetry + friend unit parity

- **PAINT:** `SilentTraceEnabled` uses **`silentTrace` only** (schema-11 `paintTraceOn=false` no longer silences session PAINT); `RecordPaint` mirrors to `sessionLog.export`; removed redundant combat early-return in `SilentTracePaint`.
- **Friend chrome:** `EnsureUnitHarmfulParity` on nameplate unit branch when friend filter (Weakened Soul without party-merge / `tgtSrc=0`).
- **Agent:** anomaly flags `PAINT_lines_missing`; FElog `paint nil` / `200 local` treated as historical when `PLATES_LOAD paint=true`.

## Release 0.2.54 — restore paint harvest + combat pending queue

- **Paint:** hostile `useTargetSrc` always runs TF heavy harvest (`CollectTargetHarmfulRows`); lean path no longer leaves `harv=0 miss=0` with live DoTs. Hostile lean fallback `ForceFill` when API sees harmful.
- **Combat:** queue `combatPendingPaint` when lockdown blocks first layout; `FlushCombatPendingPaint` on `PLAYER_REGEN_ENABLED` before `RefreshAll` (cd-only path unchanged for held gaps).
- **CARD:** `painted=` uses max(`lastPaintDebug`, fallback `_painted`); plate/regen diag deferred 120ms after paint schedule.
- **Agent:** `plateband-sv-anomaly.sh` — `session_zero_paint_streak` when `seen>20` and no `painted>0`.

## Release 0.2.53 — combat SetPoint taint + agent live log

- **Combat:** `RefreshGapCooldownsOnly` — no `SetPoint`/`ClearAllPoints`/`LayoutMergeBesideNative` under `InCombatLockdown`; fixes *Akce rozhraní selhala kvůli addonu* from gap tick/target change.
- Plate remove / clear deferred until `PLAYER_REGEN_ENABLED`.
- **`agent-live.log`:** CARD/PAINT lines for agent watch when WTF flush lags (alongside `plateband-sv-lib.sh` live_ver).

## Release 0.2.52 — NameplateUnitFor strict + SV anomaly watch

- **Bleed:** removed `NameplateUnitFor` stale `lastTargetPlateUnit` + sole-enemy fallback (party WS on mob).
- **Agent:** `plateband-sv-anomaly.sh` in watch loop (own/foreign/WS/bleed/sticky + FElog paint).

## Release 0.2.51 — selftest + SV automation + target paint

- **QA:** `plateband-selftest.sh`, `plateband-sv-gate.sh`, `plateband-sv-watch.sh`, `plateband-sv-matrix.sh`; `/pb selftest`.
- **Paint:** target/party plates bypass overlay throttle; `PLAYER_TARGET_CHANGED` clears throttle + immediate `UpdateOverlay` on new target.
- **CARD:** live `tgtSrc`; `friend=` for agent matrix.

## Release 0.2.50 — party DoTs on mobs + sticky expiry

- **Foreign DoTs:** hostile targets always **heavy** harvest (`NeedsHeavyTargetHarvest` + `apiH`); skip `CollectPlayerOwnedKeys` on hostile lean (was overskip party rows).
- **Sticky ghosts:** `GapAuraLive` returns false when spell/instance absent on `AuraUnitForPlate`; hold path prunes dead sticky before refresh; prune uses `paintAuraTok`.

## Release 0.2.49 — friendly WS + no party→mob aura bleed

- **Bug:** Party PW:S/WS debuff appeared on **mob** plates — `ShouldUseTargetAuraSource` used stale `lastTargetPlateUnit` + sole-enemy `IsTargetPlate` heuristic → harvested **`target`** (party) onto wrong plate.
- **Fix:** `useTargetSrc` only when `plate == PlateFor("target")`; `AuraUnitForPlate` binds gap apply token to plate owner; removed stale/sole-enemy target binds.
- **Friendly harmful (WFA-45):** `PlateUsesFriendlyHarmfulFilter` — harmful-only pool harvest + buff-row anchor on friend/party plates only; lean target TF parity (`EnsureTargetHarmfulParity`, `ForceFill`). Hostile harvest unchanged.
- **Locals:** friend helpers as nested `local function` (no forward decl bloat).

### Playtest

1. `/reload` → `ver=0.2.49`, own DoTs on mob still `painted>0`
2. Party PW:S → **no** shield/WS on mob; friend target WS on plate `friend=1`

## Release 0.2.48 — Plates.lua must load (200 locals) + target own-DoT bind

- **Root cause (SV/FElog):** 0.2.46 had **207** chunk `local`s → `main function has more than 200 local variables` → `PaintMergeMissing` nil → **zero own DoTs** (TF OK).
- **Fix:** pack timing constants into `PB`; remove duplicate forward decls (**179** chunk locals). `PLATES_LOAD ok=1` in SV on start.
- **Own DoTs:** force `useTargetSrc` when `plate == PlateFor("target")`; resolve `nameplateN` on target overlay paint.
- **Baseline:** still **0.2.39** `Plates.lua` logic (0.2.47 revert); WS not included.

### Playtest

1. `/reload` → `SESSION_START ver=0.2.48` + `PLATES_LOAD ok=1 paint=true`
2. Mob own DoTs → `tgtSrc=1` `painted>0` in PAINT/CARD

## Release 0.2.47 — revert `Plates.lua` to 0.2.39 baseline (WS branch rolled back)

- **Why:** Post-0.2.40 WS work regressed **own-cast DoTs on mobs** (`CollectPlayerOwnedKeys` / `foreignSkip` / `GapAuraKey` merge path — not a full plate wipe). Ondřej: „jen mé dotky.“
- **Change:** **`Modules/Plates.lua`** restored to **`plateband-v0.2.39`** (`662eb57`). All 0.2.40–0.2.46 paint/harvest/sticky/friendly-filter commits **removed** from that file. Version bump only elsewhere.
- **WS on friends:** deferred until mob **own DoTs** green in SV (`painted>0` on target mob).
- **Symlink:** disk already `0.2.47`; requires **`/reload`** → `SESSION_START ver=0.2.47`.

### Playtest (0.2.47)

1. `/reload` → **`SESSION_START ver=0.2.47`**
2. Target mob, apply **your** DoT → nameplate shows it; CARD/PAINT `painted>0` own spells.
3. Do **not** expect friendly Weakened Soul yet.

## Release 0.2.46 — hostile paint restore + stable unit key

- **Enemy DoTs:** legacy **unfiltered** `CollectPlateDebuffButtons` on hostiles (pre-0.2.41 parity); friendly filter opt-in only.
- **Target plate:** `ResolvePaintUnit` — always `nameplateN` for current target plate (fixes `pb:` vs `nameplateN` fallback split).
- **Heavy harvest:** force when TF API harmful > native (hostiles); TF harmful count on friend targets only.
- **Includes 0.2.44–0.2.45** friendly filter scope + tgtSrc bind.

### Playtest (0.2.46)

1. `/reload` → **`SESSION_START ver=0.2.46`**
2. Mob: **`tgtSrc=1` `painted>0`**
3. Friend PW:S + Weakened Soul OOC + combat

## Release 0.2.45 — enemy target TF merge (tgtSrc=0)

- **Bug:** Target mobs (e.g. Blackrock Outrunner) — TF shows debuffs, nameplate **none**; live SV `SESSION_START ver=0.2.43` (0.2.44 not loaded) and diag `target=yes tgtSrc=0` → no `CollectTargetHarmfulRows` / merge paint.
- **Fix (with 0.2.44 friendly-only filter):** plate==`PlateFor("target")`, **GUID** match on `nameplateN`, `NameplateUnitFor` bind; **`useTargetSrc` forced when `IsTargetPlate`**. Diagnose card computes live `tgtSrc`.

### Playtest (0.2.45)

1. **`/reload`** — must see **`SESSION_START ver=0.2.45`** (not 0.2.43).
2. Target mob with TF debuffs → **`tgtSrc=1` `harv>0` `painted>0`**; icons on plate.
3. Then friendly Weakened Soul.

## Release 0.2.44 — enemy debuff regression (urgent)

- **Bug:** 0.2.41+ **`IsPlateHarmfulAuraButton` on all plates** — enemy `auraPools` debuffs dropped → **no DoTs on mobs** (native merge/nativeN broken).
- **Fix:** **`PlateUsesFriendlyHarmfulFilter`** — harmful/helpful split **only** on friend/party plates; enemy plates use legacy full debuff harvest.

### Playtest (0.2.44)

1. `/reload` → **`ver=0.2.44`** in SV/FElog.
2. Mob DoTs on plate again; then friendly PW:S + Weakened Soul.

## Release 0.2.43 — friendly gap telemetry + paint nil fix

- **SV root cause (feed):** `paintTraceOn=false` silenced **all** session PAINT despite `silentTrace=true` — inbox empty; **`Plates.lua` paint nil** (early `IsLikelyBuffFrame` ref) aborted harvest OOC; **combat** `UpdateOverlay` held row without repaint; **`PLAYER_REGEN_ENABLED`** OOC repaint hit `miss=0` → clear.
- **Fix:** session PAINT when **`silentTrace` only**; **`PlateButtonProbablyHelpful`** early helper; PAINT adds **`sticky=` `ooc=`**; regen refresh deferred 120ms; 0.2.42 sticky/backfill retained.

### Playtest (0.2.43)

1. `/reload` → `ver=0.2.43`; `/felog clear`; target friend PW:S+WS OOC — icon stable; SV `PAINT … ooc=1 sticky=1`.
2. Enter combat — icon stays (no paint nil in FElog).

## Release 0.2.42 — friendly harmful stable OOC (Weakened Soul)

- **Bug:** Weakened Soul visible **in combat** only; **out of combat** gap cleared after `/reload` or `PLAYER_REGEN_ENABLED` repaints with empty harvest.
- **Root cause:** combat `UpdateOverlay` held painted row; OOC paint got `miss=0` and **`ClearFallback`** after 3s sticky; TF buff buttons skewed lean harvest vs real debuff count.
- **Fix:** **`GapStickyActive`** — hold while `GapAuraLive` (up to 30s); **`TargetFriendlyHarmfulGapExpected`** + TF backfill before clear; **`CountTargetFrameHarmfulShown`**; lean path TF-harmful prune skip; `paint_hold` relayout OOC.

### Playtest (0.2.42)

1. `/reload` → `v0.2.41` or newer **`ver=0.2.42`** in SV.
2. OOC party friend **PW:S + Weakened Soul** — red hand stays full ~15s (not combat-only).
3. Enter/leave combat — icon remains (`paint_hold` / `sticky=1` in trace).
4. `/pb diagnose` → `miss≥1` or `painted≥1` / `sticky=1` OOC.

## Release 0.2.41 — friendly harmful gaps (Weakened Soul)

- **Bug:** priest **Weakened Soul** (and similar own HARMFUL on friendlies) missing on nameplate while target-frame debuff row shows it — PW:S on buff row only.
- **Root cause:** plate `auraPools` harvested **HELPFUL** icons as “native harmful” → wrong `nativeN`, merge parented to hidden `DebuffList` (clipped).
- **Fix:** `IsPlateHarmfulAuraButton` + buff/debuff filters on `CollectPlateDebuffButtons`; anchor gap row beside **buff** band when debuff row empty; lean **target** path runs `EnsureTargetHarmfulParity` + TF scrape.

### Playtest (0.2.41)

1. `/reload` → `v0.2.41`; party friend with **PW:S** + **Weakened Soul** — red ghost-hand on plate (beside PW:S or gap row).
2. Enemy personal DoT still one icon (0.2.40 dedupe).

## Release 0.2.40 — no duplicate personal DoTs (Flame Shock ×2)

- **Bug:** own DoT (e.g. Flame Shock) painted twice — native DebuffList + Plateband gap (key mismatch `inst:` vs `spell:`).
- **Fix:** `MarkAllAuraKeys` / `AuraKeysCovered` / `NativeCoversAura` — native + gap share inst+spell+tex; personal gap only when native omitted it.

### Playtest (0.2.40)

1. `/reload` → `v0.2.40`; Flame Shock solo on mob → **one** icon on plate (not two).
2. Party DoT still appears beside native when merge on.

## Release 0.2.39 — native nameplate cooldown font

- Gap timers sample **native** debuff / nameplate aura cooldown: `SetUseAuraDisplayTime`, `SetCountdownFont` (`LayoutFont_Bold_Small_Outline` fallback), font **path + px** from `GetCountdownFontString` or `Duration` (scaled to `/pb size`).
- Removes custom 44% timer estimate — **6 / 9** fit like Blizzard row.

### Playtest (0.2.39)

1. `/reload` → `v0.2.39`; merge icon ~6–10s — center digits match native row beside it.

## Release 0.2.38 — subtle cooldown timer text

- Gap/merge **duration** uses scaled `SetDurationText` (≈44% of icon px, min 8) — matches native subtle digits, not oversized CooldownFrame “21”.
- **`Cooldown:SetHideCountdownNumbers(true)`** — swipe only; digits from aura duration text (OmniCC off via `noCooldownCount`).

### Playtest (0.2.38)

1. `/reload` → `v0.2.38`; debuff with ~20s left on merge row — center timer small like Blizzard row.
2. `/pb size 24` — timer scales down/up with icon.

## Release 0.2.37 — fixed merge-row icon size

- **All** gap/merge icons use profile **`iconSize`** (default 18, `/pb size 12–32`) on every slot — no native/TF sampling, no grow/shrink when personal DoT or spell-damage buff appears.
- Optional cap = health bar height × 0.92.

## Release 0.2.36 — gap icon size lock (personal DoT)

- **`MergeRowIconSize`:** when native harmful row shows your DoT, gap icons **do not grow** — lock uses `min(previous, sample)`; sample = smallest native kid (12–32px), capped by `/pb size` hint.
- Fixes oversized merge row (e.g. Rabid Shadowhide stack chrome) beside health bar.

## Release 0.2.35 — ADDON_ACTION_BLOCKED fix (taint)

- **Removed** per-`nameplateN` `RegisterUnitEvent(UNIT_AURA)` (0.2.34) — flooded secure path, caused *Akce rozhraní selhala kvůli addonu*.
- Paint/layout **skipped under `InCombatLockdown`** except cooldown refresh on existing gap frames; full merge on next safe frame via `ScheduleOverlayUpdate` (deferred).
- Off-target debuff paint: `NAME_PLATE_UNIT_ADDED` + target `UNIT_AURA` (unchanged).

## Release 0.2.34 — per-plate UNIT_AURA watch

- Register `UNIT_AURA` on each `nameplateN` at add / unregister at remove — off-target visible enemies refresh gaps when debuffs change (still event-driven, no scan).

## Release 0.2.33 — event-driven paint (CPU)

- **No periodic `RefreshAll` / nameplate scan** — paint on `NAME_PLATE_*`, `PLAYER_TARGET_CHANGED`, `UNIT_AURA` (target), plus **one** full refresh on zone/roster/`/pb refresh`.
- Slow **3.5s** tick only when gap frames exist (cooldown refresh); skips `EnumerateLivePlates`.
- **`paintTraceOn` default off** + schema 11 migration; **`autoDiag` default off**.
- **Live note:** last SV seen `ver=0.2.31` — **`/reload`** for `SESSION_START ver=0.2.33`.

### Playtest (0.2.33)

1. Activity Monitor: Plateband idle/combat **few %** CPU.
2. `/reload` → `SESSION_START ver=0.2.33`; merge dots still on plate add / target.

## Release 0.2.32 — combat throttle + deferred SV trace

- **Your SV still showed `SESSION_START ver=0.2.30`** — symlink updates do not hot-reload; **`/reload` required** for 0.31+ fixes.
- Combat: ticker **0.6s**, `RefreshAll("combat")` paints **target + active fallbacks only**; no silent `SnapshotDiagnose` on plate/target events.
- `UNIT_AURA` on target → single `UpdateOverlay`, not full `RefreshAll`.
- `paintTrace.export` rebuild debounced (3s); no PAINT trace in combat (`paintTraceInCombat` default **off**, schema 10).
- **A/B:** `/pb merge off` — if stutter stops, merge harvest is the cost; if not, trace was still on old build or another addon.

### Playtest (0.2.32)

1. `/reload` → `SESSION_START ver=0.2.32`.
2. Pull combat: smooth; out of combat pull enemies still get stagger tick merge.
3. Optional: `/pb merge off` one pack, then `/pb merge on`.

## Release 0.2.31 — lean harvest (all-visible merge back, no stutter)

- **Live ver confirmed:** `SESSION_START ver=0.2.30` — stutter was **not** old build; fixed in 0.2.31.
- **Root cost (0.2.24–0.2.30):** double `ReconcileTfHarmfulCoverage`, TF UI scrape every tick on lean targets, `BuildPaintTraceLine` scraping pools/TF on each PAINT, `RecordPaint` mirroring into `sessionLog.export` (`table.concat`), `SilentTraceSweep` on every `RefreshAll`.
- **Fix:** heavy target harvest only when native row incomplete; lean API path when TF matches plate; visible enemy merge restored (0.1.15-style gaps, no TF scrape); party stays group-only; tick stagger; no PAINT trace in combat / on refresh sweeps.

### Playtest (0.2.31)

1. `/reload` → `SESSION_START ver=0.2.31`; combat — no PAINT spam every 2s in SV.
2. Multi-mob pull: foreign DoTs on visible enemy plates return; target still heavy when `native<tf`.

## Release 0.2.30 — lag fix (paint scope + throttle)

- **Merge paint** runs only on **current target** (+ TF path) and **party/raid/player** nameplates — not every friendly `UnitReaction≥4` passerby plate in cities.
- **Non-target enemy** nameplates: native DebuffList only (no gap harvest every tick).
- **Party merge** throttled ~0.65s per plate; **target** ~0.22s; ticker **0.35s** (was 0.25s).
- Cached `ResolvePartyTokenForPlate`; lighter silent trace sweep.

### Playtest (0.2.30)

1. Crowded hub: FPS stable; friendly stranger nameplates unchanged (no extra dot row).
2. Target enemy: merge row still updates; party frames in instance still merge when `mergeFriendPlates` on.

## Release 0.2.29 — nameplate harmful merge (Forever)

Enemy target debuffs beside native nameplate row (TF/API parity, `SetAuraInstance` for secret icons). Party and friend nameplates use the same merge when `mergeFriendPlates` is on (default). Includes 0.2.24–0.2.28 coverage and prune fixes from Stockade playtest.

## 0.2.29 — party/friend nameplate merge

- **`ResolvePartyTokenForPlate`:** `PlateFor(partyN)==plate` binding (Forever `SameUnit` miss).
- **`IsPlayerOrFriendPlate`:** GUID match, `UnitReaction≥4`, non-attackable players.
- **Friend paint path:** full API/slots/parity on `partyN` token; prune guard; PAINT `friend=1` `party=partyN`.
- **`CollectAuraSlotsGaps`:** any unit token (not target-only).
- Enemy skip (0.2.28) no longer drops party plates once `friend=1`.

### Playtest (0.2.29)

1. Party DoT on Pichy — friendly nameplate: `friend=1`, `party=partyN`, `miss≥1`, `painted≥1`.

## 0.2.28 — prune wipe fix + TF force fill (Insurgent)

- **Duplicate `PruneInactiveGapRows` after target harvest** was clearing the queue (`miss=0` with TF full).
- **`ForceFillTargetFrameGaps`:** brute TF + legacy `TargetFrameDebuff1–40` when queue still empty.
- **TF collect:** no `SafeShown` gate on legacy debuff slots; debuff chrome bypasses `IsLikelyBuffFrame`.
- **Paint routing:** skip non-target enemy nameplates while you have a target (no stray `nameplate4` paint).
- **PAINT:** `tfBtn=` = TF button harvest count.

### Playtest (0.2.28)

1. `/reload` → `SESSION_START ver=0.2.28`; insurgent TF 3–4 → `tfBtn≥3`, `tgtSrc=1`, `miss≥1`, `painted≥1`, `cov≥tfRows`.

## 0.2.27 — secret aura paint + TF seed (Stockade Captive)

- **`ApplyGapAuraVisual`:** `SetAuraInstance` counts as visible; stack text only when icon/instance paints (fixes naked yellow stack on bar).
- **Target paint:** seed **`ReconcileTargetFrameUiButtons`** before harvest; **`pcall`** on `CollectTargetHarmfulRows`; skip prune when TF UI still has debuffs.
- **`CountTargetHarmfulExpected`:** light telemetry (no full re-harvest during paint).

### Playtest (0.2.27)

1. `/reload` → `loaded v0.2.27`; target Defias with TF Rend → plate icon + swipe, PAINT `miss≥1 painted≥1 tfRows≥1 cov≥tfRows`.

## 0.2.26 — TF UI cov parity (Defias 1-of-2)

- **`CountTargetHarmfulExpected`:** `tfRows` / PAINT `tf=` = max(API, slots, harvest, TF button count).
- **`ReconcileTargetFrameUiButtons`:** one row per Target Frame debuff button (`tfbtn:` keys) when API/harvest undercount.
- **`PushTfAuraFrame`:** accept shown TF buttons with secret icons (no public fileID).
- **`ReconcileTfHarmfulCoverage`:** reconcile no longer gates TF rows on `GapAuraLive` (prune still does).
- **Friend plates:** `UnitInParty`/`UnitInRaid`; re-run `EnsureUnitHarmfulParity` when API harmful > queue.

### Playtest (0.2.26)

1. `/reload` → **v0.2.26**; Defias Captive TF 2 harm → `tfRows≥2`, `miss≥2`, `cov≥2` on tgtSrc plate.
2. Pichy party dot → `friend=1`, `miss≥1`, `painted≥1`.

## 0.2.25 — API-first harvest + prune fix (Stockade)

- **`GapAuraLive`:** no longer drops rows when `GetAuraDataByAuraInstanceID` fails (was emptying queue → `miss=0 painted=0`).
- **`CollectTargetHarmfulFromApi` first** in TF harvest; **`CountTargetHarmfulApi`** drives PAINT `tf=` / `tfRows`.
- **Seed `CollectUnitHarmfulMirror`** at paint start (target + friend plates); reset stale PAINT debug fields per paint.

### Playtest (0.2.25)

1. `/reload` → chat **loaded v0.2.25**; Defias target: `tf≥1`, `miss≥1`, `painted≥1`, `cov≥tfRows`.
2. Friend dot (Pichy): `friend=1`, `miss≥1` without targeting them.

## 0.2.24 — TF coverage parity (tfRows / cov)

- **`NativeShownKeySet`:** gap skip uses **shown** native harmful only (pool hidden kids no longer drop TF rows).
- **`ReconcileTfHarmfulCoverage`:** after dedupe/prune, force-append every TF/API harmful not on native or queue.
- **PAINT:** `tfRows=` harmful harvest count, `cov=` native+painted, `friend=` — compare TF vs plate in SV/watch.
- **AppendGapRow:** accept spell/instance rows without public icon (secret TF).

### Playtest (0.2.24)

1. `/reload` → `ver=0.2.24`; target with N TF harm → `tfRows=N`, `cov≥N` on tgtSrc plate.

## 0.2.23 — friendly nameplate harmful merge

- **`mergeFriendPlates`** (default on, schema 9): party/friend/player nameplates use same gap row + native chrome as enemies (no early `ClearFallback`).
- **`EnsureUnitHarmfulParity`:** full harmful `C_UnitAuras` pass per `nameplateN` / party token when not on target-aura path.
- Opt out: `PlatebandDB.profile.mergeFriendPlates = false`.

### Playtest (0.2.23)

1. `/reload` → `SESSION_START ver=0.2.23`; party member with DoT — debuff row on **friendly** nameplate (PAINT `friendPlate=1`).

## 0.2.22 — expired sticky purge + target API harvest

- **`GapAuraLive` / `PruneInactiveGapRows`:** sticky, paint_hold, and queue drop **expired** or unit-absent auras (no ghost party icons).
- **`CollectTargetHarmfulFromApi`:** TF harvest backfill from `C_UnitAuras` on target (`tf/harv>0` when TF scrape empty).
- **`ShouldUseTargetAuraSource`:** `lastTargetPlateUnit` match for melee/party nameplate binding.
- Always **`CollectUnitHarmfulMirror`** on target plate path.

### Playtest (0.2.22)

1. `/reload` → PAINT `ver=0.2.22` / `SESSION_START ver=0.2.22` — symlink alone is not enough.
2. Party DoT on Defias — icons on plate + timers; after expiry row clears (`paint_hold_expired` or `painted=0`).

## 0.2.21 — no dropped DoTs (instance dedupe + TF parity)

- **`GapAuraKey`:** dedupe **auraInstanceID → spellId → texture** (fixes same-icon party DoTs vanishing when own DoT joins).
- **`NativeKeySet`:** native presence uses instance/spell keys, not texture-only.
- **`EnsureTargetHarmfulParity`:** after harvest/API, re-sync **target harmful** vs TF + `C_UnitAuras` minus native plate.

### Playtest (0.2.21)

1. `/reload` → mix own + party DoTs; plate + gap row count matches TF harmful (no missing debuffs after own lands).

## 0.2.20 — foreign timers + size when own DoT on native

- **`MergeRowIconSize`:** when native harmful row visible, gap size **tracks plate native kids** (lock may grow to match personal).
- **`paint_hold`:** `RefreshHeldGapFallback` re-applies layout + `SetCooldown` each tick (no frozen foreign swipes).
- **`EnrichGapAuraEntry`:** API/slot enrich before paint/sticky; **no `Cooldown:Clear`** on transient miss; `SetCooldown` after `SetAuraInstance`.

### Playtest (0.2.20)

1. `/reload` → own DoT on Defias-type target with party DoTs — **same size band**, all swipes live (PAINT `cdN≥1`, `gapSz` ≈ native).

## 0.2.19 — PAINT regression telemetry + agent watch

- **PAINT line:** `gapSz`, `lockSz`, `cdN` (merge icon size, per-plate lock, cooldowns applied) for `watch-forever-traces.sh` regression alerts.
- **Agent policy:** 3s `watch-forever-traces.sh watch 3` + Plateband SV — fix/ship on alert before user screenshot (see repo `.cursor/rules/plateband-proactive-watch.mdc`).

### Playtest (0.2.19)

1. `/reload` → PAINT tail includes `gapSz=` `cdN=`; watch inbox stays quiet during normal DoT play.

## 0.2.18 — gap cooldown swipe + stable TF size

- **`ApplyGapAuraVisual`:** aura rows carry `expirationTime`/`duration` (API + TF harvest); `Cooldown:SetCooldown` each paint tick; optional `SetUnit` + `SetAuraInstance`.
- **`MergeRowIconSize`:** Target Frame harmful debuff width is canonical when target exists; **`fb._pbLockedSz`** never grows when own DoT lands on native row.
- **`AuraChromeWidth`:** prefer icon child width when frame chrome is oversized; TF sample uses **minimum** visible debuff width; plate metrics cap **32px**.

### Playtest (0.2.18)

1. `/reload` → `ver=0.2.18`; party DoTs on target plate — **same size** as TF/native personal; **live cooldown swipe** on each icon.
2. Apply own DoT — gap row icons **do not jump** larger.

## 0.2.17 — native gap aura chrome (merge row)

- **Gap row uses Blizzard debuff button templates** (`DebuffButtonTemplate`, …) via `CreateGapAuraButton` + `InitAuraButton` — border, cooldown swipe, stack font like personal DebuffList.
- **`NativeAuraMetrics`:** min shown aura width 12–48px; TF fallback size; cap vs health bar (no oversized chrome).
- **Paint** stores aura rows (stacks/instance); `ApplyGapAuraVisual` applies icon + stack text.

### Playtest (0.2.17)

1. `/reload` → `ver=0.2.17`; own + party DoT on target — **same size/chrome** as native personal on plate.
2. No FElog `paint` nil spam when idle.

## 0.2.16 — personal + foreign coexist

- **`AuraIsOurPersonalOnly`** — party DoTs no longer routed only to personal / blocked from foreign.
- **Foreign pass:** `AuraCountsAsForeignGaps` = not our-personal-only; drop `CollectPlayerOwnedKeys` preload on `foreignSkip` (queue dedupe only).
- **TF supplement** always runs (CanonicalGapKey dedupe) so TF foreign icons aren't dropped when own DoT paints first.

### Playtest (0.2.16)

1. `/reload` → `ver=0.2.16`; self DoT + party DoT on target → **both** on plate (PAINT `pers≥1 for≥1`).

## 0.2.15 — TF/plate harmful dedupe

- **`CanonicalGapKey` / `tex:`** — one icon per public texture; TF harvest dedupes before paint.
- **Single `queueSkip`** across TF + API passes; skip redundant second `CollectTargetFrameMissing` when `harv>0`.
- **`DedupeGapIcons`** on queue + sticky hold.

### Playtest (0.2.15)

1. `/reload` → `ver=0.2.15`; Dragonmaw + ~2 TF harmful → **same count** above plate (no 4× same fire).

## 0.2.14 — paint hold + TF/API mirror (Dragonmaw)

- **Wipe on hit:** `UpdateOverlay` no longer `ClearFallback` before paint; sticky not cleared in routine hide; **3s gap hold** when API flickers empty after melee/`UNIT_AURA`.
- **`paint_hold`:** keep visible fallback while sticky valid instead of one-frame wipe.
- **Empty native:** `CollectUnitHarmfulMirror` + `ScrapeTargetFrameBrute` scans full `TargetFrame` when container nil.

### Playtest (0.2.14)

1. `/reload` → `ver=0.2.14`; target Dragonmaw Grunt with DoTs — 4 icons above plate.
2. **Deal damage** — row stays; SV `PAINT … painted≥1` or `paint_hold`.
3. `/reload` — PAINT lines in SV.

## 0.2.13 — systematic Lua forward decl (103 module fns)

- **Root cause:** `local function` below caller compiles to **global** nil in Lua 5.1 (e.g. `CountPlateHarmfulShown` → `MaxIcons()` L536).
- **Fix:** single forward-decl block + **`Name = function`** for all 103 chunk-level helpers in `Plates.lua` (not one-off patches).
- Removed `CollectPlateDebuffButtons` type guards (always bound after load).

### Watch

- `watch-forever-traces.sh` default poll **3s**; tails **FElog `session.log`** (live with chat; SV lags until `/reload`).
- Coordinator inbox: `/tmp/forever-trace-coordinator-inbox.txt` on each ALERT.

### Playtest (0.2.13)

1. `/reload` → `SESSION_START ver=0.2.13`; `/felog clear` optional.
2. Target + DoTs → no `paint` nil in chat/FElog; PAINT in SV after `/reload`.

## 0.2.12 — paint path forward decls (ButtonAuraIcon / metrics)

- **`NativeKeySet` L1318:** `ButtonAuraIcon`, `AuraDedupeKey` — forward decl + assignment fns (same class as 0.2.11).
- **`LayoutMergeBesideNative`:** `NativeAuraMetrics` forward decl.

### Playtest (0.2.12)

1. `/reload` → `v0.2.12`; `/felog clear` optional.
2. Target + DoTs → no FElog `paint` nil; PAINT in SV after `/reload`.

## 0.2.11 — Lua forward-decl fix (nil trace/paint)

- **`CollectPlateDebuffButtons` / `SilentTraceSweep`:** file-level forward decls; late `local function` left callers resolving **global nil** (`paint:527`, `RefreshAll:2592`).
- Silent trace assignments moved **before** `PaintMergeMissing`; `pcall` on sweep.

### Playtest (0.2.11)

1. `/reload` → `loaded v0.2.11` — no FElog nil spam.
2. DoTs on target plate → PAINT lines in SV after `/reload`.

## 0.2.10 — silent paint trace (agent-readable)

- **Silent by default:** `silentTrace` + `paintTraceOn` (schema **8**) — no chat spam; `/pb diagnose` optional.
- **PAINT lines** every ~0.5s sweep + each paint: unit, merge, native/pool/kids, tf/harv/miss/painted/fb, pers/for, tgtSrc, parent, bar/nat visibility, ver.
- **Stores:** `PlatebandDB.sessionLog.export` + `paintTrace.export` + `lastPaintTrace`; wiped each login (`SESSION_START`).
- **Agent:** `scripts/watch-plateband-sv.sh` reads `WTF/.../SavedVariables/Plateband.lua`.

### Playtest (0.2.10)

1. `/reload` → `loaded v0.2.10` (no PAINT spam in chat).
2. Fight with DoTs → `/pb dump` shows `paintTrace` tail, or send `Plateband.lua` after one `/reload`.
3. On Mac: `./scripts/watch-plateband-sv.sh` while in game (after `/reload` flush).

## 0.2.9 (HUD gate — target plate paint path)

- **Unit key:** plates without a public `nameplateN` token use stable `pb:<plate>` keys — `UpdateOverlay` no longer no-ops on `unit=nil`.
- **Target refresh:** always paints `PlateFor("target")` even when `NameplateUnitFor` fails (Forever secret `UnitIsUnit`).
- **TF-first:** `ShouldUseTargetAuraSource` (plate pointer / sole enemy / tokens) mirrors full `CollectTargetHarmfulRows` before API gap passes — Tidecaller/Murloc with TF harmful≥3 → `harv≥3`.
- **Parent:** when `native=0`, fallback parents to **health bar** (hidden `DebuffList` was clipping painted textures).
- **Diagnose:** `harv` / `miss` / `painted` / `tgtSrc` / `punit` on card; confirm **`ver=0.2.9`**.

### Playtest (0.2.9)

1. Replace zip (not symlink to old tree) → `/reload` → chat **`Plateband 0.2.9`**.
2. **`/pb merge on`** if `merge=0` in diagnose.
3. Target **Murloc** with TF harmful icons → **`/pb diagnose`** → `ver=0.2.9` · `tf≥3` · `harv≥3` · `miss≥3` · **`painted≥3`** · `fb≥3` · `tgtSrc=1`.
4. Nameplate row shows icons above health bar matching TF.

## 0.2.8 (HUD gate — empty native + TF mirror)

- **Paint abort:** no longer requires `AurasFrame`/`DebuffListFrame` at gate — `FallbackParent` (incl. `UnitFrame`) is enough; layout anchor falls back to health bar when native row empty.
- **TF dedupe fix:** `CollectTargetFrameMissing` dedupes against **native keys + icons already queued**, not `CollectPlayerOwnedKeys` — fixes Bellygrub-style targets where TF shows 2 harmful icons but plate native=0 and `fb=0` (0.2.7 pre-skipped owned spells).
- **Target detect:** sole hostile nameplate while targeting counts as target plate when `UnitIsUnit` is secret.
- **Note:** stray level-like text above a plate (e.g. “26”) is not Plateband — we paint textures only, no `SetText` on nameplates.

### Playtest (0.2.8)

1. `/reload` → `/pb diagnose` → **`ver=0.2.8`** · targeting mob with TF harmful≥2 → **`tf≥2`** · **`fb≥2`** (or **`native`+`fb`**).
2. **Bellygrub** (or any `native=0`): TF DoTs visible on plate row above/beside health bar — matches TF harmful icons.
3. UI intact — no DebuffList/name `ClearAllPoints`.

## 0.2.7 (HUD gate — Retinue TF harvest)

- **Root fix:** replace thin `CollectTargetFrameButtons` / `ButtonAuraIconAny` scrape with **Retinue parity** harvest: `debuffAuraGroup:GetFramesByIndex`, **`GetAuras():Iterate`**, `auraPools`, **`C_UnitAuras.GetAuraSlots`**, numeric **`activeDebuffs` → GetAuraDataByAuraInstanceID**, live-button brute with secret icon support.
- **TF gaps:** mirror full TF harmful row, subtract `paintKeys` (native + personal) — party warlock DoTs paint when TF shows them.
- **Paint:** `SetIconTexture` accepts `{ iconTex }` wrapper for secret/atlas TF buttons.
- **Diagnose:** `tf=` uses `CollectTargetHarmfulRows` count (falls back to legacy counter if 0).

### Playtest (0.2.7)

1. `/reload` → `/pb diagnose` → **`ver=0.2.7`** · **`tf≥2`** when TF shows personal + warlock.
2. Target mob: your DoT + **party warlock DoT** on TF → nameplate row shows **both** (`fb` includes warlock).
3. Solo target → no junk icons; UI intact after `/reload`.

## 0.2.6 (HUD gate — foreign / party DoTs)

- **TF supplement:** `CollectTargetFrameMissing` uses `ButtonAuraIconAny` — dedupe via `skipKeys` only, not ownership skip (party warlock DoTs were dropped when `isFromPlayerOrPlayerPet` mis-tagged).
- **API foreign:** `AuraCountsAsForeignGaps` — party-sourced harmful with `owned==true` still counts as foreign (`AuraLooksForeign`).
- **TF dedupe:** `tfDedupe` = painted keys + API foreign keys; personal already in `paintKeys` prevents duplicate Rake.

### Playtest (0.2.6)

1. `/reload` → `ver=0.2.6`.
2. Target mob with **your Rake + party warlock DoT** on TF → plate row shows **both** (`fb≥2` or native+rake + fb foreign).
3. Solo pull (no foreign) → no duplicate personal icons.

## 0.2.5 (HUD gate — P1 personal gaps)

- **Personal gaps (§5.2 Phase B):** when native `DebuffList` / pools show **0** harmful (Forever omits player DoTs on plate), paint player-owned HARMFUL from `C_UnitAuras` + TF buttons **only if ∉ NativeKeySet** — no `CollectPlayerOwnedKeys` on the same set used for personal eligibility.
- **Foreign path unchanged:** `CollectForeignAuraGaps` + `CollectTargetFrameMissing` with separate `foreignSkip` after personal pass.
- **Diagnose:** `native=` counts pool-enumerated harmful buttons (`CountPlateHarmfulShown`).

### Playtest (0.2.5)

1. `/reload` → `/pb diagnose` → `ver=0.2.5`.
2. Hunter pet DoT / Mark on **Ashenvale Bear** (or any `native=0` target) → plate shows **≥1** icon (`fb≥1`); TF parity for personal.
3. Party warlock DoT on same target → `fb` includes foreign; no duplicate if native already shows spell.
4. `/reload` UI intact (no name/DebuffList SetPoint).

## 0.2.4 (HUD gate — P0 §5)

- **0.1.15 data contract:** `CollectForeignAuraGaps` skips `owned==true` (no personal fallback); `CollectPlayerOwnedKeys` → `skipKeys`; target always `CollectTargetFrameMissing` after API + `nameplateN`.
- **0.2 layout retained:** `NativeAuraMetrics`, pools anchor, `FallbackParent`, beside-native only.
- **Gap sticky** ~0.4s on target when API flickers empty (no CLEU).

## 0.2.3 (HUD gate)

- **Paint path:** TF read-only gap supplement on target (`CollectTargetFrameMissing`) always after API gaps.
- **Gate:** `FallbackParent` (DebuffList/AurasFrame) — not `SafeFallbackParent`-only early exit.
- **Native detect:** nameplate `auraPools` + `CollectPlateDebuffButtons` for `NativeKeySet`, metrics, anchor.
- **Dedupe:** `CollectPlayerOwnedKeys` → `playerOnly` (foreign path only); personal gaps use native keys only.
- **Visibility:** fallback parent `DebuffList`/`AurasFrame`; higher frame level; layout health-bar fallback.

## 0.2.2 (HUD gate)

- **Fix foreign DoTs missing:** `CollectHarmfulGaps` restored 0.1.15 eligibility — skip only `owned==true` in foreign path; `allowSecretUnknown` on target/nameplate; re-added `CollectPlayerOwnedKeys` before paint.
- Removed `GapAuraEligible` `nativeN` gate that dropped secret-ownership party DoTs when any native kid showed.
- `NativeDebuffAnchorList` — layout when `AurasFrame` exists without `DebuffListFrame`.

## 0.2.1 (HUD gate)

- Gap icons **match native debuff metrics** (`NativeAuraMetrics`) — same size/row as Rake-style chrome left of health.
- Layout: `LEFT` of rightmost native + **BOTTOM** align; strata/level from `DebuffListFrame`.

## 0.2.0 (HUD gate — branch zip, not main)

- **Native-row gap:** personal + foreign harmful via `C_UnitAuras` only; dedupe `NativeKeySet`.
- **Safety:** `SafeFallbackParent`, debounce `UNIT_AURA`, `pcall` paint; no TF scrape in paint path; no health-TOP merge anchor.
- **Requires** `DebuffListFrame` on plate to paint gaps.

## 0.1.15

- **Default merge on:** `mergeMissing=true` (schema 7 migrates older saves from schema 6 off).
- **`/pb merge off`** — native DebuffList only (same safe path as 0.1.12–0.1.14 default).
- Docs: README, merge-design, loops, playtest brief updated.

## 0.1.14

- Merge beside native on enemy plates (opt-in `mergeMissing=false` default).
- TargetFrame auraPools / `C_UnitAuras` collection; no name `SetPoint`.

## 0.1.12

- Native-only safe default; strips legacy name mutation paths.