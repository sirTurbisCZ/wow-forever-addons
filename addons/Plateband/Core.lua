--[[
  Plateband — above-plate shared harmful / DoT band.
  /pb settings|help|on|off|diagnose|dump|safe|reset|size|watch
]]

local addonName = ...

Plateband = Plateband or {}
Plateband.Modules = Plateband.Modules or {}

local L = Plateband.L or {}
local Config = Plateband.Config
local Plates = Plateband.Modules.Plates
local SessionLog = Plateband.Modules.SessionLog
local SelfTest = Plateband.Modules.SelfTest
local Settings = Plateband.Modules.Settings

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

Plateband.Print = Print

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

--- Error boundary → circular log + sessionLog (+ optional ForeverErrorLog).
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
      if SessionLog and SessionLog.Append then
        SessionLog.Append(string.format("ERROR ×%s [%s] %s", tostring(e.count), ctx, msg))
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

  if SessionLog and SessionLog.Append then
    SessionLog.Append(string.format("ERROR [%s] %s", ctx, msg))
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
  if SessionLog and SessionLog.FlushPaintTrace then
    pcall(SessionLog.FlushPaintTrace)
  end
  local db = EnsureDB()
  local list = db.errors
  local slog = db.sessionLog or {}
  local nLines = type(slog.lines) == "table" and #slog.lines or 0
  Print(string.format(
    L.DUMP_HEADER or "dump — errors=%d · sessionLog lines=%d",
    #list,
    nLines
  ))
  local p = db.profile
  Print(string.format(
    L.STATUS_LINE or "enabled=%s · safe=%s · watch=%s · schema=%s · ver=%s · log=%s",
    tostring(p.enabled),
    tostring(p.safeMode),
    tostring(p.watchOn),
    tostring(db.schemaVersion),
    tostring(Config.VERSION),
    tostring(nLines)
  ))
  Print(L.LOG_HINT or "diagnostics are in SavedVariables after /reload")
  if db.lastDiagnose and db.lastDiagnose.card then
    print("|cffaaaaaa" .. tostring(db.lastDiagnose.card) .. "|r")
  elseif db.lastDiag and db.lastDiag.card then
    print("|cffaaaaaa" .. tostring(db.lastDiag.card) .. "|r")
  end
  if #list == 0 then
    Print(L.NO_ERRORS or "no errors in ring")
  else
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
  local pt = db.paintTrace or {}
  local ptN = type(pt.entries) == "table" and #pt.entries or 0
  Print(string.format("paintTrace entries=%d (silent default)", ptN))
  if ptN > 0 then
    local from = math.max(1, ptN - 12)
    print("|cff888888--- paintTrace tail ---|r")
    for i = from, ptN do
      print("|cff888888" .. tostring(pt.entries[i]) .. "|r")
    end
  end
  if db.lastPaintTrace then
    print("|cffaaaaaa lastPaintTrace: " .. tostring(db.lastPaintTrace) .. "|r")
  end
  -- Tail of session log
  if nLines > 0 then
    local from = math.max(1, nLines - 7)
    print("|cff888888--- sessionLog tail ---|r")
    for i = from, nLines do
      print("|cff888888" .. tostring(slog.lines[i]) .. "|r")
    end
  end
end

local bootFrame = CreateFrame("Frame")
local loadAnnounced = false
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
bootFrame:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == addonName then
    EnsureDB()
    if Settings and Settings.CaptureBaseline then
      SafeCall("settings:baseline", Settings.CaptureBaseline)
    end
    if Settings and Settings.CreateMinimap then
      SafeCall("minimap:create", Settings.CreateMinimap)
    end
    if SessionLog and SessionLog.SyncRuntimeVersionFromInterface then
      pcall(SessionLog.SyncRuntimeVersionFromInterface)
    end
    local reloadLogin = false
    pcall(function()
      reloadLogin = IsLoggedIn and IsLoggedIn()
    end)
    if reloadLogin then
      if SessionLog and SessionLog.BeginSession then
        SafeCall("session:begin", SessionLog.BeginSession)
      end
      if SessionLog and SessionLog.RecordChatLoaded then
        SafeCall("session:chat_loaded", function()
          SessionLog.RecordChatLoaded("reload")
        end)
      end
      -- /reload does not fire PLAYER_LOGIN — must restart plate hooks here.
      ApplyModuleState()
      if not loadAnnounced then
        loadAnnounced = true
        Print(string.format(L.LOADED or "v%s · /pb", tostring(Config.VERSION)))
      end
    end
  elseif event == "PLAYER_LOGIN" then
    EnsureDB()
    if SessionLog and SessionLog.SyncRuntimeVersionFromInterface then
      pcall(SessionLog.SyncRuntimeVersionFromInterface)
    end
    if SessionLog and SessionLog.BeginSession then
      SafeCall("session:begin", SessionLog.BeginSession)
    end
    if SessionLog and SessionLog.RecordChatLoaded then
      SafeCall("session:chat_loaded", function()
        SessionLog.RecordChatLoaded("login")
      end)
    end
    ApplyModuleState()
    if not loadAnnounced then
      loadAnnounced = true
      Print(string.format(L.LOADED or "v%s · /pb", tostring(Config.VERSION)))
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    if SessionLog and SessionLog.EnsureChatTruthCurrent then
      SafeCall("session:chat_truth_pew", function()
        SessionLog.EnsureChatTruthCurrent("reload")
      end)
    end
    ApplyModuleState()
    if Plates and Plates.Refresh then
      SafeCall("plates:pew_refresh", Plates.Refresh)
    end
  end
end)

SLASH_PLATEBAND1 = "/pb"
SLASH_PLATEBAND2 = "/plateband"
SlashCmdList.PLATEBAND = function(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$") or ""
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  local db = EnsureDB()
  local p = db.profile
  if not cmd then
    if Settings and Settings.Toggle then
      SafeCall("settings:toggle", Settings.Toggle)
    end
    return
  end
  cmd = cmd:lower()

  if cmd == "settings" then
    if Settings and Settings.Toggle then
      SafeCall("settings:toggle", Settings.Toggle)
    end
    return
  end

  if cmd == "minimap" then
    local on = not (Settings and Settings.MinimapShown and Settings.MinimapShown())
    if Settings and Settings.SetMinimapShown then
      SafeCall("minimap:set", Settings.SetMinimapShown, on)
    end
    Print(on and "minimap button shown" or "minimap button hidden")
    return
  end

  if cmd == "help" or cmd == "?" then
    local lines = L.HELP_LINES
    if type(lines) == "table" then
      for i = 1, #lines do
        Print(lines[i])
      end
    end
    local nLines = db.sessionLog and db.sessionLog.lines and #db.sessionLog.lines or 0
    Print(string.format(
      L.STATUS_LINE or "enabled=%s · safe=%s · watch=%s · schema=%s · ver=%s · log=%s",
      tostring(p.enabled),
      tostring(p.safeMode),
      tostring(p.watchOn),
      tostring(db.schemaVersion),
      tostring(Config.VERSION),
      tostring(nLines)
    ))
    Print(L.LOG_HINT or "send Plateband.lua after /reload")
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
    if SessionLog and SessionLog.BeginSession then
      -- force new session after reset
      pcall(function()
        -- BeginSession is idempotent per load; append a reset marker
        SessionLog.Append("CONFIG_RESET")
      end)
    end
    ApplyModuleState()
    if Settings and Settings.ApplyMinimap then
      pcall(Settings.ApplyMinimap) -- the button follows the default (shown, default angle)
    end
    Print(L.CONFIG_RESET or "settings reset")
    return
  end

  if cmd == "watch" then
    local a = (rest or ""):lower()
    if a == "on" or a == "1" then
      if Plates and Plates.SetWatch then
        local card = SafeCall("watch:on", Plates.SetWatch, true)
        Print(string.format(L.WATCH_ON or "watch on — card every %ss", tostring(p.watchInterval or 2)))
        if card then
          print("|cff7ec8e3" .. card .. "|r")
        end
      end
    elseif a == "off" or a == "0" then
      if Plates and Plates.SetWatch then
        SafeCall("watch:off", Plates.SetWatch, false)
      end
      Print(L.WATCH_OFF or "watch off")
    else
      Print("usage: /pb watch on/off  (currently " .. tostring(p.watchOn) .. ")")
    end
    return
  end

  if cmd == "tree" then
    if Plates and Plates.DumpTree then
      SafeCall("tree", Plates.DumpTree)
    end
    return
  end

  if cmd == "ac" then
    -- EXPERIMENTAL (0.7.0): Blizzard-managed AuraContainer row instead of the collector row.
    local a = (rest or ""):lower()
    if a == "on" or a == "1" then
      p.useAuraContainer = true
      if Plates and Plates.SetAuraContainer then
        SafeCall("ac:on", Plates.SetAuraContainer, true)
      end
      Print(L.AC_ON or "AuraContainer row on (experimental)")
    elseif a == "off" or a == "0" then
      p.useAuraContainer = false
      if Plates and Plates.SetAuraContainer then
        SafeCall("ac:off", Plates.SetAuraContainer, false)
      end
      Print(L.AC_OFF or "AuraContainer row off - legacy row")
    elseif a ~= "status" and a ~= "" then
      Print(L.AC_USAGE or "usage: /pb ac on/off/status")
      return
    end
    local lines = Plates and Plates.AuraContainerStatus and SafeCall("ac:status", Plates.AuraContainerStatus)
    if type(lines) == "table" then
      for i = 1, #lines do
        Print(lines[i])
      end
    end
    return
  end

  if cmd == "dev" then
    local a = (rest or ""):lower()
    if a == "on" or a == "1" then
      p.silentTrace = true
      p.autoDiag = true
      Print(L.DEV_ON or "dev telemetry on")
    elseif a == "off" or a == "0" then
      p.silentTrace = false
      p.autoDiag = false
      Print(L.DEV_OFF or "dev telemetry off")
    else
      Print(string.format(L.DEV_USAGE or "usage: /pb dev on/off  (currently %s)", p.silentTrace and "on" or "off"))
    end
    return
  end

  if cmd == "selftest" then
    if not SelfTest or not SelfTest.Run then
      Print("SelfTest module missing")
      return
    end
    local pass, fail = SafeCall("selftest", SelfTest.Run)
    if pass and fail then
      Print(string.format("selftest pass=%s fail=%s (see sessionLog)", tostring(pass), tostring(fail)))
    end
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

  if cmd == "merge" then
    local a = (rest or ""):lower()
    if a == "on" or a == "1" then
      p.mergeMissing = true
      if Plates and Plates.Refresh then
        SafeCall("merge:on", Plates.Refresh)
      end
      Print(L.MERGE_ON or "merge on — foreign DoTs beside native DebuffList (enemy plates)")
    elseif a == "off" or a == "0" then
      p.mergeMissing = false
      if Plates and Plates.Refresh then
        SafeCall("merge:off", Plates.Refresh)
      end
      Print(L.MERGE_OFF or "merge off — native DebuffList only")
    else
      Print(string.format(
        L.MERGE_USAGE or "usage: /pb merge on/off  (currently %s)",
        p.mergeMissing and "on" or "off"
      ))
    end
    return
  end

  Print(L.UNKNOWN_CMD or "unknown command — /pb help")
end

Plateband.ApplyModuleState = ApplyModuleState
