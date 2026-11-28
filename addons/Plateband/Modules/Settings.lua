--[[
  Plateband.Settings — the one settings window (/pb, minimap button) and the minimap button.
  Built lazily on first open; plain frames, no libraries. The only OnUpdate is the one set while the minimap
  button is being dragged (removed on drop).
]]

Plateband = Plateband or {}
Plateband.Modules = Plateband.Modules or {}

local Mod = {}
Plateband.Modules.Settings = Mod
Plateband.Settings = Mod

local frame, button, dragging
local widgets = {} -- refreshers
local baseline -- values the containers were built with (captured at ADDON_LOADED)
local PANEL_W, PANEL_H = 360, 330

local RELOAD_KEYS = { "enemyBuffs", "maxIcons" }

local function Profile()
  return Plateband.Config.GetProfile()
end

local function L()
  return Plateband.L or {}
end

local function Print(...)
  if Plateband.Print then
    Plateband.Print(...)
  end
end

local function Obj(v)
  local t = type(v)
  return (t == "table" or t == "userdata") and v or nil
end

local function Refresh()
  if Plateband.Modules.Plates and Plateband.Modules.Plates.Refresh then
    pcall(Plateband.Modules.Plates.Refresh)
  end
end

local function NeedsReload()
  if not baseline then
    return false
  end
  local p = Profile()
  for i = 1, #RELOAD_KEYS do
    if p[RELOAD_KEYS[i]] ~= baseline[RELOAD_KEYS[i]] then
      return true
    end
  end
  return false
end
Mod.NeedsReload = NeedsReload

--- After a setting that only a rebuild of the containers can apply: update the note, say it once in chat.
local function ReloadCheck()
  local need = NeedsReload()
  if frame and frame.reloadNote then
    frame.reloadNote:SetShown(need)
  end
  if need and not Mod._told then
    Mod._told = true
    Print(L().RELOAD_NEEDED or "/reload needed: this setting applies to plates created after /reload")
  elseif not need then
    Mod._told = nil
  end
end

local function Check(parent, label, y, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", 14, y)
  cb:SetSize(24, 24)
  local text = Obj(cb.text) or Obj(cb.Text)
  if not text then
    text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  end
  text:SetText(label)
  cb:SetScript("OnClick", function(self)
    local raw = self:GetChecked()
    set(raw == true or raw == 1)
  end)
  widgets[#widgets + 1] = function()
    cb:SetChecked(get() and true or false)
  end
  return cb
end

local function Slider(parent, label, y, min, max, get, set)
  local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s:SetPoint("TOPLEFT", 48, y)
  s:SetWidth(200)
  s:SetMinMaxValues(min, max)
  s:SetValueStep(1)
  if s.SetObeyStepOnDrag then
    s:SetObeyStepOnDrag(true)
  end
  local name = s.GetName and s:GetName()
  if type(name) ~= "string" then
    name = nil
  end
  local lo = Obj(s.Low) or (name and Obj(_G[name .. "Low"]))
  local hi = Obj(s.High) or (name and Obj(_G[name .. "High"]))
  local tx = Obj(s.Text) or (name and Obj(_G[name .. "Text"]))
  if lo then
    lo:SetText(tostring(min))
  end
  if hi then
    hi:SetText(tostring(max))
  end
  s:SetScript("OnValueChanged", function(_, value)
    value = math.floor((value or min) + 0.5)
    if tx then
      tx:SetText(label .. ": " .. value)
    end
    if get() ~= value then
      set(value)
    end
  end)
  widgets[#widgets + 1] = function()
    s:SetValue(get())
    if tx then
      tx:SetText(label .. ": " .. get())
    end
  end
  return s
end

--- Values the containers of this session are built with: captured at ADDON_LOADED (Core.lua), before any
--- plate row exists, so the "/reload needed" note is right even when the window is first opened later.
function Mod.CaptureBaseline()
  if baseline then
    return
  end
  local p = Profile()
  baseline = {}
  for i = 1, #RELOAD_KEYS do
    baseline[RELOAD_KEYS[i]] = p[RELOAD_KEYS[i]]
  end
end

local function Build()
  Mod.CaptureBaseline()

  local ok, f = pcall(CreateFrame, "Frame", "PlatebandSettings", UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then
    f = CreateFrame("Frame", "PlatebandSettings", UIParent, "BackdropTemplate")
    if f.SetBackdrop then
      f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
      })
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
  end
  f:SetSize(PANEL_W, PANEL_H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  local title = "Plateband \226\128\148 Settings"
  if f.SetTitle then
    pcall(f.SetTitle, f, title)
  elseif Obj(f.TitleText) then
    f.TitleText:SetText(title)
  else
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOP", 0, -14)
    t:SetText(title)
  end

  local y = -36
  Check(f, "Enable Plateband", y, function()
    return Profile().enabled ~= false
  end, function(on)
    local pr = Profile()
    pr.enabled = on
    if on then
      pr.safeMode = false
    end
    if Plateband.ApplyModuleState then
      Plateband.ApplyModuleState()
    end
  end)
  y = y - 28
  Check(f, "Friendly plates", y, function()
    return Profile().mergeFriendPlates ~= false
  end, function(on)
    Profile().mergeFriendPlates = on
    Refresh()
  end)
  y = y - 28
  Check(f, "Enemy buffs row (dispellable / stealable)", y, function()
    return Profile().enemyBuffs ~= false
  end, function(on)
    Profile().enemyBuffs = on
    ReloadCheck()
  end)
  y = y - 28
  Check(f, "Hover tooltips", y, function()
    return Profile().gapTooltip ~= false
  end, function(on)
    Profile().gapTooltip = on
    local pd = Plateband.PlatesPaintDeps
    if pd and pd.AcApplyTooltips then
      pcall(pd.AcApplyTooltips)
    end
  end)
  y = y - 28
  y = y - 24
  Slider(f, "Most icons per row", y, 1, 16, function()
    return math.max(1, math.min(16, tonumber(Profile().maxIcons) or 12))
  end, function(v)
    Profile().maxIcons = v
    ReloadCheck()
  end)

  local note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("BOTTOMLEFT", 18, 44)
  note:SetWidth(PANEL_W - 36)
  note:SetJustifyH("LEFT")
  note:SetTextColor(1, 0.6, 0.2)
  note:SetText(L().RELOAD_NOTE or "/reload needed: enemy buffs and icon count apply to plates created after /reload.")
  note:Hide()
  f.reloadNote = note

  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("BOTTOMLEFT", 18, 16)
  hint:SetWidth(PANEL_W - 36)
  hint:SetJustifyH("LEFT")
  hint:SetTextColor(0.65, 0.65, 0.65)
  hint:SetText("Chat commands: /pb help. Minimap button: /pb minimap.")

  if UISpecialFrames then
    table.insert(UISpecialFrames, "PlatebandSettings")
  end
  frame = f
  f:Hide()
  return f
end

function Mod.Refresh()
  for i = 1, #widgets do
    pcall(widgets[i])
  end
  if frame and frame.reloadNote then
    frame.reloadNote:SetShown(NeedsReload())
  end
end

function Mod.Ensure()
  if not frame then
    frame = Build()
  end
  return frame
end

function Mod.Show()
  Mod.Ensure()
  Mod.Refresh()
  frame:Show()
end

function Mod.Hide()
  if frame then
    frame:Hide()
  end
end

function Mod.Toggle()
  Mod.Ensure()
  if frame:IsShown() then
    frame:Hide()
  else
    Mod.Show()
  end
end

-- ---------------------------------------------------------------------------------------------------------
-- Minimap button (parent UIParent, anchored to the Minimap; left click toggles the window, drag moves it)
-- ---------------------------------------------------------------------------------------------------------

local atan2 = math.atan2 or function(y, x)
  return math.atan(y, x)
end

local function Cfg()
  local p = Profile()
  if type(p.minimap) ~= "table" then
    p.minimap = { show = true, angle = 230 }
  end
  return p.minimap
end

local function Place()
  if not button or not Minimap then
    return
  end
  local angle = tonumber(Cfg().angle) or 230
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
  Cfg().angle = math.deg(atan2(cy - my, cx - mx)) % 360
  Place()
end

function Mod.ApplyMinimap()
  if not button then
    return
  end
  if Cfg().show == false then
    button:Hide()
  else
    Place()
    button:Show()
  end
end

function Mod.CreateMinimap()
  if button or not Minimap then
    return button
  end
  button = CreateFrame("Button", "PlatebandMinimapButton", UIParent)
  button:SetSize(32, 32)
  button:SetFrameStrata("HIGH")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp")
  button:RegisterForDrag("LeftButton")

  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture(136467)
  bg:SetPoint("CENTER", 0, 1)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetTexture("Interface\\Icons\\Spell_Shadow_ShadowWordPain")
  icon:SetPoint("CENTER", 0, 1)
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(54, 54)
  border:SetTexture(136430)
  border:SetPoint("TOPLEFT")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  button:SetScript("OnClick", function()
    Mod.Toggle()
  end)
  button:SetScript("OnDragStart", function(self)
    dragging = true
    if GameTooltip then
      GameTooltip:Hide()
    end
    self:SetScript("OnUpdate", UpdateAngleFromCursor) -- only while dragging
  end)
  button:SetScript("OnDragStop", function(self)
    dragging = false
    self:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", function(self)
    if dragging or not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Plateband", 1, 1, 1)
    GameTooltip:AddLine("Left-click: settings window", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Drag: move", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  Mod.ApplyMinimap()
  return button
end

function Mod.SetMinimapShown(on)
  Cfg().show = on and true or false
  if on and not button then
    Mod.CreateMinimap()
  end
  Mod.ApplyMinimap()
end

function Mod.MinimapShown()
  return Cfg().show ~= false
end
