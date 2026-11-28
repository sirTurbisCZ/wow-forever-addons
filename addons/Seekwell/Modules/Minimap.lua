--[[
  Seekwell.Minimap — the minimap button.
  Parent is UIParent, anchored to the Minimap (the client clips children of the Minimap with its round mask).
  Left-click: window. Right-click: target panel. Drag: angle around the minimap (saved).
]]

Seekwell = Seekwell or {}
Seekwell.Modules = Seekwell.Modules or {}

local Mod = {}
Seekwell.Modules.Minimap = Mod

local L = Seekwell.L or {}
local button
local dragging = false
local DEFAULT_ANGLE = 200

local atan2 = math.atan2 or function(y, x)
  return math.atan(y, x)
end

local function Cfg()
  return Seekwell.Config.Get().minimap
end

local function Place()
  if not button or not Minimap then
    return
  end
  local angle = tonumber(Cfg().angle) or DEFAULT_ANGLE
  local radius = ((Minimap:GetWidth() or 140) / 2) + 4
  local rad = math.rad(angle)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function UpdateAngleFromCursor()
  if not Minimap or not Minimap.GetCenter then
    return
  end
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  if not mx or not cx or not scale or scale == 0 then
    return
  end
  cx, cy = cx / scale, cy / scale
  local angle = math.deg(atan2(cy - my, cx - mx)) % 360
  Cfg().angle = angle
  Place()
end

local function ShowTooltip(self)
  if not GameTooltip then
    return
  end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText(L.TIP_TITLE or "Seekwell", 1, 1, 1)
  GameTooltip:AddLine(L.TIP_LEFT or "", 0.8, 0.8, 0.8)
  GameTooltip:AddLine(L.TIP_RIGHT or "", 0.8, 0.8, 0.8)
  GameTooltip:AddLine(L.TIP_SHIFT or "Shift+left-click: target drops", 0.8, 0.8, 0.8)
  GameTooltip:AddLine(L.TIP_DRAG or "", 0.8, 0.8, 0.8)
  GameTooltip:Show()
end

function Mod.Create()
  if button or not Minimap then
    return button
  end
  button = CreateFrame("Button", "SeekwellMinimapButton", UIParent)
  button:SetSize(32, 32)
  button:SetFrameStrata("HIGH")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")

  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture(136467) -- LibDBIcon background
  bg:SetPoint("CENTER", 0, 1)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
  icon:SetPoint("CENTER", 0, 1)
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(54, 54)
  border:SetTexture(136430) -- LibDBIcon border
  border:SetPoint("TOPLEFT")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  button:SetScript("OnClick", Seekwell.Safe("minimap.click", function(_, mouse)
    if mouse == "RightButton" then
      -- settings window (the sections that used to open on left-click)
      if Seekwell.Window.ShowSettings then
        Seekwell.Window.ShowSettings()
      else
        Seekwell.Window.Toggle()
      end
    elseif IsShiftKeyDown and IsShiftKeyDown() then
      Seekwell.TargetPanel.Toggle()
    else
      Seekwell.Window.Toggle() -- the search browser
    end
  end))
  button:SetScript("OnDragStart", function(self)
    dragging = true
    if GameTooltip then
      GameTooltip:Hide()
    end
    self:SetScript("OnUpdate", Seekwell.Safe("minimap.drag", UpdateAngleFromCursor))
  end)
  button:SetScript("OnDragStop", function(self)
    dragging = false
    self:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", function(self)
    if not dragging then
      ShowTooltip(self)
    end
  end)
  button:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  Place()
  Mod.Apply()
  return button
end

--- Show / hide from the settings.
function Mod.Apply()
  if not button then
    if Cfg().show ~= false then
      Mod.Create()
    end
    return
  end
  if Cfg().show == false then
    button:Hide()
  else
    Place()
    button:Show()
  end
end

function Mod.SetShown(on)
  Cfg().show = on and true or false
  Mod.Apply()
end

function Mod.Reset()
  Cfg().show = true
  Cfg().angle = DEFAULT_ANGLE
  if not button then
    Mod.Create()
  end
  Mod.Apply()
end

function Mod.Button()
  return button
end
