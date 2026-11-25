--[[
  Plateband session log — friend-sendable diagnostics (silent by default).

  Primary store (Forever-safe, no io required):
    PlatebandDB.sessionLog + PlatebandDB.paintTrace
    → WTF/Account/<Account>/SavedVariables/Plateband.lua on /reload|logout

  Live agent feed (no /reload for CARD/PAINT):
    Interface/AddOns/Plateband/Logs/agent-live.log (append)
    Interface/AddOns/Plateband/Logs/agent-live-export.log (rolling tail, ~2s)
  Optional: session.log
  WTF SavedVariables still flush on logout/reload only — watch reads Logs/ first.
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
local PAINT_EXPORT_DEBOUNCE = 1.0
local LIVE_FLUSH_DEBOUNCE = 2.0
local IO_PROBE_SEC = 30
local paintExportDirty = false
local paintExportAt = 0
local liveFlushPending = false
local liveFlushTicker
local logDirty = false
local lastIoProbeAt = 0
local FILE_REL = "Interface/AddOns/Plateband/Logs/session.log"
local FILE_REL_BS = [[Interface\AddOns\Plateband\Logs\session.log]]
local AGENT_LIVE_REL = "Interface/AddOns/Plateband/Logs/agent-live.log"
local AGENT_LIVE_BS = [[Interface\AddOns\Plateband\Logs\agent-live.log]]
local AGENT_EXPORT_REL = "Interface/AddOns/Plateband/Logs/agent-live-export.log"
local AGENT_EXPORT_BS = [[Interface\AddOns\Plateband\Logs\agent-live-export.log]]
local LIVE_TAIL_LINES = 120
local AGENT_PULSE_SEC = 2.0

local fileOk -- nil=untried, false=unavailable, true=works
local agentIoOk = false
local sessionBegun = false
local agentPulseTicker

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

local function EnsureAgentLive(db)
  if type(db.agentLive) ~= "table" then
    db.agentLive = { seq = 0, ver = "", at = 0, io = "sv_only", lines = 0 }
  end
  return db.agentLive
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

local function RebuildPaintExport(pt)
  local out = {}
  local start = math.max(1, #pt.entries - 79)
  for i = start, #pt.entries do
    out[#out + 1] = pt.entries[i]
  end
  pt.export = table.concat(out, "\n")
  paintExportDirty = false
  paintExportAt = Now()
end

local function IsAgentLine(line)
  if not line or line == "" then
    return false
  end
  if line:find("PLATEBAND_CARD", 1, true) or line:find("SESSION_START", 1, true) then
    return true
  end
  if line:find("PLATES_LOAD", 1, true) or line:sub(1, 6) == "PAINT " then
    return true
  end
  if line:find("AGENT_LIVE", 1, true) then
    return true
  end
  return false
end

local function UpsertAgentLiveStamped(stamped)
  local log = EnsureLogTable()
  local n = #(log.lines or {})
  if n > 0 then
    local last = log.lines[n]
    if type(last) == "string" and last:find("AGENT_LIVE", 1, true) then
      log.lines[n] = stamped
      return
    end
  end
  log.lines[#log.lines + 1] = stamped
  while #log.lines > MAX_LINES do
    table.remove(log.lines, 1)
  end
end

local function MaybeReprobeIo()
  if agentIoOk and fileOk then
    return
  end
  local now = Now()
  if (now - lastIoProbeAt) < IO_PROBE_SEC then
    return
  end
  lastIoProbeAt = now
  if not fileOk then
    Mod.ProbeFile()
  end
  if not agentIoOk and io and io.open then
    local f = TryOpen(AGENT_LIVE_REL, "a")
    if f then
      pcall(function()
        f:close()
      end)
      agentIoOk = true
    end
  end
end

local function TryAppendAgentLive(stamped)
  local paths = { AGENT_LIVE_REL, AGENT_LIVE_BS }
  for i = 1, #paths do
    local f = TryOpen(paths[i], "a")
    if f then
      local ok = pcall(function()
        f:write(stamped)
        f:write("\n")
        f:close()
      end)
      if ok then
        agentIoOk = true
        return true
      end
    end
  end
  return false
end

function Mod.FlushLiveExport()
  local log = EnsureLogTable()
  if type(log.lines) ~= "table" or #log.lines == 0 then
    return false
  end
  local start = math.max(1, #log.lines - LIVE_TAIL_LINES + 1)
  local body = table.concat(log.lines, "\n", start, #log.lines)
  local paths = { AGENT_EXPORT_REL, AGENT_EXPORT_BS }
  for i = 1, #paths do
    local f = TryOpen(paths[i], "w")
    if f then
      local ok = pcall(function()
        f:write(body)
        if body:sub(-1) ~= "\n" then
          f:write("\n")
        end
        f:close()
      end)
      if ok then
        agentIoOk = true
        logDirty = false
        return true
      end
    end
  end
  return false
end

function Mod.ScheduleLiveFlush()
  if liveFlushPending then
    return
  end
  liveFlushPending = true
  if C_Timer and C_Timer.After then
    C_Timer.After(LIVE_FLUSH_DEBOUNCE, function()
      liveFlushPending = false
      pcall(Mod.FlushLiveExport)
    end)
  else
    liveFlushPending = false
    pcall(Mod.FlushLiveExport)
  end
end

function Mod.EnsureLiveFlushTicker()
  if liveFlushTicker or not C_Timer or not C_Timer.NewTicker then
    return
  end
  liveFlushTicker = C_Timer.NewTicker(5, function()
    if logDirty then
      pcall(Mod.FlushLiveExport)
    end
    if paintExportDirty then
      pcall(Mod.FlushPaintTrace)
    end
  end)
end

--- 2s runtime truth for agents — SV agentLive + rolling AGENT_LIVE in session export.
function Mod.PulseAgentLive()
  local db = ns.Config.EnsureDB()
  local al = EnsureAgentLive(db)
  local log = EnsureLogTable()
  al.seq = (tonumber(al.seq) or 0) + 1
  al.ver = tostring(ns.Config and ns.Config.VERSION or "?")
  al.at = Now()
  al.io = (agentIoOk or fileOk) and "file" or "sv_only"
  al.lines = #(log.lines or {})
  local body = string.format("AGENT_LIVE ver=%s seq=%s io=%s lines=%s", al.ver, tostring(al.seq), al.io, tostring(al.lines))
  local stamped = string.format("[%s] %s", tostring(Now()), body)
  UpsertAgentLiveStamped(stamped)
  log.export = table.concat(log.lines, "\n")
  logDirty = true
  MaybeReprobeIo()
  if body:find("AGENT_LIVE", 1, true) then
    TryAppendAgentLive(stamped)
    Mod.ScheduleLiveFlush()
  end
end

function Mod.EnsureAgentPulseTicker()
  if agentPulseTicker or not C_Timer or not C_Timer.NewTicker then
    return
  end
  pcall(Mod.PulseAgentLive)
  agentPulseTicker = C_Timer.NewTicker(AGENT_PULSE_SEC, function()
    pcall(Mod.PulseAgentLive)
  end)
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
  paintExportDirty = true
  local now = Now()
  if (now - paintExportAt) >= PAINT_EXPORT_DEBOUNCE then
    RebuildPaintExport(pt)
  end
end

function Mod.FlushPaintTrace()
  local db = ns.Config.EnsureDB()
  local pt = EnsurePaintTrace(db)
  if paintExportDirty or pt.export == "" then
    RebuildPaintExport(pt)
  end
  return pt.export
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
  Mod.EnsureLiveFlushTicker()
  Mod.EnsureAgentPulseTicker()
  pcall(Mod.FlushLiveExport)
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
  MaybeReprobeIo()
  log.fileOk = AppendFile(stamped) or log.fileOk
  log.export = table.concat(log.lines, "\n")
  logDirty = true
  if IsAgentLine(line) then
    TryAppendAgentLive(stamped)
    Mod.ScheduleLiveFlush()
  end
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
  -- Mirror into sessionLog.export for agent SV grep (paintTrace alone is easy to miss).
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
    agentIo = agentIoOk and true or false,
  }
end

return Mod