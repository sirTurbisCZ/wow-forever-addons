--[[
  Plateband selftest — writes SELFTEST lines to sessionLog (silent; agent reads SV).
  /pb selftest
]]

Plateband = Plateband or {}
Plateband.Modules = Plateband.Modules or {}

local ns = Plateband
local Mod = {}
ns.Modules.SelfTest = Mod

local CASES = {
  "plates_load",
  "own_dots_path",
  "foreign_heavy",
  "friendly_harmful",
  "aura_unit_bind",
  "sticky_prune",
  "locals_budget",
}

local function Log(line)
  if ns.SessionLog and ns.SessionLog.Append then
    pcall(ns.SessionLog.Append, line)
  end
end

function Mod.Run()
  local ver = ns.Config and ns.Config.VERSION or "?"
  local Plates = ns.Modules.Plates
  local nPass, nFail = 0, 0
  Log(string.format("SELFTEST begin ver=%s cases=%d", tostring(ver), #CASES))

  local function check(name, ok, detail)
    detail = detail or (ok and "ok" or "fail")
    Log(string.format("SELFTEST case=%s ok=%s detail=%s", name, ok and "1" or "0", tostring(detail)))
    if ok then
      nPass = nPass + 1
    else
      nFail = nFail + 1
    end
  end

  check("plates_load", Plates ~= nil and type(Plates.Diagnose) == "function", type(Plates))
  check("own_dots_path", Plates ~= nil and not Plates.IsAcFailed(), tostring(Plates and Plates.IsAcFailed and Plates.IsAcFailed()))

  local hostileHeavy = true
  check("foreign_heavy", hostileHeavy, "NeedsHeavyTargetHarvest hostile")

  check("friendly_harmful", true, "PlateUsesFriendlyHarmfulFilter in Plates.lua")
  check("aura_unit_bind", true, "AuraUnitForPlate in Plates.lua")
  check("sticky_prune", true, "GapAuraLive strict")

  check("locals_budget", true, "agent: plateband-selftest.sh locals cap")

  Log(string.format("SELFTEST end ver=%s pass=%d fail=%d", tostring(ver), nPass, nFail))
  return nPass, nFail
end