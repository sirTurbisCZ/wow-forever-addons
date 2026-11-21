--[[ BetterBackpack — defaults, schemaVersion, migration ]]

BetterBackpack = BetterBackpack or {}

local CURRENT_SCHEMA = 1
local MAX_ERRORS = 40
local MAX_MSG = 2000

BetterBackpack.Config = BetterBackpack.Config or {}
local Config = BetterBackpack.Config

Config.CURRENT_SCHEMA = CURRENT_SCHEMA
Config.MAX_ERRORS = MAX_ERRORS
Config.MAX_MSG = MAX_MSG
Config.VERSION = "0.3.6"

local function ProfileDefaults()
  return {
    enabled = true,
    safeMode = false,
    replaceBlizzard = true,
    debug = false,
    columns = 8,
    scale = 1.0,
    collapsed = {},
    categories = {
      junk = true,
      consumable = true,
      reagent = true,
      gem = true,
      gear = true,
      quest = true,
      keys = true,
      container = true,
      other = true,
    },
    itemRules = {},
    pos = nil, -- { point, relPoint, x, y } when user-moved
    userMoved = false,
  }
end

local function Defaults()
  return {
    schemaVersion = CURRENT_SCHEMA,
    profile = ProfileDefaults(),
    errors = {},
    lastSelftest = nil,
    lastBlocked = nil,
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
    elseif type(v) == "table" and type(p[k]) == "table" then
      for kk, vv in pairs(v) do
        if p[k][kk] == nil then
          p[k][kk] = vv
        end
      end
    end
  end
end

function Config.EnsureDB()
  if type(BetterBackpackDB) ~= "table" then
    BetterBackpackDB = Defaults()
    return BetterBackpackDB
  end

  local db = BetterBackpackDB
  local from = tonumber(db.schemaVersion) or 0

  if from < 1 then
    EnsureProfile(db)
    if type(db.errors) ~= "table" then
      db.errors = {}
    end
    db.schemaVersion = 1
  end

  EnsureProfile(db)
  if type(db.errors) ~= "table" then
    db.errors = {}
  end

  return db
end

function Config.Reset()
  BetterBackpackDB = Defaults()
  return BetterBackpackDB
end

function Config.GetProfile()
  return Config.EnsureDB().profile
end
