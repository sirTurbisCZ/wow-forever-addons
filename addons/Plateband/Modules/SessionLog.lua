--[[
  Plateband session log — friend-sendable diagnostics (silent by default).

  Primary store (Forever-safe, no io required):
    PlatebandDB.sessionLog + PlatebandDB.paintTrace
    → WTF/Account/<Account>/SavedVariables/Plateband.lua on /reload|logout

  Optional file when io exists:
    Interface/AddOns/Plateband/Logs/session.log
]]

Plateband = Plateband or {}
Plateband.Modules = Plateband.Modules or {}

local ns = Plateband
local Mod = {}
ns.Modules.SessionLog = Mod
ns.SessionLog = Mod

local MAX_LINES = 500
local MAX_PAINT = 200
local MAX_LINE = 600
local FILE_REL = "Interface/AddOns/Plateband/Logs/session.log"
local FILE_REL_BS = [[Interface\AddOns\Plateband\Logs\session.log]]

local fileOk -- nil=untried, false=unavailable, true=works
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
    db.sessionLog = { startedAt = 0, lines = {}, fileOk = false, export = "" }
  end
  if type(db.sessionLog.lines) ~= "table" then
    db.sessionLog.lines = {}
  end
  return db.sessionLog
end

local function EnsurePaintTrace(db)
  if type(db.paintTrace) ~= "table" then
    db.paintTrace = { startedAt = 0, entries = {}, export = "" }
  end
  if type(db.paintTrace.entries) ~= "table" then
    db.paintTrace.entries = {}
  end
  return db.paintTrace
end

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

--- Attempt wipe/create session.log. Returns true if file IO works.
function Mod.ProbeFile()
  if fileOk == false then
    return false
  end
  if not (io and io.open) then
    fileOk = false
    return false
  end
  local paths = { FILE_REL, FILE_REL_BS }
  for i = 1, #paths do
    local f = TryOpen(paths[i], "w")
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

local function AppendFile(line)
  if fileOk == false or not (io and io.open) then
    return false
  end
  if fileOk == nil then
    Mod.ProbeFile()
  end
  if not fileOk then
    return false
  end
  local paths = { FILE_REL, FILE_REL_BS }
  for i = 1, #paths do
    local f = TryOpen(paths[i], "a")
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

local function PushPaintEntry(line)
  local db = ns.Config.EnsureDB()
  local pt = EnsurePaintTrace(db)
  local stamped = string.format("[%s] %s", tostring(Now()), line)
  pt.entries[#pt.entries + 1] = stamped
  while #pt.entries > MAX_PAINT do
    table.remove(pt.entries, 1)
  end
  db.lastPaintTrace = line
  local out = {}
  local start = math.max(1, #pt.entries - 79)
  for i = start, #pt.entries do
    out[#out + 1] = pt.entries[i]
  end
  pt.export = table.concat(out, "\n")
end

--- Cold start: wipe session log (SV + optional file). Call once per ADDON_LOADED.
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
  local pt = EnsurePaintTrace(db)
  pt.startedAt = Now()
  pt.entries = {}
  pt.export = ""
  db.lastPaintTrace = nil
  local wroteFile = Mod.ProbeFile()
  log.fileOk = wroteFile and true or false
  local header = string.format(
    "SESSION_START ver=%s t=%s file=%s silent=1",
    tostring(ns.Config.VERSION),
    tostring(log.startedAt),
    wroteFile and "yes" or "sv_only"
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
  log.fileOk = AppendFile(stamped) or log.fileOk
  log.export = table.concat(log.lines, "\n")
end

--- Silent paint trace — PAINT / PLATE lines only (no chat).
function Mod.RecordPaint(line)
  line = Trim(line, MAX_LINE)
  if line == "" then
    return
  end
  if line:sub(1, 6) ~= "PAINT " and line:sub(1, 6) ~= "PLATE " then
    line = "PAINT " .. line
  end
  PushPaintEntry(line)
  Mod.Append(line)
end

function Mod.Status()
  local log = EnsureLogTable()
  local db = ns.Config.EnsureDB()
  local pt = type(db.paintTrace) == "table" and db.paintTrace or {}
  return {
    lines = #(log.lines or {}),
    startedAt = log.startedAt,
    fileOk = log.fileOk and true or false,
    paintEntries = #(pt.entries or {}),
  }
end

return Mod