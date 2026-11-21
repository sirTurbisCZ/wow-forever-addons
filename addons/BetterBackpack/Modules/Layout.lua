--[[
  BetterBackpack.Layout — category lanes + chrome. Own buttons only (never harvest).
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local Layout = {}
BetterBackpack.Modules.Layout = Layout

local Config = BetterBackpack.Config
local Slots = BetterBackpack.Modules.Slots

local SLOT = 37
local PAD = 4
local HEADER_H = 20
local INSET_X = 14
local TOP_CHROME = 42
local BOT_CHROME = 28

local CATEGORY_ORDER = {
  "junk", "consumable", "reagent", "gem", "gear", "quest", "container", "other",
}

local CATEGORY_LABELS = {
  junk = "Junk",
  consumable = "Consumables",
  reagent = "Materials",
  gem = "Gems",
  gear = "Gear",
  quest = "Quest",
  container = "Bags",
  other = "Other",
}

Layout.CATEGORY_ORDER = CATEGORY_ORDER
Layout.CATEGORY_LABELS = CATEGORY_LABELS

local CLASS = {
  Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5,
  Projectile = 6, Tradegoods = 7, ItemEnhancement = 8, Recipe = 9, Quest = 12,
  Key = 13, Miscellaneous = 15, Glyph = 16,
}

local main, content, freeFs, moneyFs, emptyLabel
local sectionFrames = {}
local layoutBusy = false

local function SafeNum(v, fallback)
  return Slots.SafeNum(v, fallback)
end

local function SafeStr(v)
  if type(v) ~= "string" then
    return nil
  end
  if Slots.IsSecret(v) then
    return nil
  end
  return v
end

local function Profile()
  return Config.GetProfile()
end

local function Columns()
  local c = Profile().columns
  if type(c) == "number" and c >= 4 and c <= 16 then
    return c
  end
  return 8
end

local function CategoryEnabled(key)
  if key == "other" then
    return true
  end
  local cats = Profile().categories
  if not cats then
    return true
  end
  return cats[key] ~= false
end

local function IsCollapsed(key)
  local c = Profile().collapsed
  return c and c[key] == true
end

local function ResolveItemID(bag, slot, info)
  local id = SafeNum(info and info.itemID)
  if id then
    return id
  end
  if C_Container and C_Container.GetContainerItemID then
    local ok, res = pcall(C_Container.GetContainerItemID, bag, slot)
    if ok then
      id = SafeNum(res)
      if id then
        return id
      end
    end
  end
  local link = SafeStr(info and info.hyperlink)
  if not link and C_Container and C_Container.GetContainerItemLink then
    local ok, res = pcall(C_Container.GetContainerItemLink, bag, slot)
    if ok then
      link = SafeStr(res)
    end
  end
  if link then
    local fromLink = link:match("item:(%d+)")
    if fromLink then
      return tonumber(fromLink)
    end
  end
  return nil
end

local function InstantClass(itemID)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not fn or not itemID then
    return nil, nil, nil, nil, nil
  end
  local ok, a, b, c, d, e, f, g = pcall(fn, itemID)
  if not ok then
    return nil, nil, nil, nil, nil
  end
  return SafeNum(f), SafeNum(g), SafeStr(b), SafeStr(c), SafeStr(d)
end

local function MapClassID(classID, subClassID, quality)
  if type(classID) ~= "number" then
    return nil
  end
  local EC = Enum and Enum.ItemClass
  local function eq(enumVal, num)
    if EC and type(enumVal) == "number" and classID == enumVal then
      return true
    end
    return classID == num
  end
  if eq(EC and EC.Consumable, CLASS.Consumable) then
    return "consumable"
  end
  if eq(EC and EC.Reagent, CLASS.Reagent)
      or eq(EC and EC.Tradegoods, CLASS.Tradegoods)
      or eq(EC and EC.TradeGoods, CLASS.Tradegoods)
      or classID == CLASS.Recipe
      or classID == CLASS.ItemEnhancement
      or classID == CLASS.Glyph
  then
    return "reagent"
  end
  if eq(EC and EC.Gem, CLASS.Gem) then
    return "gem"
  end
  if eq(EC and EC.Armor, CLASS.Armor) or eq(EC and EC.Weapon, CLASS.Weapon) then
    return "gear"
  end
  if classID == CLASS.Projectile then
    return "other"
  end
  if eq(EC and EC.Questitem, CLASS.Quest) or eq(EC and EC.QuestItem, CLASS.Quest) then
    return "quest"
  end
  if eq(EC and EC.Container, CLASS.Container) then
    return "container"
  end
  if eq(EC and EC.Miscellaneous, CLASS.Miscellaneous) and SafeNum(subClassID) == 0 and quality == 0 then
    return "junk"
  end
  return nil
end

local function MapTypeString(itemType, itemSubType)
  local t = (itemType or ""):lower()
  local s = (itemSubType or ""):lower()
  local blob = t .. " " .. s
  if blob:find("consumable", 1, true) or blob:find("food", 1, true) or blob:find("potion", 1, true)
      or blob:find("spotřeb", 1, true) or blob:find("lektvar", 1, true)
  then
    return "consumable"
  end
  if blob:find("trade", 1, true) or blob:find("reagent", 1, true) or blob:find("materiál", 1, true)
      or blob:find("material", 1, true) or blob:find("cloth", 1, true) or blob:find("herb", 1, true)
      or blob:find("ore", 1, true) or blob:find("leather", 1, true)
  then
    return "reagent"
  end
  if blob:find("armor", 1, true) or blob:find("weapon", 1, true) or blob:find("zbroj", 1, true)
      or blob:find("zbraň", 1, true) or blob:find("ring", 1, true) or blob:find("trinket", 1, true)
  then
    return "gear"
  end
  if blob:find("quest", 1, true) or blob:find("úkol", 1, true) then
    return "quest"
  end
  if blob:find("gem", 1, true) or blob:find("drahokam", 1, true) then
    return "gem"
  end
  if blob:find("container", 1, true) or blob:find("bag", 1, true) or blob:find("batoh", 1, true) then
    return "container"
  end
  return nil
end

function Layout.ClassifyBagSlot(bag, slot)
  if not C_Container or not C_Container.GetContainerItemInfo then
    return "other", nil
  end
  local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
  if not ok or type(info) ~= "table" then
    return nil, nil
  end
  if not info.iconFileID and not info.itemID and not info.hyperlink then
    return nil, nil
  end
  local itemID = ResolveItemID(bag, slot, info)
  local rules = Profile().itemRules
  if itemID and type(rules) == "table" then
    local rule = rules[itemID] or rules[tostring(itemID)]
    if type(rule) == "string" and rule ~= "" then
      if rule == "weapon" or rule == "armor" then
        rule = "gear"
      end
      return rule, info
    end
  end
  local quality = SafeNum(info.quality)
  local classID, subClassID, itemType, itemSubType, equipLoc = InstantClass(itemID)
  local mapped = MapClassID(classID, subClassID, quality)
  if mapped then
    return mapped, info
  end
  mapped = MapTypeString(itemType, itemSubType)
  if mapped then
    return mapped, info
  end
  if type(equipLoc) == "string" and equipLoc ~= "" then
    local el = equipLoc:upper()
    if el == "INVTYPE_FINGER" or el == "INVTYPE_NECK" or el == "INVTYPE_TRINKET"
        or el == "INVTYPE_CLOAK" or el:find("WEAPON", 1, true)
    then
      return "gear", info
    end
  end
  if quality == 0 and not Slots.IsReagentBag(bag) then
    return "junk", info
  end
  if Slots.IsReagentBag(bag) then
    return "reagent", info
  end
  return "other", info
end

local function CollectBuckets()
  local buckets = {}
  for i = 1, #CATEGORY_ORDER do
    buckets[CATEGORY_ORDER[i]] = {}
  end
  local ranges = Slots.BagRanges()
  for i = 1, #ranges do
    local bag, n = ranges[i].bag, ranges[i].slots
    for slot = 1, n do
      if Slots.SlotOccupied(bag, slot) then
        local cat = Layout.ClassifyBagSlot(bag, slot)
        if not cat or not CategoryEnabled(cat) then
          cat = "other"
        end
        if cat == "weapon" or cat == "armor" then
          cat = "gear"
        end
        if not buckets[cat] then
          cat = "other"
        end
        buckets[cat][#buckets[cat] + 1] = { bag = bag, slot = slot }
      end
    end
  end
  return buckets
end

local function RightSideBarInset()
  local parentRight, parentLeft = 0, 0
  pcall(function()
    parentRight = UIParent:GetRight() or 0
    parentLeft = UIParent:GetLeft() or 0
  end)
  if type(parentRight) ~= "number" or Slots.IsSecret(parentRight) or parentRight <= 0 then
    return 60
  end
  local mid = (parentLeft + parentRight) * 0.5
  local leftmost = parentRight
  local names = {
    "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7",
    "VerticalMultiBarsContainer",
  }
  for i = 1, #names do
    local f = _G[names[i]]
    if f then
      local shown, l = false, nil
      pcall(function()
        shown = f:IsShown()
        l = f:GetLeft()
      end)
      if shown and type(l) == "number" and not Slots.IsSecret(l) and l > mid and l < leftmost then
        leftmost = l
      end
    end
  end
  local inset = parentRight - leftmost + 12
  if inset < 40 then
    inset = 40
  end
  if inset > 220 then
    inset = 220
  end
  return inset
end

local function ActionBarCeiling()
  local y = 40
  local bars = { "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "StanceBar", "PetActionBar" }
  for i = 1, #bars do
    local f = _G[bars[i]]
    if f then
      local shown, top = false, nil
      pcall(function()
        shown = f:IsShown()
        top = f:GetTop()
      end)
      if shown and type(top) == "number" and not Slots.IsSecret(top) and top > y then
        y = top
      end
    end
  end
  return y
end

local function PlaceMainDefault()
  if not main then
    return
  end
  local p = Profile()
  if p.userMoved and type(p.pos) == "table" and p.pos.point then
    main:ClearAllPoints()
    main:SetPoint(p.pos.point, UIParent, p.pos.relPoint or p.pos.point, p.pos.x or 0, p.pos.y or 0)
    return
  end
  main:ClearAllPoints()
  local ceiling = ActionBarCeiling() + 12
  local parentRight = 1280
  pcall(function()
    parentRight = UIParent:GetRight() or 1280
  end)
  if type(parentRight) ~= "number" or Slots.IsSecret(parentRight) or parentRight <= 0 then
    parentRight = 1280
  end
  main:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", parentRight - RightSideBarInset(), ceiling)
end

local function PersistPos()
  if not main then
    return
  end
  local p = Profile()
  p.userMoved = true
  local point, _, relPoint, x, y = main:GetPoint(1)
  p.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function UpdateMoney()
  local copper = 0
  if GetMoney then
    local ok, m = pcall(GetMoney)
    if ok then
      copper = SafeNum(m, 0) or 0
    end
  end
  if main and main.moneyFrame and MoneyFrame_Update then
    pcall(MoneyFrame_Update, main.moneyFrame:GetName(), copper)
  elseif moneyFs then
    moneyFs:SetText(string.format(
      "%dg %ds %dc",
      math.floor(copper / 10000),
      math.floor((copper % 10000) / 100),
      copper % 100
    ))
  end
end

local function UpdateFreeSpace()
  if not freeFs then
    return
  end
  local free, total = 0, 0
  local ranges = Slots.BagRanges()
  for i = 1, #ranges do
    local bag, n = ranges[i].bag, ranges[i].slots
    total = total + n
    for slot = 1, n do
      if not Slots.SlotOccupied(bag, slot) then
        free = free + 1
      end
    end
  end
  local used = total - free
  if free <= 4 and total > 0 then
    freeFs:SetTextColor(1, 0.45, 0.35)
  elseif free <= 12 and total > 0 then
    freeFs:SetTextColor(1, 0.82, 0.4)
  else
    freeFs:SetTextColor(0.75, 0.75, 0.75)
  end
  freeFs:SetText(string.format("Free %d  ·  %d/%d", free, used, total))
end

local function EnsureSection(key)
  local sf = sectionFrames[key]
  if sf then
    return sf
  end
  sf = CreateFrame("Frame", "BetterBackpackSection_" .. key, content)
  sf:SetSize(100, HEADER_H)
  local header = CreateFrame("Button", nil, sf)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetHeight(HEADER_H)
  header:RegisterForClicks("LeftButtonUp")
  local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("LEFT", 4, 0)
  title:SetJustifyH("LEFT")
  header.title = title
  header:SetScript("OnClick", function()
    local p = Profile()
    if type(p.collapsed) ~= "table" then
      p.collapsed = {}
    end
    p.collapsed[key] = not p.collapsed[key]
    Layout.Relayout()
  end)
  sf.header = header
  sectionFrames[key] = sf
  return sf
end

local function DoLayout()
  if not main or not content then
    return
  end
  if layoutBusy then
    return
  end
  layoutBusy = true
  local ok, err = pcall(function()
    local cols = Columns()
    local buckets = CollectBuckets()
    local used = {}
    local y = 0
    local maxW = cols * (SLOT + PAD) - PAD
    local any = false

    for i = 1, #CATEGORY_ORDER do
      local key = CATEGORY_ORDER[i]
      if CategoryEnabled(key) then
        local list = buckets[key] or {}
        if #list > 0 then
          any = true
          local sf = EnsureSection(key)
          sf:ClearAllPoints()
          sf:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
          sf:SetWidth(maxW)
          sf:Show()
          local collapsed = IsCollapsed(key)
          sf.header.title:SetText(string.format(
            "%s%s (%d)",
            collapsed and "[+] " or "[-] ",
            CATEGORY_LABELS[key] or key,
            #list
          ))
          y = y + HEADER_H + 2
          if not collapsed then
            local col, row = 0, 0
            for j = 1, #list do
              local bag, slot = list[j].bag, list[j].slot
              local btn = Slots.Acquire(bag, slot)
              used[btn] = true
              local x = col * (SLOT + PAD)
              local yy = y + row * (SLOT + PAD)
              Slots.Place(btn, content, x, yy, true)
              col = col + 1
              if col >= cols then
                col = 0
                row = row + 1
              end
            end
            local rows = math.ceil(#list / cols)
            y = y + rows * (SLOT + PAD) + 6
          end
          sf:SetHeight(HEADER_H)
        else
          if sectionFrames[key] then
            sectionFrames[key]:Hide()
          end
        end
      end
    end

    Slots.ParkUnused(used)

    if emptyLabel then
      if any then
        emptyLabel:Hide()
      else
        emptyLabel:SetText("Bags empty")
        emptyLabel:Show()
        y = math.max(y, 40)
      end
    end

    local width = maxW + INSET_X * 2
    local height = y + TOP_CHROME + BOT_CHROME + 8
    if height < 120 then
      height = 120
    end
    content:SetSize(maxW, math.max(y, 20))
    main:SetSize(width, height)
    UpdateFreeSpace()
    UpdateMoney()
  end)
  layoutBusy = false
  if not ok and BetterBackpack.RecordError then
    BetterBackpack.RecordError("layout", err)
  end
end

local function PaintSolidBg(frame)
  if not frame then
    return
  end
  pcall(function()
    if not frame.Bg then
      frame.Bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    end
    frame.Bg:ClearAllPoints()
    frame.Bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    frame.Bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    -- Forever: prefer WHITE8X8 + vertex (SetColorTexture / DialogBox backdrop often broken).
    frame.Bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.Bg:SetVertexColor(0.07, 0.07, 0.08, 0.97)
    frame.Bg:SetAlpha(1)
    frame.Bg:Show()
  end)
  pcall(function()
    if not frame.Border then
      frame.Border = frame:CreateTexture(nil, "BORDER")
    end
    frame.Border:ClearAllPoints()
    frame.Border:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.Border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.Border:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
    frame.Border:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    frame.Border:SetVertexColor(0.55, 0.5, 0.4, 0.9)
    frame.Border:SetAlpha(0.85)
  end)
end

local function KillPortrait(frame)
  local keys = {
    "PortraitContainer", "Portrait", "portrait", "PortraitFrame", "portraitFrame",
  }
  for i = 1, #keys do
    local p = frame[keys[i]]
    if p then
      pcall(function()
        p:SetAlpha(0)
        p:Hide()
        p:SetSize(1, 1)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", frame, "TOPLEFT", -4000, 0)
        if p.EnableMouse then
          p:EnableMouse(false)
        end
      end)
    end
  end
end

function Layout.EnsureMain()
  if main then
    PaintSolidBg(main)
    return main
  end

  local templates = {
    "ButtonFrameTemplate",
    "BasicFrameTemplateWithInset",
    "BasicFrameTemplate",
  }
  for i = 1, #templates do
    local ok, frame = pcall(function()
      return CreateFrame("Frame", "BetterBackpackFrame", UIParent, templates[i])
    end)
    if ok and frame then
      main = frame
      break
    end
  end
  if not main then
    main = CreateFrame("Frame", "BetterBackpackFrame", UIParent)
  end

  pcall(function()
    if ButtonFrameTemplate_HidePortrait then
      ButtonFrameTemplate_HidePortrait(main)
    end
  end)
  KillPortrait(main)
  -- Never rely on BackdropTemplate alone — Forever often yields broken/empty chrome.
  PaintSolidBg(main)

  main:SetFrameStrata("HIGH")
  main:SetFrameLevel(100)
  main:SetMovable(true)
  main:EnableMouse(true)
  main:RegisterForDrag("LeftButton")
  main:SetScript("OnDragStart", function(self)
    if InCombatLockdown and InCombatLockdown() then
      return
    end
    self:StartMoving()
  end)
  main:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    PersistPos()
  end)
  main:SetScript("OnShow", function(self)
    KillPortrait(self)
    PaintSolidBg(self)
  end)
  main:SetScript("OnHide", function()
    local OpenClose = BetterBackpack.Modules.OpenClose
    if OpenClose and OpenClose.NotifyHidden then
      OpenClose.NotifyHidden()
    end
  end)
  if UISpecialFrames then
    table.insert(UISpecialFrames, "BetterBackpackFrame")
  end

  if main.SetTitle then
    pcall(main.SetTitle, main, "BetterBackpack")
  end
  local title = main.TitleText or main.title
  if not title then
    title = main:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
  end
  title:SetText("BetterBackpack")
  main.title = title

  local close = main.CloseButton
  if not close then
    pcall(function()
      close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
    end)
  end
  if close then
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function()
      local OpenClose = BetterBackpack.Modules.OpenClose
      if OpenClose and OpenClose.CloseOurs then
        OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.35 })
      else
        main:Hide()
      end
    end)
  end

  local sortBtn
  pcall(function()
    sortBtn = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
  end)
  if not sortBtn then
    sortBtn = CreateFrame("Button", nil, main)
    sortBtn:SetSize(56, 20)
    local fs = sortBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetAllPoints()
    fs:SetText("Sort")
    sortBtn:SetFontString(fs)
  end
  sortBtn:SetSize(56, 20)
  if close then
    sortBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -4, -8)
  else
    sortBtn:SetPoint("TOPRIGHT", main, "TOPRIGHT", -28, -8)
  end
  sortBtn:SetText("Sort")
  sortBtn:SetScript("OnClick", function()
    local Tidy = BetterBackpack.Modules.Tidy
    if Tidy and Tidy.SortBags then
      Tidy.SortBags()
    end
  end)

  freeFs = main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  freeFs:SetPoint("BOTTOMLEFT", 14, 10)
  freeFs:SetJustifyH("LEFT")
  freeFs:SetText("Free —")

  local moneyFrame
  pcall(function()
    moneyFrame = CreateFrame("Frame", "BetterBackpackMoneyFrame", main, "SmallMoneyFrameTemplate")
  end)
  if moneyFrame then
    moneyFrame:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -8, 8)
    pcall(function()
      MoneyFrame_SetType(moneyFrame, "STATIC")
    end)
    main.moneyFrame = moneyFrame
  else
    moneyFs = main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    moneyFs:SetPoint("BOTTOMRIGHT", -14, 10)
  end

  content = CreateFrame("Frame", "BetterBackpackContent", main)
  content:EnableMouse(false)
  content:SetPoint("TOPLEFT", INSET_X, -TOP_CHROME)
  content:SetSize(100, 100)

  emptyLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  emptyLabel:SetPoint("TOPLEFT", 4, -4)
  emptyLabel:Hide()

  PlaceMainDefault()
  main:Hide()
  return main
end

function Layout.IsShown()
  return main and main:IsShown()
end

function Layout.Show()
  Layout.EnsureMain()
  if not main then
    return false
  end
  local p = Profile()
  if not p.enabled or p.safeMode then
    return false
  end
  -- Show chrome first so open never depends on layout succeeding.
  main:SetAlpha(1)
  if not p.userMoved then
    -- Safe on-screen anchor (avoids secret GetRight / off-screen BOTTOMRIGHT math).
    pcall(function()
      main:ClearAllPoints()
      main:SetPoint("CENTER", UIParent, "CENTER", 200, 40)
    end)
  else
    PlaceMainDefault()
  end
  if not main:GetWidth() or main:GetWidth() < 80 then
    main:SetSize(340, 200)
  end
  main:Show()
  if main.SetToplevel then
    main:SetToplevel(true)
  end
  main:Raise()
  DoLayout()
  -- After layout size change, re-assert visible + on-screen.
  main:SetAlpha(1)
  main:Show()
  main:Raise()
  if not p.userMoved then
    local left
    pcall(function()
      left = main:GetLeft()
    end)
    if type(left) ~= "number" or left < -100 or left > 5000 then
      pcall(function()
        main:ClearAllPoints()
        main:SetPoint("CENTER", UIParent, "CENTER", 200, 40)
      end)
    end
  end
  return main:IsShown() and true or false
end

function Layout.Hide()
  if main then
    main:Hide()
  end
end

function Layout.Relayout()
  if Layout.IsShown() then
    DoLayout()
  end
end

function Layout.Refresh()
  if InCombatLockdown and InCombatLockdown() then
    Layout.RefreshCooldowns()
    return
  end
  if BetterBackpack._combatFrozen then
    return
  end
  if BetterBackpack._sortSuppressRefresh then
    return
  end
  if Layout.IsShown() then
    DoLayout()
  end
end

function Layout.RefreshCooldowns()
  if not Layout.IsShown() then
    return
  end
  Slots.ForEach(function(btn)
    if btn and btn:GetAlpha() > 0.5 and btn._bbBag ~= nil then
      Slots.SyncCooldown(btn, btn._bbBag, btn._bbSlot)
      Slots.SyncVisual(btn, btn._bbBag, btn._bbSlot)
    end
  end)
end

function Layout.UpdateMoney()
  UpdateMoney()
end

function Layout.Raise()
  if main then
    main:SetAlpha(1)
    if main.SetToplevel then
      main:SetToplevel(true)
    end
    main:Raise()
  end
end

function Layout.ResetPosition()
  local p = Profile()
  p.userMoved = false
  p.pos = nil
  PlaceMainDefault()
end

function Layout.DiagnoseBags()
  local reb = Slots.ReagentBagIndex()
  local nSlots = Slots.NumSlotsForBag(reb)
  local filled = 0
  for slot = 1, nSlots do
    if Slots.SlotOccupied(reb, slot) then
      filled = filled + 1
    end
  end
  local ranges = Slots.BagRanges()
  local total, free = 0, 0
  local hasReb = false
  for i = 1, #ranges do
    total = total + ranges[i].slots
    if ranges[i].reagent then
      hasReb = true
    end
    for s = 1, ranges[i].slots do
      if not Slots.SlotOccupied(ranges[i].bag, s) then
        free = free + 1
      end
    end
  end
  return {
    reagentSlots = nSlots,
    reagentFilled = filled,
    reagentInRanges = hasReb,
    free = free,
    total = total,
  }
end

function Layout.RunSelfTest()
  local pass, fail, notes = 0, 0, {}
  local function ok(cond, msg)
    if cond then
      pass = pass + 1
    else
      fail = fail + 1
      notes[#notes + 1] = msg
    end
  end
  if not (InCombatLockdown and InCombatLockdown()) then
    pcall(Slots.PreCreate)
  end
  local secureN, attrN = Slots.CountSecure()
  ok(Config.VERSION ~= nil, "no version")
  ok(secureN >= 36, "secure slots < 36 (got " .. tostring(secureN) .. ")")
  ok(attrN >= 36 or (InCombatLockdown and InCombatLockdown()), "attrs < 36 (got " .. tostring(attrN) .. ")")
  if InCombatLockdown and InCombatLockdown() then
    local shownSecureMouse = 0
    Slots.ForEach(function(btn)
      if btn and btn._bbSecure and btn:IsShown() and btn:GetAlpha() > 0.5 and btn:IsMouseEnabled() then
        shownSecureMouse = shownSecureMouse + 1
      end
    end)
    if Layout.IsShown() then
      ok(shownSecureMouse > 0, "combat UI shown but no mouse-enabled secure slot")
    else
      ok(true, "combat UI not shown")
      notes[#notes + 1] = "hint: open bags in combat then re-run"
    end
  else
    ok(true, "ooc combat mouse check skipped")
  end
  local combat = (InCombatLockdown and InCombatLockdown()) and 1 or 0
  local card = string.format(
    "BETTERBACKPACK_SELFTEST ver=%s pass=%d fail=%d combat=%d secure=%d attrs=%d shown=%s",
    tostring(Config.VERSION),
    pass,
    fail,
    combat,
    secureN,
    attrN,
    tostring(Layout.IsShown())
  )
  local db = Config.EnsureDB()
  db.lastSelftest = {
    card = card,
    pass = pass,
    fail = fail,
    secure = secureN,
    attrs = attrN,
    combat = combat,
    notes = notes,
    t = time and time() or 0,
  }
  return fail == 0, card, notes
end
