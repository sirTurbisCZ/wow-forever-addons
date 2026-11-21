--[[ ForeverErrorLog — defaults, schemaVersion, migration ]]

ForeverErrorLog = ForeverErrorLog or {}

local CURRENT_SCHEMA = 1
local MAX_ERRORS = 80
local MAX_MSG = 4000

ForeverErrorLog.Config = ForeverErrorLog.Config or {}
local Config = ForeverErrorLog.Config

Config.CURRENT_SCHEMA = CURRENT_SCHEMA
Config.MAX_ERRORS = MAX_ERRORS
Config.MAX_MSG = MAX_MSG

local function Defaults()
  return {
    schemaVersion = CURRENT_SCHEMA,
    enabled = true,
    -- Default OFF: Blizzard popup queues stale errors and users click "next" forever.
    -- Capture into ForeverErrorLogDB still runs.
    scriptErrors = false,
    errors = {},
  }
end

Config.Defaults = Defaults

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
  end

  -- Future migrations: if from < 2 then … end

  if type(db.errors) ~= "table" then
    db.errors = {}
  end

  return db
end

--- Reset config to defaults and clear the error ring.
function Config.Reset()
  ForeverErrorLogDB = Defaults()
  return ForeverErrorLogDB
end
