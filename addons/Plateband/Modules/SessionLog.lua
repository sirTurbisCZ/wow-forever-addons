--[[
  Plateband session log — friend-sendable diagnostics (silent by default).

  Primary store (Forever-safe, no io required):
    PlatebandDB.sessionLog + PlatebandDB.paintTrace
    → WTF/Account/<Account>/SavedVariables/Plateband.lua on /reload|logout

  Live agent feed:
    SV chatTruthLine + sessionLog/paintTrace (primary; WTF flush lag OK)
    Optional disk: one CHAT_LOADED write to agent-live-export.log when io allowlist permits
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
-- Architecture live-telemetry-options: no OnUpdate/C_Timer disk heartbeat (default off).
local CONTINUOUS_DISK_PULSE = false
local PLATEBAND_TOC = "Plateband"
local FELOG_TOC = "ForeverErrorLog"
local PB_TOC_FILE = "Interface/AddOns/Plateband/Plateband.toc"
local PB_TOC_BS = [[Interface\AddOns\Plateband\Plateband.toc]]
local FE_TOC_FILE = "Interface/AddOns/ForeverErrorLog/ForeverErrorLog.toc"
local FE_TOC_BS = [[Interface\AddOns\ForeverErrorLog\ForeverErrorLog.toc]]
local PB_CFG_FILE = "Interface/AddOns/Plateband/Config.lua"
local PB_CFG_BS = [[Interface\AddOns\Plateband\Config.lua]]
local FE_CFG_FILE = "Interface/AddOns/ForeverErrorLog/Config.lua"
local FE_CFG_BS = [[Interface\AddOns\ForeverErrorLog\Config.lua]]
local INTERFACE_TOC_STAMP = "Interface/AddOns/Plateband/Logs/interface-toc.ver"
local INTERFACE_TOC_STAMP_BS = [[Interface\AddOns\Plateband\Logs\interface-toc.ver]]

local function ParseVersionFromText(text)
  if not text or text == "" then
    return nil
  end
  local v = text:match("## Version:%s*([%d%.]+)")
  if v then
    return tostring(v)
  end
  v = text:match('Config%.VERSION%s*=%s*"([%d%.]+)"')
  if v then
    return tostring(v)
  end
  return nil
end

--- Read Interface AddOns files every call — no SV/runtime cache.
local function ReadInterfaceAddonVersion(paths)
  if not (io and io.open) then
    return nil
  end
  for i = 1, #paths do
    local f = TryOpen(paths[i], "r")
    if f then
      local ok, text = pcall(function()
        local body = f:read("*a") or ""
        f:close()
        return body
      end)
      if ok then
        local ver = ParseVersionFromText(text)
        if ver then
          return ver
        end
      end
    end
  end
  return nil
end

local function ReadTocStampVersion()
  if not (io and io.open) then
    return nil, nil
  end
  for i = 1, 2 do
    local path = i == 1 and INTERFACE_TOC_STAMP or INTERFACE_TOC_STAMP_BS
    local f = TryOpen(path, "r")
    if f then
      local ok, line = pcall(function()
        local l = f:read("*l") or ""
        f:close()
        return l
      end)
      if ok and line ~= "" then
        local pb = line:match("pb=([%d%.]+)")
        local fe = line:match("fe=([%d%.]+)")
        return pb, fe
      end
    end
  end
  return nil, nil
end

local function PickVersion(...)
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v and tostring(v) ~= "" and tostring(v) ~= "?" then
      return tostring(v)
    end
  end
  return nil
end

local function VerParts(v)
  local a, b, c = tostring(v or "0.0.0"):match("^(%d+)%.(%d+)%.(%d+)")
  return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

local function VerNewer(a, b)
  if not a or a == "" then
    return b
  end
  if not b or b == "" then
    return a
  end
  local a1, a2, a3 = VerParts(a)
  local b1, b2, b3 = VerParts(b)
  if a1 ~= b1 then
    return a1 > b1 and a or b
  end
  if a2 ~= b2 then
    return a2 > b2 and a or b
  end
  if a3 ~= b3 then
    return a3 > b3 and a or b
  end
  return a
end

local function BestVersion(...)
  local best
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v and tostring(v) ~= "" and tostring(v) ~= "?" then
      best = VerNewer(best, tostring(v))
    end
  end
  return best
end

local function QueryAddonMetadataVersion(addon)
  if type(GetAddOnMetadata) == "function" then
    local ok, v = pcall(GetAddOnMetadata, addon, "Version")
    if ok and v and tostring(v) ~= "" then
      return tostring(v)
    end
  end
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, addon, "Version")
    if ok and v and tostring(v) ~= "" then
      return tostring(v)
    end
  end
  if type(GetNumAddOns) == "function" and type(GetAddOnInfo) == "function" and type(GetAddOnMetadata) == "function" then
    local ok, n = pcall(GetNumAddOns)
    if ok and type(n) == "number" then
      for i = 1, n do
        local ok2, name = pcall(GetAddOnInfo, i)
        if ok2 and name == addon then
          local ok3, v = pcall(GetAddOnMetadata, i, "Version")
          if ok3 and v and tostring(v) ~= "" then
            return tostring(v)
          end
        end
      end
    end
  end
  return nil
end

--- Same strings as chat `loaded v%s` — always live `Plateband.Config` / `ForeverErrorLog.Config`.
function Mod.ChatLoadedVersions()
  local pbVer = tostring((Plateband.Config and Plateband.Config.VERSION) or (ns.Config and ns.Config.VERSION) or "?")
  local feVer = "?"
  if C_AddOns and C_AddOns.LoadAddOn then
    pcall(C_AddOns.LoadAddOn, "ForeverErrorLog")
  end
  pcall(function()
    if ForeverErrorLog and ForeverErrorLog.Config and ForeverErrorLog.Config.VERSION then
      feVer = tostring(ForeverErrorLog.Config.VERSION)
    end
  end)
  return pbVer, feVer
end

function Mod.ResolveExportVersions()
  local pbVer, feVer = Mod.ChatLoadedVersions()
  return pbVer, feVer, pbVer, feVer
end

local function ExportDiskStaleSec()
  local db = ns.Config.EnsureDB()
  local at = tonumber(db.ioExportDiskAt) or 0
  if at <= 0 then
    return 999
  end
  return UnixTs() - at
end

local function TryExportDiskLine(line, isRetry)
  local wrote = Mod.WriteExportL1Brute(line, true)
  if not wrote and not isRetry and C_Timer and C_Timer.After then
    local retryLine = line
    C_Timer.After(0.05, function()
      exportDiskLastGt = 0
      pcall(TryExportDiskLine, retryLine, true)
    end)
  end
  if wrote then
    MarkExportDiskAttempt()
    pcall(Mod.PublishInterfaceTocStamp)
  end
  return wrote
end

local function NoteExportIoDiag(db, ok, why)
  if type(db.exportIoDiag) ~= "table" then
    db.exportIoDiag = { ok = 0, fail = 0, lastWhy = "", lastOkGt = 0, lastFailGt = 0 }
  end
  local d = db.exportIoDiag
  if ok then
    d.ok = (tonumber(d.ok) or 0) + 1
    d.lastOkGt = (GetTime and GetTime()) or 0
    d.lastWhy = ""
  else
    d.fail = (tonumber(d.fail) or 0) + 1
    d.lastFailGt = (GetTime and GetTime()) or 0
    d.lastWhy = tostring(why or "?")
  end
  d.lastAt = Now()
end

local function AppendExportPulseLine(line)
  line = tostring(line or "")
  if line == "" or not (io and io.open) then
    return false
  end
  local paths = { EXPORT_PULSE_REL, EXPORT_PULSE_BS }
  for i = 1, #paths do
    for _, mode in ipairs({ "a", "w" }) do
      if WriteLineToPaths({ paths[i] }, line, mode) then
        return true
      end
    end
  end
  local stamped = string.format("[%s] EXPORT_PULSE_LINE %s", tostring(Now()), line)
  if WriteLineToPaths({ AGENT_LIVE_REL, AGENT_LIVE_BS }, stamped, "a") then
    return true
  end
  local db = ns.Config.EnsureDB()
  db.exportPulseTail = line
  db.exportPulseAt = Now()
  return false
end

local function ScheduleLoginExportPulses()
  exportDiskLastGt = 0
  local function go()
    exportDiskLastGt = 0
    pcall(DoExportDiskPulse)
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0.05, go)
    C_Timer.After(0.35, go)
    C_Timer.After(1.0, go)
    C_Timer.After(2.0, go)
  else
    go()
  end
end

--- Legacy continuous pulse — disabled unless CONTINUOUS_DISK_PULSE.
local function DoExportDiskPulse()
  if not CONTINUOUS_DISK_PULSE then
    return false
  end
  HydrateExportTimeAnchor()
  local loginBoost = GetTime and exportLoginBoostUntil > 0 and GetTime() <= exportLoginBoostUntil
  local stale = ExportDiskStaleSec()
  if not loginBoost and stale < EXPORT_DISK_MIN_SEC and not ExportDiskThrottleOk() then
    return false
  end
  local db = ns.Config.EnsureDB()
  pcall(ProbeExportL1Write)
  db.exportPulseSeq = (tonumber(db.exportPulseSeq) or 0) + 1
  local line = CommitChatTruthLine(Mod.BuildChatTruthLine("EXPORT_PULSE", "pulse", db.exportPulseSeq))
  local wrote = TryExportDiskLine(line)
  if not wrote then
    exportDiskLastGt = 0
    line = CommitChatTruthLine(Mod.BuildChatTruthLine("EXPORT_PULSE", "pulse", db.exportPulseSeq))
    wrote = TryWriteWholeFile({ AGENT_EXPORT_REL, AGENT_EXPORT_BS }, line) or false
    if wrote then
      db.chatTruthLine = line
      db.ioExportDiskLine = line
      db.ioExportDiskOk = true
      db.ioAllowName = "export"
      pcall(AppendExportPulseLine, line)
      MarkExportDiskAttempt()
    end
  end
  local final = tostring(db.ioExportDiskLine or db.chatTruthLine or line)
  if wrote then
    NoteExportIoDiag(db, true, "ok")
  else
    NoteExportIoDiag(db, false, "export_open")
  end
  pcall(AppendExportPulseLine, final)
  return wrote
end

local function QueueExportDiskPulse()
  if not CONTINUOUS_DISK_PULSE then
    return
  end
  if exportPulseQueued then
    return
  end
  exportPulseQueued = true
  local function run()
    exportPulseQueued = false
    pcall(DoExportDiskPulse)
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, run)
  else
    run()
  end
end

function Mod.ExportDiskPulse()
  QueueExportDiskPulse()
  return true
end

function Mod.PulseExportDiskTick(_fromEvent)
  QueueExportDiskPulse()
  return true
end

--- SV every tick; disk L1 at most once per 2s (bypassThrottle=true ignores window).
function Mod.ForceDiskExportL1(bypassThrottle)
  if not CONTINUOUS_DISK_PULSE then
    return false
  end
  if not bypassThrottle then
    return Mod.PulseExportDiskTick()
  end
  local line = BumpChatTruthSV("EXPORT_PULSE", "pulse")
  return TryExportDiskLine(line)
end

--- PLAYER_LOGIN + /reload: SV chatTruthLine + one disk attempt (no retry spam).
function Mod.LoginDiskExportOnce(loadKind)
  loadKind = tostring(loadKind or "reload")
  exportDiskLastGt = 0
  pcall(Mod.ResetExportTimeAnchor)
  local db = ns.Config.EnsureDB()
  local line = BumpChatTruthSV("CHAT_LOADED", loadKind)
  db.telemetryMode = "login_disk_once"
  if not (io and io.open) then
    db.ioAllowName = "sv_only"
    db.ioExportDiskOk = false
    NoteExportIoDiag(db, false, "no_io")
    return false
  end
  pcall(Mod.ResetExportIoGate)
  local wrote = TryExportDiskLine(line)
  if not wrote then
    wrote = TryWriteWholeFile({ AGENT_EXPORT_REL, AGENT_EXPORT_BS }, line .. "\n") or false
  end
  if wrote then
    db.ioAllowName = "export"
    db.ioExportDiskOk = true
    db.ioExportDiskLine = line
    db.exportLoginDiskAt = Now()
    NoteExportIoDiag(db, true, "login_once")
  else
    db.ioAllowName = "sv_only"
    db.ioExportDiskOk = false
    db.exportLoginDiskAt = Now()
    NoteExportIoDiag(db, false, "export_open")
  end
  return wrote
end

function Mod.FlushChatLoadedExport(loadKind)
  return Mod.LoginDiskExportOnce(loadKind)
end

function Mod.RefreshChatTruthSV(src, load)
  return BumpChatTruthSV(src, load)
end

function Mod.LiveInterfaceVersions()
  return Mod.ResolveExportVersions()
end

--- Writable stamp when AddOns/ tree is read-only — refreshed from ResolveExportVersions each pulse.
function Mod.PublishInterfaceTocStamp()
  local pbVer, feVer = Mod.ResolveExportVersions()
  if not pbVer or not feVer then
    return
  end
  local line = string.format("pb=%s fe=%s t=%s", pbVer, feVer, tostring(Now()))
  WriteLineToPaths({ INTERFACE_TOC_STAMP, INTERFACE_TOC_STAMP_BS }, line, "w")
end

local function TocVersion(addon, configFallback)
  if addon == PLATEBAND_TOC or addon == FELOG_TOC then
    local pb, fe = Mod.LiveInterfaceVersions()
    if addon == PLATEBAND_TOC then
      return pb
    end
    return fe
  end
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
local exportTruthArmed = false
local ioPulseFrame
local ioPulseLastGt = 0
local worldPulseHooked = false
local exportBurstAt = 0
local exportDriverFrame
local exportEventsRegistered = false
local EXPORT_TICK = 2.0
local EXPORT_DISK_MIN_SEC = 1.85
local exportDiskLastGt = 0
local memExportEpoch = nil
local memExportGt = nil
local exportPulseQueued = false
local exportLoginBoostUntil = 0
local BumpChatTruthSV
local ExportDiskThrottleOk
local MarkExportDiskAttempt
local EXPORT_PULSE_REL = "Interface/AddOns/Plateband/Logs/export-pulse.log"
local EXPORT_PULSE_BS = [[Interface\AddOns\Plateband\Logs\export-pulse.log]]
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

local function RawWallEpoch()
  if C_Date and C_Date.GetServerTime then
    local ok, n = pcall(C_Date.GetServerTime)
    if ok and type(n) == "number" and n > 0 then
      return math.floor(n)
    end
  end
  if os and os.time then
    local ok, n = pcall(os.time)
    if ok and type(n) == "number" and n > 0 then
      return math.floor(n)
    end
  end
  if time then
    return time()
  end
  return 0
end

local function HydrateExportTimeAnchor()
  if memExportEpoch and memExportGt and GetTime and GetTime() >= memExportGt then
    return
  end
  local db = ns.Config.EnsureDB()
  local base = tonumber(db.exportUnixEpoch)
  local gt0 = tonumber(db.exportLoadGt)
  if type(base) == "number" and base > 0 and type(gt0) == "number" and GetTime and GetTime() >= gt0 then
    memExportEpoch = base
    memExportGt = gt0
    return
  end
  pcall(Mod.ResetExportTimeAnchor)
end

--- Forever: frozen `time()` — wall = memEpoch + (GetTime() - memGt); never hydrate bad SV gt0 > GetTime().
local function UnixTs()
  if not GetTime then
    return RawWallEpoch()
  end
  HydrateExportTimeAnchor()
  if type(memExportEpoch) == "number" and memExportEpoch > 0 and type(memExportGt) == "number" then
    local gt = GetTime()
    if gt < memExportGt then
      pcall(Mod.ResetExportTimeAnchor)
      gt = GetTime()
    end
    return math.floor(memExportEpoch + (gt - memExportGt))
  end
  pcall(Mod.ResetExportTimeAnchor)
  if type(memExportEpoch) == "number" and type(memExportGt) == "number" then
    return math.floor(memExportEpoch + (GetTime() - memExportGt))
  end
  return RawWallEpoch()
end

local function Now()
  return UnixTs()
end

function Mod.ResetExportTimeAnchor()
  memExportEpoch = RawWallEpoch()
  memExportGt = (GetTime and GetTime()) or 0
  local db = ns.Config.EnsureDB()
  db.exportUnixEpoch = memExportEpoch
  db.exportLoadGt = memExportGt
end

local function ParseLineT(line)
  return tonumber(tostring(line or ""):match("t=(%d+)"))
end

local function StampExportLineT(line)
  line = tostring(line or "")
  local ts = tostring(UnixTs())
  if line:find("t=", 1, true) then
    return (line:gsub("(t=)(%d+)", "%1" .. ts, 1))
  end
  return line .. " t=" .. ts
end

--- One stamped line for disk + PlatebandDB.chatTruthLine (same `t=`).
local function CommitChatTruthLine(line)
  line = StampExportLineT(line)
  local db = ns.Config.EnsureDB()
  local ts = ParseLineT(line) or Now()
  db.chatTruthLine = line
  db.chatTruthAt = ts
  local log = EnsureLogTable()
  log.export = line
  return line, ts
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

ExportDiskThrottleOk = function()
  if not GetTime then
    return true
  end
  return (GetTime() - exportDiskLastGt) >= EXPORT_DISK_MIN_SEC
end

MarkExportDiskAttempt = function()
  if GetTime then
    exportDiskLastGt = GetTime()
  end
end

BumpChatTruthSV = function(src, load)
  local db = ns.Config.EnsureDB()
  db.exportPulseSeq = (tonumber(db.exportPulseSeq) or 0) + 1
  local seq = db.exportPulseSeq
  db.exportPulseAt = Now()
  db.exportPulseN = seq
  local line = CommitChatTruthLine(Mod.BuildChatTruthLine(src or "EXPORT_PULSE", load or "pulse", seq))
  local pbVer, feVer = Mod.ResolveExportVersions()
  db.interfacePbVer = pbVer
  db.interfaceFeVer = feVer
  local log = EnsureLogTable()
  log.export = line
  return line
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
  if ok and f then
    return f
  end
  return nil
end

function Mod.ResetExportIoGate()
  local db = ns.Config.EnsureDB()
  db.ioAllowName = nil
  db.ioAllowLastProbe = 0
  db.ioExportDiskOk = nil
  db.ioExportDiskFailAt = nil
  agentIoOk = nil
end

local function ProbeExportL1Write()
  local db = ns.Config.EnsureDB()
  pcall(Mod.ResetExportIoGate)
  if not (io and io.open) then
    db.ioExportDiskOk = false
    db.exportIoProbeWhy = "no_io"
    return false
  end
  local probe = string.format("live_ver=%s src=IO_PROBE load=probe t=%s feed=pb_bridge", tostring(ns.Config.VERSION), tostring(Now()))
  if TryWriteWholeFile({ AGENT_EXPORT_REL, AGENT_EXPORT_BS }, probe) then
    db.ioAllowName = "export"
    db.ioExportDiskOk = true
    db.exportIoProbeAt = Now()
    db.exportIoProbeWhy = ""
    return true
  end
  db.ioExportDiskOk = false
  db.exportIoProbeWhy = "agent-live-export_open"
  return false
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
        if f.flush then
          f:flush()
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

--- One L1 write per throttle window; always rebuild from Config.VERSION + fresh t=.
function Mod.WriteExportL1Brute(line, throttleBypass)
  if not (io and io.open) then
    return false
  end
  if not throttleBypass and not ExportDiskThrottleOk() and ExportDiskStaleSec() < EXPORT_DISK_MIN_SEC then
    return false
  end
  HydrateExportTimeAnchor()
  local db = ns.Config.EnsureDB()
  local hint = tostring(line or "")
  local src = hint:match("src=([^%s]+)") or "EXPORT_PULSE"
  local load = hint:match("load=([^%s]+)") or "pulse"
  local seq = tonumber(db.exportPulseSeq) or tonumber(hint:match("seq=([^%s]+)")) or 0
  line = CommitChatTruthLine(Mod.BuildChatTruthLine(src, load, seq))
  db.interfacePbVer, db.interfaceFeVer = Mod.ChatLoadedVersions()
  local f, openPath, openMode = nil, nil, nil
  local tryPaths = { AGENT_EXPORT_REL, AGENT_EXPORT_BS }
  local tryModes = { "w", "wb" }
  for pi = 1, #tryPaths do
    for mi = 1, #tryModes do
      f = TryOpen(tryPaths[pi], tryModes[mi])
      if f then
        openPath, openMode = tryPaths[pi], tryModes[mi]
        break
      end
    end
    if f then
      break
    end
  end
  if not f then
    NoteExportIoDiag(db, false, "agent-live-export_open")
    return false
  end
  line = CommitChatTruthLine(line)
  local ts = ParseLineT(line) or Now()
  local ok = pcall(function()
    f:write(line)
    f:write("\n")
    if f.flush then
      f:flush()
    end
    f:close()
  end)
  if ok then
    agentIoOk = true
    db.ioAllowName = "export"
    pcall(AppendExportPulseLine, line)
    db.ioExportDiskAt = ts
    db.ioExportDiskOk = true
    db.ioExportDiskLine = line
    db.ioExportPath = tostring(openPath or "")
    db.ioExportMode = tostring(openMode or "")
    db.chatTruthLine = line
    db.chatTruthAt = ts
    local log = EnsureLogTable()
    log.export = line
    NoteExportIoDiag(db, true, "agent-live-export")
    return true
  end
  NoteExportIoDiag(db, false, "agent-live-export_write")
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
        if f.flush then
          f:flush()
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
  local pbVer, feVer = Mod.ChatLoadedVersions()
  local pbMeta, feMeta = pbVer, feVer
  return string.format(
    "live_ver=%s plateband_ver=%s felog_ver=%s seq=%s src=%s load=%s t=%s feed=pb_bridge interface_pb=%s interface_fe=%s meta_pb=%s meta_fe=%s",
    pbVer,
    pbVer,
    feVer,
    tostring(seq),
    src,
    load,
    tostring(Now()),
    pbVer,
    feVer,
    pbMeta,
    feMeta
  )
end

function Mod.PulseExportDisk()
  return Mod.PulseExportDiskTick()
end

--- SV + disk export (chat truth line 1 + session tail).
function Mod.PulseExportTruth()
  local ok = Mod.PulseExportDisk()
  local db = ns.Config.EnsureDB()
  local seq = tonumber(db.exportPulseSeq) or 0
  if not ok then
    ok = Mod.SyncLiveExportFile("EXPORT_PULSE", "pulse", seq)
  end
  return ok
end

local function StopExportTruthPulse()
  exportTruthArmed = false
  worldPulseHooked = false
  if exportTruthTicker and exportTruthTicker.Cancel then
    pcall(exportTruthTicker.Cancel, exportTruthTicker)
  end
  exportTruthTicker = nil
  ioPulseFrame = nil
  ioPulseLastGt = 0
  if exportDriverFrame then
    exportDriverFrame:UnregisterAllEvents()
    exportDriverFrame:SetScript("OnUpdate", nil)
    exportDriverFrame:SetScript("OnEvent", nil)
    exportDriverFrame = nil
  end
  exportEventsRegistered = false
end

local EXPORT_PULSE_EVENTS = {
  "PLAYER_STARTED_MOVING",
  "PLAYER_STOPPED_MOVING",
  "PLAYER_REGEN_ENABLED",
  "PLAYER_REGEN_DISABLED",
  "ZONE_CHANGED",
  "BAG_UPDATE_DELAYED",
}

local function EnsureExportDriverTicker()
  if exportTruthTicker or not C_Timer or not C_Timer.NewTicker then
    return false
  end
  exportTruthTicker = C_Timer.NewTicker(EXPORT_TICK, function()
    pcall(DoExportDiskPulse)
  end)
  return true
end

local function EnsureExportDriverFrame()
  if exportDriverFrame or not CreateFrame or not GetTime then
    return
  end
  local parent = WorldFrame or UIParent
  exportDriverFrame = CreateFrame("Frame", "PlatebandExportDriver", parent)
  exportEventsRegistered = true
  for i = 1, #EXPORT_PULSE_EVENTS do
    pcall(exportDriverFrame.RegisterEvent, exportDriverFrame, EXPORT_PULSE_EVENTS[i])
  end
  pcall(exportDriverFrame.RegisterUnitEvent, exportDriverFrame, "UNIT_AURA", "player")
  exportDriverFrame:SetScript("OnEvent", function()
    QueueExportDiskPulse()
  end)
  local acc = 0
  exportDriverFrame:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (tonumber(elapsed) or 0)
    if acc < EXPORT_TICK then
      return
    end
    acc = acc - EXPORT_TICK
    pcall(DoExportDiskPulse)
  end)
  pcall(exportDriverFrame.Show, exportDriverFrame)
end

function Mod.SyncLiveExportFile(src, load, seq)
  local db = ns.Config.EnsureDB()
  local log = EnsureLogTable()
  -- Fresh wall clock every call (ver may be unchanged; t= still moves).
  local line = Mod.BuildChatTruthLine(src, load, seq)
  db.chatTruthLine = line
  db.chatTruthAt = Now()
  local start = math.max(1, #log.lines - LIVE_TAIL_LINES + 1)
  local tail = (type(log.lines) == "table" and #log.lines > 0)
      and table.concat(log.lines, "\n", start, #log.lines)
      or ""
  local body = tail ~= "" and (line .. "\n" .. tail) or line
  log.export = line
  logDirty = false
  if not CONTINUOUS_DISK_PULSE then
    return false
  end
  local wrote = false
  db.ioAllowLastProbe = 0
  wrote = Mod.WriteExportL1Brute(line, true) or false
  if not wrote then
    DiscoverIoAllowlist(db)
  end
  local headLine = StampExportLineT(line)
  if TryWriteWholeFile({ AGENT_HEAD_REL, AGENT_HEAD_BS }, headLine) then
    wrote = true
  end
  return wrote
end

function Mod.ScheduleExportBurst()
  local now = Now()
  if (now - exportBurstAt) < 10 then
    return
  end
  exportBurstAt = now
  if C_Timer and C_Timer.After then
    C_Timer.After(1.95, function()
      pcall(DoExportDiskPulse)
    end)
  end
end

--- Default off: drivers stopped; version truth in SV + chat (see live-telemetry-options).
function Mod.ArmExportTruthPulse(force)
  if force then
    StopExportTruthPulse()
  end
  exportTruthArmed = true
  local db = ns.Config.EnsureDB()
  db.exportPulseArmedAt = Now()
  db.continuousDiskPulse = false
end

function Mod.EnsureExportTruthTicker(force)
  Mod.ArmExportTruthPulse(force == true)
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
    wrote = Mod.WriteExportL1Brute(line, true) or wrote
  end
  if allow == "head" then
    wrote = TryWriteWholeFile({ AGENT_HEAD_REL, AGENT_HEAD_BS }, StampExportLineT(line)) or wrote
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
  local ver = tostring(Plateband.Config and Plateband.Config.VERSION or "?")
  local db = ns.Config.EnsureDB()
  db.ioExportDiskLine = nil
  pcall(Mod.ResetExportTimeAnchor)
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
  pcall(Mod.LoginDiskExportOnce, src)
  pcall(Mod.PublishChatTruthHead, "CHAT_LOADED", src, 0)
  Mod.ArmExportTruthPulse(true)
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
  if not CONTINUOUS_DISK_PULSE then
    return
  end
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
  local log = EnsureLogTable()
  log.export = table.concat(log.lines or {}, "\n")
  logDirty = false
  return true
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
      if paintExportDirty then
        pcall(Mod.FlushPaintTrace)
      end
    end)
  else
    liveFlushPending = false
    pcall(Mod.FlushLiveExport)
  end
end

function Mod.EnsureLiveFlushTicker()
  return
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
end

function Mod.EnsureAgentPulseTicker()
  Mod.ArmExportTruthPulse(false)
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
  pcall(Mod.PublishInterfaceTocStamp)
  Mod.ArmExportTruthPulse(true)
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
    exportPulseAt = tonumber(db.exportPulseAt) or 0,
    exportPulseN = tonumber(db.exportPulseN) or 0,
  }
end

return Mod