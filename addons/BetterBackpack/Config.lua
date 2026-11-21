--[[ BetterBackpack — defaults, schemaVersion, migration ]]

BetterBackpack = BetterBackpack or {}

local CURRENT_SCHEMA = 5
local MAX_ERRORS = 40
local MAX_MSG = 2000

BetterBackpack.Config = BetterBackpack.Config or {}
local Config = BetterBackpack.Config

Config.CURRENT_SCHEMA = CURRENT_SCHEMA
Config.MAX_ERRORS = MAX_ERRORS
Config.MAX_MSG = MAX_MSG
Config.VERSION = "0.5.30"

local function ProfileDefaults()
  return {
    enabled = true,
    safeMode = false,
    replaceBlizzard = true,
    debug = false,
    columns = 10, -- CombinedBags / BagShelves width feel
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
      trash = false, -- auto-destroy lane, opt-in
      other = true,
    },
    itemRules = {},
    trash = { confirm = false, confirmed = {}, destroyed = {}, log = {} },
    -- Nice-to-have (from betterbackpack/features-nth): optional Feat() modules.
    searchQuery = "",
    filterCategory = nil, -- nil / "all" = no filter; else category key
    customCategories = {}, -- { { id, name, itemIDs = {} } }
    hiddenDefaults = {}, -- { junk = true } → hide default lane (items → Other)
    stackMerge = true, -- visual merge same itemID
    fillEmptyWells = false, -- opt-in: empty slot wells in space freed by collapse / search
    pins = {}, -- { [itemID] = true } red ghost when not owned
    layoutMode = "lanes", -- "lanes" | "dense"
    bagBarNativeBag = true, -- bag-bar → Blizzard ContainerFrame; B → BetterBackpack combined
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
    from = 1
  end

  -- 0.4.2: match CombinedBags/BagShelves default width (10 cols).
  if from < 2 then
    EnsureProfile(db)
    local p = db.profile
    if type(p) == "table" and (p.columns == nil or p.columns == 8) then
      p.columns = 10
    end
    db.schemaVersion = 2
    from = 2
  end

  -- 0.5.6: 0.5.4/0.5.5 lanes rendered empty, so players clicked every header shut.
  -- Categories default expanded; drop that stuck collapse state once.
  if from < 3 then
    EnsureProfile(db)
    if type(db.profile) == "table" then
      db.profile.collapsed = {}
    end
    db.schemaVersion = 3
    from = 3
  end

  -- 0.5.9: empty fill wells off by default (0.5.8 shipped them on).
  if from < 4 then
    EnsureProfile(db)
    if type(db.profile) == "table" then
      db.profile.fillEmptyWells = false
    end
    db.schemaVersion = 4
    from = 4
  end

  -- 0.5.24: Trash destroys on drop without confirm unless user re-enables in Settings.
  if from < 5 then
    EnsureProfile(db)
    if type(db.profile) == "table" and type(db.profile.trash) == "table" then
      db.profile.trash.confirm = false
    end
    db.schemaVersion = 5
    from = 5
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
