--[[
  BetterBackpack.Settings — lanes, custom lanes, learned items, features (0.5.17).
  Same CombinedBags chrome as the bag (Layout.CreateChromedPanel), Blizzard options rows:
  gold section header + hairline, UICheckButtonTemplate, full-row click + hover highlight.
  Never SetFrameStrata (Forever ADDON_ACTION_BLOCKED) — frame level only.
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local Settings = {}
BetterBackpack.Modules.Settings = Settings

local Config = BetterBackpack.Config
local Layout = BetterBackpack.Modules.Layout

local PANEL_W = 300
local PAD_X = 16
local ROW_H = 24
local TOP = 32

local panel
local laneRows, customRows, featureRows, headers, notes = {}, {}, {}, {}, {}

local function Profile()
  return Config.GetProfile()
end

local function Feat(name)
  return BetterBackpack.Modules and BetterBackpack.Modules[name]
end

local function BuiltInOrder()
  return (Layout and Layout.CATEGORY_ORDER) or {
    "junk", "consumable", "reagent", "gem", "gear", "quest", "keys", "container", "other",
  }
end

local function CategoryLabel(key)
  if Layout and Layout.GetCategoryLabel then
    return Layout.GetCategoryLabel(key)
  end
  return key
end

local function RefreshBags()
  if Layout and Layout.Relayout then
    Layout.Relayout()
  end
end

local function Gold(fs)
  local c = NORMAL_FONT_COLOR
  if c and c.r then
    fs:SetTextColor(c.r, c.g, c.b)
  else
    fs:SetTextColor(1, 0.82, 0)
  end
end

local function Header(i, text, y)
  local h = headers[i]
  if not h then
    h = {}
    h.fs = panel.host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h.fs:SetJustifyH("LEFT")
    h.line = panel.host:CreateTexture(nil, "ARTWORK")
    h.line:SetColorTexture(1, 1, 1, 0.14)
    h.line:SetHeight(1)
    headers[i] = h
  end
  h.fs:ClearAllPoints()
  h.fs:SetPoint("TOPLEFT", panel.host, "TOPLEFT", 0, -y)
  h.fs:SetText(text)
  Gold(h.fs)
  h.fs:Show()
  h.line:ClearAllPoints()
  h.line:SetPoint("LEFT", h.fs, "RIGHT", 8, 0)
  h.line:SetPoint("RIGHT", panel.host, "RIGHT", 0, 0)
  h.line:Show()
  return y + 20
end

local function Note(i, text, y)
  local fs = notes[i]
  if not fs then
    fs = panel.host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetWidth(PANEL_W - 2 * PAD_X)
    fs:SetTextColor(0.65, 0.65, 0.65)
    notes[i] = fs
  end
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", panel.host, "TOPLEFT", 2, -y)
  fs:SetText(text)
  fs:Show()
  return y + math.ceil(fs:GetStringHeight() or 12) + 6
end

local function RowHighlight(row)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  hl:SetBlendMode("ADD")
  hl:SetAlpha(0.35)
end

local function CheckRow(pool, i)
  local row = pool[i]
  if row then
    return row
  end
  row = CreateFrame("Button", nil, panel.host)
  row:SetSize(PANEL_W - 2 * PAD_X, ROW_H)
  RowHighlight(row)
  local ok, check = pcall(CreateFrame, "CheckButton", nil, row, "UICheckButtonTemplate")
  if not ok or not check then
    check = CreateFrame("CheckButton", nil, row)
    check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  end
  check:SetSize(ROW_H, ROW_H)
  check:SetPoint("LEFT", 0, 0)
  row.check = check
  local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("LEFT", check, "RIGHT", 4, 0)
  label:SetJustifyH("LEFT")
  row.label = label
  local extra = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  extra:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  row.extra = extra
  row:SetScript("OnClick", function(self)
    if self.check:IsEnabled() then
      self.check:Click()
    end
  end)
  pool[i] = row
  return row
end

local function SmallButton(parent, text, w)
  local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
  if not ok or not b then
    b = CreateFrame("Button", nil, parent)
  end
  b:SetSize(w, 20)
  b:SetText(text)
  pcall(b.SetNormalFontObject, b, GameFontNormalSmall)
  pcall(b.SetHighlightFontObject, b, GameFontHighlightSmall)
  pcall(b.SetDisabledFontObject, b, GameFontDisableSmall)
  return b
end

local function LearnedLabel(n)
  if n == 1 then
    return "1 item"
  end
  return n .. " items"
end

local function PaintLanes(y)
  local order = BuiltInOrder()
  local p = Profile()
  if type(p.categories) ~= "table" then
    p.categories = {}
  end
  local CC = Feat("CustomCategories")
  for i = 1, #order do
    local key = order[i]
    local row = CheckRow(laneRows, i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.host, "TOPLEFT", 0, -y)
    row:Show()
    row.label:SetText(CategoryLabel(key))
    local learned = CC and CC.CountLaneRules and CC.CountLaneRules(key) or 0
    row.extra:SetText(learned > 0 and LearnedLabel(learned) or "")
    if key == "other" then
      row.check:SetChecked(true)
      row.check:Disable()
      row.label:SetText(CategoryLabel(key) .. "  |cff808080(always)|r")
      row.label:SetTextColor(0.7, 0.7, 0.7)
      row.check:SetScript("OnClick", nil)
    else
      row.check:Enable()
      row.label:SetTextColor(1, 1, 1)
      local hidden = CC and CC.IsDefaultHidden and CC.IsDefaultHidden(key)
      row.check:SetChecked(not hidden and p.categories[key] ~= false)
      row.check:SetScript("OnClick", function(self)
        local raw = self:GetChecked()
        local on = raw == true or raw == 1
        if CC and CC.SetDefaultHidden then
          CC.SetDefaultHidden(key, not on)
        else
          Profile().categories[key] = on
          RefreshBags()
        end
      end)
    end
    y = y + ROW_H
  end
  for i = #order + 1, #laneRows do
    laneRows[i]:Hide()
  end
  return y
end

local function CustomRow(i)
  local row = customRows[i]
  if row then
    return row
  end
  row = CreateFrame("Frame", nil, panel.host)
  row:SetSize(PANEL_W - 2 * PAD_X, ROW_H)
  -- Drop target too: an item dragged from the bag onto this row is taught to the lane.
  row:EnableMouse(true)
  local dropHl = row:CreateTexture(nil, "BACKGROUND")
  dropHl:SetAllPoints()
  dropHl:SetColorTexture(1, 0.82, 0, 0.12)
  dropHl:Hide()
  row.dropHl = dropHl
  local function Drop(self)
    if self.laneId and Layout and Layout.DropOnLane then
      Layout.DropOnLane(self.laneId)
    end
  end
  row:SetScript("OnReceiveDrag", Drop)
  row:SetScript("OnMouseUp", Drop)
  local swatch = row:CreateTexture(nil, "ARTWORK")
  swatch:SetSize(14, 14)
  swatch:SetPoint("LEFT", 5, 0)
  if not pcall(swatch.SetAtlas, swatch, "bag-arrow") or not swatch:GetAtlas() then
    swatch:SetColorTexture(1, 0.82, 0, 0.8)
  else
    swatch:SetRotation(math.pi / 2)
  end
  local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("LEFT", swatch, "RIGHT", 9, 0)
  label:SetJustifyH("LEFT")
  label:SetWidth(106)
  label:SetWordWrap(false)
  row.label = label
  row.del = SmallButton(row, DELETE or "Delete", 58)
  row.del:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.ren = SmallButton(row, "Rename", 62)
  row.ren:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
  customRows[i] = row
  return row
end

local function PaintCustom(y)
  local CC = Feat("CustomCategories")
  local list = CC and CC.List and CC.List() or {}
  for i = 1, #list do
    local c = list[i]
    local row = CustomRow(i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.host, "TOPLEFT", 0, -y)
    row.laneId = c.id
    local n = CC.CountLaneRules and CC.CountLaneRules(c.id) or 0
    row.label:SetText((c.name or c.id) .. (n > 0 and ("  |cff808080" .. n .. "|r") or ""))
    row.ren:SetScript("OnClick", function()
      CC.PromptRename(c.id)
    end)
    row.del:SetScript("OnClick", function()
      CC.PromptDelete(c.id)
    end)
    row:Show()
    y = y + ROW_H + 2
  end
  for i = #list + 1, #customRows do
    customRows[i]:Hide()
  end
  if #list == 0 then
    y = Note(1, "No custom lanes yet. Create one here, or drop an item on \"+ Lane\" in the bag.", y)
  else
    y = Note(4, "Drop an item from the bag on a lane here or on its header in the bag.", y)
  end
  if #list > 0 and notes[1] then
    notes[1]:Hide()
  elseif #list == 0 and notes[4] then
    notes[4]:Hide()
  end
  local add = panel.addBtn
  if not add then
    add = SmallButton(panel.host, "New lane", 96)
    add:SetScript("OnClick", function()
      if CC and CC.PromptNew then
        CC.PromptNew(nil)
      end
    end)
    panel.addBtn = add
  end
  add:ClearAllPoints()
  add:SetPoint("TOPLEFT", panel.host, "TOPLEFT", 0, -(y + 2))
  add:Show()
  return y + 28
end

local function PaintLearned(y)
  local CC = Feat("CustomCategories")
  local n = CC and CC.CountRules and CC.CountRules() or 0
  y = Note(2, "Drag an item from the bag onto another lane (its header or any item in it). "
    .. "That item goes there from now on. Drop it back on its own lane to forget.", y)
  local fs = panel.learnedFs
  if not fs then
    fs = panel.host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.learnedFs = fs
  end
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", panel.host, "TOPLEFT", 2, -(y + 4))
  fs:SetText(n > 0 and (LearnedLabel(n) .. " taught") or "Nothing taught yet")
  fs:Show()
  local forget = panel.forgetBtn
  if not forget then
    forget = SmallButton(panel.host, "Forget all", 84)
    forget:SetScript("OnClick", function()
      if CC and CC.PromptForgetAll then
        CC.PromptForgetAll()
      end
    end)
    panel.forgetBtn = forget
  end
  forget:ClearAllPoints()
  forget:SetPoint("TOPRIGHT", panel.host, "TOPRIGHT", 0, -(y + 1))
  if n > 0 then
    forget:Enable()
  else
    forget:Disable()
  end
  forget:Show()
  return y + 28
end

local FEATURES = {
  {
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
        Profile().stackMerge = on
        RefreshBags()
      end
    end,
  },
  {
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

local function PaintFeatures(y)
  for i = 1, #FEATURES do
    local d = FEATURES[i]
    local row = CheckRow(featureRows, i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.host, "TOPLEFT", 0, -y)
    row:Show()
    row.label:SetText(d.label)
    row.label:SetTextColor(1, 1, 1)
    row.extra:SetText("")
    row.check:Enable()
    row.check:SetChecked(d.get() and true or false)
    row.check:SetScript("OnClick", function(self)
      local raw = self:GetChecked()
      d.set(raw == true or raw == 1)
    end)
    y = y + ROW_H
  end
  return y
end

local function Paint()
  if not panel or not panel.host then
    return
  end
  local y = 0
  y = Header(1, "Lanes", y)
  y = Note(3, "Unchecked lanes spill into Other — nothing is hidden from the bag.", y)
  y = PaintLanes(y) + 10
  y = Header(2, "Custom lanes", y)
  y = PaintCustom(y) + 6
  y = Header(3, "Learned items", y)
  y = PaintLearned(y) + 6
  y = Header(4, "Features", y)
  y = PaintFeatures(y)
  panel.host:SetHeight(math.max(28, y))
  panel:SetHeight(TOP + y + 18)
end

function Settings.Ensure()
  if panel then
    return panel
  end
  if Layout and Layout.CreateChromedPanel then
    panel = Layout.CreateChromedPanel("BetterBackpackSettings")
  else
    panel = CreateFrame("Frame", "BetterBackpackSettings", UIParent)
  end
  panel:SetSize(PANEL_W, 420)
  panel:SetFrameLevel(510)
  panel:EnableMouse(true)
  panel:SetMovable(true)
  panel:SetClampedToScreen(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:SetScript("OnShow", function(self)
    if Layout and Layout.ApplyChrome then
      Layout.ApplyChrome(self)
    end
  end)

  local title = "BetterBackpack — Settings"
  if panel.SetTitle then
    pcall(panel.SetTitle, panel, title)
  elseif panel.TitleText then
    panel.TitleText:SetText(title)
  else
    local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOP", 0, -6)
    fs:SetText(title)
  end

  local close = panel.CloseButton
  if not close then
    local ok, b = pcall(CreateFrame, "Button", nil, panel, "UIPanelCloseButton")
    close = ok and b or nil
    if close then
      close:SetPoint("TOPRIGHT", 0, 0)
    end
  end
  if close then
    close:SetScript("OnClick", function()
      panel:Hide()
    end)
  end

  local host = CreateFrame("Frame", nil, panel)
  host:SetPoint("TOPLEFT", PAD_X, -TOP)
  host:SetWidth(PANEL_W - 2 * PAD_X)
  host:SetFrameLevel(panel:GetFrameLevel() + 20)
  panel.host = host

  if UISpecialFrames then
    table.insert(UISpecialFrames, "BetterBackpackSettings")
  end
  panel:Hide()
  return panel
end

function Settings.SetDropHints(on)
  for i = 1, #customRows do
    local row = customRows[i]
    row.dropHl:SetShown(on and row:IsShown() and true or false)
  end
end

function Settings.Refresh()
  if panel and panel:IsShown() then
    Paint()
  end
end

function Settings.Show()
  Settings.Ensure()
  Paint()
  panel:ClearAllPoints()
  local main = Layout and Layout.EnsureMain and Layout.EnsureMain()
  if main and main:IsShown() then
    panel:SetPoint("TOPRIGHT", main, "TOPLEFT", -8, 0)
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
