--[[ Wayfarer — defaults, schemaVersion, migration ]]

Wayfarer = Wayfarer or {}
Wayfarer.Config = Wayfarer.Config or {}
local Config = Wayfarer.Config

local CURRENT_SCHEMA = 1
Config.CURRENT_SCHEMA = CURRENT_SCHEMA
Config.VERSION = "0.3.1"

local function ProfileDefaults()
  return {
    minimap = { show = true, angle = 215 },
    partyMarks = {
      enabled = true,
      outline = true, -- coloured outline around the health bar
      badge = true, -- small P / R tag left of the bar
      colorMode = "class", -- "class" or "custom"
      partyColor = { r = 0.20, g = 0.90, b = 0.30 },
      raidColor = { r = 1.00, g = 0.55, b = 0.10 },
      thickness = 2,
    },
    procHUD = { -- owned by Modules/ProcHUD.lua (extend only this block)
      enabled = true,
      meter = true, -- Arcane Blast stack meter
      upcoming = true, -- the next stack is shown dimmed while its cast runs
      procs = true, -- proc icons (Clearcasting, Missile Barrage, ...)
      container = true, -- proc icons drawn by a Blizzard AuraContainer (works in combat); false = own icons only
      learnedIds = {}, -- proc aura spell ids seen out of combat (bounded), fed to the container
      dumpHint = true, -- Missiles / Barrage icons at max stacks
      actionGlow = false, -- own overlay over matching action bar buttons
      scale = 100, -- percent, 50-200
      locked = true,
      x = 0, -- HUD centre offset from the screen centre (UIParent units)
      y = -160,
      -- abWindow / abRefresh: learned from the real aura at runtime (nil = unknown, constants used)
    },
    easyFish = { -- owned by Modules/EasyFish.lua (extend only this block)
      enabled = true, -- nothing is bound until a key is chosen (easyFish.key, e.g. "F" or "ALT-F")
      poleOnly = true, -- take the key only while a fishing pole is equipped
      reach = true, -- raise the soft-interact reach while a cast runs (put back after it)
      loud = false, -- sound effects at full volume while a cast runs (put back after it)
      -- easyFish.restore (runtime): CVars a session changed, put back at the next login after a crash
    },
  }
end
Config.ProfileDefaults = ProfileDefaults

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

--- Fill missing keys (recursively) from the defaults; replaces a saved value only where a table is expected.
local function Fill(t, d)
  for k, v in pairs(d) do
    if t[k] == nil then
      t[k] = Copy(v)
    elseif type(v) == "table" then
      if type(t[k]) == "table" then
        Fill(t[k], v)
      else
        t[k] = Copy(v) -- wrong type in the saved data (e.g. procHUD = true): start that block again
      end
    end
  end
end

local function Defaults()
  return { schemaVersion = CURRENT_SCHEMA, profile = ProfileDefaults() }
end

--- Ensure WayfarerDB exists, migrate, return it.
function Config.EnsureDB()
  if type(WayfarerDB) ~= "table" then
    WayfarerDB = Defaults()
    return WayfarerDB
  end
  local db = WayfarerDB
  if type(db.profile) ~= "table" then
    db.profile = ProfileDefaults()
  end
  -- (future migrations: if (db.schemaVersion or 0) < N then ... end)
  db.schemaVersion = CURRENT_SCHEMA
  Fill(db.profile, ProfileDefaults())
  return db
end

function Config.GetProfile()
  -- Hot path (timer ticks, every nameplate update): skip the default-table merge once the database is ensured.
  local db = WayfarerDB
  if type(db) == "table" and db.schemaVersion == CURRENT_SCHEMA and type(db.profile) == "table" then
    local p = db.profile
    if type(p.minimap) == "table" and type(p.partyMarks) == "table" and type(p.procHUD) == "table"
      and type(p.easyFish) == "table" then
      return p
    end
  end
  return Config.EnsureDB().profile
end

function Config.Reset()
  WayfarerDB = Defaults()
  return WayfarerDB
end
