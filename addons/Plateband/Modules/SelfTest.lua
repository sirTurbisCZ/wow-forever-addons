--[[
  Plateband selftest — real wiring checks, results printed to chat (and sessionLog when dev telemetry is on).
  /pb selftest
]]

Plateband = Plateband or {}
Plateband.Modules = Plateband.Modules or {}

local ns = Plateband
local Mod = {}
ns.Modules.SelfTest = Mod

-- Functions PlatesPaint.lua / PlatesTrace.lua call through the Deps tables: nil here = a load-order bug.
local PAINT_DEPS = {
  "ClearFallback", "EnsureFallback", "ApplyGapAuraVisual", "LayoutMergeBesideNative", "CollectForeignAuraGaps",
  "CollectPersonalAuraGaps", "AuraUnitForPlate", "GapAuraLive", "SilentTracePaint", "NativeShownKeySet",
}
local TRACE_DEPS = { "SnapshotDiagnose", "EnumerateLivePlates", "PlateFor", "Profile" }

local function Log(line)
  if ns.SessionLog and ns.SessionLog.Append then
    pcall(ns.SessionLog.Append, line)
  end
end

local function MissingFunctions(deps, names)
  local missing = {}
  for i = 1, #names do
    if type(deps and deps[names[i]]) ~= "function" then
      missing[#missing + 1] = names[i]
    end
  end
  return missing
end

function Mod.Run()
  local ver = ns.Config and ns.Config.VERSION or "?"
  local Plates = ns.Modules.Plates
  local nPass, nFail = 0, 0
  Log(string.format("SELFTEST begin ver=%s", tostring(ver)))

  local function check(name, ok, detail)
    detail = detail or (ok and "ok" or "fail")
    Log(string.format("SELFTEST case=%s ok=%s detail=%s", name, ok and "1" or "0", tostring(detail)))
    if ok then
      nPass = nPass + 1
    else
      nFail = nFail + 1
      if ns.Print then
        ns.Print("selftest FAIL " .. name .. ": " .. tostring(detail))
      end
    end
  end

  check("plates_load", Plates ~= nil and type(Plates.Diagnose) == "function", "Plates.Diagnose")

  local paintDeps = ns.PlatesPaintDeps
  local missing = MissingFunctions(paintDeps, PAINT_DEPS)
  check("paint_deps", #missing == 0 and type(paintDeps and paintDeps.PaintMergeMissing) == "function",
    #missing == 0 and "ok" or ("missing " .. table.concat(missing, ",")))

  missing = MissingFunctions(ns.PlatesTraceDeps, TRACE_DEPS)
  check("trace_deps", #missing == 0, #missing == 0 and "ok" or ("missing " .. table.concat(missing, ",")))

  local sl = ns.SessionLog
  check("session_api", sl ~= nil and type(sl.Append) == "function" and type(sl.RecordPaint) == "function"
    and type(sl.BeginSession) == "function", "SessionLog")

  local cfg = ns.Config
  local okCfg = false
  if cfg and cfg.EnsureDB then
    local db = cfg.EnsureDB()
    okCfg = type(db) == "table" and db.schemaVersion == cfg.CURRENT_SCHEMA and type(db.profile) == "table"
  end
  check("config_schema", okCfg, "schema=" .. tostring(cfg and cfg.CURRENT_SCHEMA))

  -- TOC version must equal the running Config version (a stale /reload shows up here).
  local meta
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, "Plateband", "Version")
    if ok then
      meta = v
    end
  end
  check("version_match", meta == nil or tostring(meta) == tostring(ver),
    string.format("toc=%s config=%s", tostring(meta), tostring(ver)))

  Log(string.format("SELFTEST end ver=%s pass=%d fail=%d", tostring(ver), nPass, nFail))
  return nPass, nFail
end
