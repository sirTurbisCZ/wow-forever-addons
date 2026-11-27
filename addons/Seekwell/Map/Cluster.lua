--[[
  Seekwell.Cluster — groups map points on a grid measured in yards (one pin per cell, with a count).
  Zone size comes from C_Map.GetWorldPosFromMapPos; without it a fixed cell of 3 % of the map is used.
]]

Seekwell = Seekwell or {}
local C = {}
Seekwell.Cluster = C

local FALLBACK_CELL = 0.03
local sizes = {} -- [uiMapID] = { w, h } or false

--- Width and height of a map in yards (map x, map y), or nil.
function C.ZoneSizeYards(mapID)
  mapID = tonumber(mapID)
  if not mapID then
    return nil
  end
  local s = sizes[mapID]
  if s == nil then
    s = false
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
      local ok, w, h = pcall(function()
        local _, a = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local _, b = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
        if not a or not b then
          return nil
        end
        -- world axes are swapped relative to map axes
        return math.abs(b.y - a.y), math.abs(b.x - a.x)
      end)
      w, h = ok and tonumber(Seekwell.Secret.Plain(w)), ok and tonumber(Seekwell.Secret.Plain(h))
      if w and h and w > 0 and h > 0 then
        s = { w, h }
      end
    end
    sizes[mapID] = s
  end
  if s then
    return s[1], s[2]
  end
  return nil
end

--- points { {x, y, n, src} } -> { {x, y, count, src} } (src "mixed" when a cell mixes sources) (weighted centre of each cell), biggest first.
function C.Cluster(points, cellYards, mapID)
  local cx, cy = FALLBACK_CELL, FALLBACK_CELL
  local w, h = C.ZoneSizeYards(mapID)
  cellYards = tonumber(cellYards) or 40
  if w and h and cellYards > 0 then
    cx, cy = cellYards / w, cellYards / h
  end
  local cells, list = {}, {}
  for _, p in ipairs(points or {}) do
    local x, y, n = tonumber(p.x), tonumber(p.y), tonumber(p.n) or 1
    if x and y then
      local key = math.floor(x / cx) .. ":" .. math.floor(y / cy)
      local c = cells[key]
      if not c then
        c = { sx = 0, sy = 0, count = 0, src = p.src }
        cells[key] = c
        list[#list + 1] = c
      end
      c.sx, c.sy, c.count = c.sx + x * n, c.sy + y * n, c.count + n
      if c.src ~= p.src then
        c.src = "mixed"
      end
    end
  end
  local out = {}
  for i, c in ipairs(list) do
    out[i] = { x = c.sx / c.count, y = c.sy / c.count, count = c.count, src = c.src }
  end
  table.sort(out, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    if a.x ~= b.x then
      return a.x < b.x
    end
    return a.y < b.y
  end)
  return out
end

function C.ClearCache()
  sizes = {}
end
