--[[ PlatesTrace — PAINT trace / sweep in own chunk (WoW 60 upvalue cap). ]]
Plateband = Plateband or {}
local D = Plateband.PlatesTraceDeps
if not D then
  return
end

local PB = D.PB

function D.SilentTraceEnabled()
  local p = D.Profile()
  if p.silentTrace ~= true then
    return false
  end
  if p.paintTraceInCombat == false and D.PlayerInCombat() then
    return false
  end
  return true
end

local function SilentTraceEnabled()
  return D.SilentTraceEnabled()
end

local function BuildPaintTraceLine(why, unit, plate)
  if not SilentTraceEnabled() then
    return nil
  end
  unit = D.OverlayUnitKey(unit, plate) or tostring(unit or "?")
  local p = D.Profile()
  local lpd = D.lastPaintDebug or {}
  local fb = 0
  if unit and D.fallbacks[unit] then
    fb = tonumber(D.fallbacks[unit]._painted) or 0
  end
  local tgtSrc = D.ShouldUseTargetAuraSource(unit, plate) and 1 or 0
  local cfg = D.Config
  local ver = cfg and cfg.VERSION or "?"
  local gapW = lpd.gapW
  if not gapW and lpd.gapSpread then
    gapW = (tonumber(lpd.gapSz) or 18) * (tonumber(lpd.gapSpread) or 0)
  end
  return string.format(
    "PAINT ver=%s why=%s unit=%s tgt=%s merge=%s native=%s nativeVis=%s harv=%s miss=%s painted=%s tgtSrc=%s tfRows=%s friend=%s party=%s gapW=%s gapOff=%s",
    tostring(ver),
    tostring(why or "?"),
    tostring(unit),
    D.HasTarget() and "1" or "0",
    p.mergeMissing == true and "1" or "0",
    tostring(lpd.nativeN or "?"),
    tostring(lpd.nativeVis or "?"),
    tostring(lpd.harv or "?"),
    tostring(lpd.miss or "?"),
    tostring(math.max(tonumber(lpd.painted) or 0, fb)),
    tostring(tgtSrc),
    tostring(lpd.tfRows or "?"),
    tostring(lpd.friendPlate or "?"),
    tostring(lpd.partyTok or "?"),
    tostring(gapW or "?"),
    tostring(lpd.gapOffX or "?")
  )
end

function D.SilentTracePaint(why, unit, plate)
  if not SilentTraceEnabled() then
    return
  end
  why = tostring(why or "?")
  if why == "refresh" or why:match("^refresh") or why:match("^sweep") then
    return
  end
  if why == "paint_sample" then
    local lpd0 = D.lastPaintDebug or {}
    if (tonumber(lpd0.miss) or 0) > 0 or (tonumber(lpd0.tfRows) or 0) > 0 then
      why = "paint_gap"
    end
  end
  unit = D.OverlayUnitKey(unit, plate) or tostring(unit or "?")
  local now = GetTime and GetTime() or 0
  local minSec = (PB and PB.PAINT_TRACE_MIN_SEC) or 1.5
  if (now - (D.lastPaintTraceAt[unit] or 0)) < minSec then
    return
  end
  local lpd = D.lastPaintDebug or {}
  local sig = string.format(
    "%s:%s:%s:%s",
    tostring(lpd.miss or 0),
    tostring(lpd.painted or 0),
    tostring(lpd.harv or 0),
    tostring(lpd.cdN or 0)
  )
  if D.lastPaintTraceSig[unit] == sig and (tonumber(lpd.painted) or 0) == 0 and (tonumber(lpd.miss) or 0) == 0 then
    return
  end
  local friendP = tonumber(lpd.friendPlate) or 0
  local tfRows = tonumber(lpd.tfRows) or 0
  local missN = tonumber(lpd.miss) or 0
  local paintedN = tonumber(lpd.painted) or 0
  local fbN = 0
  if unit and D.fallbacks[unit] then
    fbN = tonumber(D.fallbacks[unit]._painted) or 0
  end
  if friendP == 1 and tfRows > 0 and paintedN == 0 and fbN > 0 then
    lpd.painted = fbN
    paintedN = fbN
    sig = string.format("%s:%s:%s:%s", tostring(missN), tostring(paintedN), tostring(lpd.harv or 0), tostring(lpd.cdN or 0))
  end
  if friendP == 1 and tfRows > 0 and paintedN == 0 and missN > 0 and why == "paint" and fbN == 0 then
    return
  end
  D.lastPaintTraceSig[unit] = sig
  D.lastPaintTraceAt[unit] = now
  local line = BuildPaintTraceLine(why, unit, plate)
  local slog = D.SessionLog
  if line and slog and slog.RecordPaint then
    pcall(slog.RecordPaint, line)
  end
  paintedN = tonumber(lpd.painted) or 0
  if friendP == 1 or paintedN >= 2 or (friendP == 1 and tfRows > 0 and paintedN == 0) then
    pcall(D.SnapshotDiagnose, "paint", {
      silent = true,
      forceSession = true,
      unit = unit,
      plate = plate,
    })
  end
end

function D.SilentTraceSweep(why)
  if not SilentTraceEnabled() then
    return
  end
  local now = GetTime and GetTime() or 0
  local sweepSec = (PB and PB.SILENT_SWEEP_SEC) or 2.0
  if (now - (D.lastSilentSweepAt or 0)) < sweepSec then
    return
  end
  D.lastSilentSweepAt = now
  local list = D.EnumerateLivePlates()
  local swept = {}
  if D.HasTarget() then
    local tp = D.PlateFor("target")
    local tu = D.NameplateUnitFor("target") or (tp and D.UnitTokenFromPlate(tp))
    tu = D.OverlayUnitKey(tu, tp)
    if tp then
      D.SilentTracePaint(why or "sweep_tgt", tu, tp)
      swept[tu or tostring(tp)] = true
    end
  end
  for i = 1, #list do
    if i > 3 then
      break
    end
    local entry = list[i]
    local u = D.OverlayUnitKey(entry.unit, entry.plate)
    if u and not swept[u] and entry.plate then
      if not D.IsPartyRaidMergePlate(u, entry.plate) and not D.IsTargetPlate(u, entry.plate) then
        -- skip ambient friendly NPC / passerby plates in trace sweep
      else
        D.SilentTracePaint((why or "sweep") .. "_np", u, entry.plate)
        swept[u] = true
      end
    end
  end
end