# Plateband changelog

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