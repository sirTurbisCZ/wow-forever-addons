--[[
  Seekwell.Locations — bridge to the optional load-on-demand addon Seekwell_Locations
  (original Classic spawn points, pfQuest / CMaNGOS classic-db, GPL-3.0).
  SeekwellLocations = { version, zones = { "Zone", ... }, zoneIds = { ["Zone"] = uiMapID },
                        npc = { [npcID] = { zoneIndex, { x, y, x, y, ... } } } }
  The data addon is loaded on the first call that needs data, never at login and never in combat
  (deferred to PLAYER_REGEN_ENABLED). Without it every lookup returns nil / empty lists.
]]

Seekwell = Seekwell or {}
local L = {}
Seekwell.Locations = L

local ADDON = "Seekwell_Locations"
local state = { loaded = false, tried = false, failed = nil, waiting = false }
local mapIndex = {} -- [mapID] = { npcID, ... }
local npcCount = nil

local function Err(context, err)
  local f = Seekwell.RecordError
  if f then
    pcall(f, "locations." .. context, err)
  end
end

local function Guard(context, fn)
  return function(...)
    local ok, a, b = pcall(fn, ...)
    if not ok then
      Err(context, a)
      return nil
    end
    return a, b
  end
end

local function Data()
  local d = rawget(_G, "SeekwellLocations")
  if type(d) == "table" and type(d.npc) == "table" then
    return d
  end
  return nil
end

local function InCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

--- true when the data addon is installed (enabled or not) or its data is already present.
L.Available = Guard("available", function()
  if Data() then
    return true
  end
  local api = rawget(_G, "C_AddOns")
  if api and api.DoesAddOnExist then
    return api.DoesAddOnExist(ADDON) and true or false
  end
  local info = (api and api.GetAddOnInfo) or rawget(_G, "GetAddOnInfo")
  if info then
    local name, _, _, _, reason = info(ADDON)
    return name ~= nil and reason ~= "MISSING"
  end
  return false
end)

local function Loaded()
  if Data() and not state.loaded then
    state.loaded = true
    if Seekwell.Spawns then
      Seekwell.Spawns.generation = (Seekwell.Spawns.generation or 0) + 1
    end
  end
  return state.loaded
end

local waiter
local function DeferUntilCombatEnds()
  if state.waiting or not CreateFrame then
    return
  end
  if not waiter then
    waiter = CreateFrame("Frame")
    waiter:SetScript("OnEvent", function(self)
      self:UnregisterEvent("PLAYER_REGEN_ENABLED")
      state.waiting = false
      L.Load()
    end)
  end
  state.waiting = true
  waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
end

--- Load the data addon once. Returns true when the data is present.
L.Load = Guard("load", function()
  if state.loaded or Data() then
    return Loaded()
  end
  if state.tried then
    return false
  end
  if InCombat() then
    DeferUntilCombatEnds()
    return false
  end
  if not L.Available() then
    state.tried, state.failed = true, "MISSING"
    return false
  end
  state.tried = true
  local api = rawget(_G, "C_AddOns")
  local load = (api and api.LoadAddOn) or rawget(_G, "LoadAddOn")
  if not load then
    state.failed = "NO_API"
    return false
  end
  local ok, res, reason = pcall(load, ADDON)
  if not ok then
    state.failed = "ERROR"
    Err("loadaddon", res)
    return false
  end
  if not res and not Data() then
    state.failed = tostring(reason or "FAILED")
    return false
  end
  return Loaded()
end)

local function Ensure()
  if state.loaded then
    return Data()
  end
  if L.Load() then
    return Data()
  end
  return nil
end

--- mapID, { {x, y}, ... } for an npc; nil when unknown.
L.ForMob = Guard("formob", function(npcID)
  local d = Ensure()
  local e = d and d.npc[tonumber(npcID) or -1]
  if type(e) ~= "table" then
    return nil
  end
  local zone = type(e[1]) == "number" and d.zones and d.zones[e[1]] or e[1]
  local mapID = d.zoneIds and d.zoneIds[zone]
  local c = e[2]
  if not mapID or type(c) ~= "table" then
    return nil
  end
  local pts = {}
  for i = 1, #c - 1, 2 do
    pts[#pts + 1] = { x = c[i], y = c[i + 1] }
  end
  return mapID, pts
end)

L.MapsForMob = Guard("mapsformob", function(npcID)
  local mapID = L.ForMob(npcID)
  return mapID and { mapID } or {}
end)

--- { npcID, ... } with bundled points on that map (built lazily per map, cached, sorted).
L.MobsInMap = Guard("mobsinmap", function(mapID)
  mapID = tonumber(mapID)
  if not mapID then
    return {}
  end
  local d = Ensure()
  if not d then
    return {}
  end
  local list = mapIndex[mapID]
  if list then
    return list
  end
  list = {}
  for npcID, e in pairs(d.npc) do
    local zone = type(e[1]) == "number" and d.zones and d.zones[e[1]] or e[1]
    if d.zoneIds and d.zoneIds[zone] == mapID then
      list[#list + 1] = npcID
    end
  end
  table.sort(list)
  mapIndex[mapID] = list
  return list
end)

local function Count()
  local d = Data()
  if not d then
    return 0
  end
  if not npcCount then
    local n = 0
    for _ in pairs(d.npc) do
      n = n + 1
    end
    npcCount = n
  end
  return npcCount
end

L.Info = Guard("info", function()
  return { npcs = Count(), loaded = state.loaded, available = L.Available() and true or false, failed = state.failed }
end)

local function Enabled()
  local ok, s = pcall(function()
    return Seekwell.Config.Get().map
  end)
  return not (ok and type(s) == "table" and s.bundled == false)
end
L.Enabled = Enabled

L.Status = Guard("status", function()
  local i = L.Info() or {}
  local use = Enabled() and "on" or "off"
  if not i.available then
    return "Classic spawn data " .. use .. " · Seekwell_Locations not installed (pins from your loot only)"
  end
  if not i.loaded then
    local extra = i.failed and (" · load failed: " .. i.failed) or (state.waiting and " · waiting for combat to end" or " · loads when first needed")
    return "Classic spawn data " .. use .. " · not loaded" .. extra
  end
  return string.format("Classic spawn data %s · %d mobs (original Classic spawns, approximate)", use, i.npcs or 0)
end)

local function Print(...)
  if Seekwell.Print then
    Seekwell.Print(...)
  else
    print(...)
  end
end

L.Slash = Guard("slash", function(rest)
  local cmd = (tostring(rest or ""):match("^%s*(%S*)") or ""):lower()
  local map = Seekwell.Config.Get().map
  if cmd == "on" or cmd == "off" then
    map.bundled = (cmd == "on")
    if Seekwell.Spawns then
      Seekwell.Spawns.generation = (Seekwell.Spawns.generation or 0) + 1
    end
    if map.bundled then
      L.Load()
    end
    Print("Classic spawn data " .. cmd)
  elseif cmd == "" or cmd == "status" then
    Print((L.Status()))
  else
    Print("usage: /sw locations on|off|status")
  end
end)

--- test hook: forget load state and caches
function L._Reset()
  state = { loaded = false, tried = false, failed = nil, waiting = false }
  mapIndex, npcCount = {}, nil
end

if Seekwell.RegisterSlash then
  Seekwell.RegisterSlash("locations", function(rest)
    L.Slash(rest)
  end)
end
if Seekwell.RegisterStatus then
  Seekwell.RegisterStatus("locations", function()
    return (L.Status())
  end)
end
