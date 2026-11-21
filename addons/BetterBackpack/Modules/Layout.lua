--[[
  BetterBackpack.Layout — category lanes + solid chrome (0.1.3).
  Forever: never SetToplevel (ADDON_ACTION_BLOCKED). Plain Frame + WHITE8X8 Bg.
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
  if blob:find("consumable", 1, true) or blob:find("food", 1, true) or blob:find("potion", 1, true) then
    return "consumable"
  end
  if blob:find("trade", 1, true) or blob:find("reagent", 1, true) or blob:find("cloth", 1, true)
      or blob:find("herb", 1, true) or blob:find("ore", 1, true) or blob:find("leather", 1, true)
  then
    return "reagent"
  end
  if blob:find("armor", 1, true) or blob:find("weapon", 1, true) or blob:find("ring", 1, true) then
    return "gear"
  end
  if blob:find("quest", 1, true) then
    return "quest"
  end
  if blob:find("gem", 1, true) then
    return "gem"
  end
  if blob:find("container", 1, true) or blob:find("bag", 1, true) then
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

local function PersistPos()
  if not main then
    return
  end
  local p = Profile()
  p.userMoved = true
  local point, _, relPoint, x, y = main:GetPoint(1)
  p.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

local function PlaceOnScreen()
  if not main then
    return
  end
  local p = Profile()
  if p.userMoved and type(p.pos) == "table" and p.pos.point then
    pcall(function()
      main:ClearAllPoints()
      main:SetPoint(p.pos.point, UIParent, p.pos.relPoint or p.pos.point, p.pos.x or 0, p.pos.y or 0)
    end)
    return
  end
  pcall(function()
    main:ClearAllPoints()
    main:SetPoint("CENTER", UIParent, "CENTER", 180, 60)
  end)
end

local function UpdateMoney()
  local copper = 0
  if GetMoney then
    local ok, m = pcall(GetMoney)
    if ok then
      copper = SafeNum(m, 0) or 0
    end
  end
  if moneyFs then
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
  freeFs:SetTextColor(0.8, 0.8, 0.8)
  freeFs:SetText(string.format("Free %d  ·  %d/%d", free, total - free, total))
end

local function EnsureSection(key)
  local sf = sectionFrames[key]
  if sf then
    return sf
  end
  sf = CreateFrame("Frame", nil, content)
  sf:SetSize(100, HEADER_H)
  local header = CreateFrame("Button", nil, sf)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetHeight(HEADER_H)
  header:RegisterForClicks("LeftButtonUp")
  local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("LEFT", 4, 0)
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
              Slots.Place(btn, content, col * (SLOT + PAD), y + row * (SLOT + PAD), true)
              col = col + 1
              if col >= cols then
                col = 0
                row = row + 1
              end
            end
            y = y + math.ceil(#list / cols) * (SLOT + PAD) + 6
          end
          sf:SetHeight(HEADER_H)
        elseif sectionFrames[key] then
          sectionFrames[key]:Hide()
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

    local width = math.max(maxW + INSET_X * 2, 320)
    local height = math.max(y + TOP_CHROME + BOT_CHROME + 8, 160)
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
      frame.Bg = frame:CreateTexture(nil, "BACKGROUND")
    end
    frame.Bg:ClearAllPoints()
    frame.Bg:SetAllPoints(frame)
    frame.Bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.Bg:SetVertexColor(0.08, 0.08, 0.09, 0.98)
    frame.Bg:SetAlpha(1)
    frame.Bg:Show()
  end)
  pcall(function()
    if not frame.Edge then
      frame.Edge = frame:CreateTexture(nil, "BORDER")
    end
    frame.Edge:ClearAllPoints()
    frame.Edge:SetPoint("TOPLEFT", -1, 1)
    frame.Edge:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.Edge:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.Edge:SetVertexColor(0.45, 0.4, 0.3, 0.7)
  end)
end

function Layout.EnsureMain()
  if main then
    PaintSolidBg(main)
    return main
  end

  -- Plain Frame only — ButtonFrameTemplate/Backdrop caused broken chrome + SetToplevel BLOCKED.
  main = CreateFrame("Frame", "BetterBackpackFrame", UIParent)
  main:SetSize(360, 280)
  PaintSolidBg(main)
  main:SetFrameStrata("DIALOG")
  main:SetFrameLevel(200)
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

  local title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("BetterBackpack")
  main.title = title

  local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
  if not close then
    close = CreateFrame("Button", nil, main)
    close:SetSize(24, 24)
    close:SetText("X")
  end
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    local OpenClose = BetterBackpack.Modules.OpenClose
    if OpenClose and OpenClose.CloseOurs then
      OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.3 })
    else
      main:Hide()
    end
  end)

  local sortBtn = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
  if sortBtn then
    sortBtn:SetSize(56, 20)
    sortBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -4, -8)
    sortBtn:SetText("Sort")
    sortBtn:SetScript("OnClick", function()
      local Tidy = BetterBackpack.Modules.Tidy
      if Tidy and Tidy.SortBags then
        Tidy.SortBags()
      end
    end)
  end

  freeFs = main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  freeFs:SetPoint("BOTTOMLEFT", 14, 10)
  freeFs:SetText("Free —")

  moneyFs = main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  moneyFs:SetPoint("BOTTOMRIGHT", -14, 10)

  content = CreateFrame("Frame", nil, main)
  content:EnableMouse(false)
  content:SetPoint("TOPLEFT", INSET_X, -TOP_CHROME)
  content:SetSize(100, 100)

  emptyLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  emptyLabel:SetPoint("TOPLEFT", 4, -4)
  emptyLabel:Hide()

  PlaceOnScreen()
  main:Hide()
  return main
end

function Layout.IsShown()
  return main and main:IsShown() and true or false
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

  main:SetParent(UIParent)
  main:SetFrameStrata("DIALOG")
  main:SetFrameLevel(200)
  main:SetAlpha(1)
  main:SetScale(1)
  if not main:GetWidth() or main:GetWidth() < 100 then
    main:SetSize(360, 280)
  end
  PlaceOnScreen()
  PaintSolidBg(main)
  main:Show()
  pcall(function()
    main:Raise()
  end)
  DoLayout()
  -- Re-assert after layout (size change).
  main:SetAlpha(1)
  main:Show()
  PlaceOnScreen()
  pcall(function()
    main:Raise()
  end)
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
  if BetterBackpack._combatFrozen or BetterBackpack._sortSuppressRefresh then
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
  if not main then
    return
  end
  -- Forever: SetToplevel is ADDON_ACTION_BLOCKED — use strata/level only.
  pcall(function()
    main:SetFrameStrata("DIALOG")
    main:SetFrameLevel(200)
    main:Raise()
  end)
end

function Layout.ResetPosition()
  local p = Profile()
  p.userMoved = false
  p.pos = nil
  PlaceOnScreen()
end

function Layout.DebugState()
  if not main then
    return { exists = false }
  end
  local left, bottom, w, h, strata
  pcall(function()
    left = main:GetLeft()
    bottom = main:GetBottom()
    w = main:GetWidth()
    h = main:GetHeight()
    strata = main:GetFrameStrata()
  end)
  return {
    exists = true,
    shown = main:IsShown() and true or false,
    alpha = main:GetAlpha(),
    left = left,
    bottom = bottom,
    w = w,
    h = h,
    strata = strata,
    parent = main:GetParent() and main:GetParent():GetName() or "?",
  }
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
  ok(secureN >= 36, "secure slots < 36")
  ok(attrN >= 36 or (InCombatLockdown and InCombatLockdown()), "attrs < 36")
  local d = Layout.DebugState()
  ok(d.exists, "main frame missing")
  local combat = (InCombatLockdown and InCombatLockdown()) and 1 or 0
  local card = string.format(
    "BETTERBACKPACK_SELFTEST ver=%s pass=%d fail=%d combat=%d secure=%d attrs=%d shown=%s w=%s h=%s strata=%s",
    tostring(Config.VERSION),
    pass,
    fail,
    combat,
    secureN,
    attrN,
    tostring(d.shown),
    tostring(d.w),
    tostring(d.h),
    tostring(d.strata)
  )
  local db = Config.EnsureDB()
  db.lastSelftest = {
    card = card,
    pass = pass,
    fail = fail,
    debug = d,
    t = time and time() or 0,
  }
  return fail == 0, card, notes
end
