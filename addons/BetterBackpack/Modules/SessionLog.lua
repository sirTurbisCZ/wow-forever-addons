--[[
  BetterBackpack session log — silent diagnostics (Forever-safe, no io required).

  Primary store:
    BetterBackpackDB.sessionLog + BetterBackpackDB.actionTrace
    → WTF/Account/<Account>/SavedVariables/BetterBackpack.lua
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local ns = BetterBackpack
local Mod = {}
ns.Modules.SessionLog = Mod
ns.SessionLog = Mod

local MAX_LINES = 500
local MAX_ACTION = 200
local MAX_LINE = 600

local sessionBegun = false

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

local function EnsureLogTable()
  local db = ns.Config.EnsureDB()
  if type(db.sessionLog) ~= "table" then
    db.sessionLog = { startedAt = 0, lines = {}, export = "" }
  end
  if type(db.sessionLog.lines) ~= "table" then
    db.sessionLog.lines = {}
  end
  return db.sessionLog
end

local function EnsureActionTrace(db)
  if type(db.actionTrace) ~= "table" then
    db.actionTrace = { startedAt = 0, entries = {}, export = "" }
  end
  if type(db.actionTrace.entries) ~= "table" then
    db.actionTrace.entries = {}
  end
  return db.actionTrace
end

local function PushActionEntry(line)
  local db = ns.Config.EnsureDB()
  local at = EnsureActionTrace(db)
  local stamped = string.format("[%s] %s", tostring(Now()), line)
  at.entries[#at.entries + 1] = stamped
  while #at.entries > MAX_ACTION do
    table.remove(at.entries, 1)
  end
  db.lastActionTrace = line
  local out = {}
  local start = math.max(1, #at.entries - 79)
  for i = start, #at.entries do
    out[#out + 1] = at.entries[i]
  end
  at.export = table.concat(out, "\n")
end

function Mod.BeginSession()
  if sessionBegun then
    return EnsureLogTable()
  end
  sessionBegun = true
  local db = ns.Config.EnsureDB()
  local log = EnsureLogTable()
  log.startedAt = Now()
  log.lines = {}
  log.export = ""
  local at = EnsureActionTrace(db)
  at.startedAt = Now()
  at.entries = {}
  at.export = ""
  db.lastActionTrace = nil
  local header = string.format(
    "SESSION_START ver=%s t=%s silent=1",
    tostring(ns.Config.VERSION),
    tostring(log.startedAt)
  )
  Mod.Append(header)
  return log
end

function Mod.Append(line)
  line = Trim(line, MAX_LINE)
  if line == "" then
    return
  end
  local log = EnsureLogTable()
  if not sessionBegun then
    sessionBegun = true
    if type(log.lines) ~= "table" or #log.lines == 0 then
      log.startedAt = Now()
      log.lines = {}
    end
  end
  local stamped = string.format("[%s] %s", tostring(Now()), line)
  log.lines[#log.lines + 1] = stamped
  while #log.lines > MAX_LINES do
    table.remove(log.lines, 1)
  end
  log.export = table.concat(log.lines, "\n")
end

--- ACTION lines for bulk sell / vendor / layout (no chat).
function Mod.RecordAction(line)
  line = Trim(line, MAX_LINE)
  if line == "" then
    return
  end
  if line:sub(1, 7) ~= "ACTION " then
    line = "ACTION " .. line
  end
  if ns.Config and ns.Config.VERSION then
    if not line:find("ver=", 1, true) then
      line = line .. " ver=" .. tostring(ns.Config.VERSION)
    end
  end
  PushActionEntry(line)
  Mod.Append(line)
end

function Mod.Status()
  local log = EnsureLogTable()
  local db = ns.Config.EnsureDB()
  local at = type(db.actionTrace) == "table" and db.actionTrace or {}
  return {
    lines = #(log.lines or {}),
    startedAt = log.startedAt,
    actionEntries = #(at.entries or {}),
  }
end

return Mod