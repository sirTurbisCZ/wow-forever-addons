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
-- Forever io allowlist: *agent-live*.log works; *live-head* / felog-live-head are blocked.
local AGENT_HEAD_REL = "Interface/AddOns/Plateband/Logs/agent-live-head.log"
local AGENT_HEAD_BS = [[Interface\AddOns\Plateband\Logs\agent-live-head.log]]
local RUNTIME_VER_REL = "Interface/AddOns/Plateband/Logs/runtime-ver.log"
local RUNTIME_VER_BS = [[Interface\AddOns\Plateband\Logs\runtime-ver.log]]
local LIVE_HEAD_REL = "Interface/AddOns/Plateband/Logs/live-head.log"
local LIVE_HEAD_BS = [[Interface\AddOns\Plateband\Logs\live-head.log]]
local FELOG_HEAD_REL = "Interface/AddOns/ForeverErrorLog/Logs/live-head.log"
local FELOG_HEAD_BS = [[Interface\AddOns\ForeverErrorLog\Logs\live-head.log]]
local FELOG_BRIDGE_REL = "Interface/AddOns/Plateband/Logs/felog-live-head.log"
local FELOG_BRIDGE_BS = [[Interface\AddOns\Plateband\Logs\felog-live-head.log]]
local FELOG_EXPORT_REL = "Interface/AddOns/ForeverErrorLog/Logs/agent-live-export.log"
local FELOG_EXPORT_BS = [[Interface\AddOns\ForeverErrorLog\Logs\agent-live-export.log]]
local FELOG_STREAM_REL = "Interface/AddOns/ForeverErrorLog/Logs/live-stream.log"
local FELOG_STREAM_BS = [[Interface\AddOns\ForeverErrorLog\Logs\live-stream.log]]
local LIVE_TAIL_LINES = 120
local AGENT_PULSE_SEC = 2.0
local PLATEBAND_TOC = "Plateband"
local FELOG_TOC = "ForeverErrorLog"

local function TocVersion(addon, configFallback)
  if type(GetAddOnMetadata) == "function" then
    local ok, v = pcall(GetAddOnMetadata, addon, "Version")
    if ok and v and tostring(v) ~= "" then
      return tostring(v)
    end
  end
  if configFallback ~= nil and tostring(configFallback) ~= "" then
    return tostring(configFallback)
  end
  return "?"
end

local fileOk -- nil=untried, false=unavailable, true=works
local agentIoOk = false
local sessionBegun = false
local agentPulseTicker
local exportTruthTicker
local felogPending = {}
local FELG_PENDING_MAX = 80
local felogHooked

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

--- Append-only probe — live feed must not depend on session.log truncate (Forever).
function Mod.ProbeAgentIo()
  if not (io and io.open) then
    agentIoOk = false
    return false
  end
  local paths = { AGENT_LIVE_REL, AGENT_LIVE_BS }
  for i = 1, #paths do
    local f = TryOpen(paths[i], "a")
    if f then
      pcall(function()
        f:close()
      end)
      agentIoOk = true
      return true
    end
  end
  agentIoOk = false
  return false
end

--- Optional session.log wipe (legacy); agent feed is independent.
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
  if line:find("CHAT_LOADED", 1, true) or line:find("RUNTIME_VER", 1, true) then
    return true
  end
  return false
end

local function WriteLineToPaths(paths, line, mode)
  if not line or line == "" or not (io and io.open) then
    return false
  end
  mode = mode or "w"
  for i = 1, #paths do
    local f = TryOpen(paths[i], mode)
    if f then
      local ok = pcall(function()
        f:write(line)
        if line:sub(-1) ~= "\n" then
          f:write("\n")
        end
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

local function TryWriteWholeFile(paths, body)
  if not body or body == "" or not (io and io.open) then
    return false
  end
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
        return true
      end
    end
  end
  return false
end

--- Forever io: only exact agent-live-export.log is writable (not agent-live-head.log).
local function DiscoverIoAllowlist(db)
  if db.ioAllowName == "sv_only" then
    local now = Now()
    if (now - (db.ioAllowLastProbe or 0)) < IO_PROBE_SEC then
      return "sv_only"
    end
    db.ioAllowName = nil
    db.ioAllowLastProbe = now
  elseif db.ioAllowName and db.ioAllowName ~= "" then
    return db.ioAllowName
  end
  local probe = string.format("IO_PROBE export t=%s", tostring(Now()))
  if TryWriteWholeFile({ AGENT_EXPORT_REL, AGENT_EXPORT_BS }, probe) then
    db.ioAllowName = "export"
    return "export"
  end
  if TryWriteWholeFile({ AGENT_HEAD_REL, AGENT_HEAD_BS }, probe) then
    db.ioAllowName = "head"
    return "head"
  end
  if WriteLineToPaths({ AGENT_LIVE_REL, AGENT_LIVE_BS }, probe, "a") then
    db.ioAllowName = "live"
    return "live"
  end
  db.ioAllowName = "sv_only"
  return "sv_only"
end

function Mod.BuildChatTruthLine(src, load, seq)
  src = tostring(src or "CHAT_LOADED")
  load = tostring(load or "reload")
  seq = tonumber(seq) or 0
  local pbVer = TocVersion(PLATEBAND_TOC, ns.Config and ns.Config.VERSION)
  local feVer = TocVersion(FELOG_TOC, ForeverErrorLog and ForeverErrorLog.Config and ForeverErrorLog.Config.VERSION)
  return string.format(
    "live_ver=%s plateband_ver=%s felog_ver=%s seq=%s src=%s load=%s t=%s feed=pb_bridge",
    pbVer,
    pbVer,
    feVer,
    tostring(seq),
    src,
    load,
    tostring(Now())
  )
end

--- Single write path: line 1 live_ver= + session tail in agent-live-export + SV export blob.
function Mod.SyncLiveExportFile(src, load, seq)
  local db = ns.Config.EnsureDB()
  local log = EnsureLogTable()
  local line = Mod.BuildChatTruthLine(src, load, seq)
  db.chatTruthLine = line
  db.chatTruthAt = Now()
  local start = math.max(1, #log.lines - LIVE_TAIL_LINES + 1)
  local tail = (type(log.lines) == "table" and #log.lines > 0)
      and table.concat(log.lines, "\n", start, #log.lines)
      or ""
  local body = tail ~= "" and (line .. "\n" .. tail) or line
  log.export = body
  logDirty = false
  local wrote = false
  DiscoverIoAllowlist(db)
  if TryWriteWholeFile({ AGENT_EXPORT_REL, AGENT_EXPORT_BS }, body) then
    agentIoOk = true
    wrote = true
  end
  if db.ioAllowName == "head" then
    wrote = TryWriteWholeFile({ AGENT_HEAD_REL, AGENT_HEAD_BS }, line) or wrote
  end
  return wrote
end

function Mod.EnsureExportTruthTicker()
  if exportTruthTicker or not C_Timer or not C_Timer.NewTicker then
    return
  end
  pcall(Mod.SyncLiveExportFile, "EXPORT_PULSE", "pulse", 0)
  exportTruthTicker = C_Timer.NewTicker(AGENT_PULSE_SEC, function()
    local db = ns.Config.EnsureDB()
    local seq = 0
    if type(db.agentLive) == "table" then
      seq = tonumber(db.agentLive.seq) or 0
    end
    pcall(Mod.SyncLiveExportFile, "EXPORT_PULSE", "pulse", seq)
  end)
end

--- Primary chat-truth: line 1 of agent-live-export (+ optional head file when io allows).
function Mod.WriteAgentLiveHead(line)
  line = tostring(line or "")
  if line == "" then
    return false
  end
  local db = ns.Config.EnsureDB()
  local log = EnsureLogTable()
  db.chatTruthLine = line
  db.chatTruthAt = Now()
  local allow = DiscoverIoAllowlist(db)
  local body = line
  if type(log.lines) == "table" and #log.lines > 0 then
    body = line .. "\n" .. table.concat(log.lines, "\n")
  end
  local wrote = false
  if allow == "export" or allow == "sv_only" then
    wrote = TryWriteWholeFile({ AGENT_EXPORT_REL, AGENT_EXPORT_BS }, body) or wrote
  end
  if allow == "head" then
    wrote = TryWriteWholeFile({ AGENT_HEAD_REL, AGENT_HEAD_BS }, line) or wrote
  end
  if wrote then
    logDirty = false
    return true
  end
  return false
end

--- Forever blocks io under ForeverErrorLog/; Plateband can write those paths.
--- Unified head: chat truth (Plateband + FElog TOC versions), ≤2s on CHAT_LOADED + 2s pulse.
function Mod.PublishChatTruthHead(src, load, seq)
  src = tostring(src or "CHAT_LOADED")
  load = tostring(load or "reload")
  seq = tonumber(seq) or 0
  local pbVer = tostring(ns.Config and ns.Config.VERSION or "?")
  local feVer = "?"
  if ForeverErrorLog and ForeverErrorLog.Config and ForeverErrorLog.Config.VERSION then
    feVer = tostring(ForeverErrorLog.Config.VERSION)
  end
  local line = Mod.BuildChatTruthLine(src, load, seq)
  local ok = Mod.SyncLiveExportFile(src, load, seq)
  if not ok then
    ok = Mod.MirrorFelogLogs(line, nil, nil)
  end
  pcall(Mod.WriteLiveHeadFile, pbVer, seq, src, load)
  if ForeverErrorLog and ForeverErrorLog.ApplyLiveHeadSnapshot then
    pcall(ForeverErrorLog.ApplyLiveHeadSnapshot, pbVer, feVer, src, load, seq)
  end
  return ok
end

function Mod.MirrorFelogLogs(headLine, exportBody, streamLine)
  local ok = false
  if headLine and headLine ~= "" then
    if WriteLineToPaths({ FELOG_HEAD_REL, FELOG_HEAD_BS }, headLine, "w") then
      ok = true
    end
    if WriteLineToPaths({ FELOG_BRIDGE_REL, FELOG_BRIDGE_BS }, headLine, "w") then
      ok = true
    end
  end
  if type(exportBody) == "string" and exportBody ~= "" then
    if WriteLineToPaths({ FELOG_EXPORT_REL, FELOG_EXPORT_BS }, exportBody, "w") then
      ok = true
    end
  end
  if type(streamLine) == "string" and streamLine ~= "" then
    if WriteLineToPaths({ FELOG_STREAM_REL, FELOG_STREAM_BS }, streamLine, "a") then
      ok = true
    end
  end
  return ok
end

--- One-line live truth for agents (≤2s after /reload, no SV flush).
function Mod.WriteLiveHeadFile(ver, seq, src, load)
  ver = tostring(ver or (ns.Config and ns.Config.VERSION) or "?")
  seq = tostring(seq or "0")
  src = tostring(src or "chat")
  load = tostring(load or "-")
  local line = string.format(
    "live_ver=%s seq=%s src=%s load=%s t=%s deployed=%s",
    ver,
    seq,
    src,
    load,
    tostring(Now()),
    ver
  )
  local paths = { LIVE_HEAD_REL, LIVE_HEAD_BS }
  for i = 1, #paths do
    local f = TryOpen(paths[i], "w")
    if f then
      local ok = pcall(function()
        f:write(line)
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

function Mod.TryWriteRuntimeVerFile(ver)
  ver = tostring(ver or (ns.Config and ns.Config.VERSION) or "?")
  local line = string.format("RUNTIME_VER ver=%s t=%s", ver, tostring(Now()))
  local paths = { RUNTIME_VER_REL, RUNTIME_VER_BS }
  for i = 1, #paths do
    local f = TryOpen(paths[i], "w")
    if f then
      local ok = pcall(function()
        f:write(line)
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

--- Runtime stamp — every load (login + /reload); SV + Logs before WTF flush.
function Mod.RecordChatLoaded(src)
  src = tostring(src or "login")
  local ver = tostring(ns.Config and ns.Config.VERSION or "?")
  local db = ns.Config.EnsureDB()
  local at = Now()
  db.runtimeVer = { ver = ver, at = at, src = "chat", load = src }
  db.liveHead = string.format(
    "ver=%s seq=0 at=%s io=sv_only src=chat load=%s",
    ver,
    tostring(at),
    src
  )
  pcall(Mod.ProbeAgentIo)
  Mod.Append(string.format("CHAT_LOADED ver=%s src=%s", ver, src))
  Mod.Append(string.format("RUNTIME_VER ver=%s src=chat load=%s", ver, src))
  pcall(Mod.TryWriteRuntimeVerFile, ver)
  if ForeverErrorLog and ForeverErrorLog.NotifyRuntime then
    pcall(ForeverErrorLog.NotifyRuntime, "Plateband", ver, src, "CHAT_LOADED")
  end
  pcall(Mod.PublishChatTruthHead, "CHAT_LOADED", src, 0)
  pcall(Mod.SyncLiveExportFile, "CHAT_LOADED", src, 0)
  Mod.EnsureExportTruthTicker()
  pcall(Mod.PulseAgentLive)
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
  local now = Now()
  if (now - lastIoProbeAt) < IO_PROBE_SEC then
    return
  end
  lastIoProbeAt = now
  if not agentIoOk then
    pcall(Mod.ProbeAgentIo)
  end
  if not fileOk then
    pcall(Mod.ProbeFile)
  end
end

local function FlushFelogPending()
  local feed = ForeverErrorLog and ForeverErrorLog.AgentFeed
  if not feed then
    return
  end
  for i = 1, #felogPending do
    pcall(feed, "Plateband", felogPending[i])
  end
  felogPending = {}
end

local function EnsureFelogBridgeHook()
  if felogHooked then
    return
  end
  felogHooked = true
  if not CreateFrame then
    return
  end
  local f = CreateFrame("Frame")
  f:RegisterEvent("ADDON_LOADED")
  f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == "ForeverErrorLog" then
      FlushFelogPending()
    end
  end)
  if ForeverErrorLog and ForeverErrorLog.AgentFeed then
    FlushFelogPending()
  end
end

--- Always mirror agent lines to FElog SV (sessionLog.agentExport) — not only when Plateband io fails.
local function MirrorToFelog(line)
  EnsureFelogBridgeHook()
  local feed = ForeverErrorLog and ForeverErrorLog.AgentFeed
  if feed then
    pcall(feed, "Plateband", line)
    return
  end
  felogPending[#felogPending + 1] = line
  while #felogPending > FELG_PENDING_MAX do
    table.remove(felogPending, 1)
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
  local db = ns.Config.EnsureDB()
  local seq = 0
  if type(db.agentLive) == "table" then
    seq = tonumber(db.agentLive.seq) or 0
  end
  return Mod.SyncLiveExportFile("FLUSH", "pulse", seq)
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
  db.liveHead = string.format(
    "ver=%s seq=%s at=%s io=%s src=chat",
    al.ver,
    tostring(al.seq),
    tostring(al.at),
    al.io
  )
  local body = string.format("AGENT_LIVE ver=%s seq=%s io=%s lines=%s", al.ver, tostring(al.seq), al.io, tostring(al.lines))
  local stamped = string.format("[%s] %s", tostring(Now()), body)
  UpsertAgentLiveStamped(stamped)
  log.export = table.concat(log.lines, "\n")
  logDirty = true
  MaybeReprobeIo()
  pcall(Mod.TryWriteRuntimeVerFile, al.ver)
  if not TryAppendAgentLive(stamped) then
    MirrorToFelog(body)
  end
  pcall(Mod.PublishChatTruthHead, "AGENT_LIVE", "pulse", al.seq)
  Mod.ScheduleLiveFlush()
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
  local agentIo = Mod.ProbeAgentIo()
  pcall(Mod.ProbeFile)
  log.fileOk = (agentIo or fileOk) and true or false
  local ver = tostring(ns.Config.VERSION)
  local header = string.format(
    "SESSION_START ver=%s t=%s file=%s silent=1",
    ver,
    tostring(log.startedAt),
    agentIo and "file" or "sv_only"
  )
  db.runtimeVer = {
    ver = ver,
    at = log.startedAt,
    src = "session",
    load = "addon",
  }
  db.liveHead = string.format(
    "ver=%s seq=0 at=%s io=%s src=session load=addon",
    ver,
    tostring(log.startedAt),
    agentIo and "file" or "sv_only"
  )
  pcall(Mod.PublishChatTruthHead, "SESSION_START", "addon", 0)
  Mod.Append(header)
  pcall(Mod.TryWriteRuntimeVerFile, ver)
  pcall(Mod.SyncLiveExportFile, "SESSION_START", "addon", 0)
  Mod.EnsureLiveFlushTicker()
  Mod.EnsureAgentPulseTicker()
  Mod.EnsureExportTruthTicker()
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
  if fileOk then
    log.fileOk = AppendFile(stamped) or log.fileOk
  end
  log.export = table.concat(log.lines, "\n")
  logDirty = true
  if IsAgentLine(line) then
    if not TryAppendAgentLive(stamped) then
      MirrorToFelog(line)
    end
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