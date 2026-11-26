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
local CONTENT_W = PANEL_W - NAV_W - PAD * 3 - 26 -- 26px reserved for the Blizzard scroll bar (arrows + track)

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
local trashChecks, trashRows, learnedRows = {}, {}, {}
local autoSellMarkedRows, autoSellPreviewRows, autoSellDropRow = {}, {}, nil
local Paint -- forward declaration (defined after the paint helpers)

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
  -- pairs, not #: pools can be sparse (e.g. notes[4..6] used without notes[1..3]).
  local function hidePool(pool)
    for _, f in pairs(pool) do
      if f and f.Hide then
        f:Hide()
      end
    end
  end
  hidePool(laneRows)
  hidePool(customRows)
  hidePool(featureRows)
  hidePool(trashRows)
  hidePool(learnedRows)
  hidePool(trashChecks)
  hidePool(autoSellMarkedRows)
  hidePool(autoSellPreviewRows)
  if autoSellDropRow and autoSellDropRow.Hide then
    autoSellDropRow:Hide()
  end
  for i = 1, #headers do
    if headers[i].fs then
      headers[i].fs:Hide()
    end
    if headers[i].line then
      headers[i].line:Hide()
    end
  end
  hidePool(notes)
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

-- Item names come from the client cache: ask for uncached items and repaint when they arrive.
local nameWatcher
local function ItemNameOrRequest(T, id)
  local name = T and T.ItemName and T.ItemName(id)
  if name and name ~= ("item:" .. tostring(id)) then
    return name
  end
  if C_Item and C_Item.RequestLoadItemDataByID then
    pcall(C_Item.RequestLoadItemDataByID, id)
  end
  if not nameWatcher then
    nameWatcher = CreateFrame("Frame")
    nameWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    local pending = false
    nameWatcher:SetScript("OnEvent", function()
      if pending or not (panel and panel:IsShown()) then
        return
      end
      if currentSection ~= "learned" and currentSection ~= "trash" then
        return
      end
      pending = true
      C_Timer.After(0.3, function()
        pending = false
        if panel and panel:IsShown() then
          Paint()
        end
      end)
    end)
  end
  return "Loading item…"
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
  y = Note(4, "Trash |cffff6666(destroy)|r is not Junk (sell). Rules are per character. Drop an item on the Trash header — it is destroyed (with confirmation) and future loot of it too. The list below shows what this character auto-destroys; Keep removes an item from it.", y)
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
    r.label:SetText(ItemNameOrRequest(T, id))
    r.extra:SetText("")
    r.forget:SetScript("OnClick", function()
      T.Forget(id)
    end)
    r:Show()
    y = y + ROW_H
  end
  if #ids == 0 then
    y = Note(6, "Nothing is auto-destroyed on this character.", y)
  end
  return y
end

local LEARNED_ROW_H = 36


local function LearnedRow(i)
  local row = learnedRows[i]
  if row then
    return row
  end
  row = CreateFrame("Frame", nil, Content())
  row:SetSize(CONTENT_W, LEARNED_ROW_H)
  row:EnableMouse(true)
  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(26, 26)
  icon:SetPoint("LEFT", 3, 0)
  row.icon = icon
  local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
  label:SetJustifyH("LEFT")
  label:SetWidth(CONTENT_W - 120)
  label:SetWordWrap(false)
  row.label = label
  local extra = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  extra:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
  extra:SetJustifyH("LEFT")
  extra:SetWidth(CONTENT_W - 120)
  extra:SetWordWrap(false)
  row.extra = extra
  row.forget = SmallButton(row, "Forget", 58)
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
  learnedRows[i] = row
  return row
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
  y = y + 28
  local T = Feat("Trash")
  local list = CC and CC.ListRules and CC.ListRules() or {}
  for i = 1, #list do
    local entry = list[i]
    local id, lane = entry.itemID, entry.lane
    local r = LearnedRow(i)
    r.itemID = id
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", Content(), "TOPLEFT", 0, -y)
    r.icon:SetTexture(T and T.ItemIcon and T.ItemIcon(id) or nil)
    r.label:SetText(ItemNameOrRequest(T, id))
    local natural = Layout and Layout.NaturalLaneForID and Layout.NaturalLaneForID(id) or "other"
    r.extra:SetText(string.format("in |cffffffff%s|r · default: %s", CategoryLabel(lane), CategoryLabel(natural)))
    r.forget:SetScript("OnClick", function()
      if lane == "trash" and T and T.Forget then
        T.Forget(id)
      elseif CC and CC.AssignItem then
        CC.AssignItem(id, nil)
      end
    end)
    r:Show()
    y = y + LEARNED_ROW_H
  end
  return y
end

local function AutoSellMarkedRow(i)
  local row = autoSellMarkedRows[i]
  if row then
    return row
  end
  row = CreateFrame("Frame", nil, Content())
  row:SetSize(CONTENT_W, ROW_H)
  row:EnableMouse(true)
  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetPoint("LEFT", 3, 0)
  row.icon = icon
  local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
  label:SetJustifyH("LEFT")
  label:SetWidth(320)
  row.label = label
  local extra = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  extra:SetPoint("LEFT", label, "RIGHT", 4, 0)
  row.extra = extra
  row.forget = SmallButton(row, "Remove", 62)
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
  autoSellMarkedRows[i] = row
  return row
end

local function AutoSellPreviewRow(i)
  local row = autoSellPreviewRows[i]
  if row then
    return row
  end
  row = CreateFrame("Frame", nil, Content())
  row:SetSize(CONTENT_W, ROW_H)
  row:EnableMouse(true)
  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(18, 18)
  icon:SetPoint("LEFT", 3, 0)
  row.icon = icon
  local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
  label:SetJustifyH("LEFT")
  label:SetWidth(280)
  row.label = label
  local extra = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  extra:SetPoint("LEFT", label, "RIGHT", 4, 0)
  row.extra = extra
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
  autoSellPreviewRows[i] = row
  return row
end

local function AutoSellDrop()
  if not autoSellDropRow then
    autoSellDropRow = CreateFrame("Frame", nil, Content())
    autoSellDropRow:SetSize(CONTENT_W, ROW_H)
    autoSellDropRow:EnableMouse(true)
    autoSellDropRow:RegisterForDrag("LeftButton")
    local hl = autoSellDropRow:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(0.2, 0.6, 1, 0.12)
    hl:Hide()
    autoSellDropRow.hl = hl
    local fs = autoSellDropRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("LEFT", 6, 0)
    fs:SetText("Drag item here — always sell at vendor (this character)")
    autoSellDropRow.label = fs
    local function TryDrop()
      local VJ = Feat("VendorJunk")
      if VJ and VJ.MarkFromCursor and VJ.MarkFromCursor() then
        Settings.Refresh()
      end
    end
    autoSellDropRow:SetScript("OnReceiveDrag", TryDrop)
    autoSellDropRow:SetScript("OnMouseUp", TryDrop)
    autoSellDropRow:SetScript("OnEnter", function(self)
      self.hl:Show()
    end)
    autoSellDropRow:SetScript("OnLeave", function(self)
      self.hl:Hide()
    end)
  end
  return autoSellDropRow
end

local function ReasonLabel(reason)
  if reason == "grey" then
    return "grey"
  end
  if reason == "junk lane" then
    return "junk lane"
  end
  if reason == "marked" then
    return "marked"
  end
  return ""
end

local function PaintAutoSell(y)
  local VJ = Feat("VendorJunk")
  if not VJ then
    return y
  end
  y = y + 8
  y = Note(9, "Vendor auto-sell is |cff88ccffper character|r. Marked itemIDs always sell when vendor sell runs.", y)
  local drop = AutoSellDrop()
  drop:ClearAllPoints()
  drop:SetPoint("TOPLEFT", Content(), "TOPLEFT", 0, -y)
  drop:Show()
  y = y + ROW_H + 4
  local marked = VJ.MarkedIDs and VJ.MarkedIDs() or {}
  if #marked > 0 then
    y = Note(10, "Marked always sell:", y)
    for i = 1, #marked do
      local id = marked[i]
      local r = AutoSellMarkedRow(i)
      r.itemID = id
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", Content(), "TOPLEFT", 0, -y)
      r.icon:SetTexture(VJ.ItemIcon and VJ.ItemIcon(id))
      r.label:SetText(VJ.ItemName and VJ.ItemName(id) or tostring(id))
      r.extra:SetText("")
      r.forget:SetScript("OnClick", function()
        if VJ.Unmark then
          VJ.Unmark(id)
          Settings.Refresh()
        end
      end)
      r:Show()
      y = y + ROW_H
    end
  end
  local preview = VJ.PreviewBagItems and VJ.PreviewBagItems() or {}
  y = Note(11, "In bags now (will sell at vendor):", y)
  if #preview == 0 then
    y = Note(12, "Nothing matched — carry grey junk, Junk lane items, or mark itemIDs above.", y)
  else
    for i = 1, #preview do
      local e = preview[i]
      local id = e.itemID
      local r = AutoSellPreviewRow(i)
      r.itemID = id
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", Content(), "TOPLEFT", 0, -y)
      r.icon:SetTexture(VJ.ItemIcon and VJ.ItemIcon(id))
      r.label:SetText(VJ.ItemName and VJ.ItemName(id) or tostring(id))
      local bits = {}
      if e.stacks and e.stacks > 1 then
        bits[#bits + 1] = "x" .. e.stacks
      end
      local rl = ReasonLabel(e.reason)
      if rl ~= "" then
        bits[#bits + 1] = rl
      end
      r.extra:SetText(table.concat(bits, " · "))
      r:Show()
      y = y + ROW_H
    end
  end
  return y
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
    label = "Auto-sell grey items at vendor",
    get = function()
      local VJ = Feat("VendorJunk")
      return VJ and VJ.IsEnabled()
    end,
    set = function(on)
      local VJ = Feat("VendorJunk")
      if VJ and VJ.SetEnabled then
        VJ.SetEnabled(on)
      else
        Profile().autoSellJunk = on
      end
      Settings.Refresh()
    end,
  },
  {
    label = "Auto-sell: include Junk lane (non-grey)",
    get = function()
      local VJ = Feat("VendorJunk")
      return VJ and VJ.LaneOptIn()
    end,
    set = function(on)
      local VJ = Feat("VendorJunk")
      if VJ and VJ.SetLaneOptIn then
        VJ.SetLaneOptIn(on)
      else
        Profile().autoSellJunkLane = on
      end
      Settings.Refresh()
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
  y = Note(8, "Optional bag behaviour. Bulk RMB on lane headers needs vendor, mail, or bank open (OOC).", y)
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
  y = PaintAutoSell(y)
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

local lastPaintedSection
local function PaintContent()
  HideAll()
  if panel and panel.scroll and lastPaintedSection ~= currentSection then
    panel.scroll:SetVerticalScroll(0)
  end
  lastPaintedSection = currentSection
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
  local contentH = math.max(120, y + 8)
  Content():SetHeight(contentH)
  local sbar = panel.scroll and panel.scroll.ScrollBar
  if sbar and panel.scroll.GetHeight then
    sbar:SetShown(contentH - (panel.scroll:GetHeight() or 0) > 1)
  end
end

Paint = function()
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

  -- Scrollable content (Blizzard UIPanelScrollFrameTemplate: arrows, track, thumb, mouse wheel).
  local okScroll, scroll = pcall(CreateFrame, "ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  if not okScroll or not scroll then
    scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
      local max = self:GetVerticalScrollRange() or 0
      self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * 48)))
    end)
  end
  scroll:SetPoint("TOPLEFT", panel.navDiv, "TOPRIGHT", PAD, 0)
  scroll:SetSize(CONTENT_W, PANEL_H - TOP - PAD)
  scroll:SetFrameLevel(panel:GetFrameLevel() + 20)
  local sb = scroll.ScrollBar or (scroll.GetName and scroll:GetName() and _G[scroll:GetName() .. "ScrollBar"])
  if sb then
    sb:ClearAllPoints()
    sb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -16)
    sb:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 16)
    sb:SetFrameLevel(panel:GetFrameLevel() + 25)
    -- Show the bar only when the content is taller than the viewport.
    scroll:HookScript("OnScrollRangeChanged", function(_, _, yRange)
      sb:SetShown((yRange or 0) > 1)
    end)
    sb:Hide()
  end
  panel.scroll = scroll
  panel.content = CreateFrame("Frame", nil, scroll)
  panel.content:SetSize(CONTENT_W, PANEL_H - TOP - PAD)
  scroll:SetScrollChild(panel.content)
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
  if main and main:IsShown() and (main:GetAlpha() or 0) > 0.5 then
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