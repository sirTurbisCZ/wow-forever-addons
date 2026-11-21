--[[
  BetterBackpack.Settings — Interface Options style (0.5.24).
  Left category list, right content pane. Same CombinedBags chrome as the bag.
  Never SetFrameStrata (Forever ADDON_ACTION_BLOCKED) — frame level only.
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local Settings = {}
BetterBackpack.Modules.Settings = Settings

local Config = BetterBackpack.Config
local Layout = BetterBackpack.Modules.Layout

local PANEL_W, PANEL_H = 580, 460
local NAV_W = 132
local PAD = 10
local TOP = 36
local ROW_H = 24
local CONTENT_W = PANEL_W - NAV_W - PAD * 3

local SECTIONS = {
  { id = "lanes", label = "Lanes" },
  { id = "custom", label = "Custom lanes" },
  { id = "trash", label = "Trash" },
  { id = "learned", label = "Learned" },
  { id = "features", label = "Features" },
}

local panel
local currentSection = "lanes"
local navBtns = {}
local laneRows, customRows, featureRows, headers, notes = {}, {}, {}, {}, {}
local trashChecks, trashRows = {}, {}

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

local function Content()
  return panel and panel.content
end

local function Gold(fs)
  local c = NORMAL_FONT_COLOR
  if c and c.r then
    fs:SetTextColor(c.r, c.g, c.b)
  else
    fs:SetTextColor(1, 0.82, 0)
  end
end

local function HideAll()
  local function hidePool(pool)
    for i = 1, #pool do
      pool[i]:Hide()
    end
  end
  hidePool(laneRows)
  hidePool(customRows)
  hidePool(featureRows)
  hidePool(trashRows)
  hidePool(trashChecks)
  for i = 1, #headers do
    if headers[i].fs then
      headers[i].fs:Hide()
    end
    if headers[i].line then
      headers[i].line:Hide()
    end
  end
  for i = 1, #notes do
    notes[i]:Hide()
  end
  if panel then
    if panel.addBtn then
      panel.addBtn:Hide()
    end
    if panel.forgetBtn then
      panel.forgetBtn:Hide()
    end
    if panel.learnedFs then
      panel.learnedFs:Hide()
    end
  end
end

local function SectionTitle(text, y)
  local h = headers[1]
  if not h then
    h = {}
    h.fs = Content():CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h.fs:SetJustifyH("LEFT")
    headers[1] = h
  end
  h.fs:ClearAllPoints()
  h.fs:SetPoint("TOPLEFT", Content(), "TOPLEFT", 2, -y)
  h.fs:SetText(text)
  Gold(h.fs)
  h.fs:Show()
  return y + 26
end

local function Note(i, text, y)
  local fs = notes[i]
  if not fs then
    fs = Content():CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetWidth(CONTENT_W - 4)
    fs:SetTextColor(0.65, 0.65, 0.65)
    notes[i] = fs
  end
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", Content(), "TOPLEFT", 2, -y)
  fs:SetText(text)
  fs:Show()
  return y + math.ceil(fs:GetStringHeight() or 12) + 8
end

local function RowHighlight(row)
  if row._bbRowHl then
    return
  end
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  hl:SetBlendMode("ADD")
  hl:SetAlpha(0.35)
  row._bbRowHl = hl
end

local function CheckRow(pool, i)
  local row = pool[i]
  if row then
    return row
  end
  row = CreateFrame("Button", nil, Content())
  row:SetSize(CONTENT_W, ROW_H)
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
  b:SetSize(w, 22)
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
  y = Note(1, "Unchecked lanes spill into Other — nothing is hidden from the bag.", y)
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
    row:SetPoint("TOPLEFT", Content(), "TOPLEFT", 0, -y)
    row:Show()
    row.laneKey = key
    row.label:SetText(CategoryLabel(key) .. (key == "trash" and "  |cffff5050(auto-destroy)|r" or ""))
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
      local on = Layout and Layout.CategoryEnabled and Layout.CategoryEnabled(key)
      if on == nil then
        on = not hidden and p.categories[key] ~= false
      end
      row.check:SetChecked(on and true or false)
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
  return y
end

local function CustomRow(i)
  local row = customRows[i]
  if row then
    return row
  end
  row = CreateFrame("Frame", nil, Content())
  row:SetSize(CONTENT_W, ROW_H)
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
  label:SetWidth(200)
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
  y = Note(2, "Create and rename lanes here only. Drop an item on a row or on a lane header in the bag to teach it.", y)
  local add = panel.addBtn
  if not add then
    add = SmallButton(Content(), "New lane", 96)
    add:SetScript("OnClick", function()
      if CC and CC.PromptNew then
        CC.PromptNew(nil)
      end
    end)
    panel.addBtn = add
  end
  add:ClearAllPoints()
  add:SetPoint("TOPLEFT", Content(), "TOPLEFT", 0, -y)
  add:Show()
  y = y + 30
  local list = CC and CC.List and CC.List() or {}
  for i = 1, #list do
    local c = list[i]
    local row = CustomRow(i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", Content(), "TOPLEFT", 0, -y)
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
  if #list == 0 then
    y = Note(3, "No custom lanes yet — use New lane above.", y)
  end
  return y
end

local function TrashRow(i)
  local row = trashRows[i]
  if row then
    return row
  end
  row = CreateFrame("Frame", nil, Content())
  row:SetSize(CONTENT_W, ROW_H)
  row:EnableMouse(true)
  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetPoint("LEFT", 3, 0)
  pcall(icon.SetDesaturated, icon, true)
  icon:SetAlpha(0.7)
  row.icon = icon
  local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
  label:SetJustifyH("LEFT")
  label:SetWidth(240)
  label:SetWordWrap(false)
  row.label = label
  local extra = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  extra:SetPoint("LEFT", label, "RIGHT", 4, 0)
  row.extra = extra
  row.forget = SmallButton(row, "Keep", 58)
  row.forget:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row:SetScript("OnEnter", function(self)
    if self.itemID and GameTooltip.SetItemByID then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  trashRows[i] = row
  return row
end

local function TrashStatus(T)
  local r = T.TestResult and T.TestResult()
  if r and r.click == false then
    return "|cffff5050/bb trashtest: this client blocks destroying — Trash can't work.|r"
  end
  return "New loot waits in Trash (red) and is destroyed on your next click in the bag."
end

local function PaintTrash(y)
  local T = Feat("Trash")
  if not T then
    return y
  end
  y = Note(4, "Trash |cffff6666(destroy)|r is not Junk (sort). Drop on the Trash header — destroyed immediately. Ghost icon = future loot destroyed. Keep to stop.", y)
  y = Note(5, TrashStatus(T), y)
  local row = CheckRow(trashChecks, 1)
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", Content(), "TOPLEFT", 0, -y)
  row:Show()
  row.label:SetText("Don't ask again (skip all destroy confirms)")
  row.label:SetTextColor(1, 1, 1)
  row.extra:SetText("")
  row.check:Enable()
  row.check:SetChecked(T.DontAskAgain and T.DontAskAgain() or false)
  row.check:SetScript("OnClick", function(self)
    local raw = self:GetChecked()
    local dontAsk = raw == true or raw == 1
    if T.SetDontAskAgain then
      T.SetDontAskAgain(dontAsk)
    else
      T.SetConfirm(not dontAsk)
    end
  end)
  y = y + ROW_H + 6
  local ids = T.TaughtIDs()
  for i = 1, #ids do
    local id = ids[i]
    local r = TrashRow(i)
    r.itemID = id
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", Content(), "TOPLEFT", 0, -y)
    r.icon:SetTexture(T.ItemIcon(id))
    r.label:SetText(T.ItemName(id))
    local n = T.DestroyedCount(id)
    r.extra:SetText(n > 0 and ("x" .. n) or "")
    r.forget:SetScript("OnClick", function()
      T.Forget(id)
    end)
    r:Show()
    y = y + ROW_H
  end
  if #ids == 0 then
    y = Note(6, "Nothing in Trash yet.", y)
  end
  return y
end

local function PaintLearned(y)
  local CC = Feat("CustomCategories")
  local n = CC and CC.CountRules and CC.CountRules() or 0
  y = Note(7, "Drag an item onto another lane header (or an item in that lane). Drop back on its natural lane to forget.", y)
  local fs = panel.learnedFs
  if not fs then
    fs = Content():CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.learnedFs = fs
  end
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", Content(), "TOPLEFT", 2, -y)
  fs:SetText(n > 0 and (LearnedLabel(n) .. " taught") or "Nothing taught yet")
  fs:Show()
  y = y + 24
  local forget = panel.forgetBtn
  if not forget then
    forget = SmallButton(Content(), "Forget all", 88)
    forget:SetScript("OnClick", function()
      if CC and CC.PromptForgetAll then
        CC.PromptForgetAll()
      end
    end)
    panel.forgetBtn = forget
  end
  forget:ClearAllPoints()
  forget:SetPoint("TOPLEFT", Content(), "TOPLEFT", 0, -y)
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
  y = Note(8, "Optional bag behaviour.", y)
  for i = 1, #FEATURES do
    local d = FEATURES[i]
    local row = CheckRow(featureRows, i)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", Content(), "TOPLEFT", 0, -y)
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

local function NavButton(i)
  local btn = navBtns[i]
  if btn then
    return btn
  end
  btn = CreateFrame("Button", nil, panel.nav)
  btn:SetSize(NAV_W - 8, 24)
  btn:SetNormalFontObject(GameFontHighlight)
  btn:SetHighlightFontObject(GameFontHighlight)
  btn:SetDisabledFontObject(GameFontDisable)
  local hl = btn:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.82, 0, 0.15)
  hl:Hide()
  btn.hl = hl
  local sel = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
  sel:SetAllPoints()
  sel:SetColorTexture(1, 0.82, 0, 0.28)
  sel:Hide()
  btn.sel = sel
  btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  btn.text:SetPoint("LEFT", 10, 0)
  btn.text:SetJustifyH("LEFT")
  btn:SetScript("OnClick", function()
    currentSection = SECTIONS[i].id
    Settings.Refresh()
  end)
  btn:SetScript("OnEnter", function(self)
    if currentSection ~= SECTIONS[i].id then
      self.hl:Show()
    end
  end)
  btn:SetScript("OnLeave", function(self)
    self.hl:Hide()
  end)
  navBtns[i] = btn
  return btn
end

local function PaintNav()
  local y = 4
  for i = 1, #SECTIONS do
    local sec = SECTIONS[i]
    local btn = NavButton(i)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", panel.nav, "TOPLEFT", 4, -y)
    btn.text:SetText(sec.label)
    local on = currentSection == sec.id
    btn.sel:SetShown(on)
    btn.text:SetTextColor(on and 1 or 0.75, on and 0.82 or 0.75, on and 0 or 0.75)
    btn:Show()
    y = y + 26
  end
  for i = #SECTIONS + 1, #navBtns do
    navBtns[i]:Hide()
  end
end

local function PaintContent()
  HideAll()
  local title
  for i = 1, #SECTIONS do
    if SECTIONS[i].id == currentSection then
      title = SECTIONS[i].label
      break
    end
  end
  local y = 0
  y = SectionTitle(title or "Settings", y)
  if currentSection == "lanes" then
    y = PaintLanes(y)
  elseif currentSection == "custom" then
    y = PaintCustom(y)
  elseif currentSection == "trash" then
    y = PaintTrash(y)
  elseif currentSection == "learned" then
    y = PaintLearned(y)
  elseif currentSection == "features" then
    y = PaintFeatures(y)
  end
  Content():SetHeight(math.max(120, y + 8))
end

local function Paint()
  if not panel or not panel.content then
    return
  end
  PaintNav()
  PaintContent()
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
  panel:SetSize(PANEL_W, PANEL_H)
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
  end

  local close = panel.CloseButton
  if close then
    close:SetScript("OnClick", function()
      panel:Hide()
    end)
  end

  panel.nav = CreateFrame("Frame", nil, panel)
  panel.nav:SetPoint("TOPLEFT", PAD, -TOP)
  panel.nav:SetSize(NAV_W, PANEL_H - TOP - PAD)
  panel.nav:SetFrameLevel(panel:GetFrameLevel() + 15)

  if not panel.navDiv then
    panel.navDiv = panel:CreateTexture(nil, "ARTWORK")
    panel.navDiv:SetColorTexture(1, 1, 1, 0.12)
    panel.navDiv:SetWidth(1)
  end
  panel.navDiv:ClearAllPoints()
  panel.navDiv:SetPoint("TOP", panel.nav, "TOPRIGHT", 4, 0)
  panel.navDiv:SetPoint("BOTTOM", panel.nav, "BOTTOMRIGHT", 4, 0)
  panel.navDiv:Show()

  panel.content = CreateFrame("Frame", nil, panel)
  panel.content:SetPoint("TOPLEFT", panel.navDiv, "TOPRIGHT", PAD, 0)
  panel.content:SetSize(CONTENT_W, PANEL_H - TOP - PAD)
  panel.content:SetFrameLevel(panel:GetFrameLevel() + 20)
  panel.host = panel.content

  if UISpecialFrames then
    table.insert(UISpecialFrames, "BetterBackpackSettings")
  end
  panel:Hide()
  return panel
end

function Settings.SetDropHints(on)
  local show = on and panel and panel:IsShown() and currentSection == "custom"
  for i = 1, #customRows do
    local row = customRows[i]
    if row.dropHl then
      row.dropHl:SetShown(show and row:IsShown() and true or false)
    end
  end
end

function Settings.LaneUnderMouse()
  if not (panel and panel:IsVisible()) then
    return nil
  end
  local pools = { { laneRows, "laneKey" }, { customRows, "laneId" } }
  for p = 1, #pools do
    local pool, field = pools[p][1], pools[p][2]
    for i = 1, #pool do
      local row = pool[i]
      if row[field] and row:IsVisible() and row:IsMouseOver() then
        return row[field]
      end
    end
  end
  return nil
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
  if Layout and Layout.Raise then
    Layout.Raise()
  end
  panel:SetFrameLevel((main and main:GetFrameLevel() or 200) + 30)
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