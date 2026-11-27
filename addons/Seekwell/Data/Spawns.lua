--[[
  Seekwell.Spawns — mob positions learned from your own loot, plus original Classic spawn points from the optional
  Seekwell_Locations addon (Data/Locations.lua; setting map.bundled), plus ForeverDB spawns (Data/FDBBridge.lua; when ForeverDB
  has an npc its points replace the Classic bundle for that npc). Points carry src = "learned" | "fdb" | "classic".
  SeekwellDB.learned.spawn[uiMapID][npcID] = "x,y;x,y;..." with x, y in 0..1 on a 0.5 % grid,
  at most 64 cells per npc + map, no duplicates. Positions are where YOU stood when looting: approximate.
]]

Seekwell = Seekwell or {}
local Sp = {}
Seekwell.Spawns = Sp

local GRID = 0.005
local CAP = 64
Sp.GRID, Sp.CAP = GRID, CAP
Sp.generation = 0

local function Store()
  local l = Seekwell.Config.Learned()
  if type(l.spawn) ~= "table" then
    l.spawn = {}
  end
  return l.spawn
end

--- Snap a 0..1 coordinate to the grid; returns the number and its compact text.
local function Quantize(v)
  local q = math.floor(v / GRID + 0.5) * GRID
  local s = string.format("%.3f", q):gsub("0+$", ""):gsub("%.$", "")
  return tonumber(s), s
end
Sp.Quantize = Quantize

--- Add one position; returns true when a new cell was stored.
function Sp.Add(npcID, mapID, x, y)
  npcID, mapID, x, y = tonumber(npcID), tonumber(mapID), tonumber(x), tonumber(y)
  if not (npcID and mapID and x and y) then
    return false
  end
  if x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then
    return false
  end
  local _, xs = Quantize(x)
  local _, ys = Quantize(y)
  local cell = xs .. "," .. ys
  local st = Store()
  local m = st[mapID]
  if type(m) ~= "table" then
    m = {}
    st[mapID] = m
  end
  local cur = type(m[npcID]) == "string" and m[npcID] or ""
  if cur == "" then
    m[npcID] = cell
  else
    if (";" .. cur .. ";"):find(";" .. cell .. ";", 1, true) then
      return false
    end
    local n = select(2, cur:gsub(";", "")) + 1
    if n >= CAP then
      return false
    end
    m[npcID] = cur .. ";" .. cell
  end
  Sp.generation = Sp.generation + 1
  return true
end

local DEDUP = 0.015 -- bundled points this close (0..1 map units) to a learned point are skipped

local function Bundled()
  local loc = Seekwell.Locations
  if not loc then
    return nil
  end
  local ok, s = pcall(function()
    return Seekwell.Config.Get().map
  end)
  if ok and type(s) == "table" and s.bundled == false then
    return nil
  end
  return loc
end
Sp.Bundled = Bundled

--- The ForeverDB bridge when its data is loaded (Data/FDBBridge.lua), else nil.
local function FDB()
  local F = Seekwell.FDB
  if F and F.Data and F.Data() then
    return F
  end
  return nil
end
Sp.FDB = FDB

local function AddNear(out, nLearned, x, y, src)
  for i = 1, nLearned do
    local dx, dy = out[i].x - x, out[i].y - y
    if dx * dx + dy * dy < DEDUP * DEDUP then
      return
    end
  end
  out[#out + 1] = { x = x, y = y, n = 1, src = src }
end

--- { {x, y, n, src} } for an npc on a map (n = 1 per cell; src "learned" or "classic").
function Sp.ForMob(npcID, mapID)
  local m = Store()[tonumber(mapID) or -1]
  local s = type(m) == "table" and m[tonumber(npcID) or -1]
  local out = {}
  if type(s) == "string" then
    for xs, ys in s:gmatch("([%d%.]+),([%d%.]+)") do
      local x, y = tonumber(xs), tonumber(ys)
      if x and y then
        out[#out + 1] = { x = x, y = y, n = 1, src = "learned" }
      end
    end
  end
  local F = FDB()
  local fmaps = F and F.Spawns(npcID)
  if fmaps and #fmaps > 0 then
    -- ForeverDB positions replace the old Classic bundle for this npc
    local nLearned = #out
    for _, e in ipairs(fmaps) do
      if e.mapID == tonumber(mapID) then
        for _, p in ipairs(e.points) do
          AddNear(out, nLearned, p.x, p.y, "fdb")
        end
      end
    end
    return out
  end
  local loc = Bundled()
  if loc then
    local bm, pts = loc.ForMob(npcID)
    if bm and bm == tonumber(mapID) and type(pts) == "table" then
      local nLearned = #out
      for _, p in ipairs(pts) do
        local near = false
        for i = 1, nLearned do
          local dx, dy = out[i].x - p.x, out[i].y - p.y
          if dx * dx + dy * dy < DEDUP * DEDUP then
            near = true
            break
          end
        end
        if not near then
          out[#out + 1] = { x = p.x, y = p.y, n = 1, src = "classic" }
        end
      end
    end
  end
  return out
end

function Sp.MapsForMob(npcID)
  npcID = tonumber(npcID)
  local out, seen = {}, {}
  for mapID, m in pairs(Store()) do
    if type(m) == "table" and type(m[npcID]) == "string" and m[npcID] ~= "" then
      out[#out + 1] = mapID
      seen[mapID] = true
    end
  end
  local F = FDB()
  local fm = F and F.MapsForNpc(npcID) or {}
  for _, mapID in ipairs(fm) do
    if not seen[mapID] then
      out[#out + 1] = mapID
      seen[mapID] = true
    end
  end
  local loc = (#fm == 0) and Bundled() or nil
  if loc then
    for _, mapID in ipairs(loc.MapsForMob(npcID) or {}) do
      if not seen[mapID] then
        out[#out + 1] = mapID
      end
    end
  end
  table.sort(out)
  return out
end

function Sp.MobsInMap(mapID)
  local m = Store()[tonumber(mapID) or -1]
  local out = {}
  if type(m) == "table" then
    for npcID, s in pairs(m) do
      if type(s) == "string" and s ~= "" then
        out[#out + 1] = npcID
      end
    end
  end
  local loc = Bundled()
  if loc then
    local seen = {}
    for _, id in ipairs(out) do
      seen[id] = true
    end
    for _, id in ipairs(loc.MobsInMap(mapID) or {}) do
      if not seen[id] then
        out[#out + 1] = id
        seen[id] = true
      end
    end
  end
  local F = FDB()
  if F then
    local seen = {}
    for _, id in ipairs(out) do
      seen[id] = true
    end
    for _, id in ipairs(F.MobsInMap(mapID) or {}) do
      if not seen[id] then
        out[#out + 1] = id
      end
    end
  end
  table.sort(out)
  return out
end

--- Number of learned cells, number of npc + map pairs.
function Sp.Count()
  local cells, pairsN = 0, 0
  for _, m in pairs(Store()) do
    if type(m) == "table" then
      for _, s in pairs(m) do
        if type(s) == "string" and s ~= "" then
          pairsN = pairsN + 1
          cells = cells + select(2, s:gsub(";", "")) + 1
        end
      end
    end
  end
  return cells, pairsN
end

--- Bundled Classic spawn data: npcs in it (0 when Seekwell_Locations is not loaded), loaded flag.
function Sp.CountBundled()
  local loc = Seekwell.Locations
  local i = loc and loc.Info and loc.Info()
  return (i and i.npcs) or 0, (i and i.loaded) and true or false
end
