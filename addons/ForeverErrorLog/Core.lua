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
local LIVE_HEAD_REL = "Interface/AddOns/ForeverErrorLog/Logs/live-head.log"
local LIVE_HEAD_BS = [[Interface\AddOns\ForeverErrorLog\Logs\live-head.log]]
local AGENT_EXPORT_REL = "Interface/AddOns/ForeverErrorLog/Logs/agent-live-export.log"
local AGENT_EXPORT_BS = [[Interface\AddOns\ForeverErrorLog\Logs\agent-live-export.log]]
local PB_EXPORT_REL = "Interface/AddOns/Plateband/Logs/agent-live-export.log"
local PB_EXPORT_BS = [[Interface\AddOns\Plateband\Logs\agent-live-export.log]]
local pbExportPulseSeq = 0
local LIVE_STREAM_REL = "Interface/AddOns/ForeverErrorLog/Logs/live-stream.log"
local LIVE_STREAM_BS = [[Interface\AddOns\ForeverErrorLog\Logs\live-stream.log]]
local AGENT_TAIL_LINES = 160
local livePulseTicker
local livePulseArmed = false
local livePulseFrame
local livePulseLastGt = 0
local felogWorldPulseHooked = false
local felogExportBurstAt = 0
local felogExportDriver
local FELOG_EXPORT_TICK = 1.95

local WriteLiveHeadFile
local FlushAgentExportFiles
local UpdateLiveHeadFromAgent
local DiskBridge

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

local function ProbeSessionFileAppend()
  if not (io and io.open) then
    fileOk = false
    return false
  end
  for _, path in ipairs({ FILE_REL, FILE_REL_BS }) do
    local f = TryOpen(path, "a")
    if f then
      pcall(function()
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
    ProbeSessionFileAppend()
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
  if stamped:find("AGENT[", 1, true) then
    if type(log.agentExport) ~= "string" then
      log.agentExport = ""
    end
    local maxAgent = Config.MAX_AGENT_EXPORT_LINES or 120
    local agentLines = {}
    if log.agentExport ~= "" then
      for agentLine in log.agentExport:gmatch("[^\n]+") do
        agentLines[#agentLines + 1] = agentLine
      end
    end
    agentLines[#agentLines + 1] = stamped
    while #agentLines > maxAgent do
      table.remove(agentLines, 1)
    end
    log.agentExport = table.concat(agentLines, "\n")
  end
  log.fileOk = AppendSessionFile(stamped) or log.fileOk
  if not AppendLiveStream(stamped) then
    DiskBridge(nil, nil, stamped)
  end
  if stamped:find("AGENT[", 1, true) then
    pcall(FlushAgentExportFiles, log)
  end
end

local function EnsureLiveHeadTable(db)
  if type(db.liveHead) ~= "table" then
    db.liveHead = {
      platebandVer = "",
      felogVer = tostring(Config.VERSION or "?"),
      seq = 0,
      src = "",
      load = "",
      at = 0,
      lastPaint = "",
      lastCard = "",
      feed = "sv_only",
    }
  end
  return db.liveHead
end

local function AppendTextFile(relPaths, line)
  if not (io and io.open) or not line or line == "" then
    return false
  end
  for i = 1, #relPaths do
    local f = TryOpen(relPaths[i], "a")
    if f then
      local ok = pcall(function()
        f:write(line)
        if line:sub(-1) ~= "\n" then
          f:write("\n")
        end
        f:close()
      end)
      if ok then
        fileOk = true
        return true
      end
    end
  end
  return false
end

local function WriteTextFile(relPaths, body)
  if not (io and io.open) then
    return false
  end
  for i = 1, #relPaths do
    local f = TryOpen(relPaths[i], "w")
    if f then
      local ok = pcall(function()
        f:write(body)
        if body:sub(-1) ~= "\n" then
          f:write("\n")
        end
        f:close()
      end)
      if ok then
        return true
      end
    end
  end
  return false
end

FlushAgentExportFiles = function(log)
  if not log then
    return
  end
  local body = type(log.agentExport) == "string" and log.agentExport or ""
  if body == "" then
    return
  end
  local wrote = WriteTextFile({ AGENT_EXPORT_REL, AGENT_EXPORT_BS }, body)
  local bridged = false
  if not wrote then
    bridged = DiskBridge(nil, body, nil)
  end
  local db = EnsureDB()
  local lh = EnsureLiveHeadTable(db)
  if wrote then
    lh.feed = "file"
  elseif bridged then
    lh.feed = "pb_bridge"
  end
  pcall(WriteLiveHeadFile, lh)
end

DiskBridge = function(headLine, exportBody, streamLine)
  local sl = Plateband and Plateband.SessionLog
  if not sl or type(sl.MirrorFelogLogs) ~= "function" then
    return false
  end
  return sl.MirrorFelogLogs(headLine, exportBody, streamLine) and true or false
end

local function FormatLiveHeadLine(lh)
  lh = lh or {}
  local at = tonumber(lh.at) or Now()
  local felogVer = tostring(Config.VERSION or "?")
  local line = string.format(
    "live_ver=%s plateband_ver=%s felog_ver=%s seq=%s src=%s load=%s t=%s feed=%s",
    tostring(lh.platebandVer ~= "" and lh.platebandVer or felogVer or "?"),
    tostring(lh.platebandVer or ""),
    tostring(felogVer),
    tostring(lh.seq or 0),
    tostring(lh.src or "felog"),
    tostring(lh.load or "-"),
    tostring(at),
    tostring(lh.feed or "sv_only")
  )
  if type(lh.lastPaint) == "string" and lh.lastPaint ~= "" then
    line = line .. " last_paint=" .. Trim(lh.lastPaint, 220)
  end
  if type(lh.lastCard) == "string" and lh.lastCard ~= "" then
    line = line .. " last_card=" .. Trim(lh.lastCard, 220)
  end
  return line
end

WriteLiveHeadFile = function(lh)
  lh = lh or EnsureLiveHeadTable(EnsureDB())
  local db = EnsureDB()
  lh.felogVer = tostring(Config.VERSION or "?")
  if (tonumber(lh.at) or 0) <= 0 then
    lh.at = Now()
  end
  local line = FormatLiveHeadLine(lh)
  local wrote = WriteTextFile({ LIVE_HEAD_REL, LIVE_HEAD_BS }, line)
  local bridged = false
  if not wrote then
    bridged = DiskBridge(line, nil, nil)
  end
  if wrote then
    lh.feed = "file"
  elseif bridged then
    lh.feed = "pb_bridge"
  end
  db.liveHead = lh
  if bridged and not wrote then
    DiskBridge(nil, nil, string.format("[%s] LIVE_HEAD %s", tostring(Now()), line))
  end
  return wrote or bridged
end

UpdateLiveHeadFromAgent = function(source, payload)
  source = tostring(source or "")
  payload = tostring(payload or "")
  if source ~= "Plateband" then
    return
  end
  local db = EnsureDB()
  local lh = EnsureLiveHeadTable(db)
  local ver = payload:match("ver=([0-9%.]+)")
  local seq = tonumber(payload:match("seq=([0-9]+)"))
  local load = payload:match("load=([%w_]+)") or payload:match("src=([%w_]+)")
  if payload:find("CHAT_LOADED", 1, true) then
    lh.src = "CHAT_LOADED"
    load = payload:match("src=([%w_]+)") or load
  elseif payload:find("SESSION_START", 1, true) then
    lh.src = "SESSION_START"
    load = "addon"
  elseif payload:find("AGENT_LIVE", 1, true) then
    lh.src = "AGENT_LIVE"
    load = load or "pulse"
  elseif payload:sub(1, 6) == "PAINT " then
    lh.lastPaint = Trim(payload, 220)
    lh.src = lh.src ~= "" and lh.src or "PAINT"
  elseif payload:find("PLATEBAND_CARD", 1, true) then
    lh.lastCard = Trim(payload, 220)
    lh.src = lh.src ~= "" and lh.src or "CARD"
  elseif payload:find("RUNTIME_VER", 1, true) then
    lh.src = "RUNTIME_VER"
    load = payload:match("load=([%w_]+)") or load
  end
  if ver then
    lh.platebandVer = ver
  end
  if seq then
    lh.seq = seq
  end
  if load and load ~= "" then
    lh.load = load
  end
  lh.at = Now()
  db.liveHead = lh
  pcall(WriteLiveHeadFile, lh)
end

local PB_TOC_FILE = "Interface/AddOns/Plateband/Plateband.toc"
local PB_TOC_BS = [[Interface\AddOns\Plateband\Plateband.toc]]
local FE_TOC_FILE = "Interface/AddOns/ForeverErrorLog/ForeverErrorLog.toc"
local FE_TOC_BS = [[Interface\AddOns\ForeverErrorLog\ForeverErrorLog.toc]]
local PB_CFG_FILE = "Interface/AddOns/Plateband/Config.lua"
local PB_CFG_BS = [[Interface\AddOns\Plateband\Config.lua]]
local FE_CFG_FILE = "Interface/AddOns/ForeverErrorLog/Config.lua"
local FE_CFG_BS = [[Interface\AddOns\ForeverErrorLog\Config.lua]]

local function FelogParseVersionText(text)
  if not text then
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

local function FelogReadInterfaceVersion(paths)
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
        local ver = FelogParseVersionText(text)
        if ver then
          return ver
        end
      end
    end
  end
  return nil
end

local PB_TOC_STAMP = "Interface/AddOns/Plateband/Logs/interface-toc.ver"
local PB_TOC_STAMP_BS = [[Interface\AddOns\Plateband\Logs\interface-toc.ver]]

local function FelogEnsurePlatebandForToc()
  if Plateband and Plateband.Config and Plateband.Config.VERSION then
    return
  end
  if C_AddOns and C_AddOns.LoadAddOn then
    pcall(C_AddOns.LoadAddOn, "Plateband")
  elseif LoadAddOn then
    pcall(LoadAddOn, "Plateband")
  end
end

local function FelogReadPlatebandTocStamp()
  if not (io and io.open) then
    return nil, nil
  end
  for i = 1, 2 do
    local path = i == 1 and PB_TOC_STAMP or PB_TOC_STAMP_BS
    local f = TryOpen(path, "r")
    if f then
      local ok, line = pcall(function()
        local l = f:read("*l") or ""
        f:close()
        return l
      end)
      if ok and line ~= "" then
        return line:match("pb=([%d%.]+)"), line:match("fe=([%d%.]+)")
      end
    end
  end
  return nil, nil
end

local function FelogPickVersion(...)
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v and tostring(v) ~= "" and tostring(v) ~= "?" then
      return tostring(v)
    end
  end
  return nil
end

local function FelogVerParts(v)
  local a, b, c = tostring(v or "0.0.0"):match("^(%d+)%.(%d+)%.(%d+)")
  return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

local function FelogVerNewer(a, b)
  if not a or a == "" then
    return b
  end
  if not b or b == "" then
    return a
  end
  local a1, a2, a3 = FelogVerParts(a)
  local b1, b2, b3 = FelogVerParts(b)
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

local function FelogBestVersion(...)
  local best
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v and tostring(v) ~= "" and tostring(v) ~= "?" then
      best = FelogVerNewer(best, tostring(v))
    end
  end
  return best
end

local function FelogQueryMetadataVersion(addon)
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
  return nil
end

local function FelogResolveExportVersions()
  FelogEnsurePlatebandForToc()
  local feChat = Config and Config.VERSION and tostring(Config.VERSION) or nil
  local pbChat
  if Plateband and Plateband.Config and Plateband.Config.VERSION then
    pbChat = tostring(Plateband.Config.VERSION)
  end
  local pbStamp, feStamp = FelogReadPlatebandTocStamp()
  local pbToc = FelogReadInterfaceVersion({ PB_TOC_FILE, PB_TOC_BS, PB_CFG_FILE, PB_CFG_BS })
  local feToc = FelogReadInterfaceVersion({ FE_TOC_FILE, FE_TOC_BS, FE_CFG_FILE, FE_CFG_BS })
  local pbMeta = FelogQueryMetadataVersion("Plateband")
  local feMeta = FelogQueryMetadataVersion("ForeverErrorLog")
  local pbVer = FelogBestVersion(pbChat, pbStamp, pbToc, pbMeta)
  local feVer = FelogBestVersion(feChat, feStamp, feToc, feMeta)
  pbMeta = pbMeta or pbVer
  feMeta = feMeta or feVer
  return pbVer, feVer, pbMeta, feMeta
end

local function FelogPlatebandExportLine()
  pbExportPulseSeq = pbExportPulseSeq + 1
  local pbVer, feVer, pbMeta, feMeta = FelogResolveExportVersions()
  pbMeta = pbMeta or pbVer
  feMeta = feMeta or feVer
  return string.format(
    "live_ver=%s plateband_ver=%s felog_ver=%s seq=%s src=EXPORT_PULSE load=pulse t=%s feed=pb_bridge interface_pb=%s interface_fe=%s meta_pb=%s meta_fe=%s",
    pbVer,
    pbVer,
    feVer,
    tostring(pbExportPulseSeq),
    tostring(Now()),
    pbVer,
    feVer,
    pbMeta,
    feMeta
  )
end

local function WritePlatebandExportLine(line)
  line = tostring(line or "")
  if line == "" or not (io and io.open) then
    return false
  end
  for i = 1, 2 do
    local path = i == 1 and PB_EXPORT_REL or PB_EXPORT_BS
    local f = TryOpen(path, "w")
    if f then
      local ok = pcall(function()
        f:write(line)
        f:write("\n")
        if f.flush then
          f:flush()
        end
        f:close()
      end)
      if ok then
        return true
      end
    end
  end
  return false
end

local function ScheduleFelogExportBurst()
  local now = Now()
  if (now - felogExportBurstAt) < 5 then
    return
  end
  felogExportBurstAt = now
  pcall(function()
    WritePlatebandExportLine(FelogPlatebandExportLine())
  end)
  local delays = { 0.15, 0.35, 0.75, 1.5, 2, 4, 8 }
  for i = 1, #delays do
  local d = delays[i]
    if C_Timer and C_Timer.After then
      C_Timer.After(d, function()
        pcall(function()
          WritePlatebandExportLine(FelogPlatebandExportLine())
        end)
      end)
    end
  end
end

local function EnsureFelogWorldIoPulse()
  if felogWorldPulseHooked or not WorldFrame or not GetTime then
    return
  end
  felogWorldPulseHooked = true
  local lastGt = GetTime()
  local w = CreateFrame("Frame", nil, WorldFrame)
  w:SetScript("OnUpdate", function()
    local gt = GetTime()
    if (gt - lastGt) < 2.0 then
      return
    end
    lastGt = gt
    pcall(PulseLiveHeadFile)
  end)
  pcall(w.Show, w)
end

local function PulseLiveHeadFile()
  local bridgeLine = FelogPlatebandExportLine()
  WritePlatebandExportLine(bridgeLine)
  local sl = Plateband and Plateband.SessionLog
  if sl and type(sl.PulseExportDisk) == "function" then
    pcall(sl.PulseExportDisk)
    return
  end
  if sl and type(sl.PulseExportTruth) == "function" then
    pcall(sl.PulseExportTruth)
    return
  end
  if sl and type(sl.PublishChatTruthHead) == "function" then
    local db = EnsureDB()
    local lh = EnsureLiveHeadTable(db)
    local seq = tonumber(lh.seq) or 0
    pcall(sl.PublishChatTruthHead, "FELOG_PULSE", "pulse", seq)
    return
  end
  local db = EnsureDB()
  local lh = EnsureLiveHeadTable(db)
  lh.felogVer = tostring(Config.VERSION or "?")
  local pb = Plateband and Plateband.Config and Plateband.Config.VERSION
  if pb then
    lh.platebandVer = tostring(pb)
  end
  if (tonumber(lh.at) or 0) <= 0 then
    lh.at = Now()
  end
  pcall(WriteLiveHeadFile, lh)
end

local function StopLivePulse()
  livePulseArmed = false
  felogWorldPulseHooked = false
  if livePulseTicker and livePulseTicker.Cancel then
    pcall(livePulseTicker.Cancel, livePulseTicker)
  end
  livePulseTicker = nil
  livePulseFrame = nil
  if felogExportDriver then
    felogExportDriver:SetScript("OnUpdate", nil)
    felogExportDriver = nil
  end
end

local function EnsureFelogExportDriver()
  if felogExportDriver or not CreateFrame or not GetTime then
    return
  end
  local parent = WorldFrame or UIParent
  felogExportDriver = CreateFrame("Frame", "FelogExportDriver", parent)
  local lastGt = GetTime()
  felogExportDriver:SetScript("OnUpdate", function()
    local gt = GetTime()
    if (gt - lastGt) < FELOG_EXPORT_TICK then
      return
    end
    lastGt = gt
    pcall(PulseLiveHeadFile)
  end)
  pcall(felogExportDriver.Show, felogExportDriver)
end

local function ArmLivePulse(force)
  if livePulseArmed and not force then
    return
  end
  if force then
    StopLivePulse()
  elseif livePulseArmed then
    return
  end
  livePulseArmed = true
  pcall(PulseLiveHeadFile)
  ScheduleFelogExportBurst()
  EnsureFelogWorldIoPulse()
  EnsureFelogExportDriver()

  if not livePulseFrame and CreateFrame then
    local parent = WorldFrame or UIParent
    livePulseFrame = CreateFrame("Frame", "FelogIoPulse", parent)
  end
  if livePulseFrame then
    livePulseLastGt = (GetTime and GetTime()) or livePulseLastGt
    livePulseFrame:SetScript("OnUpdate", function()
      if not GetTime then
        return
      end
      local gt = GetTime()
      if (gt - livePulseLastGt) < 2.0 then
        return
      end
      livePulseLastGt = gt
      pcall(PulseLiveHeadFile)
    end)
    pcall(livePulseFrame.Show, livePulseFrame)
  end

  if C_Timer and C_Timer.NewTicker and not livePulseTicker then
    livePulseTicker = C_Timer.NewTicker(2.0, function()
      pcall(PulseLiveHeadFile)
    end)
  end
end

local function EnsureLivePulseTicker(force)
  ArmLivePulse(force == true)
end

local function AppendLiveStream(stamped)
  AppendTextFile({ LIVE_STREAM_REL, LIVE_STREAM_BS }, stamped)
end

local function PrintLoadedLine(reload)
  local db = EnsureDB()
  local n = #(db.errors or {})
  local ver = tostring(Config.VERSION or "?")
  local slog = db.sessionLog
  local feed = (slog and slog.fileOk) and "file" or ((db.liveHead and db.liveHead.feed) or "sv_only")
  if n > 0 then
    Print(string.format(
      L.LOADED_COUNT or "loaded v%s — %d errors stored (historical) · session %s · /felog session",
      ver,
      n,
      tostring(feed)
    ))
  else
    Print(string.format(
      L.LOADED_EMPTY or "loaded v%s — session %s · /felog session · popup off",
      ver,
      tostring(feed)
    ))
  end
  if reload then
    Print(string.format(L.RELOAD_LINE or "reloaded v%s · live-head via %s", ver, tostring(feed)))
  end
end

local function StampFelogReload()
  local db = EnsureDB()
  local lh = EnsureLiveHeadTable(db)
  lh.src = "FELOG_LOAD"
  lh.load = "reload"
  lh.at = Now()
  lh.felogVer = tostring(Config.VERSION or "?")
  db.liveHead = lh
  AppendSession(string.format("CHAT_LOADED ver=%s src=reload addon=ForeverErrorLog", lh.felogVer))
  pcall(function()
    WritePlatebandExportLine(FelogPlatebandExportLine())
  end)
end

--- Wipe session log on cold load. Error ring is kept across sessions.
local function BeginSession()
  if sessionBegun then
    return
  end
  sessionBegun = true
  local db = EnsureDB()
  local wrote = ProbeSessionFileAppend()
  db.sessionLog = {
    startedAt = Now(),
    lines = {},
    fileOk = wrote and true or false,
    export = "",
    agentExport = "",
  }
  AppendSession(string.format(
    "SESSION_START ver=%s file=%s",
    tostring(Config.VERSION or "?"),
    wrote and "yes" or "sv_only"
  ))
  local db = EnsureDB()
  local lh = EnsureLiveHeadTable(db)
  lh.felogVer = tostring(Config.VERSION or "?")
  lh.src = "SESSION_START"
  lh.load = "addon"
  lh.at = Now()
  db.liveHead = lh
  EnsureLivePulseTicker(true)
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
    Print(L.BUGGRABBER or "hooked into BugGrabber")
    return
  end

  if type(seterrorhandler) ~= "function" then
    Print(L.NO_SETHANDLER or "seterrorhandler missing")
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

local function DeferArmLivePulse()
  local function arm()
    pcall(function()
      EnsureLivePulseTicker(true)
    end)
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, arm)
    C_Timer.After(0.5, arm)
  else
    arm()
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == addonName then
    EnsureDB()
    BeginSession()
    InstallHandler()
    DeferArmLivePulse()
    local loggedIn = false
    pcall(function()
      if IsLoggedIn then
        loggedIn = IsLoggedIn()
      end
    end)
    if loggedIn then
      pcall(StopLivePulse)
      pcall(EnsureLivePulseTicker, true)
      pcall(StampFelogReload)
      pcall(ScheduleFelogExportBurst)
      if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
          PrintLoadedLine(true)
        end)
      else
        PrintLoadedLine(true)
      end
    end
  elseif event == "PLAYER_LOGIN" then
    EnsureDB()
    BeginSession()
    InstallHandler()
    SuppressScriptErrorsPopup()
    DeferArmLivePulse()
    PrintLoadedLine(false)
  elseif event == "PLAYER_ENTERING_WORLD" then
    DeferArmLivePulse()
  end
end)

-- Public API for other Forever addons (optional)
ForeverErrorLog.Record = function(msg, stack)
  Record(msg, stack)
end

--- Cross-addon live feed (append session.log — works when target addon io is blocked).
ForeverErrorLog.AgentFeed = function(source, line)
  if not sessionBegun then
    BeginSession()
  end
  source = tostring(source or "?")
  line = Trim(tostring(line or ""), 490)
  if line == "" then
    return
  end
  AppendSession(string.format("AGENT[%s] %s", source, line))
  pcall(UpdateLiveHeadFromAgent, source, line)
end

ForeverErrorLog.AgentFeedReady = function()
  return sessionBegun and type(ForeverErrorLog.AgentFeed) == "function"
end

--- Explicit runtime stamp from bridge addons (Plateband SessionLog).
ForeverErrorLog.ApplyLiveHeadSnapshot = function(plateVer, feVer, src, loadKind, seq)
  local db = EnsureDB()
  local lh = EnsureLiveHeadTable(db)
  plateVer = tostring(plateVer or "")
  feVer = tostring(feVer or Config.VERSION or "?")
  if plateVer ~= "" then
    lh.platebandVer = plateVer
  end
  lh.felogVer = feVer
  lh.src = tostring(src or "CHAT_LOADED")
  lh.load = tostring(loadKind or "reload")
  lh.seq = tonumber(seq) or lh.seq or 0
  lh.at = Now()
  lh.feed = "pb_bridge"
  db.liveHead = lh
end

ForeverErrorLog.NotifyRuntime = function(source, ver, loadKind, src)
  if not sessionBegun then
    BeginSession()
  end
  source = tostring(source or "addon")
  ver = tostring(ver or "?")
  loadKind = tostring(loadKind or "runtime")
  src = tostring(src or "notify")
  local db = EnsureDB()
  local lh = EnsureLiveHeadTable(db)
  if source == "Plateband" then
    lh.platebandVer = ver
  end
  lh.src = src
  lh.load = loadKind
  lh.at = Now()
  db.liveHead = lh
  AppendSession(string.format(
    "AGENT[%s] RUNTIME_VER ver=%s src=%s load=%s",
    source,
    ver,
    src,
    loadKind
  ))
  pcall(WriteLiveHeadFile, lh)
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

  if cmd == "session" then
    local slog = db.sessionLog or {}
    local lines = type(slog.lines) == "table" and slog.lines or {}
    local n = #lines
    Print(string.format(L.SESSION_HEADER or "session lines=%d file=%s (LIVE this login)", n, tostring(slog.fileOk)))
    if n == 0 then
      Print(L.NO_SESSION or "no session lines yet")
      return
    end
    local from = math.max(1, n - 12)
    for i = from, n do
      print("|cff888888" .. tostring(lines[i]) .. "|r")
    end
    print("|cffaaaaaa" .. (L.SESSION_HINT or "agent tail: scripts/watch-forever-traces.sh watch 3") .. "|r")
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
