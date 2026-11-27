--[[
  Seekwell.ItemView — helpers of the browser (where a mob is known, nearest spot, waypoint, item name /
  quality) and the item API: ItemView.Show(id) selects the item on the Search page (UI/Browser.lua right pane;
  the separate item page is gone since 0.3.1). Also /sw find <name|link|id>.
]]

Seekwell = Seekwell or {}
local IV = {}
Seekwell.ItemView = IV

local function Safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok and Seekwell.RecordError then
      Seekwell.RecordError("itemview." .. name, err)
    end
  end
end
IV.Safe = Safe

local function MapName(id)
  local S = Seekwell.Sources
  return S and S.MapName and S.MapName(id) or nil
end
IV.MapName = MapName

local function SpawnMaps(npcID)
  local Sp = Seekwell.Spawns
  if not (Sp and Sp.MapsForMob) then
    return {}
  end
  local ok, list = pcall(Sp.MapsForMob, npcID)
  return (ok and type(list) == "table") and list or {}
end

local function SpawnPoints(npcID, mapID)
  local Sp = Seekwell.Spawns
  if not (Sp and Sp.ForMob) then
    return {}
  end
  local ok, pts = pcall(Sp.ForMob, npcID, mapID)
  return (ok and type(pts) == "table") and pts or {}
end

--- Zones where a mob is known (learned sightings npc.m + Seekwell.Spawns): names, spot count, source labels
--- ("bundled Classic data" etc. when points carry src), sorted map ids with spots.
function IV.Where(npcID)
  npcID = tonumber(npcID)
  local maps, spots, srcs, withSpots = {}, 0, {}, {}
  local db = rawget(_G, "SeekwellDB")
  local l = type(db) == "table" and db.learned or nil
  local e = l and type(l.npc) == "table" and l.npc[npcID] or nil
  if type(e) == "table" and type(e.m) == "table" then
    for id in pairs(e.m) do
      maps[id] = true
    end
  end
  for _, id in ipairs(SpawnMaps(npcID)) do
    maps[id] = true
    local pts = SpawnPoints(npcID, id)
    if #pts > 0 then
      withSpots[#withSpots + 1] = id
    end
    spots = spots + #pts
    for _, p in ipairs(pts) do
      if type(p) == "table" and type(p.src) == "string" and p.src ~= "" then
        srcs[p.src] = true
      end
    end
  end
  local names = {}
  for id in pairs(maps) do
    names[#names + 1] = MapName(id) or ("map " .. tostring(id))
  end
  table.sort(names)
  local labels = {}
  for s in pairs(srcs) do
    labels[#labels + 1] = s
  end
  table.sort(labels)
  return names, spots, (#labels > 0) and table.concat(labels, ", ") or nil, withSpots
end

--- Known spot of a mob nearest to the player (same map first): mapID, x, y (0..1) or nil.
function IV.Nearest(npcID)
  local _, _, _, withSpots = IV.Where(npcID)
  if #withSpots == 0 then
    return nil
  end
  local pm, px, py
  local V = Seekwell.Vendor
  if V and V.PlayerPos then
    local ok, a, b, c = pcall(V.PlayerPos)
    if ok then
      pm, px, py = a, b, c
    end
  end
  local mapID = withSpots[1]
  for _, id in ipairs(withSpots) do
    if id == pm then
      mapID = id
    end
  end
  local best, bestD
  for _, p in ipairs(SpawnPoints(npcID, mapID)) do
    if type(p) == "table" and tonumber(p.x) and tonumber(p.y) then
      local d = 0
      if mapID == pm and px and py then
        d = (p.x - px / 100) ^ 2 + (p.y - py / 100) ^ 2
      end
      if not bestD or d < bestD then
        best, bestD = p, d
      end
    end
  end
  if not best then
    return nil
  end
  return mapID, best.x, best.y
end

--- Waypoint to the nearest known spot of a mob (Seekwell.Map.Waypoint if present, else Seekwell.Waypoint.Set).
function IV.WaypointTo(npcID)
  local mapID, x, y = IV.Nearest(npcID)
  if not mapID then
    if Seekwell.Print then
      Seekwell.Print("no known spot for this mob yet")
    end
    return nil
  end
  local R = Seekwell.Registry
  local label = (R and R.NpcName(npcID)) or ("npc " .. tostring(npcID))
  local M = Seekwell.Map
  if M and type(M.Waypoint) == "function" then
    return M.Waypoint(mapID, x, y, label)
  end
  local W = Seekwell.Waypoint
  if W and W.Set then
    return W.Set(mapID, x, y, label)
  end
  return nil
end

function IV.ItemName(id)
  local TP = Seekwell.TargetPanel
  if TP and TP.ItemInfo then
    local name, _, quality, icon = TP.ItemInfo(id)
    if not name and Seekwell.DJ and Seekwell.DJ.ItemName then
      local ok, n = pcall(Seekwell.DJ.ItemName, id)
      name = ok and n or nil -- Forever-only items: the Dungeon Journal knows the name before the client cache
    end
    return name, quality, icon
  end
  return nil
end

function IV.QualityRGB(q)
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if type(c) == "table" and c.r then
    return c.r, c.g, c.b
  end
  return 1, 1, 1
end

local function LevelText(d)
  if d and d.minLevel then
    if d.maxLevel and d.maxLevel ~= d.minLevel then
      return " (" .. d.minLevel .. "-" .. d.maxLevel .. ")"
    end
    return " (" .. d.minLevel .. ")"
  end
  return ""
end
IV.LevelText = LevelText

--- The selected item of the Search page (nil when a mob or nothing is selected).
function IV.Current()
  local B = Seekwell.Browser
  local s = B and B.Selected and B.Selected()
  return s and s.kind == "item" and s.id or nil
end

--- Show an item: selects it on the Search page (right pane).
function IV.Show(id)
  id = tonumber(id)
  local B = Seekwell.Browser
  if id and B and B.Select then
    B.Select("item", id)
  end
end

function IV.Render()
  local B = Seekwell.Browser
  if B and B.RenderDetail then
    B.RenderDetail()
  end
end

--- /sw find <item name|link|id>, or a mob name when no item matches.
local function Trim(s)
  return (tostring(s or ""):match("^%s*(.-)%s*$")) or ""
end

function IV.SlashFind(rest)
  rest = Trim(rest)
  local W = Seekwell.Wish
  local B = Seekwell.Browser
  local found = W and W.Find and W.Find(rest, 8) or {}
  local q = rest:lower()
  if #found == 1 or (#found > 1 and found[1].name:lower() == q) then
    IV.Show(found[1].id)
    return
  end
  if #found > 1 then
    Seekwell.Print(string.format("find: %d+ items match \"%s\" \226\128\148 see the Search page", #found, rest))
    if B and B.Open then
      B.Open(rest, "items")
    end
    return
  end
  local mobs = (B and B.SearchMobs) and B.SearchMobs(q, 50) or {}
  local exact
  for _, m in ipairs(mobs) do
    if m.name:lower() == q then
      exact = m
      break
    end
  end
  if #mobs == 1 or exact then
    Seekwell.MobView.Show((exact or mobs[1]).id)
  elseif #mobs > 1 then
    Seekwell.Print(string.format("find: %d mobs match \"%s\" \226\128\148 see the Search page", #mobs, rest))
    if B and B.Open then
      B.Open(rest, "mobs")
    end
  else
    Seekwell.Print("find: no item or mob found for \"" .. rest .. "\"")
  end
end

if Seekwell.RegisterSlash then
  Seekwell.RegisterSlash("find", function(rest)
    IV.SlashFind(rest)
  end)
end
