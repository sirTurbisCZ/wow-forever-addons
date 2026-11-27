--[[
  Seekwell.MapPreview — a small zone map drawn inside the browser (right pane of the Search page).
  Zone art comes from the C_Map art layer tiles (GetMapArtLayers / GetMapArtLayerTextures, layer 1); when the
  client has no art for a map the panel falls back to a dark grid. Pins are pooled buttons on top (hover tooltip
  with the name and source, click = waypoint). Own frames only, no OnUpdate; it redraws only when Show is called.
]]

Seekwell = Seekwell or {}
local MP = {}
Seekwell.MapPreview = MP

local MAX_PINS = 250
local GRID_X, GRID_Y = 8, 6
local PIN_SIZE = 11
local MERGE = 0.022 -- points closer than this (share of the map) are drawn as one pin with a count

local function Safe(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      local rec = Seekwell.RecordError
      if rec then
        pcall(rec, "mappreview." .. name, err)
      end
    end
  end
end
MP.Safe = Safe

--- Art layer 1 of a map: { w, h, tileW, tileH, textures } or nil.
function MP.ArtInfo(mapID)
  mapID = tonumber(mapID)
  if not (mapID and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then
    return nil
  end
  local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
  local layer = ok and type(layers) == "table" and layers[1] or nil
  if type(layer) ~= "table" then
    return nil
  end
  local ok2, textures = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
  if not (ok2 and type(textures) == "table" and #textures > 0) then
    return nil
  end
  local w, h = tonumber(layer.layerWidth), tonumber(layer.layerHeight)
  local tw, th = tonumber(layer.tileWidth), tonumber(layer.tileHeight)
  if not (w and h and tw and th and w > 0 and h > 0 and tw > 0 and th > 0) then
    return nil
  end
  return { w = w, h = h, tileW = tw, tileH = th, textures = textures }
end

local Proto = {}

function Proto:Tile(i)
  local t = self.tiles[i]
  if not t then
    t = self.canvas:CreateTexture(nil, "BACKGROUND", nil, 1)
    self.tiles[i] = t
  end
  return t
end

function Proto:Grid(i)
  local t = self.grid[i]
  if not t then
    t = self.canvas:CreateTexture(nil, "BACKGROUND", nil, 2)
    t:SetColorTexture(1, 1, 1, 0.08)
    self.grid[i] = t
  end
  return t
end

function Proto:Pin(i)
  local p = self.pins[i]
  if p then
    return p
  end
  local pv = self
  p = CreateFrame("Button", nil, self.canvas)
  p:SetSize(PIN_SIZE, PIN_SIZE)
  p:SetFrameLevel((self.canvas:GetFrameLevel() or 1) + 2)
  Seekwell.PinArt.Build(p, PIN_SIZE)
  p:SetScript("OnEnter", Safe("pin.enter", function(self)
    local pt = self.pt
    Seekwell.PinArt.Highlight(self, true)
    if pt and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(pt.label or "?")
      local src = pt.src == "learned" and "learned (your loot / sightings)" or pt.src == "classic" and "bundled Classic data" or pt.src == "fdb" and "ForeverDB spawn data (approximate)" or pt.src == "entrance" and "dungeon entrance" or (pt.src or "known spot")
      GameTooltip:AddLine(src, 0.7, 0.7, 0.7)
      GameTooltip:AddLine(string.format("%.1f, %.1f \194\183 click: waypoint", (pt.x or 0) * 100, (pt.y or 0) * 100), 0.6, 0.8, 1)
      GameTooltip:Show()
    end
  end))
  p:SetScript("OnLeave", function(self)
    Seekwell.PinArt.Highlight(self, false)
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  p:SetScript("OnClick", Safe("pin.click", function(self)
    if self.pt then
      pv:Waypoint(self.pt)
    end
  end))
  self.pins[i] = p
  return p
end

function Proto:Waypoint(pt)
  local mapID = self.mapID
  if not (mapID and pt and pt.x and pt.y) then
    return nil
  end
  local M = Seekwell.Map
  if M and type(M.Waypoint) == "function" then
    return M.Waypoint(mapID, pt.x, pt.y, pt.label)
  end
  local W = Seekwell.Waypoint
  if W and W.Set then
    return W.Set(mapID, pt.x, pt.y, pt.label)
  end
  return nil
end

function Proto:SetSize(w, h)
  self.w, self.h = math.max(40, tonumber(w) or 460), math.max(40, tonumber(h) or 300)
  self.frame:SetSize(self.w, self.h)
end

--- Paint mapID with points { {x, y (0..1), label, src} }; returns true when art tiles were used.
function Proto:Show(mapID, points)
  self.mapID = tonumber(mapID)
  points = type(points) == "table" and points or {}
  local W, H = self.w, self.h
  local art = self.mapID and MP.ArtInfo(self.mapID) or nil
  local dw, dh = W, H
  local nTiles, nGrid = 0, 0
  if art then
    local scale = math.min(W / art.w, H / art.h)
    dw, dh = art.w * scale, art.h * scale
    local cols = math.max(1, math.ceil(art.w / art.tileW))
    local rowsN = math.max(1, math.ceil(art.h / art.tileH))
    local n = math.min(#art.textures, cols * rowsN)
    for i = 1, n do
      local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
      -- edge tiles only partly cover the layer: draw the covered part only
      local fw = math.min(1, (art.w - col * art.tileW) / art.tileW)
      local fh = math.min(1, (art.h - row * art.tileH) / art.tileH)
      local t = self:Tile(i)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", col * art.tileW * scale, -row * art.tileH * scale)
      t:SetSize(art.tileW * scale * fw, art.tileH * scale * fh)
      t:SetTexture(art.textures[i])
      t:SetTexCoord(0, fw, 0, fh)
      t:Show()
    end
    nTiles = n
  else
    for i = 1, GRID_X - 1 do
      nGrid = nGrid + 1
      local t = self:Grid(nGrid)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", W * i / GRID_X, 0)
      t:SetSize(1, H)
      t:Show()
    end
    for i = 1, GRID_Y - 1 do
      nGrid = nGrid + 1
      local t = self:Grid(nGrid)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 0, -H * i / GRID_Y)
      t:SetSize(W, 1)
      t:Show()
    end
  end
  for i = nTiles + 1, #self.tiles do
    self.tiles[i]:Hide()
  end
  for i = nGrid + 1, #self.grid do
    self.grid[i]:Hide()
  end
  self.canvas:ClearAllPoints()
  self.canvas:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
  self.canvas:SetSize(dw, dh)
  -- merge close points (a mob with hundreds of spawns would otherwise be one black blob)
  local merged, cells = {}, {}
  for _, pt in ipairs(points) do
    local x, y = tonumber(pt.x), tonumber(pt.y)
    if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
      local key = math.floor(x / MERGE) .. ":" .. math.floor(y / MERGE)
      local m = cells[key]
      if m then
        m.count = m.count + (tonumber(pt.count) or 1)
      else
        m = {}
        for k, v in pairs(pt) do
          m[k] = v
        end
        m.count = tonumber(pt.count) or 1
        cells[key] = m
        merged[#merged + 1] = m
      end
    end
  end
  local np = 0
  for _, pt in ipairs(merged) do
    if np >= MAX_PINS then
      break
    end
    local x, y = tonumber(pt.x), tonumber(pt.y)
    do
      np = np + 1
      local p = self:Pin(np)
      p.pt = pt
      p:ClearAllPoints()
      p:SetPoint("CENTER", self.canvas, "TOPLEFT", x * dw, -y * dh)
      Seekwell.PinArt.Apply(p, pt, PIN_SIZE)
      p:Show()
    end
  end
  for i = np + 1, #self.pins do
    self.pins[i].pt = nil
    self.pins[i]:Hide()
  end
  self.hasArt, self.nPins, self.nTiles = art and true or false, np, nTiles
  self.msg:SetText(art and "" or (self.mapID and "map art not available \226\128\148 grid view" or "no known zone"))
  self.msg:SetShown(not art)
  return self.hasArt
end

function Proto:Clear()
  return self:Show(nil, {})
end

--- New preview inside parent: obj with :SetSize(w, h), :Show(mapID, points), :Clear(), .frame, .hasArt, .nPins.
function MP.Create(parent, w, h)
  local pv = setmetatable({ tiles = {}, grid = {}, pins = {} }, { __index = Proto })
  local f = CreateFrame("Frame", nil, parent)
  pv.frame = f
  local bg = f:CreateTexture(nil, "BACKGROUND", nil, -7)
  bg:SetAllPoints()
  bg:SetColorTexture(0.04, 0.05, 0.07, 0.95)
  local border = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetColorTexture(1, 0.82, 0, 0.25)
  if f.SetClipsChildren then
    pcall(f.SetClipsChildren, f, true)
  end
  pv.canvas = CreateFrame("Frame", nil, f)
  pv.msg = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  pv.msg:SetPoint("BOTTOMLEFT", 6, 4)
  pv:SetSize(w, h)
  return pv
end
