--[[
  Seekwell.PinArt — one pin look for the world map, the minimap and the browser map preview.
  A round pin: source ring (cyan = learned by you, thin dark = Classic data, violet = dungeon entrance),
  a disc in the drop-% colour band (grey < 1 %, white 1-10, green 10-30, gold > 30, light blue = unknown),
  and a glyph by kind (mob = skull, vendor = coin, quest = "!", entrance = portal). Clusters are bigger
  and carry an outlined count. Textures are created in Lua and coloured with SetVertexColor only.
  Texture paths used here are the ones installed Classic-client addons use (see Docs/README.md).
]]

Seekwell = Seekwell or {}
local PA = {}
Seekwell.PinArt = PA

PA.TEX = {
  disc = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", -- white round disc (ForeverDungeonJournal, SKTools)
  mob = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", -- skull
  vendor = "Interface\\MoneyFrame\\UI-GoldIcon", -- coin
  quest = "Interface\\GossipFrame\\AvailableQuestIcon", -- yellow "!"
  entrance = "Interface\\Icons\\Spell_Arcane_PortalDalaran", -- portal
  glow = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", -- hover glow (ADD)
}

PA.UNKNOWN_RGB = { 0.55, 0.8, 1 }
PA.LEARNED_RING = { 0.2, 0.95, 1, 1 }
PA.CLASSIC_RING = { 0.16, 0.16, 0.18, 1 }
PA.ENTRANCE_RING = { 0.8, 0.45, 1, 1 }

--- Drop-% colour band (also used for tooltip text).
function PA.BandColor(p)
  p = tonumber(p)
  if not p then
    return PA.UNKNOWN_RGB[1], PA.UNKNOWN_RGB[2], PA.UNKNOWN_RGB[3]
  elseif p < 1 then
    return 0.6, 0.6, 0.6
  elseif p < 10 then
    return 1, 1, 1
  elseif p <= 30 then
    return 0.2, 1, 0.2
  end
  return 1, 0.82, 0
end

function PA.Band(p)
  p = tonumber(p)
  if not p then
    return "unknown"
  elseif p < 1 then
    return "grey"
  elseif p < 10 then
    return "white"
  elseif p <= 30 then
    return "green"
  end
  return "gold"
end

--- "mob" | "vendor" | "quest" | "entrance"
function PA.Kind(pt)
  local k = type(pt) == "table" and (pt.kind or (pt.src == "entrance" and "entrance")) or nil
  if k == "entrance" or k == "dungeon" then
    return "entrance"
  elseif k == "vendor" or k == "quest" then
    return k
  end
  return "mob"
end

local function Tex(f, layer, sub)
  local t = f:CreateTexture(nil, layer, nil, sub)
  return t
end

--- Create the textures once (idempotent). size = base pin size in px.
function PA.Build(f, size)
  local a = rawget(f, "_art")
  if a then
    return a
  end
  a = { size = tonumber(size) or 20 }
  a.ring = Tex(f, "BACKGROUND", 1)
  a.disc = Tex(f, "BORDER", 1)
  -- TempPortraitAlphaMask is a black mask picture: used as a texture it paints black discs whatever the vertex
  -- colour is. Use a white colour texture cut round by a mask instead (fallback: the old texture).
  a.shine = Tex(f, "ARTWORK", 2)
  a.shine:Hide()
  for _, t in ipairs({ a.ring, a.disc, a.shine }) do
    local okM, mask = pcall(function()
      return f:CreateMaskTexture()
    end)
    if okM and mask and t.AddMaskTexture and t.SetColorTexture then
      mask:SetTexture(PA.TEX.disc, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mask:SetAllPoints(t)
      t:AddMaskTexture(mask)
      t:SetColorTexture(1, 1, 1, 1)
    else
      t:SetTexture(PA.TEX.disc)
    end
  end
  a.glyph = Tex(f, "ARTWORK", 1)
  a.glow = Tex(f, "OVERLAY", 1)
  a.glow:SetTexture(PA.TEX.glow)
  if a.glow.SetBlendMode then
    a.glow:SetBlendMode("ADD")
  end
  a.glow:Hide()
  a.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  if a.count.GetFont and a.count.SetFont then
    pcall(function()
      local font, h = a.count:GetFont()
      if font then
        a.count:SetFont(font, math.max(11, tonumber(h) or 12), "OUTLINE")
      end
    end)
  end
  for _, t in ipairs({ a.ring, a.disc, a.glyph, a.glow }) do
    t:SetPoint("CENTER")
  end
  a.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -3)
  rawset(f, "_art", a)
  return a
end

local function Layout(a, s)
  local cl = a.cluster and 3 or 0
  if a.kind == "mob" then
    s = math.max(7, math.floor(s * 0.5 + 0.5)) -- small dot, like a gathering node
  end
  s = s + cl
  local ringPad = (a.kind == "mob" and 2) or (a.thinRing and 2 or 4)
  a.ring:SetSize(s, s)
  a.disc:SetSize(s - ringPad, s - ringPad)
  local g = math.floor((s - ringPad) * 0.72 + 0.5)
  a.glyph:SetSize(g, g)
  a.glow:SetSize(s * 1.6, s * 1.6)
  if false then
    local sh = math.max(2, math.floor(s * 0.4 + 0.5))
    a.shine:SetSize(sh, sh)
    a.shine:ClearAllPoints()
    a.shine:SetPoint("CENTER", a.disc, "CENTER", -s * 0.12, s * 0.12)
    a.shine:SetVertexColor(1, 1, 1, 0.75)
    a.shine:Show()
  else
    a.shine:Hide()
  end
  a.cur = s
end

--- Paint a pin for pt { p, src, kind, count }; returns the band name (tests).
function PA.Apply(f, pt, size)
  local a = PA.Build(f, size)
  a.size = tonumber(size) or a.size
  pt = type(pt) == "table" and pt or {}
  local kind = PA.Kind(pt)
  a.kind = kind
  a.cluster = (tonumber(pt.count) or 1) > 1
  a.thinRing = pt.src == "classic" or pt.src == "fdb"
  local ring = (kind == "entrance" and PA.ENTRANCE_RING) or ((pt.src == "learned" or pt.src == "mixed") and PA.LEARNED_RING)
    or PA.CLASSIC_RING
  a.ring:SetVertexColor(ring[1], ring[2], ring[3], ring[4])
  a.glyph:SetTexture(PA.TEX[kind] or PA.TEX.mob)
  -- mob spots are plain silver dots (like the gold gathering-node dots); other kinds keep their glyph
  if kind == "mob" then
    a.glyph:Hide()
  else
    a.glyph:Show()
  end
  if a.glyph.SetTexCoord then
    if kind == "entrance" then
      a.glyph:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
      a.glyph:SetTexCoord(0, 1, 0, 1)
    end
  end
  local band
  if kind == "mob" then
    band = PA.Band(pt.p)
    -- silver, so mob spots differ from the gold gathering nodes of the minimap (the % band stays in the tooltip)
    a.disc:SetVertexColor(0.78, 0.78, 0.78, 1)
    a.glyph:SetVertexColor(0.08, 0.06, 0.05, 1) -- dark skull on the coloured disc
  elseif kind == "entrance" then
    band = "entrance"
    a.disc:SetVertexColor(0.22, 0.08, 0.32, 0.95)
    a.glyph:SetVertexColor(1, 1, 1, 1)
  else
    band = kind
    a.disc:SetVertexColor(0.1, 0.08, 0.04, 0.9)
    a.glyph:SetVertexColor(1, 1, 1, 1)
  end
  a.count:SetText(a.cluster and tostring(pt.count) or "")
  a.band = band
  Layout(a, a.size)
  a.glow:Hide()
  return band
end

--- Hover: art 1.2x bigger + glow (the frame scale stays with the map canvas).
function PA.Highlight(f, on)
  local a = rawget(f, "_art")
  if not a then
    return
  end
  Layout(a, on and a.size * 1.2 or a.size)
  if on then
    a.glow:Show()
  else
    a.glow:Hide()
  end
end
