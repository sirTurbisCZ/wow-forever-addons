# Playtest brief — Plateband 0.1.15

Release gate — native DebuffList safe default + opt-in party/foreign DoT merge beside native on **enemy** nameplates.

**0.1.15**
- Version **0.1.15**; merge ships per `Docs/merge-design.md` (no name `SetPoint`; no DebuffList mutation).
- Default **merge on** (`mergeMissing=true`, schema 7 migrates prior saves).
- **`/pb merge off`** restores native-only.

**Smoke (solo)**
1. `/reload` → chat `loaded v0.1.15` (mentions merge on by default).
2. `/pb diagnose` → `merge=1`, personal DoTs on target plate, `native>0`, `fb=0` unless foreign omitted, `blocked=0`.
3. Party/friend nameplates: name readable, not glued to bar (`/pb merge off` baseline).

**Smoke (group + enemy target, default merge)**
1. No slash needed — merge already on; `/pb merge off` then `on` still works.
2. Target mob with party-applied DoT Blizzard omits from nameplate DebuffList.
3. Icons appear **to the right** of native debuff row (same band); no duplicate personal icons.
4. `/pb diagnose` → `merge=1`, `tf>0` when TargetFrame has hidden auras, `fb>0` when merge painted.
5. `/pb merge off` → merge icons clear; native row unchanged.

**Regression**
- Never `ADDON_ACTION_BLOCKED` from Plateband `SetPoint` on name/DebuffList during above steps.
- `/pb safe` clears fallbacks; `/pb on` resumes.

Dist zip: `./scripts/package-addon.sh Plateband` → `dist/Plateband-0.1.15.zip`.