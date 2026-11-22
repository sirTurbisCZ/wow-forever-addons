--[[ BetterBackpack — defaults, schemaVersion, migration ]]

BetterBackpack = BetterBackpack or {}

local CURRENT_SCHEMA = 8
local MAX_ERRORS = 40
local MAX_MSG = 2000

BetterBackpack.Config = BetterBackpack.Config or {}
local Config = BetterBackpack.Config

Config.CURRENT_SCHEMA = CURRENT_SCHEMA
Config.MAX_ERRORS = MAX_ERRORS
Config.MAX_MSG = MAX_MSG
Config.VERSION = "1.2.4"

local function CharVendorDefaults()
  return {
    autoSellJunk = false,
    autoSellJunkLane = false,
    autoSellMarked = {}, -- [itemID] = true — always sell at vendor (this character)
  }
end

Config.CharVendorDefaults = CharVendorDefaults

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
      recipe = true,
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
    stackMerge = true, -- visual merge same itemID + same isLocked
    fillEmptyWells = false, -- opt-in: empty slot wells in space freed by collapse / search
    pins = {}, -- { [itemID] = true } red ghost when not owned
    layoutMode = "lanes", -- "lanes" | "dense"
    bagBarNativeBag = true, -- bar slots → native single bag; main backpack + B → BB combined
    autoSellJunk = false, -- vendor: auto-sell poor (grey) quality items
    autoSellJunkLane = false, -- vendor: also sell non-grey items in Junk lane (opt-in)
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

  -- 0.5.63: vendor auto-sell defaults (off).
  if from < 6 then
    EnsureProfile(db)
    if type(db.profile) == "table" then
      if db.profile.autoSellJunk == nil then
        db.profile.autoSellJunk = false
      end
      if db.profile.autoSellJunkLane == nil then
        db.profile.autoSellJunkLane = false
      end
    end
    db.schemaVersion = 6
    from = 6
  end

  -- 1.2.2: Recipes lane enabled for existing profiles.
  if from < 7 then
    EnsureProfile(db)
    if type(db.profile) == "table" and type(db.profile.categories) == "table" then
      if db.profile.categories.recipe == nil then
        db.profile.categories.recipe = true
      end
    end
    db.schemaVersion = 7
    from = 7
  end

  -- 1.2.4: vendor auto-sell prefs per character (migrate current char from account profile).
  if from < 8 then
    EnsureProfile(db)
    db.chars = type(db.chars) == "table" and db.chars or {}
    local key
    if UnitName then
      local name = UnitName("player")
      local realm = (GetRealmName and GetRealmName()) or ""
      if name and name ~= "" then
        key = tostring(name) .. "-" .. tostring(realm)
      end
    end
    if key and type(db.profile) == "table" then
      local c = db.chars[key]
      if type(c) ~= "table" then
        c = {}
        db.chars[key] = c
      end
      if c.autoSellJunk == nil then
        c.autoSellJunk = db.profile.autoSellJunk == true
      end
      if c.autoSellJunkLane == nil then
        c.autoSellJunkLane = db.profile.autoSellJunkLane == true
      end
      if type(c.autoSellMarked) ~= "table" then
        c.autoSellMarked = {}
      end
    end
    db.schemaVersion = 8
    from = 8
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

function Config.CharKey()
  if not UnitName then
    return nil
  end
  local name = UnitName("player")
  if not name or name == "" then
    return nil
  end
  local realm = (GetRealmName and GetRealmName()) or ""
  return tostring(name) .. "-" .. tostring(realm)
end

function Config.EnsureCharProfile(db, key)
  if not key or key == "" then
    return nil
  end
  db.chars = type(db.chars) == "table" and db.chars or {}
  local c = db.chars[key]
  if type(c) ~= "table" then
    c = {}
    db.chars[key] = c
  end
  local d = CharVendorDefaults()
  for k, v in pairs(d) do
    if c[k] == nil then
      c[k] = v
    end
  end
  if type(c.autoSellMarked) ~= "table" then
    c.autoSellMarked = {}
  end
  return c
end

function Config.GetCharProfile()
  local db = Config.EnsureDB()
  local key = Config.CharKey()
  if not key then
    db._charVendorStub = db._charVendorStub or CharVendorDefaults()
    if type(db._charVendorStub.autoSellMarked) ~= "table" then
      db._charVendorStub.autoSellMarked = {}
    end
    return db._charVendorStub
  end
  return Config.EnsureCharProfile(db, key)
end
