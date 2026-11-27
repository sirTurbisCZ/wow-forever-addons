--[[
  Seekwell.Position — learns where mobs live: on LOOT_OPENED, the player's map position is stored
  for every creature in the loot window (Seekwell.Spawns). Secret or missing positions learn nothing.
]]

Seekwell = Seekwell or {}
local Pos = {}
Seekwell.Position = Pos

local frame

--- uiMapID, x, y of the player, or nil (unknown, secret, or the API is missing).
function Pos.PlayerPosition()
  local Sec = Seekwell.Secret
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
    return nil
  end
  local mapID = tonumber(Sec.Get(C_Map.GetBestMapForUnit, "player"))
  if not mapID then
    return nil
  end
  local pos = Sec.Get(C_Map.GetPlayerMapPosition, mapID, "player")
  if type(pos) ~= "table" and type(pos) ~= "userdata" then
    return nil
  end
  local ok, x, y = pcall(pos.GetXY, pos)
  if not ok then
    return nil
  end
  x, y = tonumber(Sec.Plain(x)), tonumber(Sec.Plain(y))
  if not x or not y or (x == 0 and y == 0) then
    return nil
  end
  return mapID, x, y
end

local function LootNpcs()
  local Sec = Seekwell.Secret
  local n = tonumber(Sec.Get(GetNumLootItems)) or 0
  local out, seen = {}, {}
  if n <= 0 or not GetLootSourceInfo then
    return out
  end
  for slot = 1, n do
    local res = { pcall(GetLootSourceInfo, slot) }
    if res[1] then
      for i = 2, #res, 2 do
        local id = Sec.NpcIDFromGUID(res[i])
        if id and not seen[id] then
          seen[id] = true
          out[#out + 1] = id
        end
      end
    end
  end
  return out
end

function Pos.OnLootOpened()
  if not Seekwell.Config.Get().learn then
    return
  end
  local npcs = LootNpcs()
  if #npcs == 0 then
    return
  end
  local mapID, x, y = Pos.PlayerPosition()
  if not mapID then
    return
  end
  local added = false
  for _, npcID in ipairs(npcs) do
    if Seekwell.Spawns.Add(npcID, mapID, x, y) then
      added = true
    end
  end
  if added and Seekwell.Map and Seekwell.Map.OnDataChanged then
    Seekwell.Map.OnDataChanged()
  end
end

-- dungeon entrances: the last outdoor position before entering an instance -----------------------
-- learned.entrance[instanceName] = { m = uiMapID, x = 0..1, y = 0..1, s = time } (only for dungeons the
-- Dungeon Journal bridge cannot place; ids/names are never range-filtered, Forever-only content included)
local lastOut, lastOutT, wasOutdoor = nil, 0, true
local ENTRANCE_MAX_AGE = 180 -- s between the last outdoor fix and the loading screen

local function InInstance()
  if not IsInInstance then
    return false
  end
  local ok, v = pcall(IsInInstance)
  return ok and Seekwell.Secret.Plain(v) == true
end

--- settings.forever.learnEntrances (default on; independent of settings.learn for the ticker switch)
local function LearnEntrances()
  local s = Seekwell.Config.Get()
  local f = type(s.forever) == "table" and s.forever or nil
  return not (f and f.learnEntrances == false)
end
Pos.LearnEntrances = LearnEntrances

function Pos.NoteOutdoor()
  if not LearnEntrances() or InInstance() then
    return
  end
  local m, x, y = Pos.PlayerPosition()
  if m then
    lastOut, lastOutT = { m = m, x = x, y = y }, (GetTime and GetTime()) or 0
  end
end

function Pos.OnEnteringWorld()
  local inside = InInstance()
  if inside and wasOutdoor and lastOut and LearnEntrances() and Seekwell.Config.Get().learn ~= false then
    local now = (GetTime and GetTime()) or 0
    local Sec = Seekwell.Secret
    local ok, name, kind = pcall(GetInstanceInfo)
    name, kind = ok and Sec.Str(name) or nil, ok and Sec.Str(kind) or nil
    local DJ = Seekwell.DJ
    local je = DJ and (DJ.FindByInstance or DJ.Get)(name)
    local placed = je and je.entrance
    if name and name ~= "" and (kind == "party" or kind == "raid") and not placed and now - lastOutT <= ENTRANCE_MAX_AGE then
      local l = Seekwell.Config.Learned()
      if type(l.entrance) ~= "table" then
        l.entrance = {}
      end
      l.entrance[name] = { m = lastOut.m, x = math.floor(lastOut.x * 1000 + 0.5) / 1000, y = math.floor(lastOut.y * 1000 + 0.5) / 1000,
        s = time and time() or 0 }
    end
  end
  wasOutdoor = not inside
  if not inside then
    Pos.NoteOutdoor()
  end
end

function Pos.Start()
  if frame then
    return
  end
  frame = CreateFrame("Frame")
  frame:RegisterEvent("LOOT_OPENED")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:RegisterEvent("ZONE_CHANGED")
  frame:RegisterEvent("ZONE_CHANGED_INDOORS")
  frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  frame:RegisterEvent("PLAYER_STOPPED_MOVING")
  frame:SetScript("OnEvent", Seekwell.Safe("position", function(_, event)
    if event == "LOOT_OPENED" then
      Pos.OnLootOpened()
      Pos.NoteOutdoor()
    elseif event == "PLAYER_ENTERING_WORLD" then
      Pos.OnEnteringWorld()
    else
      Pos.NoteOutdoor()
    end
  end))
  Pos.UpdateTicker()
end

local ticker
--- One cheap position read every 5 s while outdoors (the portal walk-in is rarely a stop); runs only while
--- settings.forever.learnEntrances is on, cancelled entirely when it is off.
function Pos.UpdateTicker()
  local want = LearnEntrances()
  if want and not ticker and C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(5, Seekwell.Safe("position.tick", function()
      if wasOutdoor then
        Pos.NoteOutdoor()
      end
    end))
  elseif not want and ticker then
    ticker:Cancel()
    ticker = nil
    lastOut = nil
  end
  return ticker ~= nil
end

function Pos.TickerRunning()
  return ticker ~= nil
end

Seekwell.RegisterStart("position", Pos.Start) -- Util/Ext.lua, loaded early
