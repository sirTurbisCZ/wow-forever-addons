--[[
  BetterBackpack.Pins — track items not owned (red ghost icon, no bag slot).
  profile.pins = { [itemID] = true }
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local Pins = {}
BetterBackpack.Modules.Pins = Pins

local Config = BetterBackpack.Config
local Slots = BetterBackpack.Modules.Slots

local SLOT = 37
local PAD = 2
local HEADER_H = 18
local ghosts = {} -- itemID → frame
local section

local function Profile()
  return Config.GetProfile()
end

local function EnsurePins()
  local p = Profile()
  if type(p.pins) ~= "table" then
    p.pins = {}
  end
  return p.pins
end

local function SafeNum(v)
  if Slots and Slots.SafeNum then
    return Slots.SafeNum(v)
  end
  if type(v) == "number" then
    return v
  end
  return nil
end

function Pins.List()
  local pins = EnsurePins()
  local out = {}
  for id, on in pairs(pins) do
    local n = SafeNum(tonumber(id) or id)
    if on and n then
      out[#out + 1] = n
    end
  end
  table.sort(out)
  return out
end

function Pins.Add(itemID)
  itemID = SafeNum(tonumber(itemID) or itemID)
  if not itemID then
    return
  end
  EnsurePins()[itemID] = true
  local Layout = BetterBackpack.Modules.Layout
  if Layout and Layout.Relayout then
    Layout.Relayout()
  end
end

function Pins.Remove(itemID)
  itemID = SafeNum(tonumber(itemID) or itemID)
  if not itemID then
    return
  end
  EnsurePins()[itemID] = nil
  local Layout = BetterBackpack.Modules.Layout
  if Layout and Layout.Relayout then
    Layout.Relayout()
  end
end

function Pins.Toggle(itemID)
  itemID = SafeNum(tonumber(itemID) or itemID)
  if not itemID then
    return
  end
  local pins = EnsurePins()
  if pins[itemID] then
    Pins.Remove(itemID)
  else
    Pins.Add(itemID)
  end
end

local function OwnedItemIDs()
  local owned = {}
  if not (Slots and Slots.BagRanges) then
    return owned
  end
  local ranges = Slots.BagRanges()
  for i = 1, #ranges do
    local bag, n = ranges[i].bag, ranges[i].slots
    for slot = 1, n do
      if Slots.SlotOccupied(bag, slot) and C_Container and C_Container.GetContainerItemID then
        local ok, id = pcall(C_Container.GetContainerItemID, bag, slot)
        if ok then
          id = SafeNum(id)
          if id then
            owned[id] = true
          end
        end
      end
    end
  end
  return owned
end

local function EnsureGhost(parent, itemID)
  local g = ghosts[itemID]
  if g then
    return g
  end
  g = CreateFrame("Button", nil, parent)
  g:SetSize(SLOT, SLOT)
  g:EnableMouse(true)
  local icon = g:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  g.icon = icon
  local veil = g:CreateTexture(nil, "OVERLAY")
  veil:SetAllPoints()
  veil:SetColorTexture(0.85, 0.12, 0.12, 0.45)
  g.veil = veil
  local border = g:CreateTexture(nil, "OVERLAY", nil, 1)
  border:SetAllPoints()
  border:SetColorTexture(0.9, 0.15, 0.15, 0.55)
  pcall(function()
    border:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
    border:SetBlendMode("ADD")
    border:SetVertexColor(1, 0.2, 0.2, 0.9)
  end)
  g:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
      pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
    else
      GameTooltip:SetText("Pinned item " .. tostring(itemID))
    end
    GameTooltip:AddLine("Not in bags — pin (no slot reserved)", 1, 0.4, 0.4, true)
    GameTooltip:AddLine("Click to unpin", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  g:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  g:SetScript("OnClick", function()
    Pins.Remove(itemID)
  end)
  ghosts[itemID] = g
  return g
end

local function SetGhostIcon(g, itemID)
  local tex
  if C_Item and C_Item.GetItemIconByID then
    local ok, t = pcall(C_Item.GetItemIconByID, itemID)
    if ok then
      tex = t
    end
  end
  if not tex and GetItemIcon then
    local ok, t = pcall(GetItemIcon, itemID)
    if ok then
      tex = t
    end
  end
  if tex and not (Slots.IsSecret and Slots.IsSecret(tex)) then
    g.icon:SetTexture(tex)
  else
    g.icon:SetColorTexture(0.3, 0.1, 0.1, 0.9)
  end
  g.icon:SetVertexColor(1, 0.55, 0.55)
end

--- Place ghost icons for pinned-but-not-owned items. Returns extra height used.
function Pins.Layout(parent, startY, cols)
  cols = cols or 8
  local list = Pins.List()
  local owned = OwnedItemIDs()
  local missing = {}
  for i = 1, #list do
    local id = list[i]
    if not owned[id] then
      missing[#missing + 1] = id
    end
  end

  -- Hide all ghosts first.
  for _, g in pairs(ghosts) do
    g:Hide()
  end

  if #missing == 0 then
    if section then
      section:Hide()
    end
    return 0
  end

  if not section then
    section = CreateFrame("Frame", nil, parent)
    local header = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 4, 0)
    section.header = header
  end
  section:SetParent(parent)
  section:ClearAllPoints()
  section:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -startY)
  section:Show()
  section.header:SetText(string.format("Pinned — missing (%d)", #missing))
  section.header:SetTextColor(1, 0.35, 0.35)

  local y = HEADER_H + 2
  local col, row = 0, 0
  for i = 1, #missing do
    local id = missing[i]
    local g = EnsureGhost(parent, id)
    SetGhostIcon(g, id)
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", parent, "TOPLEFT", col * (SLOT + PAD), -(startY + y + row * (SLOT + PAD)))
    g:Show()
    col = col + 1
    if col >= cols then
      col = 0
      row = row + 1
    end
  end
  local rows = math.ceil(#missing / cols)
  local h = y + rows * (SLOT + PAD) + 4
  section:SetHeight(HEADER_H)
  return h
end
