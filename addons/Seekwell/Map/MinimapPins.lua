--[[
  Seekwell.MinimapPins — up to 12 pins (same art as the world map, 16 px) on the minimap for the nearest learned spots of the active hunt.
  Own projection (player map position, zone size in yards, minimap zoom, rotation). A 10 Hz ticker runs
  only while a hunt is active and the setting is on; unknown or secret positions hide every dot.
]]

Seekwell = Seekwell or {}
local MP = {}
Seekwell.MinimapPins = MP

local MAX = 12
local EVERY = 0.1
-- minimap diameter in yards for each zoom level
local YARDS = {
  indoor = { [0] = 300, 240, 180, 120, 80, 50 },
  outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
}
MP.MAX = MAX

MP.SIZE = 16

local pool = {}
local ticker
local lastSig, lastN -- redraw guard of MP.Draw

local function NewPin()
  local p = CreateFrame("Frame", nil, Minimap)
  p:SetSize(MP.SIZE, MP.SIZE)
  if p.SetFrameLevel and Minimap.GetFrameLevel then
    p:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 5)
  end
  Seekwell.PinArt.Build(p, MP.SIZE)
  p:EnableMouse(true)
  p:SetScript("OnEnter", function(self)
    Seekwell.PinArt.Highlight(self, true)
    if self.pt and Seekwell.Map then
      pcall(function()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        Seekwell.Map.FillTooltip(GameTooltip, self.pt)
        if self.dist then
          GameTooltip:AddLine(string.format("%d yd", self.dist), 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
      end)
    end
  end)
  p:SetScript("OnLeave", function(self)
    Seekwell.PinArt.Highlight(self, false)
    GameTooltip:Hide()
  end)
  p:Hide()
  return p
end

local function HideFrom(n)
  if n <= 1 then
    lastSig, lastN = nil, nil
  end
  for i = n, #pool do
    pool[i]:Hide()
  end
end

local function Num(fn, ...)
  return tonumber(Seekwell.Secret.Get(fn, ...))
end

--- Place the dots; returns how many are shown.
function MP.Draw()
  local Map = Seekwell.Map
  local s = Seekwell.Config.Get().map
  if not (Map and Map.Current() and s.enabled and s.minimap and Minimap) then
    HideFrom(1)
    return 0
  end
  local mapID, px, py = Seekwell.Position.PlayerPosition()
  local zw, zh = Seekwell.Cluster.ZoneSizeYards(mapID)
  if not mapID or not zw then
    HideFrom(1)
    return 0
  end
  local indoors = Seekwell.Secret.Get(IsIndoors) and "indoor" or "outdoor"
  local zoom = Num(Minimap.GetZoom, Minimap) or 0
  -- nothing moved, zoomed or changed since the last redraw: keep the dots as they are (the ticker runs 10x per second)
  local pts = Map.PointsForMap(mapID)
  local rot = (GetCVar and Seekwell.Secret.Get(GetCVar, "rotateMinimap") == "1") and string.format("%.3f", Num(GetPlayerFacing) or 0) or "-"
  local sig = table.concat({ tostring(mapID), string.format("%.5f:%.5f", px or 0, py or 0), tostring(zoom), indoors, rot,
    tostring(Map.PointsVersion and Map.PointsVersion() or 0) }, "|")
  if sig == lastSig and lastN then
    return lastN
  end
  local radius = (YARDS[indoors][zoom] or 466) / 2
  local facing
  if GetCVar and Seekwell.Secret.Get(GetCVar, "rotateMinimap") == "1" then
    facing = Num(GetPlayerFacing)
    if not facing then
      HideFrom(1)
      return 0
    end
  end
  local cos, sin = math.cos(facing or 0), math.sin(facing or 0)
  local halfW = (Num(Minimap.GetWidth, Minimap) or 140) / 2
  local halfH = (Num(Minimap.GetHeight, Minimap) or 140) / 2
  local near = {}
  for _, pt in ipairs(pts) do
    -- yards east and north of the player (map y grows southwards)
    local ex, ny = (pt.x - px) * zw / radius, (py - pt.y) * zh / radius
    if facing then
      ex, ny = ex * cos + ny * sin, ny * cos - ex * sin
    end
    local d = math.sqrt(ex * ex + ny * ny)
    if d <= 1 then
      near[#near + 1] = { pt = pt, ex = ex, ny = ny, d = d }
    end
  end
  table.sort(near, function(a, b)
    return a.d < b.d
  end)
  local n = math.min(MAX, #near)
  for i = 1, n do
    local e = near[i]
    local p = pool[i]
    if not p then
      p = NewPin()
      pool[i] = p
    end
    p.pt, p.dist = e.pt, math.floor(e.d * radius + 0.5)
    Seekwell.PinArt.Apply(p, e.pt, MP.SIZE)
    p:ClearAllPoints()
    p:SetPoint("CENTER", Minimap, "CENTER", e.ex * halfW, e.ny * halfH)
    p:Show()
  end
  HideFrom(n + 1)
  lastSig, lastN = sig, n
  return n
end

local function Tick()
  local ok, err = pcall(MP.Draw)
  if not ok then
    HideFrom(1)
    if Seekwell.RecordError then
      Seekwell.RecordError("map.minimap", err)
    end
  end
end

--- Start or stop the ticker to match the hunt and settings.
function MP.Update()
  lastSig, lastN = nil, nil -- explicit update: always redraw
  local Map = Seekwell.Map
  local s = Seekwell.Config.Get().map
  local want = Map and Map.Current() and s.enabled and s.minimap
  if want and not ticker and C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(EVERY, Tick)
  elseif not want and ticker then
    ticker:Cancel()
    ticker = nil
  end
  Tick()
end

function MP.Running()
  return ticker ~= nil
end

function MP.PoolSize()
  return #pool
end
