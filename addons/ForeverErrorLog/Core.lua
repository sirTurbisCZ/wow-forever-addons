--[[
  Forever Error Log — lean capture of Lua errors into SavedVariables.
  /felog help|list|dump|clear|reset  (+ on|off, ui on|off)
]]

local addonName = ...

ForeverErrorLog = ForeverErrorLog or {}

local L = ForeverErrorLog.L or {}
local Config = ForeverErrorLog.Config

local installed
local originalHandler
local sessionBegun = false
local fileOk -- nil untried / false / true

local function EnsureDB()
  return Config.EnsureDB()
end

local function Print(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring(select(i, ...))
  end
  print((L.PREFIX or "[FElog]") .. " " .. table.concat(parts, " "))
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

local FILE_REL = "Interface/AddOns/ForeverErrorLog/Logs/session.log"
local FILE_REL_BS = [[Interface\AddOns\ForeverErrorLog\Logs\session.log]]

local function TryOpen(path, mode)
  if not (io and io.open) then
    return nil
  end
  local ok, f = pcall(io.open, path, mode)
  if ok then
    return f
  end
  return nil
end

local function ProbeSessionFile()
  if fileOk == false then
    return false
  end
  if not (io and io.open) then
    fileOk = false
    return false
  end
  for _, path in ipairs({ FILE_REL, FILE_REL_BS }) do
    local f = TryOpen(path, "w")
    if f then
      pcall(function()
        f:write("")
        f:close()
      end)
      fileOk = true
      return true
    end
  end
  fileOk = false
  return false
end

local function AppendSessionFile(line)
  if fileOk == false or not (io and io.open) then
    return false
  end
  if fileOk == nil then
    ProbeSessionFile()
  end
  if not fileOk then
    return false
  end
  for _, path in ipairs({ FILE_REL, FILE_REL_BS }) do
    local f = TryOpen(path, "a")
    if f then
      local ok = pcall(function()
        f:write(line)
        f:write("\n")
        f:close()
      end)
      if ok then
        return true
      end
    end
  end
  fileOk = false
  return false
end

local function AppendSession(line)
  local db = EnsureDB()
  local log = db.sessionLog
  if type(log) ~= "table" then
    return
  end
  if type(log.lines) ~= "table" then
    log.lines = {}
  end
  line = Trim(line, 500)
  local stamped = string.format("[%s] %s", tostring(Now()), line)
  log.lines[#log.lines + 1] = stamped
  local maxN = Config.MAX_SESSION_LINES or 200
  while #log.lines > maxN do
    table.remove(log.lines, 1)
  end
  log.export = table.concat(log.lines, "\n")
  log.fileOk = AppendSessionFile(stamped) or log.fileOk
end

--- Wipe session log on cold load. Error ring is kept across sessions.
local function BeginSession()
  if sessionBegun then
    return
  end
  sessionBegun = true
  local db = EnsureDB()
  local wrote = ProbeSessionFile()
  db.sessionLog = {
    startedAt = Now(),
    lines = {},
    fileOk = wrote and true or false,
    export = "",
  }
  AppendSession(string.format(
    "SESSION_START ver=%s file=%s",
    tostring(Config.VERSION or "?"),
    wrote and "yes" or "sv_only"
  ))
end

local function AddonFromMessage(msg)
  if type(msg) ~= "string" then
    return "?"
  end
  local add = msg:match("[/\\]AddOns[/\\]([^/\\]+)")
  if add then
    return add
  end
  add = msg:match("AddOns\\([^\\]+)")
  if add then
    return add
  end
  return "?"
end

local function Record(msg, stack)
  local db = EnsureDB()
  if not db.enabled then
    return
  end
  local maxMsg = Config.MAX_MSG
  msg = Trim(msg, maxMsg)
  stack = Trim(stack or "", maxMsg)
  local list = db.errors
  for i = 1, #list do
    local e = list[i]
    if e.msg == msg then
      e.count = (e.count or 1) + 1
      e.last = Now()
      if stack ~= "" then
        e.stack = stack
      end
      AppendSession(string.format("ERROR ×%s [%s] %s", tostring(e.count), tostring(e.addon or "?"), msg))
      return
    end
  end
  list[#list + 1] = {
    msg = msg,
    stack = stack,
    addon = AddonFromMessage(msg),
    first = Now(),
    last = Now(),
    count = 1,
  }
  while #list > Config.MAX_ERRORS do
    table.remove(list, 1)
  end
  AppendSession(string.format("ERROR [%s] %s", tostring(AddonFromMessage(msg)), msg))
  local short = msg
  if #short > 180 then
    short = short:sub(1, 177) .. "..."
  end
  Print(tostring(AddonFromMessage(msg)) .. ": " .. short)
end

local function FormatEntry(e, i)
  local n = e.count and e.count > 1 and (" ×" .. e.count) or ""
  return string.format("%d. [%s]%s %s", i, e.addon or "?", n, e.msg or "?")
end

local function ListSummary()
  local db = EnsureDB()
  local list = db.errors
  if #list == 0 then
    Print(L.NO_ERRORS or "no errors stored")
    return
  end
  Print(string.format(L.LIST_HEADER or "%d error(s) — last 15:", #list))
  local from = math.max(1, #list - 14)
  for i = from, #list do
    print("|cffaaaaaa" .. FormatEntry(list[i], i) .. "|r")
  end
  Print(L.DUMP_HINT or "full text is in ForeverErrorLogDB")
end

local function DumpRecent()
  local db = EnsureDB()
  local list = db.errors
  if #list == 0 then
    Print(L.NO_ERRORS or "no errors stored")
    return
  end
  local from = math.max(1, #list - 9)
  for i = from, #list do
    local e = list[i]
    print("|cffd94a4a" .. FormatEntry(e, i) .. "|r")
    if e.stack and e.stack ~= "" then
      for line in e.stack:gmatch("[^\n]+") do
        print("|cff888888  " .. line:sub(1, 180) .. "|r")
      end
    end
  end
end

local function SetScriptErrorsCVar(on)
  local value = on and "1" or "0"
  if C_CVar and C_CVar.SetCVar then
    pcall(C_CVar.SetCVar, "scriptErrors", value)
  elseif SetCVar then
    pcall(SetCVar, "scriptErrors", value)
  end
end

local function SuppressScriptErrorsPopup()
  local db = EnsureDB()
  db.scriptErrors = false
  SetScriptErrorsCVar(false)
  if ScriptErrorsFrame then
    pcall(function()
      if ScriptErrorsFrame.Hide then
        ScriptErrorsFrame:Hide()
      end
      if type(ScriptErrorsFrame.messageCount) == "number" then
        ScriptErrorsFrame.messageCount = 0
      end
      if type(ScriptErrorsFrame.messages) == "table" and wipe then
        wipe(ScriptErrorsFrame.messages)
      end
      if ScriptErrorsFrame.index then
        ScriptErrorsFrame.index = 0
      end
    end)
  end
end

local function InstallHandler()
  -- Idempotent within a session (ADDON_LOADED + PLAYER_LOGIN).
  if installed then
    return
  end
  installed = true
  originalHandler = geterrorhandler and geterrorhandler() or nil

  if BugGrabber and BugGrabber.RegisterCallback then
    pcall(function()
      BugGrabber.RegisterCallback(addonName, "BugGrabber_BugGrabbed", function(_, err)
        if type(err) == "table" then
          Record(err.message or err.error or tostring(err), err.stack or "")
        else
          Record(tostring(err), "")
        end
      end)
    end)
    local db = EnsureDB()
    if db.silentBoot == false then
      Print(L.BUGGRABBER or "hooked into BugGrabber")
    else
      AppendSession("INFO hooked BugGrabber silentBoot=1")
    end
    return
  end

  if type(seterrorhandler) ~= "function" then
    local db = EnsureDB()
    if db.silentBoot == false then
      Print(L.NO_SETHANDLER or "seterrorhandler missing")
    else
      AppendSession("WARN seterrorhandler missing")
    end
    return
  end

  seterrorhandler(function(msg)
    local stack = ""
    if debugstack then
      local ok, s = pcall(debugstack, 3)
      if ok then
        stack = s or ""
      end
    end
    pcall(Record, msg, stack)
    local db = EnsureDB()
    if db.scriptErrors then
      if originalHandler then
        return originalHandler(msg)
      end
      if ScriptErrorsFrame and ScriptErrorsFrame.DisplayMessage then
        pcall(ScriptErrorsFrame.DisplayMessage, ScriptErrorsFrame, msg)
      end
    end
  end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == addonName then
    EnsureDB()
    BeginSession()
    InstallHandler()
  elseif event == "PLAYER_LOGIN" then
    EnsureDB()
    BeginSession()
    InstallHandler()
    SuppressScriptErrorsPopup()
    local db = ForeverErrorLogDB
    local n = #(db.errors or {})
    if db.silentBoot == false then
      if n > 0 then
        Print(string.format(L.LOADED_COUNT or "loaded — %d stored", n))
      else
        Print(L.LOADED_EMPTY or "loaded — capturing to log, popup off · /felog")
      end
    elseif n > 0 then
      Print(string.format(L.LOADED_COUNT or "loaded — %d stored", n))
    end
  end
end)

-- Public API for other Forever addons (optional)
ForeverErrorLog.Record = function(msg, stack)
  Record(msg, stack)
end
ForeverErrorLog.Count = function()
  return #(EnsureDB().errors or {})
end
ForeverErrorLog.GetErrors = function()
  return EnsureDB().errors
end

SLASH_FOREVERERRORLOG1 = "/felog"
SLASH_FOREVERERRORLOG2 = "/ferrors"
SLASH_FOREVERERRORLOG3 = "/forevererrors"
SlashCmdList.FOREVERERRORLOG = function(msg)
  msg = (msg or ""):match("^%s*(.-)%s*$") or ""
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = (cmd or "help"):lower()
  local db = EnsureDB()

  if cmd == "help" or cmd == "?" then
    local lines = L.HELP_LINES
    if type(lines) == "table" then
      for i = 1, #lines do
        Print(lines[i])
      end
    end
    Print(string.format(
      L.STATUS_LINE or "stored: %d · enabled=%s · schema=%s",
      #(db.errors or {}),
      tostring(db.enabled),
      tostring(db.schemaVersion)
    ))
    return
  end

  if cmd == "list" or cmd == "ls" then
    ListSummary()
    return
  end

  if cmd == "dump" then
    DumpRecent()
    return
  end

  if cmd == "clear" then
    db.errors = {}
    db.lastExport = nil
    Print(L.LOG_CLEARED or "log cleared")
    return
  end

  if cmd == "reset" then
    Config.Reset()
    SuppressScriptErrorsPopup()
    Print(L.CONFIG_RESET or "config reset to defaults (log cleared)")
    return
  end

  if cmd == "on" then
    db.enabled = true
    Print(L.CAPTURE_ON or "capture on")
    return
  end

  if cmd == "off" then
    db.enabled = false
    Print(L.CAPTURE_OFF or "capture off")
    return
  end

  if cmd == "ui" then
    local a = (rest or ""):lower()
    if a == "on" or a == "1" then
      db.scriptErrors = true
      SetScriptErrorsCVar(true)
      Print(L.UI_ON or "scriptErrors popup on")
    elseif a == "off" or a == "0" then
      db.scriptErrors = false
      SetScriptErrorsCVar(false)
      Print(L.UI_OFF or "scriptErrors popup off")
    else
      Print(string.format(L.UI_STATUS or "scriptErrors preference: %s", tostring(db.scriptErrors)))
    end
    return
  end

  Print(L.UNKNOWN_CMD or "unknown command — /felog help")
end
