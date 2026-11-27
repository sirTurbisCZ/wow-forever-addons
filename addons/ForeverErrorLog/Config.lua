--[[ ForeverErrorLog — defaults, schemaVersion, migration ]]

ForeverErrorLog = ForeverErrorLog or {}

local CURRENT_SCHEMA = 5
local MAX_ERRORS = 80
local MAX_MSG = 1500
local MAX_SESSION_LINES = 200
local MAX_AGENT_EXPORT_LINES = 120

ForeverErrorLog.Config = ForeverErrorLog.Config or {}
local Config = ForeverErrorLog.Config

Config.CURRENT_SCHEMA = CURRENT_SCHEMA
Config.MAX_ERRORS = MAX_ERRORS
Config.MAX_MSG = MAX_MSG
Config.MAX_SESSION_LINES = MAX_SESSION_LINES
Config.MAX_AGENT_EXPORT_LINES = MAX_AGENT_EXPORT_LINES
Config.VERSION = "0.2.1"

local function Defaults()
  return {
    schemaVersion = CURRENT_SCHEMA,
    enabled = true,
    -- Default OFF: Blizzard popup queues stale errors and users click "next" forever.
    -- Capture into ForeverErrorLogDB still runs.
    scriptErrors = false,
    -- Default OFF: AgentFeed / live-head / session export for dev scripts (/felog dev on).
    devTelemetry = false,
    errors = {},
    errorArchive = {
      sessions = {},
    },
    sessionLog = {
      startedAt = 0,
      lines = {},
      export = "",
      agentExport = "",
    },
    liveHead = {
      platebandVer = "",
      felogVer = Config.VERSION or "?",
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
      export = "",
      agentExport = "",
    }
  end
  db.sessionLog.fileOk = nil
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
    from = 3
  end

  if from < 4 then
    if type(db.errorArchive) ~= "table" then
      db.errorArchive = { sessions = {} }
    end
    if type(db.errorArchive.sessions) ~= "table" then
      db.errorArchive.sessions = {}
    end
    db.schemaVersion = 4
    from = 4
  end

  if from < 5 then
    -- 0.2.0: no io in Forever; ring is reset once per load (no persisted token); dev telemetry is opt-in.
    db.errorWipeTok = nil
    if db.devTelemetry == nil then
      db.devTelemetry = false
    end
    if type(db.sessionLog) == "table" and db.devTelemetry ~= true then
      db.sessionLog.export = ""
      db.sessionLog.agentExport = ""
    end
    db.schemaVersion = 5
  end

  if type(db.errors) ~= "table" then
    db.errors = {}
  end
  if type(db.errorArchive) ~= "table" then
    db.errorArchive = { sessions = {} }
  end
  EnsureSessionLog(db)

  return db
end

--- Reset config to defaults and clear the error ring.
function Config.Reset()
  ForeverErrorLogDB = Defaults()
  return ForeverErrorLogDB
end
