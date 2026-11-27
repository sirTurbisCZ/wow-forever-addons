--[[ Seekwell — defaults, schemaVersion, migration ]]

Seekwell = Seekwell or {}
Seekwell.Config = Seekwell.Config or {}
local Config = Seekwell.Config

local CURRENT_SCHEMA = 1
Config.CURRENT_SCHEMA = CURRENT_SCHEMA
Config.VERSION = "0.5.5"

local function SettingsDefaults()
  return {
    minimap = { show = true, angle = 200 },
    tooltip = { enabled = true, max = 3, skipIfDropsShown = true }, -- "Seekwell: Mob 12.5 %" lines on item tooltips (1-5)
    classic = true, -- include Tinny's Classic estimates
    wishIgnoreOwned = true, -- owned wishlist items are ticked and left out of alerts, hunts and the zone summary
    hideQuest = false, -- hide quest items in the drop lists
    learn = true, -- learn drops from your own loot windows
    share = false, -- share learned data with group / guild (Net/Share.lua; default OFF)
    shareChannels = { party = true, guild = true }, -- owned by Net/Share.lua: where sharing sends / listens
    shareStats = true, -- owned by Net/Share.lua: show the share counters in /sw status
    dev = false,
    map = { enabled = true, minimap = true, minPct = 0, cellYards = 40, bundled = true }, -- owned by Map/*.lua (extend only this block)
    alerts = { enabled = true, wantedMob = true, wantedDrop = true, nameplates = false, sound = false,
      removeOnLoot = false, throttleSec = 60 }, -- owned by UI/Alerts.lua
    zone = { vendors = true, quests = true, maxMobs = 300 }, -- owned by UI/ZoneView.lua (+ Learn/Vendor.lua, Learn/Quest.lua: learn vendors / quest rewards)
    panel = { point = "CENTER", x = 320, y = 60 }, -- target panel position
    browser = { mode = "all", onlyLocated = false, onlyWish = false, minPct = 0, autoPin = true, filtersOpen = false, foreverOnly = false, locatedFirst = true }, -- owned by UI/Browser.lua (extend only this block)
    forever = { dj = true, nodes = true, learnEntrances = true, fdbData = true }, -- Forever content bridges (Data/DJBridge.lua: ForeverDungeonJournal at runtime; nodes: GatherLite, not used yet; fdb: Data/FDBBridge.lua, the ForeverDBData addon at runtime)
  }
end
Config.SettingsDefaults = SettingsDefaults

local function Copy(v)
  if type(v) ~= "table" then
    return v
  end
  local out = {}
  for k, x in pairs(v) do
    out[k] = Copy(x)
  end
  return out
end

--- Fill missing keys (recursively) from the defaults; never overwrites existing values.
local function Fill(t, d)
  for k, v in pairs(d) do
    if t[k] == nil then
      t[k] = Copy(v)
    elseif type(v) == "table" and type(t[k]) == "table" then
      Fill(t[k], v)
    end
  end
end
Config.Fill = Fill

local function LearnedDefaults()
  return { npc = {}, count = 0 }
end

local function Defaults()
  return { schemaVersion = CURRENT_SCHEMA, settings = SettingsDefaults(), learned = LearnedDefaults() }
end

local function CharDefaults()
  return { schemaVersion = CURRENT_SCHEMA, wish = {}, wishMobs = {} }
end

-- MIGRATIONS[n] upgrades a database from schema n to n + 1 (one step each).
-- Schema 1 is the first one: there is nothing older to convert yet.
local MIGRATIONS = {}
local CHAR_MIGRATIONS = {}

local function Migrate(db, steps)
  local v = tonumber(db.schemaVersion) or 0
  while v < CURRENT_SCHEMA do
    local step = (steps or MIGRATIONS)[v]
    if step then
      step(db)
    end
    v = v + 1
    db.schemaVersion = v
  end
end
Config.Migrate = Migrate

--- Ensure SeekwellDB exists, migrate, return it.
function Config.EnsureDB()
  if type(SeekwellDB) ~= "table" then
    SeekwellDB = Defaults()
    return SeekwellDB
  end
  local db = SeekwellDB
  Migrate(db)
  if type(db.settings) ~= "table" then
    db.settings = SettingsDefaults()
  end
  if type(db.learned) ~= "table" or type(db.learned.npc) ~= "table" then
    db.learned = LearnedDefaults()
  end
  db.schemaVersion = CURRENT_SCHEMA
  Fill(db.settings, SettingsDefaults())
  return db
end

function Config.EnsureCharDB()
  if type(SeekwellCharDB) ~= "table" then
    SeekwellCharDB = CharDefaults()
    return SeekwellCharDB
  end
  local c = SeekwellCharDB
  Migrate(c, CHAR_MIGRATIONS)
  if type(c.wish) ~= "table" then
    c.wish = {}
  end
  if type(c.wishMobs) ~= "table" then
    c.wishMobs = {} -- [npcID] = true: mobs wanted explicitly (UI/Alerts.lua)
  end
  c.schemaVersion = CURRENT_SCHEMA
  return c
end

function Config.Get()
  return Config.EnsureDB().settings
end

function Config.Learned()
  return Config.EnsureDB().learned
end

function Config.Char()
  return Config.EnsureCharDB()
end

--- Settings only; learned data and the wishlist are kept.
function Config.Reset()
  Config.EnsureDB().settings = SettingsDefaults()
  return SeekwellDB
end

function Config.ResetLearned()
  Config.EnsureDB().learned = LearnedDefaults()
  return SeekwellDB.learned
end
