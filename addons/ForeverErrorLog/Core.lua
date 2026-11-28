--[[
  Forever Error Log — lean capture of Lua errors into SavedVariables.
  /felog [window]|help|list|dump|session|archive|clear|reset|minimap  (+ on|off, ui|dev|taint on|off)
  Dev telemetry (AgentFeed / live head / session export) runs only after /felog dev on.
]]

local addonName = ...

ForeverErrorLog = ForeverErrorLog or {}

local L = ForeverErrorLog.L or {}
local Config = ForeverErrorLog.Config

local installed
local baseHandler -- first handler captured at install (Blizzard default); never replaced
local originalHandler -- handler we forward to: baseHandler, or one another addon installed later
local ourHandler
local inHandler, inBase, needBase, forwarded = false, false, false, false
local lastRawMsg, lastRawAt, lastRawEntry
local lastPrintAt, suppressedPrints = -10, 0
local PRINT_GAP = 2
local ARCHIVE_TOP_N = 20
local STACK_MAX = 1500
local sessionBegun = false
local ringReset = false
local ARCHIVE_SESSIONS_MAX = 8
local ARCHIVE_TEXT_MAX = 1000

local function EnsureDB()
  return Config.EnsureDB()
end

local function Print(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[i] = tostring(select(i, ...))
  end
  print((L.PREFIX or "[ForeverErrorLog]") .. " " .. table.concat(parts, " "))
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

local function DevOn()
  return EnsureDB().devTelemetry == true
end

--- Append one line to the bounded in-SV session log. `isAgent` lines also feed agentExport (dev only).
local function AppendSession(line, isAgent)
  local db = EnsureDB()
  local log = db.sessionLog
  if type(log) ~= "table" then
    return
  end
  if type(log.lines) ~= "table" then
    log.lines = {}
  end
  local stamped = string.format("[%s] %s", tostring(Now()), Trim(line, 500))
  log.lines[#log.lines + 1] = stamped
  local maxN = Config.MAX_SESSION_LINES or 200
  while #log.lines > maxN do
    table.remove(log.lines, 1)
  end
  if db.devTelemetry ~= true then
    return
  end
  log.export = table.concat(log.lines, "\n")
  if isAgent then
    local maxAgent = Config.MAX_AGENT_EXPORT_LINES or 120
    local agentLines = {}
    if type(log.agentExport) == "string" and log.agentExport ~= "" then
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

local function CompactEntry(e)
  return {
    msg = Trim(e.msg, ARCHIVE_TEXT_MAX),
    stack = Trim(e.stack or "", ARCHIVE_TEXT_MAX),
    addon = e.addon,
    first = e.first,
    last = e.last,
    count = e.count,
  }
end

local function ArchiveErrorRing(list, loadKind)
  if type(list) ~= "table" or #list == 0 then
    return 0
  end
  local db = EnsureDB()
  if type(db.errorArchive) ~= "table" then
    db.errorArchive = { sessions = {} }
  end
  local arch = db.errorArchive.sessions
  if type(arch) ~= "table" then
    arch = {}
    db.errorArchive.sessions = arch
  end
  -- Archive only the most frequent entries (ties keep list order).
  local order = {}
  for i = 1, #list do
    order[i] = i
  end
  if #order > ARCHIVE_TOP_N then
    table.sort(order, function(x, y)
      local cx, cy = list[x].count or 1, list[y].count or 1
      if cx ~= cy then
        return cx > cy
      end
      return x < y
    end)
    for i = #order, ARCHIVE_TOP_N + 1, -1 do
      order[i] = nil
    end
    table.sort(order)
  end
  local snap = {}
  for i = 1, #order do
    snap[i] = CompactEntry(list[order[i]])
  end
  arch[#arch + 1] = {
    at = Now(),
    load = tostring(loadKind or "?"),
    n = #snap,
    errors = snap,
  }
  while #arch > ARCHIVE_SESSIONS_MAX do
    table.remove(arch, 1)
  end
  return #snap
end

--- Once per addon load (login, /reload): archive the prior ring and start a fresh live list.
--- Idempotent within a load, so callers from other addons (Plateband CHAT_LOADED) are harmless.
function ForeverErrorLog.ResetErrorRingOnChatLoaded(loadKind)
  if ringReset then
    return false
  end
  ringReset = true
  local db = EnsureDB()
  loadKind = tostring(loadKind or "login")
  local n = ArchiveErrorRing(db.errors, loadKind)
  wipe(db.errors)
  db.lastExport = nil
  lastRawEntry = nil
  AppendSession(string.format("ERROR_RING_WIPE load=%s archived=%d live=0", loadKind, n))
  return true
end

local function PrintLoadedLine()
  local db = EnsureDB()
  local ver = tostring(Config.VERSION or "?")
  if db.enabled == false then
    Print(string.format(L.LOADED_OFF or "v%s · /felog · capture OFF (/felog on)", ver))
  else
    Print(string.format(L.LOADED or "v%s · /felog", ver))
  end
end

--- Fresh session log on every addon load; archives the previous error ring.
local function BeginSession(loadKind)
  if sessionBegun then
    return
  end
  sessionBegun = true
  local db = EnsureDB()
  db.sessionLog = {
    startedAt = Now(),
    lines = {},
    export = "",
    agentExport = "",
  }
  ForeverErrorLog.ResetErrorRingOnChatLoaded(loadKind or "addon")
  AppendSession(string.format("SESSION_START ver=%s", tostring(Config.VERSION or "?")))
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

--- Store one error. Returns true when captured (false when capture is off).
local function Record(msg, stack, addonOverride)
  local db = EnsureDB()
  if not db.enabled then
    return false
  end
  msg = Trim(msg, Config.MAX_MSG)
  stack = Trim(stack or "", STACK_MAX)
  if addonOverride then
    addonOverride = Trim(addonOverride, 100)
  end
  local list = db.errors
  for i = 1, #list do
    local e = list[i]
    if e.msg == msg then
      e.count = (e.count or 1) + 1
      e.last = Now()
      if stack ~= "" then
        e.stack = stack
      end
      -- Repeats are logged sparsely so an error storm cannot flood the session log.
      if e.count == 2 or e.count % 100 == 0 then
        AppendSession(string.format("ERROR ×%s [%s] %s", tostring(e.count), tostring(e.addon or "?"), msg))
      end
      return true, e
    end
  end
  local addon = addonOverride or AddonFromMessage(msg)
  local entry = {
    msg = msg,
    stack = stack,
    addon = addon,
    first = Now(),
    last = Now(),
    count = 1,
  }
  list[#list + 1] = entry
  while #list > Config.MAX_ERRORS do
    table.remove(list, 1)
  end
  AppendSession(string.format("ERROR [%s] %s", tostring(addon), msg))
  -- At most one chat line per PRINT_GAP seconds; the rest is counted.
  local t = GetTime and GetTime() or 0
  if t - lastPrintAt >= PRINT_GAP then
    lastPrintAt = t
    local more = suppressedPrints > 0 and (" (+" .. suppressedPrints .. " more)") or ""
    suppressedPrints = 0
    Print(tostring(addon) .. ": " .. Trim(msg, 180) .. more)
  else
    suppressedPrints = suppressedPrints + 1
  end
  return true, entry
end

local function FormatEntry(e, i)
  local n = e.count and e.count > 1 and (" ×" .. e.count) or ""
  return string.format("%d. [%s]%s %s", i, e.addon or "?", n, e.msg or "?")
end

ForeverErrorLog.FormatEntry = FormatEntry

--- Archive the live list, then wipe it. Returns how many entries were archived.
local function ClearErrors()
  local db = EnsureDB()
  local n = ArchiveErrorRing(db.errors, "manual_clear")
  wipe(db.errors)
  db.lastExport = nil
  lastRawEntry = nil
  return n
end
ForeverErrorLog.ClearErrors = ClearErrors

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

local function GetScriptErrorsCVar()
  if C_CVar and C_CVar.GetCVar then
    local ok, v = pcall(C_CVar.GetCVar, "scriptErrors")
    if ok then
      return v
    end
  elseif GetCVar then
    local ok, v = pcall(GetCVar, "scriptErrors")
    if ok then
      return v
    end
  end
  return nil
end

--- Set the scriptErrors CVar only when it differs (avoids rewriting the account-wide CVar every load).
local function SetScriptErrorsCVar(on)
  local value = on and "1" or "0"
  if GetScriptErrorsCVar() == value then
    return
  end
  if C_CVar and C_CVar.SetCVar then
    pcall(C_CVar.SetCVar, "scriptErrors", value)
  elseif SetCVar then
    pcall(SetCVar, "scriptErrors", value)
  end
end

local function ClearScriptErrorsFrame()
  if not ScriptErrorsFrame then
    return
  end
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

--- Apply the saved popup preference (db.scriptErrors) — never overrides it.
local function ApplyScriptErrorsPref()
  local want = EnsureDB().scriptErrors == true
  SetScriptErrorsCVar(want)
  if not want then
    ClearScriptErrorsFrame()
  end
end

--- Taint events may carry secret/nil values: stringify defensively.
local function SafeStr(v)
  if v == nil then
    return "?"
  end
  local ok, s = pcall(tostring, v)
  if ok and type(s) == "string" then
    return s
  end
  return "?"
end

--- Record a failure of our own code or of a forwarded handler (once per dispatch, never rethrown).
local function NoteFailure(err)
  pcall(Record, "ForeverErrorLog handler failed: " .. Trim(SafeStr(err), 300), "", "ForeverErrorLog")
end

--- Hand the error to the Blizzard base handler (popup). Guarded against loops; failures are swallowed.
local function CallBase(msg)
  if inBase then
    return true
  end
  inBase = true
  local ok, err = true, nil
  if baseHandler and baseHandler ~= ourHandler then
    ok, err = pcall(baseHandler, msg)
  elseif ScriptErrorsFrame and ScriptErrorsFrame.DisplayMessage then
    ok, err = pcall(ScriptErrorsFrame.DisplayMessage, ScriptErrorsFrame, msg)
  end
  inBase = false
  return ok, err
end

--- Forward to the handler that was active before us. A handler installed by another addon always gets
--- the error (it may forward back to us, which reaches the base handler through the re-entry path).
local function Forward(msg, wantBase)
  forwarded = true
  local target = originalHandler
  local ok, err = true, nil
  if target and target ~= baseHandler and target ~= ourHandler then
    ok, err = pcall(target, msg)
  elseif wantBase then
    ok, err = CallBase(msg)
  end
  if not ok then
    NoteFailure(err)
  end
end

local function Dispatch(msg)
  local db = EnsureDB()
  local t = GetTime and GetTime() or 0
  local wantBase = db.scriptErrors == true
  if lastRawEntry and type(msg) == "string" and msg == lastRawMsg and (t - lastRawAt) < 1 and db.enabled then
    -- same error again within 1 s: count it without taking a stack
    lastRawEntry.count = (lastRawEntry.count or 1) + 1
    lastRawEntry.last = Now()
    lastRawAt = t
    needBase = wantBase
    return Forward(msg, wantBase)
  end
  local stack = ""
  if debugstack then
    local ok, s = pcall(debugstack, 3)
    if ok then
      stack = s or ""
    end
  end
  local ok, captured, entry = pcall(Record, msg, stack)
  captured = ok and captured == true
  if captured and type(msg) == "string" then
    lastRawMsg, lastRawAt, lastRawEntry = msg, t, entry
  end
  -- The base (popup) handler is wanted when the popup is on, capture is off, or capture failed.
  wantBase = wantBase or not captured
  needBase = wantBase
  return Forward(msg, wantBase)
end

local function InstallHandler()
  -- Idempotent within a load.
  if installed then
    return
  end
  installed = true
  baseHandler = geterrorhandler and geterrorhandler() or nil
  originalHandler = baseHandler

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
    Print(L.NO_SETHANDLER or "seterrorhandler missing — use /console scriptErrors 1 at least")
    return
  end

  ourHandler = function(msg)
    if inHandler then
      -- A forwarded handler came back to us: this is the chain's way to the base handler. Never loop.
      if needBase then
        CallBase(msg)
      end
      return
    end
    inHandler, forwarded = true, false
    local ok, err = pcall(Dispatch, msg)
    if not ok then
      NoteFailure(err)
      if not forwarded then
        pcall(Forward, msg, true)
      end
    end
    inHandler, needBase = false, false
  end
  seterrorhandler(ourHandler)
end

--- Another addon may call seterrorhandler after us: forward to its handler and put ours back on top.
--- The first-captured base handler is kept so the popup path survives any wrapping.
local function EnsureHandlerOnTop()
  if not ourHandler or type(geterrorhandler) ~= "function" or type(seterrorhandler) ~= "function" then
    return
  end
  local cur = geterrorhandler()
  if cur and cur ~= ourHandler then
    originalHandler = cur
    seterrorhandler(ourHandler)
  end
end

local lastTaintMsg, lastTaintAt, lastTaintEntry = nil, 0, nil

--- ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN -> one error entry (bursts are counted, not repeated).
local function OnTaint(kind, who, what)
  local db = EnsureDB()
  if db.captureTaint == false then
    return
  end
  who, what = SafeStr(who), SafeStr(what)
  local msg = string.format("[%s] %s tried %s", kind, who, what)
  local t = GetTime and GetTime() or 0
  if lastTaintEntry and msg == lastTaintMsg and (t - lastTaintAt) < 1 and db.enabled then
    lastTaintEntry.count = (lastTaintEntry.count or 1) + 1
    lastTaintEntry.last = Now()
    lastTaintAt = t
    return
  end
  local ok, entry = Record(msg, "", who)
  if ok then
    lastTaintMsg, lastTaintAt, lastTaintEntry = msg, t, entry
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(frame.RegisterEvent, frame, "ADDON_ACTION_BLOCKED")
pcall(frame.RegisterEvent, frame, "ADDON_ACTION_FORBIDDEN")
frame:SetScript("OnEvent", function(_, event, name, arg2)
  if event == "ADDON_ACTION_BLOCKED" then
    pcall(OnTaint, "blocked", name, arg2)
  elseif event == "ADDON_ACTION_FORBIDDEN" then
    pcall(OnTaint, "forbidden", name, arg2)
  elseif event == "ADDON_LOADED" and name == addonName then
    EnsureDB()
    pcall(BeginSession, "addon")
    InstallHandler()
    pcall(ApplyScriptErrorsPref)
  elseif event == "PLAYER_LOGIN" then
    EnsureDB()
    pcall(BeginSession, "login")
    InstallHandler()
    pcall(EnsureHandlerOnTop)
    pcall(ApplyScriptErrorsPref)
    PrintLoadedLine()
  elseif event == "PLAYER_ENTERING_WORLD" then
    pcall(EnsureHandlerOnTop)
  end
end)

-- Public API for other Forever addons (optional)
ForeverErrorLog.Record = function(msg, stack)
  local ok = Record(msg, stack)
  return ok
end

--- Compact live-head update from a bridge addon line (dev telemetry only).
local function UpdateLiveHeadFromAgent(source, payload)
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
  elseif payload:sub(1, 6) == "PAINT " then
    lh.lastPaint = Trim(payload, 220)
    lh.src = lh.src ~= "" and lh.src or "PAINT"
  elseif payload:find("PLATEBAND_CARD", 1, true) then
    lh.lastCard = Trim(payload, 220)
    lh.src = lh.src ~= "" and lh.src or "CARD"
  elseif payload:find("RUNTIME_VER", 1, true) then
    lh.src = "RUNTIME_VER"
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
  lh.felogVer = tostring(Config.VERSION or "?")
  lh.at = Now()
  lh.feed = "pb_bridge"
end

--- Cross-addon telemetry line (dev telemetry only; no-op by default).
ForeverErrorLog.AgentFeed = function(source, line)
  if not DevOn() then
    return
  end
  if not sessionBegun then
    BeginSession()
  end
  source = tostring(source or "?")
  line = Trim(tostring(line or ""), 490)
  if line == "" then
    return
  end
  AppendSession(string.format("AGENT[%s] %s", source, line), true)
  pcall(UpdateLiveHeadFromAgent, source, line)
end

ForeverErrorLog.AgentFeedReady = function()
  return sessionBegun and DevOn()
end

--- Explicit runtime stamp from a bridge addon (dev telemetry only).
ForeverErrorLog.ApplyLiveHeadSnapshot = function(plateVer, feVer, src, loadKind, seq)
  if not DevOn() then
    return
  end
  local db = EnsureDB()
  local lh = EnsureLiveHeadTable(db)
  plateVer = tostring(plateVer or "")
  if plateVer ~= "" then
    lh.platebandVer = plateVer
  end
  lh.felogVer = tostring(feVer or Config.VERSION or "?")
  lh.src = tostring(src or "CHAT_LOADED")
  lh.load = tostring(loadKind or "reload")
  lh.seq = tonumber(seq) or lh.seq or 0
  lh.at = Now()
  lh.feed = "pb_bridge"
end

--- Runtime version note from a bridge addon: (source, ver, loadKind, src). Dev telemetry only.
ForeverErrorLog.NotifyRuntime = function(source, ver, loadKind, src)
  if not DevOn() then
    return
  end
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
  AppendSession(string.format("AGENT[%s] RUNTIME_VER ver=%s src=%s load=%s", source, ver, src, loadKind), true)
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
  local W = ForeverErrorLog.Window
  if msg == "" and W then
    W.Toggle()
    return
  end
  cmd = (cmd or "help"):lower()
  local db = EnsureDB()

  if (cmd == "window" or cmd == "settings" or cmd == "minimap") and W then
    if cmd == "settings" then
      W.Open()
    elseif cmd == "window" then
      W.Toggle()
    else
      W.ToggleMinimap()
    end
    return
  end

  if cmd == "taint" then
    local a = (rest or ""):lower()
    if a == "on" or a == "1" then
      db.captureTaint = true
    elseif a == "off" or a == "0" then
      db.captureTaint = false
    end
    Print(string.format(L.TAINT_STATUS or "taint capture: %s — /felog taint on|off", tostring(db.captureTaint ~= false)))
    return
  end

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
    Print(string.format(L.SESSION_HEADER or "session lines=%d (this load)", n))
    if n == 0 then
      Print(L.NO_SESSION or "no session lines yet")
      return
    end
    local from = math.max(1, n - 12)
    for i = from, n do
      print("|cff888888" .. tostring(lines[i]) .. "|r")
    end
    print("|cffaaaaaa" .. (L.SESSION_HINT or "prior rings: /felog archive · live list: /felog list") .. "|r")
    return
  end

  if cmd == "clear" then
    local n = ClearErrors()
    Print(string.format(L.LOG_CLEARED or "log cleared (archived %d)", n))
    return
  end

  if cmd == "archive" or cmd == "history" then
    local arch = type(db.errorArchive) == "table" and db.errorArchive.sessions or {}
    local n = #arch
    Print(string.format(L.ARCHIVE_HEADER or "%d archived session(s) — /felog archive dump", n))
    if n == 0 then
      Print(L.NO_ARCHIVE or "no archived error rings yet")
      return
    end
    local from = math.max(1, n - 5)
    for i = from, n do
      local s = arch[i]
      print(string.format(
        "|cffaaaaaa%d. load=%s at=%s n=%s|r",
        i,
        tostring(s.load or "?"),
        tostring(s.at or "?"),
        tostring(s.n or 0)
      ))
    end
    if (rest or ""):lower() == "dump" then
      local s = arch[n]
      local errs = type(s.errors) == "table" and s.errors or {}
      local f = math.max(1, #errs - 8)
      for j = f, #errs do
        print("|cff888888  " .. FormatEntry(errs[j], j) .. "|r")
      end
    end
    return
  end

  if cmd == "reset" then
    Config.Reset()
    pcall(ApplyScriptErrorsPref)
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
    Print(L.CAPTURE_OFF or "capture off — errors go to the default handler")
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
      ApplyScriptErrorsPref()
      Print(L.UI_OFF or "scriptErrors popup off (capture still runs)")
    else
      Print(string.format(L.UI_STATUS or "scriptErrors preference: %s", tostring(db.scriptErrors)))
    end
    return
  end

  if cmd == "dev" then
    local a = (rest or ""):lower()
    if a == "on" or a == "1" then
      db.devTelemetry = true
      Print(L.DEV_ON or "dev telemetry on")
    elseif a == "off" or a == "0" then
      db.devTelemetry = false
      Print(L.DEV_OFF or "dev telemetry off")
    else
      Print(string.format(L.DEV_STATUS or "dev telemetry: %s — /felog dev on|off", tostring(db.devTelemetry == true)))
    end
    return
  end

  Print(L.UNKNOWN_CMD or "unknown command — /felog help")
end
