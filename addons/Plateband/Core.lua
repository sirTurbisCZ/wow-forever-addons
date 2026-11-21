--[[
  Plateband — above-plate shared harmful / DoT band.
  /pb help|on|off|diagnose|dump|safe|reset|size
]]

local addonName = ...

Plateband = Plateband or {}
Plateband.Modules = Plateband.Modules or {}

local L = Plateband.L or {}
local Config = Plateband.Config
local Plates = Plateband.Modules.Plates

local function EnsureDB()
  return Config.EnsureDB()
end

local function Print(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring(select(i, ...))
  end
  print((L.PREFIX or "[Plateband]") .. " " .. table.concat(parts, " "))
end

local function Trim(s, maxLen)
  s = tostring(s or "")
  if #s > maxLen then
    return s:sub(1, maxLen - 3) .. "..."
  end
  return s
end

local function Now()
  if time then
    return time()
  end
  return 0
end

--- Error boundary → circular log (+ optional ForeverErrorLog).
function Plateband.RecordError(context, err)
  local db = EnsureDB()
  local msg = Trim(tostring(err or "?"), Config.MAX_MSG)
  local ctx = Trim(tostring(context or "?"), 120)
  local stack = ""
  if debugstack then
    local ok, s = pcall(debugstack, 3)
    if ok then
      stack = Trim(s or "", Config.MAX_MSG)
    end
  end

  local list = db.errors
  for i = 1, #list do
    local e = list[i]
    if e.msg == msg and e.context == ctx then
      e.count = (e.count or 1) + 1
      e.last = Now()
      if stack ~= "" then
        e.stack = stack
      end
      return
    end
  end

  list[#list + 1] = {
    msg = msg,
    context = ctx,
    stack = stack,
    first = Now(),
    last = Now(),
    count = 1,
  }
  while #list > Config.MAX_ERRORS do
    table.remove(list, 1)
  end

  if ForeverErrorLog and ForeverErrorLog.Record then
    pcall(ForeverErrorLog.Record, "Plateband:" .. ctx .. " " .. msg, stack)
  end
end

local function SafeCall(context, fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  if not ok then
    Plateband.RecordError(context, a)
    return nil
  end
  return a, b, c
end

local function ModuleWanted()
  local p = Config.GetProfile()
  return p.enabled and not p.safeMode
end

local function ApplyModuleState()
  if not Plates then
    return
  end
  if ModuleWanted() then
    SafeCall("plates:start", Plates.Start)
  else
    SafeCall("plates:stop", Plates.Stop)
  end
end

local function DumpRing()
  local db = EnsureDB()
  local list = db.errors
  Print(string.format(L.DUMP_HEADER or "dump — errors=%d", #list))
  local p = db.profile
  Print(string.format(
    L.STATUS_LINE or "enabled=%s · safe=%s · schema=%s · ver=%s",
    tostring(p.enabled),
    tostring(p.safeMode),
    tostring(db.schemaVersion),
    tostring(Config.VERSION)
  ))
  if db.lastDiag and db.lastDiag.card then
    print("|cffaaaaaa" .. tostring(db.lastDiag.card) .. "|r")
  end
  if #list == 0 then
    Print(L.NO_ERRORS or "no errors in ring")
    return
  end
  local from = math.max(1, #list - 9)
  for i = from, #list do
    local e = list[i]
    local n = e.count and e.count > 1 and (" ×" .. e.count) or ""
    print(string.format(
      "|cffd94a4a%d. [%s]%s %s|r",
      i,
      e.context or "?",
      n,
      e.msg or "?"
    ))
    if e.stack and e.stack ~= "" then
      for line in e.stack:gmatch("[^\n]+") do
        print("|cff888888  " .. line:sub(1, 160) .. "|r")
      end
    end
  end
end

local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == addonName then
    EnsureDB()
  elseif event == "PLAYER_LOGIN" then
    EnsureDB()
    ApplyModuleState()
    Print(string.format(L.LOADED or "loaded v%s · /pb", tostring(Config.VERSION)))
  end
end)

SLASH_PLATEBAND1 = "/pb"
SLASH_PLATEBAND2 = "/plateband"
SlashCmdList.PLATEBAND = function(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$") or ""
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = (cmd or "help"):lower()
  local db = EnsureDB()
  local p = db.profile

  if cmd == "help" or cmd == "?" then
    local lines = L.HELP_LINES
    if type(lines) == "table" then
      for i = 1, #lines do
        Print(lines[i])
      end
    end
    Print(string.format(
      L.STATUS_LINE or "enabled=%s · safe=%s · schema=%s · ver=%s",
      tostring(p.enabled),
      tostring(p.safeMode),
      tostring(db.schemaVersion),
      tostring(Config.VERSION)
    ))
    return
  end

  if cmd == "on" then
    p.enabled = true
    p.safeMode = false
    ApplyModuleState()
    Print(L.ENABLED or "band on")
    return
  end

  if cmd == "off" then
    p.enabled = false
    ApplyModuleState()
    Print(L.DISABLED or "band off")
    return
  end

  if cmd == "safe" then
    p.safeMode = true
    ApplyModuleState()
    Print(L.SAFE_ON or "safe mode — band cleared; /pb on to resume")
    return
  end

  if cmd == "reset" then
    Config.Reset()
    ApplyModuleState()
    Print(L.CONFIG_RESET or "config reset to defaults")
    return
  end

  if cmd == "diagnose" or cmd == "diag" then
    if not Plates or not Plates.Diagnose then
      Print("plates module missing")
      return
    end
    local card = SafeCall("diagnose", Plates.Diagnose)
    if card then
      print("|cff7ec8e3" .. card .. "|r")
    end
    return
  end

  if cmd == "dump" then
    DumpRing()
    if Plates and Plates.Diagnose then
      local card = SafeCall("dump:diagnose", Plates.Diagnose)
      if card then
        print("|cff7ec8e3" .. card .. "|r")
      end
    end
    return
  end

  if cmd == "size" then
    local n = tonumber(rest)
    if not n or n < 12 or n > 32 then
      Print(L.SIZE_BAD or "usage: /pb size <12-32>")
      return
    end
    p.iconSize = math.floor(n + 0.5)
    if Plates and Plates.Refresh then
      SafeCall("size:refresh", Plates.Refresh)
    end
    Print(string.format(L.SIZE_SET or "icon size hint: %d", p.iconSize))
    return
  end

  Print(L.UNKNOWN_CMD or "unknown command — /pb help")
end

-- Public hooks for other Forever tools
Plateband.Print = Print
Plateband.ApplyModuleState = ApplyModuleState
