--[[ Plateband — defaults, schemaVersion, migration ]]

Plateband = Plateband or {}

local CURRENT_SCHEMA = 7
local MAX_ERRORS = 40
local MAX_MSG = 2000

Plateband.Config = Plateband.Config or {}
local Config = Plateband.Config

Config.CURRENT_SCHEMA = CURRENT_SCHEMA
Config.MAX_ERRORS = MAX_ERRORS
Config.MAX_MSG = MAX_MSG
Config.VERSION = "0.2.6"

local function ProfileDefaults()
  return {
    enabled = true,
    safeMode = false,
    iconSize = 18,
    maxIcons = 12,
    showBand = true,
    -- Never replace/park native DebuffList (personal = Blizzard only).
    paintOverlay = false,
    -- 0.1.15: safe beside-native merge default on (schema 6 had opt-in off).
    mergeMissing = true,
    watchOn = false,
    watchInterval = 2,
    autoDiag = true,
    chatOnChange = false,
  }
end

local function Defaults()
  return {
    schemaVersion = CURRENT_SCHEMA,
    profile = ProfileDefaults(),
    errors = {},
    lastDiagnose = nil,
    lastDiag = nil, -- alias
    sessionLog = {
      startedAt = 0,
      lines = {},
      fileOk = false,
      export = "",
    },
  }
end

Config.Defaults = Defaults
Config.ProfileDefaults = ProfileDefaults

local function EnsureProfile(db)
  if type(db.profile) ~= "table" then
    db.profile = ProfileDefaults()
    return
  end
  local p = db.profile
  local d = ProfileDefaults()
  for k, v in pairs(d) do
    if p[k] == nil then
      p[k] = v
    end
  end
end

local function EnsureSessionLog(db)
  if type(db.sessionLog) ~= "table" then
    db.sessionLog = {
      startedAt = 0,
      lines = {},
      fileOk = false,
      export = "",
    }
  end
  if type(db.sessionLog.lines) ~= "table" then
    db.sessionLog.lines = {}
  end
end

--- Ensure PlatebandDB exists, migrate schema, return db.
function Config.EnsureDB()
  if type(PlatebandDB) ~= "table" then
    PlatebandDB = Defaults()
    return PlatebandDB
  end

  local db = PlatebandDB
  local from = tonumber(db.schemaVersion) or 0

  if from < 1 then
    EnsureProfile(db)
    if type(db.errors) ~= "table" then
      db.errors = {}
    end
    db.schemaVersion = 1
    from = 1
  end

  if from < 2 then
    EnsureSessionLog(db)
    EnsureProfile(db)
    if db.lastDiagnose == nil and db.lastDiag ~= nil then
      db.lastDiagnose = db.lastDiag
    end
    db.schemaVersion = 2
    from = 2
  end

  if from < 3 then
    EnsureProfile(db)
    -- Kill chat flood from v0.1.1 chatOnChange=true default.
    db.profile.chatOnChange = false
    db.schemaVersion = 3
    from = 3
  end

  if from < 4 then
    EnsureProfile(db)
    -- Solo native-first: never cover name/health with overlay paint.
    db.profile.paintOverlay = false
    db.schemaVersion = 4
    from = 4
  end

  if from < 5 then
    EnsureProfile(db)
    db.profile.paintOverlay = false
    db.profile.mergeMissing = true
    db.schemaVersion = 5
    from = 5
  end

  if from < 6 then
    EnsureProfile(db)
    -- Name mutation broke Forever plates — force native-only until merge is opt-in safe.
    db.profile.paintOverlay = false
    db.profile.mergeMissing = false
    db.schemaVersion = 6
    from = 6
  end

  if from < 7 then
    EnsureProfile(db)
    db.profile.paintOverlay = false
    db.profile.mergeMissing = true
    db.schemaVersion = 7
  end

  EnsureProfile(db)
  EnsureSessionLog(db)
  if type(db.errors) ~= "table" then
    db.errors = {}
  end

  return db
end

function Config.Reset()
  PlatebandDB = Defaults()
  return PlatebandDB
end

function Config.GetProfile()
  return Config.EnsureDB().profile
end
