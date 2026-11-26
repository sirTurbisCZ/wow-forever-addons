--[[ BetterBackpack — defaults, schemaVersion, migration ]]

BetterBackpack = BetterBackpack or {}

local CURRENT_SCHEMA = 12
local MAX_ERRORS = 40
local MAX_MSG = 2000

BetterBackpack.Config = BetterBackpack.Config or {}
local Config = BetterBackpack.Config

Config.CURRENT_SCHEMA = CURRENT_SCHEMA
Config.MAX_ERRORS = MAX_ERRORS
Config.MAX_MSG = MAX_MSG
Config.VERSION = "1.3.7"

local function CharVendorDefaults()
  return {
    -- Trash (destroy) lane state is per character since schema 11; confirm is ON by default.
    trash = { confirm = true, confirmed = {}, destroyed = {}, log = {} },
    autoSellJunk = false,
    autoSellJunkLane = false,
    autoSellMarked = {}, -- [itemID] = true — always sell at vendor (this character)
    customCategories = {}, -- { { id, name, itemIDs = {} } } per character
    itemRules = {}, -- drag-teach → custom_* lanes (per character)
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
    -- Nice-to-have (from betterbackpack/features-nth): optional Feat() modules.
    searchQuery = "",
    filterCategory = nil, -- nil / "all" = no filter; else category key
    customCategories = {}, -- { { id, name, itemIDs = {} } }
    hiddenDefaults = {}, -- { junk = true } → hide default lane (items → Other)
    stackMerge = true, -- visual merge same itemID + same isLocked
    fillEmptyWells = false, -- opt-in: empty slot wells in space freed by collapse / search
    pins = {}, -- { [itemID] = true } red ghost when not owned
    layoutMode = "lanes", -- "lanes" | "dense"
    autoSellJunk = false, -- vendor: auto-sell poor (grey) quality items
    autoSellJunkLane = false, -- vendor: also sell non-grey items in Junk lane (opt-in)
    pos = nil, -- { point, relPoint, x, y } when user-moved
    userMoved = false,
    -- Silent session trace → BetterBackpackDB (no bulk/vendor chat spam).
    silentTrace = true,
    actionTraceOn = true,
  }
end

local function Defaults()
  return {
    schemaVersion = CURRENT_SCHEMA,
    profile = ProfileDefaults(),
    errors = {},
    lastSelftest = nil,
    lastBlocked = nil,
    sessionLog = { startedAt = 0, lines = {}, export = "" },
    actionTrace = { startedAt = 0, entries = {}, export = "" },
    lastActionTrace = nil,
  }
end

local function EnsureSessionLog(db)
  if type(db.sessionLog) ~= "table" then
    db.sessionLog = { startedAt = 0, lines = {}, export = "" }
  end
  if type(db.sessionLog.lines) ~= "table" then
    db.sessionLog.lines = {}
  end
  if type(db.actionTrace) ~= "table" then
    db.actionTrace = { startedAt = 0, entries = {}, export = "" }
  end
  if type(db.actionTrace.entries) ~= "table" then
    db.actionTrace.entries = {}
  end
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

  -- 1.2.6: custom lanes + custom item rules per character; migrate current char from profile.
  if from < 9 then
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
    local function CopyCustomCategories(src)
      local out = {}
      if type(src) ~= "table" then
        return out
      end
      for i = 1, #src do
        local e = src[i]
        if type(e) == "table" and type(e.id) == "string" then
          local itemIDs = {}
          if type(e.itemIDs) == "table" then
            for k, v in pairs(e.itemIDs) do
              itemIDs[k] = v
            end
          end
          out[#out + 1] = {
            id = e.id,
            name = e.name or e.id,
            itemIDs = itemIDs,
          }
        end
      end
      return out
    end
    if key and type(db.profile) == "table" then
      local c = db.chars[key]
      if type(c) ~= "table" then
        c = {}
        db.chars[key] = c
      end
      local hadCustom = type(db.profile.customCategories) == "table" and #db.profile.customCategories > 0
      if hadCustom then
        if type(c.customCategories) ~= "table" or #c.customCategories == 0 then
          c.customCategories = CopyCustomCategories(db.profile.customCategories)
        end
      end
      if type(c.itemRules) ~= "table" then
        c.itemRules = {}
      end
      if type(db.profile.itemRules) == "table" then
        for itemID, rule in pairs(db.profile.itemRules) do
          if type(rule) == "string" and rule:find("^custom_", 1) then
            if c.itemRules[itemID] == nil then
              c.itemRules[itemID] = rule
            end
          end
        end
      end
      db.profile.customCategories = {}
      if type(db.profile.itemRules) == "table" then
        for itemID, rule in pairs(db.profile.itemRules) do
          if type(rule) == "string" and rule:find("^custom_", 1) then
            db.profile.itemRules[itemID] = nil
          end
        end
      end
    end
    db.schemaVersion = 9
    from = 9
  end

  -- 1.2.7: silent ACTION trace (agent-readable SV, wipe each login).
  if from < 10 then
    EnsureProfile(db)
    if type(db.profile) == "table" then
      if db.profile.silentTrace == nil then
        db.profile.silentTrace = true
      end
      if db.profile.actionTraceOn == nil then
        db.profile.actionTraceOn = true
      end
    end
    EnsureSessionLog(db)
    db.schemaVersion = 10
    from = 10
  end

  -- 1.3.0: Trash rules + confirm state become per character. Account-wide trash rules are parked in
  -- db.legacyTrash and copied to EVERY character on its first login (EnsureCharProfile).
  if from < 11 then
    EnsureProfile(db)
    if type(db.profile) == "table" then
      local legacy = { rules = {}, confirmed = {}, destroyed = {} }
      if type(db.profile.itemRules) == "table" then
        for itemID, rule in pairs(db.profile.itemRules) do
          if rule == "trash" then
            legacy.rules[itemID] = "trash"
            db.profile.itemRules[itemID] = nil
          end
        end
      end
      local old = db.profile.trash
      if type(old) == "table" then
        if type(old.confirmed) == "table" then
          for k, v in pairs(old.confirmed) do
            legacy.confirmed[k] = v
          end
        end
        if type(old.destroyed) == "table" then
          for k, v in pairs(old.destroyed) do
            legacy.destroyed[k] = v
          end
        end
      end
      db.profile.trash = nil
      db.legacyTrash = legacy
    end
    db.schemaVersion = 11
    from = 11
  end

  -- 1.3.4: ALL item rules (built-in lanes too) are per character. Remaining account rules are parked in
  -- db.legacyRules and copied to every character on its first login (EnsureCharProfile).
  if from < 12 then
    EnsureProfile(db)
    local legacy = {}
    if type(db.profile) == "table" and type(db.profile.itemRules) == "table" then
      for itemID, rule in pairs(db.profile.itemRules) do
        if type(rule) == "string" and rule ~= "" then
          legacy[itemID] = rule
        end
      end
      db.profile.itemRules = {}
    end
    db.legacyRules = legacy
    db.schemaVersion = 12
    from = 12
  end

  EnsureProfile(db)
  if type(db.errors) ~= "table" then
    db.errors = {}
  end
  EnsureSessionLog(db)

  return db
end

--- Reset("all") wipes everything (every character). Reset() resets account settings + the CURRENT
--- character only; other characters keep their lanes, rules and vendor settings.
function Config.Reset(scope)
  if scope == "all" or type(BetterBackpackDB) ~= "table" then
    BetterBackpackDB = Defaults()
    return BetterBackpackDB
  end
  local db = Config.EnsureDB()
  db.profile = ProfileDefaults()
  local key = Config.CharKey()
  if key and type(db.chars) == "table" then
    -- *Migrated=true: a reset character must not get the legacy account rules copied back.
    db.chars[key] = { trashMigrated = true, rulesMigrated = true }
  end
  return db
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
  if type(c.customCategories) ~= "table" then
    c.customCategories = {}
  end
  if type(c.itemRules) ~= "table" then
    c.itemRules = {}
  end
  if type(c.trash) ~= "table" then
    c.trash = { confirm = true, confirmed = {}, destroyed = {}, log = {} }
  end
  for _, k in ipairs({ "confirmed", "destroyed", "log" }) do
    if type(c.trash[k]) ~= "table" then
      c.trash[k] = {}
    end
  end
  if c.trash.confirm == nil then
    c.trash.confirm = true
  end
  -- Schema 12: copy the former account-wide item rules into this character once.
  if not c.rulesMigrated then
    c.rulesMigrated = true
    local legacyRules = db.legacyRules
    if type(legacyRules) == "table" then
      for itemID, rule in pairs(legacyRules) do
        if c.itemRules[itemID] == nil and c.itemRules[tostring(itemID)] == nil then
          c.itemRules[itemID] = rule
        end
      end
    end
  end
  -- Schema 11: copy the former account-wide trash rules into this character once.
  if not c.trashMigrated then
    c.trashMigrated = true
    local legacy = db.legacyTrash
    if type(legacy) == "table" then
      for itemID, rule in pairs(legacy.rules or {}) do
        if c.itemRules[itemID] == nil and c.itemRules[tostring(itemID)] == nil then
          c.itemRules[itemID] = rule
        end
      end
      for k, v in pairs(legacy.confirmed or {}) do
        c.trash.confirmed[k] = v
      end
      for k, v in pairs(legacy.destroyed or {}) do
        c.trash.destroyed[k] = v
      end
    end
  end
  return c
end

function Config.GetCharProfile()
  local db = Config.EnsureDB()
  local key = Config.CharKey()
  if not key then
    db._charVendorStub = db._charVendorStub or CharVendorDefaults()
    local s = db._charVendorStub
    if type(s.autoSellMarked) ~= "table" then
      s.autoSellMarked = {}
    end
    if type(s.customCategories) ~= "table" then
      s.customCategories = {}
    end
    if type(s.itemRules) ~= "table" then
      s.itemRules = {}
    end
    if type(s.trash) ~= "table" then
      s.trash = { confirm = true, confirmed = {}, destroyed = {}, log = {} }
    end
    return s
  end
  return Config.EnsureCharProfile(db, key)
end
