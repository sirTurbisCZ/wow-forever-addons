--[[
  BetterBackpack.Settings — category lanes + nice-to-have toggles (0.5.0).
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local Settings = {}
BetterBackpack.Modules.Settings = Settings

local Config = BetterBackpack.Config
local Layout = BetterBackpack.Modules.Layout

local panel
local rows = {}
local featureRows = {}

local function Profile()
  return Config.GetProfile()
end

local function Feat(name)
  return BetterBackpack.Modules and BetterBackpack.Modules[name]
end

local function CategoryOrder()
  if Layout and Layout.GetCategoryOrder then
    return Layout.GetCategoryOrder()
  end
  return (Layout and Layout.CATEGORY_ORDER) or {
    "junk", "consumable", "reagent", "gem", "gear", "quest", "keys", "container", "other",
  }
end

local function CategoryLabel(key)
  if Layout and Layout.GetCategoryLabel then
    return Layout.GetCategoryLabel(key)
  end
  local labels = (Layout and Layout.CATEGORY_LABELS) or {}
  return labels[key] or key
end

local function RefreshBags()
  if Layout and Layout.Relayout then
    Layout.Relayout()
  elseif Layout and Layout.Refresh then
    Layout.Refresh()
  end
end

local function MakeCheck(parent)
  local btn
  pcall(function()
    btn = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  end)
  if not btn then
    btn = CreateFrame("CheckButton", nil, parent)
    btn:SetSize(24, 24)
    local box = btn:CreateTexture(nil, "BACKGROUND")
    box:SetAllPoints()
    box:SetColorTexture(0.2, 0.2, 0.2, 0.9)
    pcall(function()
      btn:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    end)
  end
  return btn
end

local function PaintFeatureToggles(y)
  local defs = {
    {
      key = "stackMerge",
      label = "Visual stack merge",
      get = function()
        local SM = Feat("StackMerge")
        return not SM or SM.IsEnabled()
      end,
      set = function(on)
        local SM = Feat("StackMerge")
        if SM and SM.SetEnabled then
          SM.SetEnabled(on)
        else
          Profile().stackMerge = on and true or false
          RefreshBags()
        end
      end,
    },
    {
      key = "dense",
      label = "Dense layout (more columns)",
      get = function()
        local LM = Feat("LayoutModes")
        return LM and LM.Get and LM.Get() == "dense"
      end,
      set = function(on)
        local LM = Feat("LayoutModes")
        if LM and LM.Set then
          LM.Set(on and "dense" or "lanes")
        else
          Profile().layoutMode = on and "dense" or "lanes"
          RefreshBags()
        end
      end,
    },
  }
  for i = 1, #defs do
    local d = defs[i]
    local row = featureRows[i]
    if not row then
      row = CreateFrame("Frame", nil, panel.host)
      row:SetSize(260, 26)
      local check = MakeCheck(row)
      check:SetPoint("LEFT", 0, 0)
      row.check = check
      local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      label:SetPoint("LEFT", check, "RIGHT", 4, 0)
      label:SetJustifyH("LEFT")
      row.label = label
      featureRows[i] = row
    end
    row:Show()
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.host, "TOPLEFT", 0, -y)
    row.label:SetText(d.label)
    row.label:SetTextColor(0.85, 0.9, 1)
    row.check:Enable()
    row.check:SetChecked(d.get() and true or false)
    row.check:SetScript("OnClick", function(self)
      local raw = self:GetChecked()
      d.set(raw == true or raw == 1)
    end)
    y = y + 28
  end
  for i = #defs + 1, #featureRows do
    featureRows[i]:Hide()
  end
  return y
end

local function PaintRows()
  if not panel or not panel.host then
    return
  end
  local order = CategoryOrder()
  local p = Profile()
  if type(p.categories) ~= "table" then
    p.categories = {}
  end
  local y = 0
  for i = 1, #order do
    local key = order[i]
    local row = rows[i]
    if not row then
      row = CreateFrame("Frame", nil, panel.host)
      row:SetSize(260, 26)
      local check = MakeCheck(row)
      check:SetPoint("LEFT", 0, 0)
      row.check = check
      local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      label:SetPoint("LEFT", check, "RIGHT", 4, 0)
      label:SetJustifyH("LEFT")
      row.label = label
      rows[i] = row
    end
    row:Show()
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.host, "TOPLEFT", 0, -y)
    local labelText = CategoryLabel(key)
    row.label:SetText(labelText)
    if key == "other" then
      row.check:SetChecked(true)
      row.check:Disable()
      row.label:SetText(labelText .. " (always)")
      row.label:SetTextColor(0.7, 0.7, 0.7)
      row.check:SetScript("OnClick", nil)
    elseif type(key) == "string" and key:find("^custom_", 1) then
      row.check:SetChecked(true)
      row.check:Disable()
      row.label:SetTextColor(0.7, 1, 0.7)
      row.check:SetScript("OnClick", nil)
    else
      row.check:Enable()
      row.label:SetTextColor(1, 1, 1)
      local on = p.categories[key] ~= false
      row.check:SetChecked(on and true or false)
      row.check:SetScript("OnClick", function(self)
        local raw = self:GetChecked()
        local enabled = (raw == true or raw == 1)
        local CC = Feat("CustomCategories")
        if CC and CC.SetDefaultHidden then
          CC.SetDefaultHidden(key, not enabled)
        else
          local prof = Profile()
          if type(prof.categories) ~= "table" then
            prof.categories = {}
          end
          prof.categories[key] = enabled and true or false
          RefreshBags()
        end
      end)
    end
    y = y + 28
  end
  for i = #order + 1, #rows do
    rows[i]:Hide()
  end
  y = y + 8
  local sep = panel.featSep
  if not sep then
    sep = panel.host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.featSep = sep
  end
  sep:ClearAllPoints()
  sep:SetPoint("TOPLEFT", panel.host, "TOPLEFT", 0, -y)
  sep:SetText("Features")
  sep:Show()
  y = y + 18
  y = PaintFeatureToggles(y)
  panel.host:SetHeight(math.max(28, y))
  panel:SetHeight(56 + y + 48)
end

function Settings.Ensure()
  if panel then
    return panel
  end
  panel = CreateFrame("Frame", "BetterBackpackSettings", UIParent)
  panel:SetSize(300, 320)
  pcall(function()
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
  end)
  panel:SetFrameLevel(400)
  panel:EnableMouse(true)
  panel:SetMovable(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.06, 0.06, 0.07, 0.96)
  local edge = panel:CreateTexture(nil, "BORDER")
  edge:SetPoint("TOPLEFT", -1, 1)
  edge:SetPoint("BOTTOMRIGHT", 1, -1)
  edge:SetColorTexture(0.45, 0.4, 0.3, 0.7)

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("BetterBackpack — Categories")
  panel.title = title

  local close
  pcall(function()
    close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  end)
  if not close then
    close = CreateFrame("Button", nil, panel)
    close:SetSize(24, 24)
    close:SetText("X")
  end
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    panel:Hide()
  end)

  local tip = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  tip:SetPoint("TOPLEFT", 14, -34)
  tip:SetWidth(270)
  tip:SetJustifyH("LEFT")
  tip:SetText("Uncheck = hide that lane. Those items still appear under Other (nothing is hidden from the bag).")

  local host = CreateFrame("Frame", nil, panel)
  host:SetPoint("TOPLEFT", 14, -56)
  host:SetWidth(270)
  panel.host = host

  if UISpecialFrames then
    table.insert(UISpecialFrames, "BetterBackpackSettings")
  end

  panel:Hide()
  return panel
end

function Settings.Show()
  Settings.Ensure()
  PaintRows()
  panel:ClearAllPoints()
  local main = Layout and Layout.EnsureMain and Layout.EnsureMain()
  if main and main:IsShown() then
    panel:SetPoint("RIGHT", main, "LEFT", -12, 0)
  else
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
  panel:Show()
  panel:Raise()
end

function Settings.Hide()
  if panel then
    panel:Hide()
  end
end

function Settings.Toggle()
  Settings.Ensure()
  if panel:IsShown() then
    panel:Hide()
  else
    Settings.Show()
  end
end

function Settings.IsShown()
  return panel and panel:IsShown() and true or false
end
