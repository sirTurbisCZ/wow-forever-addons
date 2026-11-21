--[[
  BetterBackpack.Layout — category lanes + CombinedBags chrome (0.2.9).
  Forever: never SetToplevel (ADDON_ACTION_BLOCKED).
  Slots parented to main (not content) so icons paint above Inset; park host never Hide.
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local Layout = {}
BetterBackpack.Modules.Layout = Layout

local Config = BetterBackpack.Config
local Slots = BetterBackpack.Modules.Slots

local SLOT = 37
local PAD = 4
local HEADER_H = 18
local HEADER_PAD = 2
local SECTION_GAP = 4 -- even gap after every section (incl. last trimmed)
local INSET_X = 12
local TOP_CHROME = 56 -- title + CombinedBags-style sort row (AutoSort at y=-34)
local BOT_CHROME = 26 -- free-slots + money strip
local FOOTER_H = 20
local SORT_BTN_W, SORT_BTN_H = 28, 26 -- BagItemAutoSortButton
local GEAR_BTN = 26 -- visible gear, same ballpark as broom

local CATEGORY_ORDER = {
  "junk", "consumable", "reagent", "gem", "gear", "quest", "keys", "container", "other",
}

local CATEGORY_LABELS = {
  junk = "Junk",
  consumable = "Consumables",
  reagent = "Materials",
  gem = "Gems",
  gear = "Gear",
  quest = "Quest",
  keys = "Keys",
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

local main, content, freeFs, moneyFs, emptyLabel, sortBtn, settingsBtn
local sectionFrames = {}
local layoutBusy = false
local bagHoverHooked = false
local bagBarHoverHooked = {}
local focusBagID = nil
-- Forward decl: DoLayout runs before the definition body below (Lua 5.1 upvalue).
local EnsureTitleChrome
local SetBagMatchHighlight
local ClearBagMatchGlows

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
  if eq(EC and EC.Key, CLASS.Key) or classID == CLASS.Key then
    return "keys"
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
  if Slots.IsKeyringBag and Slots.IsKeyringBag(bag) then
    return "keys", info
  end
  if classID == CLASS.Key then
    return "keys", info
  end
  if quality == 0 and not Slots.IsReagentBag(bag) and not (Slots.IsKeyringBag and Slots.IsKeyringBag(bag)) then
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
        -- Disabled category → Other (items always visible somewhere).
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
  if main and main.moneyFrame and MoneyFrame_Update then
    local name
    pcall(function()
      name = main.moneyFrame:GetName()
    end)
    if name then
      pcall(MoneyFrame_Update, name, copper)
      return
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

-- Classic used/total N/M, colored by fill %.
local function UpdateFreeSpace()
  freeFs = (main and main.freeFs) or freeFs
  if not freeFs then
    return
  end
  local free, total = 0, 0
  local okRanges, ranges = pcall(function()
    return Slots.BagRanges()
  end)
  if okRanges and type(ranges) == "table" then
    for i = 1, #ranges do
      local bag, n = ranges[i].bag, ranges[i].slots
      n = tonumber(n) or 0
      total = total + n
      for slot = 1, n do
        if not Slots.SlotOccupied(bag, slot) then
          free = free + 1
        end
      end
    end
  end
  local used = total - free
  if used < 0 then
    used = 0
  end
  pcall(function()
    freeFs:Show()
    freeFs:ClearAllPoints()
    local footer = main.footer or freeFs:GetParent()
    freeFs:SetPoint("LEFT", footer, "LEFT", 4, 0)
    freeFs:SetPoint("TOP", footer, "TOP", 0, 0)
    freeFs:SetPoint("BOTTOM", footer, "BOTTOM", 0, 0)
    if freeFs.SetFontObject and NumberFontNormalSmall then
      freeFs:SetFontObject(NumberFontNormalSmall)
    end
    freeFs:SetJustifyH("LEFT")
    freeFs:SetJustifyV("MIDDLE")
    freeFs:SetDrawLayer("OVERLAY", 7)
    freeFs:SetText(string.format("%d/%d", used, total))
    -- ≤50% green, ≤75% yellow, <100% orange, 100% red
    local ratio = (total > 0) and (used / total) or 0
    if ratio <= 0.50 then
      freeFs:SetTextColor(0.25, 0.85, 0.35)
    elseif ratio <= 0.75 then
      freeFs:SetTextColor(0.95, 0.85, 0.20)
    elseif ratio < 1 then
      freeFs:SetTextColor(1.0, 0.55, 0.15)
    else
      freeFs:SetTextColor(0.95, 0.25, 0.20)
    end
  end)
end

local function BagsMatchForHighlight(a, b)
  if a == nil or b == nil then
    return false
  end
  if Slots.IsReagentBag(a) and Slots.IsReagentBag(b) then
    return true
  end
  local na, nb = SafeNum(a, nil), SafeNum(b, nil)
  return na ~= nil and nb ~= nil and na == nb
end

local function EnsureBagIndicator(btn)
  if not btn then
    return nil
  end
  local ind = btn.BagIndicator
  if not ind then
    ind = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    btn.BagIndicator = ind
  end
  pcall(function()
    local ok = pcall(ind.SetAtlas, ind, "bags-glow-white", true)
    if not ok then
      ind:SetColorTexture(0.35, 0.75, 1, 0.45)
    end
    if ind.SetBlendMode then
      ind:SetBlendMode("ADD")
    end
    ind:ClearAllPoints()
    ind:SetAllPoints(btn)
  end)
  return ind
end

local function ShowBagIndicator(ind, show)
  if not ind then
    return
  end
  pcall(function()
    if ind.SetShown then
      ind:SetShown(show and true or false)
    elseif show then
      ind:Show()
    else
      ind:Hide()
    end
  end)
end

SetBagMatchHighlight = function(bagID, highlight)
  pcall(function()
    Slots.ForEach(function(btn)
      if not btn or (btn:GetAlpha() or 0) < 0.5 then
        ShowBagIndicator(btn and btn.BagIndicator, false)
        return
      end
      local show = highlight and BagsMatchForHighlight(btn._bbBag, bagID)
      local ind = EnsureBagIndicator(btn)
      ShowBagIndicator(ind, show)
    end)
  end)
end

ClearBagMatchGlows = function()
  pcall(function()
    Slots.ForEach(function(btn)
      if btn and btn.BagIndicator then
        ShowBagIndicator(btn.BagIndicator, false)
      end
    end)
  end)
end

function Layout.SetBagFocus(bagID)
  if type(bagID) == "number" then
    focusBagID = bagID
  else
    focusBagID = nil
  end
  if not Layout.IsShown() then
    return
  end
  if focusBagID ~= nil then
    SetBagMatchHighlight(focusBagID, true)
  else
    ClearBagMatchGlows()
  end
end

function Layout.ClearBagFocus()
  focusBagID = nil
  ClearBagMatchGlows()
end

function Layout.GetBagFocus()
  return focusBagID
end

local function ResolveBagBarBagID(btn, forcedBag)
  if forcedBag ~= nil then
    return forcedBag
  end
  if not btn then
    return nil
  end
  local bagID
  pcall(function()
    if btn.GetBagID then
      bagID = btn:GetBagID()
    elseif btn.bagID ~= nil then
      bagID = btn.bagID
    elseif btn.id ~= nil then
      bagID = btn.id
    end
  end)
  return bagID
end

local function HookOneBagBarButton(btn, forcedBag)
  if not btn or bagBarHoverHooked[btn] then
    return
  end
  local canEnter = false
  pcall(function()
    canEnter = btn.HasScript and btn:HasScript("OnEnter")
  end)
  if not canEnter then
    local ot
    pcall(function()
      ot = btn.GetObjectType and btn:GetObjectType()
    end)
    if ot ~= "Button" and ot ~= "CheckButton" and ot ~= "Frame" then
      return
    end
  end
  bagBarHoverHooked[btn] = true
  pcall(function()
    btn:HookScript("OnEnter", function(self)
      if not Layout.IsShown() then
        return
      end
      local bagID = ResolveBagBarBagID(self, forcedBag)
      if bagID ~= nil then
        SetBagMatchHighlight(bagID, true)
      end
    end)
  end)
  pcall(function()
    btn:HookScript("OnLeave", function()
      if focusBagID ~= nil and Layout.IsShown() then
        SetBagMatchHighlight(focusBagID, true)
      else
        ClearBagMatchGlows()
      end
    end)
  end)
end

local function HookBagBarButtons()
  local reb = Slots.ReagentBagIndex and Slots.ReagentBagIndex()
  HookOneBagBarButton(_G.CharacterReagentBag0Slot, reb)
  HookOneBagBarButton(_G.ReagentBagSlot, reb)
  HookOneBagBarButton(_G.MainMenuBarBagButton5, reb)
  HookOneBagBarButton(_G.MainMenuBarBackpackButton, 0)
  for i = 0, 3 do
    HookOneBagBarButton(_G["CharacterBag" .. i .. "Slot"])
    HookOneBagBarButton(_G["MainMenuBarBagButton" .. (i + 1)])
  end
  for _, rootName in ipairs({ "BagsBar", "MainMenuBarBagButtons", "MicroButtonAndBagsBar" }) do
    local root = _G[rootName]
    if root and root.GetChildren then
      local kids = { root:GetChildren() }
      for i = 1, #kids do
        HookOneBagBarButton(kids[i])
      end
    end
  end
  local combined = ContainerFrameCombinedBags
  if combined then
    if combined.PortraitButton then
      HookOneBagBarButton(combined.PortraitButton, 0)
    end
    local list = combined.BagSlots or combined.bagButtons or combined.Bags
    if type(list) == "table" then
      for _, slotBtn in pairs(list) do
        HookOneBagBarButton(slotBtn)
      end
    end
  end
end

local function InstallBagHoverHighlight()
  HookBagBarButtons()
  if bagHoverHooked then
    return
  end
  bagHoverHooked = true
  local combined = ContainerFrameCombinedBags
  if combined and combined.SetItemsMatchingBagHighlighted then
    pcall(function()
      hooksecurefunc(combined, "SetItemsMatchingBagHighlighted", function(_, bagID, highlight)
        if not Layout.IsShown() then
          return
        end
        if highlight then
          SetBagMatchHighlight(bagID, true)
        else
          ClearBagMatchGlows()
        end
      end)
    end)
  end
  if combined and combined.OnBagSlotLeave then
    pcall(function()
      hooksecurefunc(combined, "OnBagSlotLeave", function()
        ClearBagMatchGlows()
      end)
    end)
  end
  if EventRegistry and EventRegistry.RegisterCallback then
    pcall(function()
      local function slotOf(a, b)
        if type(b) == "table" and (b.GetBagID or b.bagID ~= nil) then
          return b
        end
        if type(a) == "table" and (a.GetBagID or a.bagID ~= nil) then
          return a
        end
      end
      EventRegistry:RegisterCallback("BagSlot.OnEnter", function(a, b)
        if not Layout.IsShown() then
          return
        end
        local slot = slotOf(a, b)
        local bagID = ResolveBagBarBagID(slot)
        if bagID == nil and slot then
          local n = ""
          pcall(function()
            n = slot.GetName and slot:GetName() or ""
          end)
          if type(n) == "string" and n:lower():find("reagent", 1, true) then
            bagID = Slots.ReagentBagIndex and Slots.ReagentBagIndex()
          end
        end
        if bagID ~= nil then
          SetBagMatchHighlight(bagID, true)
        end
      end)
      EventRegistry:RegisterCallback("BagSlot.OnLeave", function()
        ClearBagMatchGlows()
      end)
    end)
  end
end

local function EnsureSection(key)
  local sf = sectionFrames[key]
  if sf then
    return sf
  end
  sf = CreateFrame("Frame", nil, content)
  sf:SetSize(100, HEADER_H)
  sf:SetFrameLevel((content:GetFrameLevel() or 1) + 5)
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
          y = y + HEADER_H + HEADER_PAD
          if not collapsed then
            local col, row = 0, 0
            local rows = math.ceil(#list / cols)
            -- Parent to main (absolute), not content — content sat under Inset.Bg.
            local parentFrame = main or content
            for j = 1, #list do
              local bag, slot = list[j].bag, list[j].slot
              local btn = Slots.Acquire(bag, slot)
              if btn then
                used[btn] = true
                local px = INSET_X + col * (SLOT + PAD)
                local py = TOP_CHROME + y + row * (SLOT + PAD)
                Slots.Place(btn, parentFrame, px, py, true)
              end
              col = col + 1
              if col >= cols then
                col = 0
                row = row + 1
              end
            end
            y = y + rows * (SLOT + PAD)
          end
          -- Even gap after every section (trimmed once at end).
          y = y + SECTION_GAP
          sf:SetHeight(HEADER_H)
        elseif sectionFrames[key] then
          sectionFrames[key]:Hide()
        end
      elseif sectionFrames[key] then
        sectionFrames[key]:Hide()
      end
    end

    Slots.ParkUnused(used)

    if emptyLabel then
      if any then
        emptyLabel:Hide()
      else
        emptyLabel:SetText("Bags empty")
        emptyLabel:Show()
        y = math.max(y, 36)
      end
    end

    -- Drop trailing section gap so footer sits under last row (no empty black).
    if y >= SECTION_GAP then
      y = y - SECTION_GAP
    end
    local contentH = math.max(y, 1)
    local width = math.max(maxW + INSET_X * 2, 320)
    -- Hug content: no min-180, no +8 fluff.
    local height = TOP_CHROME + contentH + BOT_CHROME
    content:ClearAllPoints()
    -- Always from main (not Inset) — Inset stretch left empty black below Other.
    content:SetPoint("TOPLEFT", main, "TOPLEFT", INSET_X, -TOP_CHROME)
    content:SetSize(maxW, contentH)
    content:Show()
    -- Must sit above ButtonFrameTemplate Inset.Bg or lanes look empty (counts only).
    local mainLvl = main:GetFrameLevel() or 200
    pcall(function()
      if main.Inset then
        main.Inset:SetFrameLevel(math.max(1, mainLvl + 1))
        main.Inset:EnableMouse(false)
      end
    end)
    content:SetFrameLevel(mainLvl + 40)
    main:SetSize(width, height)
    if main.footer then
      main.footer:ClearAllPoints()
      main.footer:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 10, 6)
      main.footer:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -10, 6)
      main.footer:SetFrameLevel(mainLvl + 5)
    end
    if main.moneyFrame then
      main.moneyFrame:ClearAllPoints()
      main.moneyFrame:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -4, 6)
      pcall(function()
        main.moneyFrame:SetFrameLevel(mainLvl + 6)
      end)
    end
    -- Shrink Inset so its Bg does not paint empty under content.
    pcall(function()
      if main.Inset then
        main.Inset:ClearAllPoints()
        main.Inset:SetPoint("TOPLEFT", main, "TOPLEFT", 4, -(TOP_CHROME - 6))
        main.Inset:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -4, BOT_CHROME - 4)
      end
    end)
    EnsureTitleChrome(main)
    UpdateFreeSpace()
    UpdateMoney()
    if focusBagID ~= nil then
      SetBagMatchHighlight(focusBagID, true)
    end
  end)
  layoutBusy = false
  if not ok and BetterBackpack.RecordError then
    BetterBackpack.RecordError("layout", err)
  end
end

local function IsSecret(v)
  return Slots.IsSecret and Slots.IsSecret(v)
end

local function SafeAtlas(tex)
  if not tex or not tex.GetAtlas then
    return nil
  end
  local ok, a = pcall(tex.GetAtlas, tex)
  if ok and type(a) == "string" and a ~= "" and not IsSecret(a) then
    return a
  end
  return nil
end

local function SafeTexture(tex)
  if not tex or not tex.GetTexture then
    return nil
  end
  local ok, t = pcall(tex.GetTexture, tex)
  if ok and t ~= nil and not IsSecret(t) then
    return t
  end
  return nil
end

local function CopyTex(dst, src)
  if not dst or not src then
    return false
  end
  local atlas = SafeAtlas(src)
  if atlas then
    pcall(dst.SetAtlas, dst, atlas)
    return true
  end
  local path = SafeTexture(src)
  if path then
    pcall(dst.SetTexture, dst, path)
    pcall(function()
      local l, r, t, b = src:GetTexCoord()
      if type(l) == "number" then
        dst:SetTexCoord(l, r, t, b)
      end
    end)
    return true
  end
  return false
end

local function CombinedBagTitle()
  if type(COMBINED_BAG_TITLE) == "string" and COMBINED_BAG_TITLE ~= "" and not IsSecret(COMBINED_BAG_TITLE) then
    return COMBINED_BAG_TITLE
  end
  local src = ContainerFrameCombinedBags
  if src then
    local t = src.TitleText or (src.TitleContainer and src.TitleContainer.TitleText)
    if t and t.GetText then
      local ok, s = pcall(t.GetText, t)
      if ok and type(s) == "string" and s ~= "" and not IsSecret(s) then
        return s
      end
    end
  end
  return "BetterBackpack"
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

local function ApplyPanelBackgroundColor(frame)
  pcall(function()
    if not frame.Bg then
      frame.Bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
      frame.Bg:SetPoint("TOPLEFT", 6, -21)
      frame.Bg:SetPoint("BOTTOMRIGHT", -6, 2)
    end
    local r, g, b, a = 0.058, 0.058, 0.058, 1
    if PANEL_BACKGROUND_COLOR and type(PANEL_BACKGROUND_COLOR.r) == "number" then
      local c = PANEL_BACKGROUND_COLOR
      r, g, b, a = c.r, c.g, c.b, c.a or 1
    end
    if frame.Bg.SetColorTexture then
      frame.Bg:SetColorTexture(r, g, b, a)
    else
      frame.Bg:SetTexture("Interface\\Buttons\\WHITE8X8")
      frame.Bg:SetVertexColor(r, g, b, a)
    end
    frame.Bg:SetAlpha(1)
    frame.Bg:Show()
    if frame.Inset and frame.Inset.Bg then
      if frame.Inset.Bg.SetColorTexture then
        frame.Inset.Bg:SetColorTexture(r, g, b, math.min(a, 0.92))
      else
        frame.Inset.Bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        frame.Inset.Bg:SetVertexColor(r, g, b, math.min(a, 0.92))
      end
      frame.Inset.Bg:SetAlpha(1)
    end
  end)
end

--[[ Match classic CombinedBags chrome (NineSlice kit + solid fill — never copy stashed alpha). ]]
local function ApplyCombinedBagsChrome(frame)
  if not frame then
    return
  end
  pcall(function()
    local src = ContainerFrameCombinedBags
    if src and src.NineSlice and NineSliceUtil then
      local kit
      if src.NineSlice.GetFrameLayoutTextureKit then
        kit = src.NineSlice:GetFrameLayoutTextureKit()
      end
      if type(kit) == "string" and not IsSecret(kit) then
        if not frame.NineSlice then
          frame.NineSlice = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
          frame.NineSlice:SetAllPoints()
        end
        NineSliceUtil.ApplyLayoutByName(frame.NineSlice, "UniqueCornersLayout", kit)
        frame.NineSlice:SetAlpha(1)
        frame.NineSlice:Show()
      end
    end
  end)
  ApplyPanelBackgroundColor(frame)
  pcall(function()
    local src = ContainerFrameCombinedBags
    if src and src.TopTileStreaks then
      if not frame.TopTileStreaks then
        frame.TopTileStreaks = frame:CreateTexture(nil, "ARTWORK", nil, -7)
        frame.TopTileStreaks:SetPoint("TOPLEFT", 6, -21)
        frame.TopTileStreaks:SetPoint("TOPRIGHT", -6, -21)
        frame.TopTileStreaks:SetHeight(40)
      end
      CopyTex(frame.TopTileStreaks, src.TopTileStreaks)
      frame.TopTileStreaks:Show()
      frame.TopTileStreaks:SetAlpha(1)
    end
  end)
  -- Force solid fill even if CombinedBags Bg was alpha-0 when copied.
  pcall(function()
    if frame.Bg then
      local r, g, b, a = 0.058, 0.058, 0.058, 0.97
      if PANEL_BACKGROUND_COLOR and type(PANEL_BACKGROUND_COLOR.r) == "number" then
        local c = PANEL_BACKGROUND_COLOR
        r, g, b, a = c.r, c.g, c.b, c.a or 0.97
      end
      if frame.Bg.SetColorTexture then
        frame.Bg:SetColorTexture(r, g, b, a)
      else
        frame.Bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        frame.Bg:SetVertexColor(r, g, b, a)
      end
      frame.Bg:SetAlpha(1)
      frame.Bg:Show()
    end
  end)
end

local function CreateBagPanel()
  -- Named frame persists across failed EnsureMain — always reuse, never double-create.
  local frame = _G.BetterBackpackFrame
  if not frame then
    local templates = {
      "ButtonFrameTemplate",
      "BasicFrameTemplateWithInset",
      "BasicFrameTemplate",
    }
    for i = 1, #templates do
      local ok, f = pcall(function()
        return CreateFrame("Frame", "BetterBackpackFrame", UIParent, templates[i])
      end)
      if ok and f then
        frame = f
        break
      end
    end
  end
  if not frame then
    frame = CreateFrame("Frame", "BetterBackpackFrame", UIParent)
  end
  frame:SetParent(UIParent)
  pcall(function()
    if ButtonFrameTemplate_HidePortrait then
      ButtonFrameTemplate_HidePortrait(frame)
    end
  end)
  KillPortrait(frame)
  ApplyCombinedBagsChrome(frame)
  return frame
end

local function DestroyHalfBuilt()
  if main then
    pcall(function()
      main:Hide()
      main:SetParent(nil)
    end)
  end
  main, content, freeFs, moneyFs, emptyLabel, sortBtn = nil, nil, nil, nil, nil, nil
  sectionFrames = {}
  pcall(function()
    local old = _G.BetterBackpackFrame
    if old and old ~= main then
      old:Hide()
      old:SetParent(nil)
    end
  end)
end

local CHROME_VER = 8

local function ClearLegacyTextChrome(btn)
  if not btn then
    return
  end
  if btn._bbBg then
    btn._bbBg:Hide()
  end
  if btn._bbLabel then
    btn._bbLabel:SetText("")
    btn._bbLabel:Hide()
  end
end

-- BagItemAutoSortButton clone (Forever CombinedBags).
local function StyleNativeSortButton(btn)
  ClearLegacyTextChrome(btn)
  btn:SetSize(SORT_BTN_W, SORT_BTN_H)
  if not btn._bbSortStyled then
    pcall(function()
      local nt = btn:CreateTexture(nil, "ARTWORK")
      nt:SetAllPoints()
      if nt.SetAtlas then
        nt:SetAtlas("bags-button-autosort-up", true)
      end
      btn:SetNormalTexture(nt)
      btn._bbSortNormal = nt
    end)
    pcall(function()
      local pt = btn:CreateTexture(nil, "ARTWORK")
      pt:SetAllPoints()
      if pt.SetAtlas then
        pt:SetAtlas("bags-button-autosort-down", true)
      end
      btn:SetPushedTexture(pt)
    end)
    pcall(function()
      btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      local ht = btn:GetHighlightTexture()
      if ht then
        ht:ClearAllPoints()
        ht:SetSize(24, 23)
        ht:SetPoint("CENTER", 0, 0)
      end
    end)
    btn._bbSortStyled = true
  end
  btn:EnableMouse(true)
  btn:Show()
end

-- Visible options gear left of broom (file texture — atlases were invisible on Forever).
local function StyleNativeGearButton(btn)
  ClearLegacyTextChrome(btn)
  btn:SetSize(GEAR_BTN, GEAR_BTN)
  -- Always rebuild icon so CHROME_VER bumps repaint a blank atlas from 0.2.6.
  local icon = btn._bbGearIcon
  if not icon then
    icon = btn:CreateTexture(nil, "ARTWORK")
    btn._bbGearIcon = icon
  end
  icon:ClearAllPoints()
  icon:SetPoint("CENTER", 0, 0)
  icon:SetSize(GEAR_BTN - 2, GEAR_BTN - 2)
  icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:SetVertexColor(1, 0.82, 0.2)
  icon:Show()
  pcall(function()
    btn:SetNormalTexture(nil)
    btn:SetPushedTexture(nil)
  end)
  -- Keep a hit-tested normal so click/highlight work.
  pcall(function()
    local hit = btn:CreateTexture(nil, "BACKGROUND")
    hit:SetAllPoints()
    hit:SetColorTexture(0, 0, 0, 0.01)
    btn:SetNormalTexture(hit)
  end)
  pcall(function()
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  end)
  btn._bbGearStyled = true
  btn:EnableMouse(true)
  btn:Show()
end

--[[
  Assign into forward-declared EnsureTitleChrome (must NOT use `local function` here).
  CombinedBags placement: sort TOPRIGHT -9,-34; gear left of sort; title left.
]]
EnsureTitleChrome = function(frame)
  if not frame then
    return
  end
  local close = frame.CloseButton
  if not close then
    pcall(function()
      close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
      frame.CloseButton = close
    end)
  end
  if close then
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, -1)
    close:SetFrameLevel((frame:GetFrameLevel() or 1) + 520)
    close:Show()
  end

  pcall(function()
    local title = CombinedBagTitle()
    if frame.SetTitle then
      frame:SetTitle(title)
    end
    local tt = frame.TitleText
      or (frame.TitleContainer and frame.TitleContainer.TitleText)
      or frame.title
    if tt then
      tt:ClearAllPoints()
      local anchor = frame.TitleContainer or frame
      tt:SetPoint("LEFT", anchor, "LEFT", 10, 0)
      tt:SetPoint("RIGHT", frame, "RIGHT", -40, 0)
      if tt.SetJustifyH then
        tt:SetJustifyH("LEFT")
      end
      tt:SetText(title)
    end
  end)

  -- Native AutoSort sits on the frame (not title strip), TOPRIGHT -9,-34.
  local tidy = frame.sortBtn or _G.BetterBackpackSortButton
  if not tidy then
    tidy = CreateFrame("Button", "BetterBackpackSortButton", frame)
  end
  frame.sortBtn = tidy
  tidy:SetParent(frame)
  tidy:ClearAllPoints()
  tidy:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -34)
  StyleNativeSortButton(tidy)
  tidy:SetFrameLevel((frame:GetFrameLevel() or 1) + 500)
  tidy:SetAlpha(1)
  tidy:SetScript("OnEnter", function(self)
    if not GameTooltip then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    pcall(function()
      if GameTooltip_SetTitle then
        GameTooltip_SetTitle(
          GameTooltip,
          (type(BAG_CLEANUP_BAGS) == "string" and BAG_CLEANUP_BAGS) or "Clean Up Bags",
          HIGHLIGHT_FONT_COLOR
        )
      else
        GameTooltip:SetText((type(BAG_CLEANUP_BAGS) == "string" and BAG_CLEANUP_BAGS) or "Clean Up Bags")
      end
      local desc = (type(BAG_CLEANUP_BAGS_DESCRIPTION) == "string" and BAG_CLEANUP_BAGS_DESCRIPTION)
        or "Sort bags to free space."
      if GameTooltip_AddNormalLine then
        GameTooltip_AddNormalLine(GameTooltip, desc)
      else
        GameTooltip:AddLine(desc, 1, 1, 1, true)
      end
    end)
    GameTooltip:Show()
  end)
  tidy:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  tidy:SetScript("OnClick", function()
    pcall(function()
      if PlaySound and SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then
        PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
      end
    end)
    local Tidy = BetterBackpack.Modules.Tidy
    if Tidy and Tidy.SortBags then
      Tidy.SortBags()
    end
  end)
  tidy:Show()
  frame.tidy = tidy
  sortBtn = tidy

  local gear = frame.settingsBtn or _G.BetterBackpackSettingsButton
  if not gear then
    gear = CreateFrame("Button", "BetterBackpackSettingsButton", frame)
  end
  frame.settingsBtn = gear
  gear:SetParent(frame)
  gear:ClearAllPoints()
  -- Explicitly left of broom (CombinedBags filter gear sits near sort).
  gear:SetPoint("RIGHT", tidy, "LEFT", -6, 0)
  StyleNativeGearButton(gear)
  gear:SetFrameLevel((frame:GetFrameLevel() or 1) + 510)
  gear:SetAlpha(1)
  gear:SetScript("OnEnter", function(self)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText("Nastavení")
      GameTooltip:AddLine("Kategorie zapnout / vypnout. Skrytá → Other.", 0.7, 0.7, 0.7, true)
      GameTooltip:Show()
    end
  end)
  gear:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)
  gear:SetScript("OnClick", function()
    local S = BetterBackpack.Modules.Settings
    if S and S.Toggle then
      S.Toggle()
    end
  end)
  gear:Show()
  if gear._bbGearIcon then
    gear._bbGearIcon:Show()
  end
  frame.gear = gear
  settingsBtn = gear

  -- Hide legacy text strip if present.
  if frame._bbChrome then
    pcall(frame._bbChrome.Hide, frame._bbChrome)
  end
  frame._bbChromeVer = CHROME_VER

  pcall(function()
    if frame.TitleContainer then
      local need = (frame:GetFrameLevel() or 1) + 50
      if (frame.TitleContainer:GetFrameLevel() or 1) >= need then
        frame.TitleContainer:SetFrameLevel(need)
      end
    end
  end)
end

function Layout.EnsureMain()
  -- Recover half-built frame (error mid-EnsureMain left empty chrome).
  if main and not content then
    DestroyHalfBuilt()
  end
  if main then
    KillPortrait(main)
    ApplyCombinedBagsChrome(main)
    EnsureTitleChrome(main)
    InstallBagHoverHighlight()
    return main
  end

  local built = CreateBagPanel()
  -- Reattach locals if a prior load already finished chrome on this named frame.
  if built._bbBuilt and built._bbContent then
    main = built
    content = built._bbContent
    freeFs = built.freeFs
    moneyFs = built._bbMoneyFs
    emptyLabel = built._bbEmpty
    EnsureTitleChrome(main)
    InstallBagHoverHighlight()
    return main
  end
  built:SetSize(400, 320)
  built:SetFrameStrata("DIALOG")
  built:SetFrameLevel(200)
  built:SetMovable(true)
  built:EnableMouse(true)
  built:RegisterForDrag("LeftButton")
  built:SetScript("OnDragStart", function(self)
    if InCombatLockdown and InCombatLockdown() then
      return
    end
    self:StartMoving()
  end)
  built:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    PersistPos()
  end)
  built:SetScript("OnShow", function(self)
    KillPortrait(self)
    ApplyCombinedBagsChrome(self)
    local title = CombinedBagTitle()
    if self.SetTitle then
      pcall(self.SetTitle, self, title)
    elseif self.TitleText then
      self.TitleText:SetText(title)
    elseif self.title then
      self.title:SetText(title)
    end
  end)
  built:SetScript("OnHide", function()
    local OpenClose = BetterBackpack.Modules.OpenClose
    if OpenClose and OpenClose.NotifyHidden then
      OpenClose.NotifyHidden()
    end
  end)
  if UISpecialFrames then
    local already = false
    for i = 1, #UISpecialFrames do
      if UISpecialFrames[i] == "BetterBackpackFrame" then
        already = true
        break
      end
    end
    if not already then
      table.insert(UISpecialFrames, "BetterBackpackFrame")
    end
  end

  local titleText = CombinedBagTitle()
  if built.SetTitle then
    pcall(built.SetTitle, built, titleText)
  end
  if not built.TitleText and not built.title then
    local title = built:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -6)
    title:SetText(titleText)
    built.title = title
  elseif built.TitleText then
    built.TitleText:SetText(titleText)
  end

  local close = built.CloseButton
  if not close then
    pcall(function()
      close = CreateFrame("Button", nil, built, "UIPanelCloseButton")
      built.CloseButton = close
    end)
  end
  if close then
    close:SetScript("OnClick", function()
      local OpenClose = BetterBackpack.Modules.OpenClose
      if OpenClose and OpenClose.CloseOurs then
        OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.25 })
      else
        built:Hide()
      end
    end)
  end

  -- Native CombinedBags chrome (AutoSort + gear).
  EnsureTitleChrome(built)

  -- Footer on main (not Inset) — stable when main:SetSize runs.
  local footer = CreateFrame("Frame", nil, built)
  footer:SetHeight(FOOTER_H)
  footer:EnableMouse(false)
  footer:SetPoint("BOTTOMLEFT", built, "BOTTOMLEFT", 8, 6)
  footer:SetPoint("BOTTOMRIGHT", built, "BOTTOMRIGHT", -8, 6)
  footer:SetFrameLevel((built:GetFrameLevel() or 1) + 5)

  -- CombinedBags CountContainer: NumberFontNormalSmall.
  local fs
  pcall(function()
    fs = footer:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  end)
  if not fs then
    fs = footer:CreateFontString(nil, "OVERLAY")
    pcall(function()
      fs:SetFontObject(NumberFontNormalSmall or GameFontHighlightSmall)
    end)
  end
  fs:ClearAllPoints()
  fs:SetPoint("LEFT", footer, "LEFT", 4, 0)
  fs:SetPoint("TOP", footer, "TOP", 0, 0)
  fs:SetPoint("BOTTOM", footer, "BOTTOM", 0, 0)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("MIDDLE")
  fs:SetText("0/0")
  fs:SetTextColor(0.25, 0.85, 0.35)
  fs:SetDrawLayer("OVERLAY", 7)

  local moneyFrame
  pcall(function()
    moneyFrame = CreateFrame("Frame", "BetterBackpackMoneyFrame", built, "SmallMoneyFrameTemplate")
  end)
  if moneyFrame then
    moneyFrame:ClearAllPoints()
    moneyFrame:SetPoint("BOTTOMRIGHT", built, "BOTTOMRIGHT", -4, 6)
    pcall(function()
      if MoneyFrame_SetType then
        MoneyFrame_SetType(moneyFrame, "STATIC")
      end
    end)
    -- Hide leftover "Player" label some templates show.
    pcall(function()
      if moneyFrame.border then
        moneyFrame.border:Hide()
      end
      local name = moneyFrame:GetName()
      if name and _G[name .. "TrialErrorButton"] then
        _G[name .. "TrialErrorButton"]:Hide()
      end
    end)
  end
  local moneyFallback
  if not moneyFrame then
    moneyFallback = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    moneyFallback:SetPoint("RIGHT", footer, "RIGHT", 0, 1)
    moneyFallback:SetJustifyH("RIGHT")
  end

  local contentFrame = CreateFrame("Frame", nil, built)
  contentFrame:EnableMouse(false)
  contentFrame:SetPoint("TOPLEFT", built, "TOPLEFT", INSET_X, -TOP_CHROME)
  contentFrame:SetSize(100, 100)
  contentFrame:SetFrameLevel((built:GetFrameLevel() or 200) + 40)
  contentFrame:Show()
  pcall(function()
    if built.Inset then
      built.Inset:SetFrameLevel((built:GetFrameLevel() or 200) + 1)
      built.Inset:EnableMouse(false)
    end
  end)

  local empty = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  empty:SetPoint("TOPLEFT", 4, -4)
  empty:Hide()

  -- Commit only when fully built.
  main = built
  content = contentFrame
  freeFs = fs
  moneyFs = moneyFallback
  emptyLabel = empty
  main.footer = footer
  main.freeFs = freeFs
  main.moneyFrame = moneyFrame
  main._bbContent = contentFrame
  main._bbEmpty = empty
  main._bbMoneyFs = moneyFallback
  main._bbBuilt = true
  EnsureTitleChrome(main)

  InstallBagHoverHighlight()
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
    main:SetSize(400, 320)
  end
  PlaceOnScreen()
  KillPortrait(main)
  ApplyCombinedBagsChrome(main)
  EnsureTitleChrome(main)
  InstallBagHoverHighlight()
  main:Show()
  pcall(function()
    main:Raise()
  end)
  DoLayout()
  main:SetAlpha(1)
  main:Show()
  PlaceOnScreen()
  ApplyCombinedBagsChrome(main)
  EnsureTitleChrome(main)
  UpdateFreeSpace()
  UpdateMoney()
  pcall(function()
    main:Raise()
  end)
  -- Re-raise chrome after Raise() so TitleContainer cannot bury it.
  EnsureTitleChrome(main)
  UpdateFreeSpace()
  return main:IsShown() and true or false
end

function Layout.Hide()
  focusBagID = nil
  ClearBagMatchGlows()
  local S = BetterBackpack.Modules.Settings
  if S and S.Hide then
    S.Hide()
  end
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
  local tidyOn = sortBtn and sortBtn:IsShown()
  local gearOn = settingsBtn and settingsBtn:IsShown()
  local chromeVer = main._bbChromeVer
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
    uklid = tidyOn and true or false,
    nastaveni = gearOn and true or false,
    chromeVer = chromeVer,
    ver = Config.VERSION,
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
