--[[ ForeverErrorLog — defaults, schemaVersion, migration ]]

ForeverErrorLog = ForeverErrorLog or {}

local CURRENT_SCHEMA = 3
local MAX_ERRORS = 80
local MAX_MSG = 4000
local MAX_SESSION_LINES = 200
local MAX_AGENT_EXPORT_LINES = 120

ForeverErrorLog.Config = ForeverErrorLog.Config or {}
local Config = ForeverErrorLog.Config

Config.CURRENT_SCHEMA = CURRENT_SCHEMA
Config.MAX_ERRORS = MAX_ERRORS
Config.MAX_MSG = MAX_MSG
Config.MAX_SESSION_LINES = MAX_SESSION_LINES
Config.MAX_AGENT_EXPORT_LINES = MAX_AGENT_EXPORT_LINES
Config.VERSION = "0.1.20"

local function Defaults()
  return {
    schemaVersion = CURRENT_SCHEMA,
    enabled = true,
    -- Default OFF: Blizzard popup queues stale errors and users click "next" forever.
    -- Capture into ForeverErrorLogDB still runs.
    scriptErrors = false,
    errors = {},
    sessionLog = {
      startedAt = 0,
      lines = {},
      fileOk = false,
      export = "",
      agentExport = "",
    },
    liveHead = {
      platebandVer = "",
      felogVer = Config.VERSION or "0.1.4",
      seq = 0,
      src = "",
      load = "",
      at = 0,
      lastPaint = "",
      lastCard = "",
      feed = "sv_only",
    },
  }
end

Config.Defaults = Defaults

local function EnsureSessionLog(db)
  if type(db.sessionLog) ~= "table" then
    db.sessionLog = {
      startedAt = 0,
      lines = {},
      fileOk = false,
      export = "",
      agentExport = "",
    }
  end
  if type(db.sessionLog.lines) ~= "table" then
    db.sessionLog.lines = {}
  end
  if type(db.sessionLog.agentExport) ~= "string" then
    db.sessionLog.agentExport = ""
  end
end

--- Ensure ForeverErrorLogDB exists, migrate schema, return db.
function Config.EnsureDB()
  if type(ForeverErrorLogDB) ~= "table" then
    ForeverErrorLogDB = Defaults()
    return ForeverErrorLogDB
  end

  local db = ForeverErrorLogDB
  local from = tonumber(db.schemaVersion) or 0

  if from < 1 then
    -- Pre-schema / empty SV → apply defaults without wiping an existing error list.
    if type(db.errors) ~= "table" then
      db.errors = {}
    end
    if db.enabled == nil then
      db.enabled = true
    end
    if db.scriptErrors == nil then
      db.scriptErrors = false
    end
    db.schemaVersion = 1
    from = 1
  end

  if from < 2 then
    EnsureSessionLog(db)
    db.schemaVersion = 2
    from = 2
  end

  if from < 3 then
    if type(db.liveHead) ~= "table" then
      db.liveHead = {
        platebandVer = "",
        seq = 0,
        src = "",
        load = "",
        at = 0,
        lastPaint = "",
        lastCard = "",
      }
    end
    db.schemaVersion = 3
  end

  if type(db.errors) ~= "table" then
    db.errors = {}
  end
  EnsureSessionLog(db)

  return db
end

--- Reset config to defaults and clear the error ring.
function Config.Reset()
  ForeverErrorLogDB = Defaults()
  return ForeverErrorLogDB
end
