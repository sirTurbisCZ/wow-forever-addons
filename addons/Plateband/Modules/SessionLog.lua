--[[
  Plateband session log — small, bounded diagnostics stored in SavedVariables only
  (the Forever client has no `io`, so nothing here writes files).

  Always on (cheap): ERROR lines in PlatebandDB.sessionLog (last MAX_LINES).
  Dev telemetry (profile.silentTrace, default OFF — `/pb dev on`):
    PAINT/PLATE trace -> PlatebandDB.paintTrace (+ copy of every line in sessionLog),
    exports for the host scripts, mirror to ForeverErrorLog (when its own dev flag is on).
]]

Plateband = Plateband or {}
Plateband.Modules = Plateband.Modules or {}

local ns = Plateband
local Mod = {}
ns.Modules.SessionLog = Mod
ns.SessionLog = Mod

local MAX_LINES = 300
local MAX_PAINT = 200
local MAX_LINE = 600
local PAINT_EXPORT_DEBOUNCE = 1.0

local sessionBegun = false
local paintExportDirty = false
local paintExportAt = 0

local function Now()
  if time then
    return time()
  end
  return 0
end

local function Trim(s, maxLen)
  s = tostring(s or "")
  if #s > maxLen then
    return s:sub(1, maxLen - 3) .. "..."
  end
  return s
end

local function DB()
  return ns.Config.EnsureDB()
end

local function DevOn()
  local ok, p = pcall(ns.Config.GetProfile)
  return ok and type(p) == "table" and p.silentTrace == true
end
Mod.DevOn = DevOn

local function EnsureLogTable()
  local db = DB()
  if type(db.sessionLog) ~= "table" then
    db.sessionLog = { startedAt = 0, lines = {}, export = "" }
  end
  local log = db.sessionLog
  if type(log.lines) ~= "table" then
    log.lines = {}
  end
  if type(log.export) ~= "string" then
    log.export = ""
  end
  return log
end

local function EnsurePaintTrace(db)
  if type(db.paintTrace) ~= "table" then
    db.paintTrace = { startedAt = 0, entries = {}, export = "" }
  end
  local pt = db.paintTrace
  if type(pt.entries) ~= "table" then
    pt.entries = {}
  end
  if type(pt.export) ~= "string" then
    pt.export = ""
  end
  return pt
end

local function RebuildPaintExport(pt)
  paintExportDirty = false
  paintExportAt = Now()
  pt.export = table.concat(pt.entries, "\n")
end

--- Runtime version = the loaded Config.VERSION (there is no io to compare against disk).
function Mod.SyncRuntimeVersionFromInterface()
  return tostring((ns.Config and ns.Config.VERSION) or "?")
end

--- Wipe the session log once per load.
function Mod.BeginSession()
  if sessionBegun then
    return EnsureLogTable()
  end
  sessionBegun = true
  local db = DB()
  local log = EnsureLogTable()
  log.startedAt = Now()
  log.lines = {}
  log.export = ""
  local pt = EnsurePaintTrace(db)
  pt.startedAt = Now()
  pt.entries = {}
  pt.export = ""
  db.lastPaintTrace = nil
  Mod.Append(string.format("SESSION_START ver=%s t=%s", Mod.SyncRuntimeVersionFromInterface(), tostring(log.startedAt)))
  return log
end

local function IsAgentLine(line)
  return line:sub(1, 6) == "PAINT " or line:sub(1, 6) == "PLATE " or line:find("PLATEBAND_CARD", 1, true) ~= nil
    or line:find("CHAT_LOADED", 1, true) ~= nil or line:find("SESSION_START", 1, true) ~= nil
end

--- Append one line. ERROR lines are always kept; everything else only with dev telemetry on.
function Mod.Append(line)
  line = Trim(line, MAX_LINE)
  if line == "" then
    return
  end
  local dev = DevOn()
  if not dev and line:sub(1, 5) ~= "ERROR" and line:sub(1, 13) ~= "SESSION_START" then
    return
  end
  local log = EnsureLogTable()
  if not sessionBegun then
    sessionBegun = true
    log.startedAt = Now()
  end
  local stamped = string.format("[%s] %s", tostring(Now()), line)
  log.lines[#log.lines + 1] = stamped
  while #log.lines > MAX_LINES do
    table.remove(log.lines, 1)
  end
  if dev then
    log.export = table.concat(log.lines, "\n")
    if IsAgentLine(line) and ForeverErrorLog and ForeverErrorLog.AgentFeed then
      pcall(ForeverErrorLog.AgentFeed, "Plateband", line)
    end
  end
end

--- Chat "loaded" bookkeeping, once per login / reload.
function Mod.RecordChatLoaded(src)
  src = tostring(src or "login")
  local ver = Mod.SyncRuntimeVersionFromInterface()
  local db = DB()
  db.runtimeVer = { ver = ver, at = Now(), src = "chat", load = src }
  -- Fresh error ring per load (FELog archives its own ring itself; its reset is idempotent per load).
  if type(db.errors) == "table" and wipe then
    wipe(db.errors)
  end
  if DevOn() then
    db.chatTruthLine = string.format("CHAT_LOADED ver=%s src=%s t=%s", ver, src, tostring(Now()))
    Mod.Append(string.format("CHAT_LOADED ver=%s src=%s", ver, src))
    if ForeverErrorLog and ForeverErrorLog.NotifyRuntime then
      pcall(ForeverErrorLog.NotifyRuntime, "Plateband", ver, "CHAT_LOADED", src)
    end
  else
    db.chatTruthLine = nil
  end
end

--- Kept for Core's PEW hook: nothing to re-verify without io.
function Mod.EnsureChatTruthCurrent()
  return Mod.SyncRuntimeVersionFromInterface()
end

--- Silent paint trace (dev telemetry): PAINT / PLATE lines only (no chat).
function Mod.RecordPaint(line)
  if not DevOn() then
    return
  end
  line = Trim(line, MAX_LINE)
  if line == "" then
    return
  end
  if line:sub(1, 6) ~= "PAINT " and line:sub(1, 6) ~= "PLATE " then
    line = "PAINT " .. line
  end
  local db = DB()
  local pt = EnsurePaintTrace(db)
  pt.entries[#pt.entries + 1] = string.format("[%s] %s", tostring(Now()), line)
  while #pt.entries > MAX_PAINT do
    table.remove(pt.entries, 1)
  end
  db.lastPaintTrace = line
  paintExportDirty = true
  if (Now() - paintExportAt) >= PAINT_EXPORT_DEBOUNCE then
    RebuildPaintExport(pt)
  end
  -- Also mirror into the session log (agent grep convenience, dev only).
  Mod.Append(line)
end

function Mod.FlushPaintTrace()
  local pt = EnsurePaintTrace(DB())
  if paintExportDirty or pt.export == "" then
    RebuildPaintExport(pt)
  end
  return pt.export
end

function Mod.Status()
  local log = EnsureLogTable()
  local pt = EnsurePaintTrace(DB())
  return {
    lines = #log.lines,
    startedAt = log.startedAt,
    paintEntries = #pt.entries,
    dev = DevOn(),
  }
end
