--[[
  BetterBackpack.Layout — category lanes + CombinedBags chrome (0.5.14).
  Forever: never SetToplevel / SetFrameStrata (ADDON_ACTION_BLOCKED).
  Chrome metrics from Baganator Forever Blizzard skin + ContainerFrameCombinedBags:
    ButtonFrameOffset=6, Bg/TopTile @ (6,-21), NineSlice borders, Inset hidden.
  Title buttons = AutoSort twins (no glow). NTH via Feat("Search|…") only.
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local Layout = {}
BetterBackpack.Modules.Layout = Layout

local Config = BetterBackpack.Config
local Slots = BetterBackpack.Modules.Slots

local function Feat(name)
  return BetterBackpack.Modules and BetterBackpack.Modules[name]
end

local SLOT = 37
local PAD = 2 -- dense grid (0.5.8)
local HEADER_H = 18
local HEADER_PAD = 2
local SECTION_GAP = 4
-- Baganator Forever Blizzard skin: ButtonFrameOffset=6, OffsetTop=2.
local BF_OFFSET = 6
local BF_OFFSET_TOP = 2
local INSET_X = BF_OFFSET + 8 -- content left/right inside NineSlice (symmetric, CombinedBags feel)
local TOP_CHROME = 54 -- title + search row (Baganator search ≈ -28)
local BOT_CHROME = 30 -- footer strip inside bottom border
local FOOTER_H = 20
-- Narrowest grid that still fits title|broom|gear|X, search box and N/M + money footer.
local MIN_COLS = 6
local CHROME_BTN = 32
local CLASSIC_BORDER = {
  "BotLeftCorner", "BotRightCorner", "BottomBorder", "LeftBorder", "RightBorder",
  "TopRightCorner", "TopLeftCorner", "TopBorder",
}

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

function Layout.GetCategoryOrder()
  local CC = Feat("CustomCategories")
  if CC and CC.ExtendOrder then
    return CC.ExtendOrder(CATEGORY_ORDER)
  end
  return CATEGORY_ORDER
end

function Layout.GetCategoryLabel(key)
  local CC = Feat("CustomCategories")
  if CC and CC.Label then
    local custom = CC.Label(key)
    if custom then
      return custom
    end
  end
  return CATEGORY_LABELS[key] or key
end

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
local ApplyCombinedBagsChrome
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
  if type(c) ~= "number" or c < 4 or c > 16 then
    c = 10 -- Combined Bags width feel (BagShelves)
  end
  local LM = Feat("LayoutModes")
  if LM and LM.Columns then
    return LM.Columns(c)
  end
  return c
end

local function CategoryEnabled(key)
  if key == "other" then
    return true
  end
  if type(key) == "string" and key:find("^custom_", 1) then
    return true
  end
  local CC = Feat("CustomCategories")
  if CC and CC.IsDefaultHidden and CC.IsDefaultHidden(key) then
    return false
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
  local CC = Feat("CustomCategories")
  if CC and CC.Resolve and itemID then
    local custom = CC.Resolve(itemID)
    if type(custom) == "string" and custom ~= "" then
      if custom == "weapon" or custom == "armor" then
        custom = "gear"
      end
      return custom, info
    end
  end
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

local function IsFiltering()
  local S, F = Feat("Search"), Feat("Filter")
  local q = S and S.GetQuery and S.GetQuery() or ""
  local f = F and F.GetCategory and F.GetCategory()
  return (type(q) == "string" and q ~= "") or f ~= nil
end

-- unfiltered=true ignores Search/Filter: used to size the frame so filtering never resizes it.
local function CollectBuckets(unfiltered)
  local order = Layout.GetCategoryOrder()
  local buckets = {}
  for i = 1, #order do
    buckets[order[i]] = {}
  end
  local Search = not unfiltered and Feat("Search")
  local Filter = not unfiltered and Feat("Filter")
  local ranges = Slots.BagRanges()
  for i = 1, #ranges do
    local bag, n = ranges[i].bag, ranges[i].slots
    for slot = 1, n do
      if Slots.SlotOccupied(bag, slot) then
        -- Disabled category → Other (items always visible somewhere).
        local cat, info = Layout.ClassifyBagSlot(bag, slot)
        if not cat or not CategoryEnabled(cat) then
          cat = "other"
        end
        if cat == "weapon" or cat == "armor" then
          cat = "gear"
        end
        if not buckets[cat] then
          if type(cat) == "string" and cat:find("^custom_", 1) then
            buckets[cat] = {}
          else
            cat = "other"
          end
        end
        if Search and Search.Passes and not Search.Passes(bag, slot, info) then
          -- filtered out by search
        elseif Filter and Filter.Passes and not Filter.Passes(cat) then
          -- filtered out by category filter
        else
          buckets[cat][#buckets[cat] + 1] = { bag = bag, slot = slot }
        end
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

-- Classic used/total N/M: ONLY GetContainerNumSlots(0..NUM_BAG_SLOTS). 102 was 70+32 keyring invent.
local freeSpaceLogged = false

local function LogPlayerSlotsOnce(used, total, parts)
  if freeSpaceLogged then
    return
  end
  freeSpaceLogged = true
  local msg = string.format(
    "|cff88ff88BetterBackpack|r slots %s → used/total=%d/%d (player+reagent, no keyring/bank)",
    tostring(parts or "?"),
    used or 0,
    total or 0
  )
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(msg)
  end
end

local function UpdateFreeSpace()
  freeFs = (main and main.freeFs) or freeFs
  if not freeFs then
    return
  end
  local used, total, free, parts = 0, 0, 0, "?"
  pcall(function()
    if Slots.CountPlayerSlots then
      used, total, free, parts = Slots.CountPlayerSlots()
    else
      local ranges = Slots.PlayerBagRanges and Slots.PlayerBagRanges() or {}
      for i = 1, #ranges do
        local n = ranges[i].slots
        total = total + n
        for slot = 1, n do
          if not Slots.SlotOccupied(ranges[i].bag, slot) then
            free = free + 1
          end
        end
      end
      used = total - free
    end
  end)
  if used < 0 then
    used = 0
  end
  LogPlayerSlotsOnce(used, total, parts)
  pcall(function()
    freeFs:Show()
    freeFs:ClearAllPoints()
    local footer = main.footer or freeFs:GetParent()
    -- Same font + baseline as the money text (copper button is always shown).
    local moneyText
    pcall(function()
      local mname = main.moneyFrame and main.moneyFrame:GetName()
      local gold = mname and _G[mname .. "CopperButton"]
      moneyText = gold and gold.GetFontString and gold:GetFontString()
    end)
    local fontSet = false
    if moneyText then
      pcall(function()
        local fo = moneyText:GetFontObject()
        if fo then
          freeFs:SetFontObject(fo)
          fontSet = true
        else
          local f, sz, fl = moneyText:GetFont()
          if f and sz then
            freeFs:SetFont(f, sz, fl)
            fontSet = true
          end
        end
      end)
    end
    if not fontSet then
      freeFs:SetFontObject(NumberFontNormalRight or NumberFontNormal)
    end
    local placed = false
    if moneyText then
      pcall(function()
        local mb, fb = moneyText:GetBottom(), main:GetBottom()
        if type(mb) == "number" and type(fb) == "number" and mb - fb >= 0 and mb - fb < 40 then
          freeFs:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", BF_OFFSET + 8, mb - fb)
          placed = true
        end
      end)
    end
    if not placed then
      freeFs:SetPoint("LEFT", footer, "LEFT", 4, 0)
      freeFs:SetPoint("TOP", footer, "TOP", 0, 0)
      freeFs:SetPoint("BOTTOM", footer, "BOTTOM", 0, 0)
    end
    freeFs:SetJustifyH("LEFT")
    freeFs:SetJustifyV("MIDDLE")
    freeFs:SetDrawLayer("OVERLAY", 7)
    freeFs:SetText(string.format("%d/%d", used, total))
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
  -- Baganator Forever category header: bag-arrow atlas (rotated) + GameFontNormalMed2 label.
  local header = CreateFrame("Button", nil, sf)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetHeight(HEADER_H)
  header:RegisterForClicks("LeftButtonUp")
  local arrow = header:CreateTexture(nil, "ARTWORK")
  arrow:SetSize(14, 14)
  arrow:SetPoint("LEFT", 0, 0)
  if pcall(arrow.SetAtlas, arrow, "bag-arrow") and arrow:GetAtlas() then
    header.arrowAtlas = true
  end
  header.arrow = arrow
  local title = header:CreateFontString(nil, "OVERLAY")
  if not pcall(title.SetFontObject, title, GameFontNormalMed2 or GameFontNormal) then
    title:SetFontObject(GameFontNormal)
  end
  title:SetPoint("LEFT", arrow, "RIGHT", 6, 0)
  title:SetJustifyH("LEFT")
  header.title = title
  local countFs = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  countFs:SetPoint("LEFT", title, "RIGHT", 4, 0)
  header.countFs = countFs
  header:SetScript("OnEnter", function(self)
    self.title:SetTextColor(1, 1, 1)
  end)
  header:SetScript("OnLeave", function(self)
    local c = NORMAL_FONT_COLOR
    if c and c.r then
      self.title:SetTextColor(c.r, c.g, c.b)
    else
      self.title:SetTextColor(1, 0.82, 0)
    end
  end)
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

local function SetHeaderState(header, label, count, collapsed)
  header.title:SetText(label)
  header.countFs:SetText(string.format("(%d)", count))
  local arrow = header.arrow
  pcall(function()
    if header.arrowAtlas then
      -- Baganator: expanded = π/2 (points down), collapsed = -π (points right).
      arrow:SetRotation(collapsed and -math.pi or math.pi / 2)
    else
      arrow:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    end
  end)
end

-- Filtered view keeps the unfiltered frame size; pad the space under the matches with
-- empty bags-item-slot64 wells so the window reads as a bag, not a blank panel.
local wellPool = {}
local function FillEmptyWells(on, startY, contentH, cols)
  local n = 0
  if on then
    local y = startY
    while y + SLOT <= contentH + 0.5 do
      for col = 0, cols - 1 do
        n = n + 1
        local w = wellPool[n]
        if not w then
          w = content:CreateTexture(nil, "BACKGROUND", nil, 1)
          w:SetSize(SLOT, SLOT)
          if not pcall(w.SetAtlas, w, "bags-item-slot64") or not w:GetAtlas() then
            w:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
            w:SetTexCoord(0.15, 0.85, 0.15, 0.85)
          end
          w:SetAlpha(0.9)
          wellPool[n] = w
        end
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", content, "TOPLEFT", col * (SLOT + PAD), -y)
        w:Show()
      end
      y = y + SLOT + PAD
    end
  end
  for i = n + 1, #wellPool do
    wellPool[i]:Hide()
  end
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
    local maxCols = Columns()
    local used = {}
    local y = 0
    local any = false
    local order = Layout.GetCategoryOrder()
    local SM = Feat("StackMerge")

    local function MergedLists(buckets)
      local out = {}
      for i = 1, #order do
        local key = order[i]
        if CategoryEnabled(key) then
          local list = buckets[key] or {}
          if SM and SM.Collapse then
            list = SM.Collapse(list)
          end
          out[key] = list
        end
      end
      return out
    end

    local lists = MergedLists(CollectBuckets(false))
    -- Size from the unfiltered bag: search / filter / "No matches" keep the same frame.
    -- Frame size = full bag, every lane expanded, no search/filter. Collapse and search
    -- only change what is drawn inside; the window never resizes for them.
    local sizing = IsFiltering() and MergedLists(CollectBuckets(true)) or lists

    -- Hug content: grid is as wide as the widest lane (capped at maxCols).
    local widest = 0
    for _, list in pairs(sizing) do
      if #list > widest then
        widest = #list
      end
    end
    local cols = math.max(math.min(widest, maxCols), math.min(MIN_COLS, maxCols))
    local contentW = cols * SLOT + (cols - 1) * PAD

    local lanesH = 0
    for i = 1, #order do
      local list = sizing[order[i]]
      if list and #list > 0 then
        lanesH = lanesH + HEADER_H + HEADER_PAD
        lanesH = lanesH + math.ceil(#list / cols) * (SLOT + PAD) - PAD
        lanesH = lanesH + SECTION_GAP
      end
    end

    for i = 1, #order do
      local key = order[i]
      if CategoryEnabled(key) then
        local list = lists[key] or {}
        if #list > 0 then
          any = true
          local sf = EnsureSection(key)
          sf:ClearAllPoints()
          sf:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
          sf:SetWidth(contentW)
          sf:Show()
          local collapsed = IsCollapsed(key)
          SetHeaderState(sf.header, Layout.GetCategoryLabel(key), #list, collapsed)
          y = y + HEADER_H + HEADER_PAD
          if not collapsed then
            local col, row = 0, 0
            local rows = math.ceil(#list / cols)
            -- Parent to main (absolute), not content — content sat under Inset.Bg.
            local parentFrame = main or content
            for j = 1, #list do
              local entry = list[j]
              local bag, slot = entry.bag, entry.slot
              local btn = Slots.Acquire(bag, slot)
              if btn then
                used[btn] = true
                local px = INSET_X + col * (SLOT + PAD)
                local py = TOP_CHROME + y + row * (SLOT + PAD)
                Slots.Place(btn, parentFrame, px, py, true)
                if SM and SM.ApplyDisplayCount then
                  SM.ApplyDisplayCount(btn, entry)
                end
              end
              col = col + 1
              if col >= cols then
                col = 0
                row = row + 1
              end
            end
            y = y + rows * (SLOT + PAD) - PAD
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

    for key, sf in pairs(sectionFrames) do
      local still = false
      for i = 1, #order do
        if order[i] == key then
          still = true
          break
        end
      end
      if not still then
        sf:Hide()
      end
    end

    local PinsMod = Feat("Pins")
    if PinsMod and PinsMod.Layout then
      local pinH = PinsMod.Layout(content, y, cols) or 0
      if pinH > 0 then
        any = true
        y = y + pinH + SECTION_GAP
        lanesH = lanesH + pinH + SECTION_GAP
      end
    end

    Slots.ParkUnused(used)

    if emptyLabel then
      if any then
        emptyLabel:Hide()
      else
        local q = Feat("Search") and Feat("Search").GetQuery and Feat("Search").GetQuery() or ""
        local filt = Feat("Filter") and Feat("Filter").GetCategory and Feat("Filter").GetCategory()
        if (q and q ~= "") or filt then
          emptyLabel:SetText("No matches")
        else
          emptyLabel:SetText("Bags empty")
        end
        emptyLabel:Show()
        y = math.max(y, 36)
      end
    end

    -- Drop trailing section gap so footer sits under last row (no empty black).
    if y >= SECTION_GAP then
      y = y - SECTION_GAP
    end
    if lanesH >= SECTION_GAP then
      lanesH = lanesH - SECTION_GAP
    end
    local contentH = math.max(y, lanesH, 40)
    local width = INSET_X + contentW + INSET_X
    local height = TOP_CHROME + contentH + BOT_CHROME
    content:ClearAllPoints()
    -- Always from main (not Inset) — Inset stretch left empty black below Other.
    content:SetPoint("TOPLEFT", main, "TOPLEFT", INSET_X, -TOP_CHROME)
    content:SetSize(contentW, contentH)
    content:Show()
    -- Space freed by collapse / search (frame stays full size) → empty wells.
    FillEmptyWells(Profile().fillEmptyWells == true, y + SECTION_GAP, contentH, cols)
    -- Content above Bg; Inset stays hidden (Baganator). NineSlice draws borders.
    local mainLvl = main:GetFrameLevel() or 200
    pcall(function()
      if main.Inset then
        main.Inset:Hide()
        main.Inset:EnableMouse(false)
      end
      if main.NineSlice then
        main.NineSlice:SetFrameLevel(mainLvl + 2)
      end
    end)
    content:SetFrameLevel(mainLvl + 40)
    main:SetSize(width, height)
    if main.footer then
      main.footer:ClearAllPoints()
      main.footer:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", BF_OFFSET + 4, 6)
      main.footer:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -(BF_OFFSET + 4), 6)
      main.footer:SetFrameLevel(mainLvl + 5)
      -- Hairline between grid and footer (N/M + money).
      local line = main.footer.hairline
      if not line then
        line = main.footer:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.14)
        main.footer.hairline = line
      end
      line:ClearAllPoints()
      line:SetPoint("BOTTOMLEFT", main.footer, "TOPLEFT", 0, 1)
      line:SetPoint("BOTTOMRIGHT", main.footer, "TOPRIGHT", 0, 1)
      if PixelUtil and PixelUtil.SetHeight then
        PixelUtil.SetHeight(line, 1)
      else
        line:SetHeight(1)
      end
      line:Show()
    end
    if main.moneyFrame then
      main.moneyFrame:ClearAllPoints()
      main.moneyFrame:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -(BF_OFFSET + 2), 6)
      pcall(function()
        main.moneyFrame:SetFrameLevel(mainLvl + 6)
      end)
    end
    ApplyCombinedBagsChrome(main)
    EnsureTitleChrome(main)
    local SearchChrome = Feat("Search")
    if SearchChrome and SearchChrome.EnsureChrome then
      pcall(SearchChrome.EnsureChrome, main)
    end
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

--[[
  Legit CombinedBags / Baganator Forever Blizzard chrome:
  NineSlice borders, TopTileStreaks, solid Bg inset (6,-21), Inset hidden.
  Assigns the forward-declared upvalue (DoLayout calls it) — not `local function`.
]]
ApplyCombinedBagsChrome = function(frame)
  if not frame then
    return
  end
  local src = ContainerFrameCombinedBags

  -- Baganator backpack: Inset:Hide() — NineSlice draws the border.
  pcall(function()
    if frame.Inset then
      frame.Inset:Hide()
      frame.Inset:EnableMouse(false)
      if frame.Inset.SetAlpha then
        frame.Inset:SetAlpha(0)
      end
    end
  end)

  pcall(function()
    if src and src.NineSlice and NineSliceUtil then
      local kit
      if src.NineSlice.GetFrameLayoutTextureKit then
        kit = src.NineSlice:GetFrameLayoutTextureKit()
      end
      if type(kit) == "string" and not IsSecret(kit) then
        if not frame.NineSlice then
          frame.NineSlice = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
          frame.NineSlice:SetAllPoints(frame)
        end
        NineSliceUtil.ApplyLayoutByName(frame.NineSlice, "UniqueCornersLayout", kit)
        frame.NineSlice:SetAlpha(1)
        frame.NineSlice:Show()
        if frame.NineSlice.SetFrameLevel then
          frame.NineSlice:SetFrameLevel((frame:GetFrameLevel() or 1) + 2)
        end
      end
    end
  end)

  -- Classic border regions when NineSlice has no painted kids (Baganator fallback).
  pcall(function()
    local ns = frame.NineSlice
    local needClassic = not ns or (ns.GetRegions and ns:GetRegions() == nil)
    if not needClassic then
      return
    end
    for i = 1, #CLASSIC_BORDER do
      local key = CLASSIC_BORDER[i]
      local tex = frame[key]
      if not tex and src and src[key] then
        tex = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        frame[key] = tex
        CopyTex(tex, src[key])
        pcall(function()
          local p, rel, rp, x, y = src[key]:GetPoint(1)
          if p then
            tex:ClearAllPoints()
            tex:SetPoint(p, frame, rp or p, x or 0, y or 0)
          end
          if src[key].GetSize then
            local w, h = src[key]:GetSize()
            if type(w) == "number" and w > 0 then
              tex:SetSize(w, h)
            end
          end
        end)
      end
      if tex then
        tex:SetAlpha(1)
        tex:Show()
      end
    end
  end)

  ApplyPanelBackgroundColor(frame)
  pcall(function()
    if not frame.Bg then
      return
    end
    frame.Bg:ClearAllPoints()
    -- Baganator Forever retail path with borders on.
    frame.Bg:SetPoint("TOPLEFT", frame, "TOPLEFT", BF_OFFSET, -21)
    frame.Bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -BF_OFFSET, 2)
    frame.Bg:SetAlpha(1)
    frame.Bg:Show()
    if frame.Bg.SetDrawLayer then
      frame.Bg:SetDrawLayer("BACKGROUND", -8)
    end
  end)

  pcall(function()
    if not frame.TopTileStreaks then
      frame.TopTileStreaks = frame:CreateTexture(nil, "ARTWORK", nil, -6)
    end
    frame.TopTileStreaks:ClearAllPoints()
    frame.TopTileStreaks:SetPoint("TOPLEFT", frame, "TOPLEFT", BF_OFFSET, -21)
    frame.TopTileStreaks:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -BF_OFFSET, -21)
    frame.TopTileStreaks:SetHeight(40)
    if src and src.TopTileStreaks then
      CopyTex(frame.TopTileStreaks, src.TopTileStreaks)
    end
    frame.TopTileStreaks:SetAlpha(1)
    frame.TopTileStreaks:Show()
  end)

  pcall(function()
    if frame.CloseButton then
      frame.CloseButton:SetFrameLevel((frame:GetFrameLevel() or 1) + 520)
    end
    if frame.TitleContainer then
      frame.TitleContainer:SetFrameLevel((frame:GetFrameLevel() or 1) + 50)
      frame.TitleContainer:Show()
    end
  end)
end

local function CreateBagPanel()
  -- Named frame persists across failed EnsureMain — always reuse, never double-create.
  -- Prefer ButtonFrameTemplate (CombinedBags-class chrome: TitleContainer, Close, Inset, Bg).
  -- Forever may fire ADDON_ACTION_BLOCKED on template SetFrameStrata — that is an *event*,
  -- not a hard abort when CreateFrame is pcall'd. Never call SetFrameStrata ourselves.
  local frame = _G.BetterBackpackFrame
  if not frame then
    local templates = {
      "ButtonFrameTemplate",
      "BasicFrameTemplateWithInset",
      "BasicFrameTemplate",
    }
    for i = 1, #templates do
      local tmpl = templates[i]
      local ok, f = pcall(function()
        return CreateFrame("Frame", "BetterBackpackFrame", UIParent, tmpl)
      end)
      frame = _G.BetterBackpackFrame
      if not frame and ok and f then
        frame = f
      end
      if frame then
        frame._bbTemplate = tmpl
        break
      end
    end
  end
  if not frame then
    frame = CreateFrame("Frame", "BetterBackpackFrame", UIParent)
    frame._bbTemplate = "plain"
  end
  pcall(function()
    if frame:GetParent() ~= UIParent then
      frame:SetParent(UIParent)
    end
  end)
  -- Never SetFrameStrata / SetToplevel — level only (OpenClose / Raise).
  pcall(function()
    frame:SetFrameLevel(500)
  end)
  pcall(function()
    if ButtonFrameTemplate_HidePortrait then
      ButtonFrameTemplate_HidePortrait(frame)
    end
  end)
  pcall(function()
    if ButtonFrameTemplate_HideButtonBar then
      ButtonFrameTemplate_HideButtonBar(frame)
    end
  end)
  pcall(function()
    -- Baganator Forever path: no-portrait layout type when supported.
    frame.layoutType = "ButtonFrameTemplateNoPortrait"
  end)
  KillPortrait(frame)
  ApplyCombinedBagsChrome(frame)
  return frame
end

local function DestroyHalfBuilt()
  -- Keep parent UIParent — SetParent(nil) left a shell that Show() could not revive.
  if main then
    pcall(function()
      main:Hide()
    end)
  end
  main, content, freeFs, moneyFs, emptyLabel, sortBtn, settingsBtn = nil, nil, nil, nil, nil, nil, nil
  sectionFrames = {}
  pcall(function()
    local old = _G.BetterBackpackFrame
    if old then
      old._bbBuilt = nil
      old._bbContent = nil
      old._bbEmpty = nil
      old._bbMoneyFs = nil
      old:Hide()
      if old:GetParent() ~= UIParent then
        old:SetParent(UIParent)
      end
    end
  end)
end

local CHROME_VER = 28 -- 0.5.14: broom/gear = Close size, flush left of X; flat gear
local chromeLogged = false
local customChromeHidden = false

--[[
  0.4.2: twin BagItemAutoSortButton style for BOTH title buttons.
  - Same pixel size as native AutoSort (not Close 32×32)
  - Atlas art (not pixelated UI-OptionsButton)
  - No ADD MouseHilight glow
]]

local function HideLegacyChromeOnce()
  if customChromeHidden then
    return
  end
  customChromeHidden = true
  for _, name in ipairs({
    "BetterBackpackSortButton",
    "BetterBackpackSettingsButton",
    "BetterBackpackSortBtn12",
    "BetterBackpackGearBtn12",
    "BetterBackpackSortBtn13",
    "BetterBackpackGearBtn13",
    "BetterBackpackSettingsBtn15",
    "BetterBackpackGearBtn16",
    "BetterBackpackTidyBtn16",
  }) do
    local b = _G[name]
    if b then
      pcall(function()
        b:Hide()
        b:EnableMouse(false)
        b:ClearAllPoints()
        b:SetAlpha(0)
      end)
    end
  end
end

local function MeasureAutoSortSize()
  -- Native BagItemAutoSortButton is typically 25×23 — do not Show() (flash).
  local w, h = 25, 23
  local sortNative = _G.BagItemAutoSortButton
  if sortNative then
    pcall(function()
      local cw, ch = sortNative:GetWidth(), sortNative:GetHeight()
      if type(cw) == "number" and cw >= 8 then
        w = cw
      end
      if type(ch) == "number" and ch >= 8 then
        h = ch
      end
    end)
  end
  return w, h
end

local function LogChromeOnce(tidy, gear, close)
  if chromeLogged then
    return
  end
  chromeLogged = true
  local function wh(b)
    if not b then
      return "nil"
    end
    local w, h, name = 0, 0, "?"
    pcall(function()
      w, h = b:GetWidth(), b:GetHeight()
      name = (b.GetName and b:GetName()) or name
    end)
    return string.format("%s %.0fx%.0f", tostring(name), w or 0, h or 0)
  end
  local msg = string.format(
    "|cff88ff88BetterBackpack|r chrome tidy=%s gear=%s close=%s ver=%d",
    wh(tidy),
    wh(gear),
    wh(close),
    CHROME_VER
  )
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(msg)
  end
end

local function AtlasExists(atlas)
  if type(atlas) ~= "string" or not (C_Texture and C_Texture.GetAtlasInfo) then
    return false
  end
  local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
  return ok and info ~= nil
end

-- Read a native button state texture (atlas preferred, + own size if not stretched).
local function NativeArt(tex, owner)
  if not tex then
    return nil
  end
  local d
  local atlas = SafeAtlas(tex)
  if atlas then
    d = { atlas = atlas }
  else
    local file = SafeTexture(tex)
    if not file then
      return nil
    end
    d = { file = file }
    pcall(function()
      local c = { tex:GetTexCoord() }
      if #c == 8 and not IsSecret(c[1]) then
        d.coords = c
      end
    end)
  end
  pcall(function()
    local b = tex:GetBlendMode()
    if type(b) == "string" and not IsSecret(b) then
      d.blend = b
    end
    if owner then
      local w, h = tex:GetSize()
      local ow = owner:GetWidth()
      if type(w) == "number" and w > 0 and type(ow) == "number" and math.abs(w - ow) > 0.5 then
        local p, _, rp, x, y = tex:GetPoint(1)
        d.w, d.h, d.p, d.rp, d.x, d.y = w, h, p or "CENTER", rp or p or "CENTER", x or 0, y or 0
      end
    end
  end)
  return d
end

local function SetStateArt(btn, which, d)
  pcall(function()
    if not d then
      btn["Set" .. which .. "Texture"](btn, nil)
      return
    end
    local setAtlas = btn["Set" .. which .. "Atlas"]
    if d.atlas and setAtlas then
      if which == "Highlight" then
        setAtlas(btn, d.atlas, d.blend or "ADD")
      else
        setAtlas(btn, d.atlas)
      end
    elseif which == "Highlight" then
      btn:SetHighlightTexture(d.file, d.blend or "ADD")
    else
      btn["Set" .. which .. "Texture"](btn, d.file)
    end
    local t = btn["Get" .. which .. "Texture"](btn)
    if t then
      if d.file and d.coords then
        t:SetTexCoord(unpack(d.coords))
      end
      t:ClearAllPoints()
      if d.w then
        t:SetSize(d.w, d.h)
        t:SetPoint(d.p, btn, d.rp, d.x, d.y)
      else
        t:SetAllPoints(btn)
      end
    end
  end)
end

--[[
  Real CombinedBags broom: adopt the live BagItemAutoSortButton (Blizzard art, size,
  tooltip). Not protected, so SetParent is safe; OnClick routes to Tidy (OOC guard +
  refresh suppression). If Blizzard re-parents it (CombinedBags update) while ours is
  open, re-grab on the next frame — never inside the SetParent hook (no thrash).
]]
local adoptingSort = false
local nativeSortHooked = false

local function AdoptNativeAutoSort(frame, anchor, level, gap, w, h)
  local native = _G.BagItemAutoSortButton
  if not native or not frame then
    return nil
  end
  adoptingSort = true
  local ok = pcall(function()
    if native:GetParent() ~= frame then
      native:SetParent(frame)
    end
    if not native._bbNativeW then
      native._bbNativeW, native._bbNativeH = native:GetWidth(), native:GetHeight()
    end
    native:SetSize(w, h)
    native:ClearAllPoints()
    native:SetPoint("RIGHT", anchor, "LEFT", -gap, 0)
    native:SetFrameLevel(level)
    native:SetAlpha(1)
    native:EnableMouse(true)
    native:Show()
  end)
  adoptingSort = false
  if not ok then
    return nil
  end
  if not native._bbTidyWired then
    native._bbTidyWired = true
    pcall(function()
      native:SetScript("OnClick", function()
        local T = BetterBackpack.Modules.Tidy
        if T and T.SortBags then
          T.SortBags()
        end
      end)
    end)
  end
  if not nativeSortHooked then
    nativeSortHooked = true
    pcall(function()
      hooksecurefunc(native, "SetParent", function(_, parent)
        if adoptingSort or parent == main then
          return
        end
        if C_Timer and C_Timer.After then
          C_Timer.After(0, function()
            if main and Layout.IsShown() and Profile().enabled then
              pcall(EnsureTitleChrome, main)
            end
          end)
        end
      end)
    end)
  end
  return native
end

function Layout.ReleaseNativeAutoSort()
  local native = _G.BagItemAutoSortButton
  if not native or not main or native:GetParent() ~= main then
    return
  end
  adoptingSort = true
  pcall(function()
    local combined = ContainerFrameCombinedBags
    if native._bbNativeW then
      native:SetSize(native._bbNativeW, native._bbNativeH)
    end
    if combined then
      native:SetParent(combined)
      native:ClearAllPoints()
      native:SetPoint("TOPRIGHT", combined, "TOPRIGHT", -40, -4)
    else
      native:SetParent(UIParent)
      native:Hide()
    end
  end)
  adoptingSort = false
end

-- ContainerFrame.xml BagItemAutoSortButton: 25×23, highlight 21×20 centered.
local SQUARE_HILIGHT = {
  file = "Interface\\Buttons\\ButtonHilight-Square",
  blend = "ADD",
  w = 21,
  h = 20,
  p = "CENTER",
  rp = "CENTER",
  x = 0,
  y = 0,
}
local GEAR_ATLASES = { "questlog-icon-setting", "GM-icon-settings", "OptionsIcon-Brown", "Gear" }

--[[
  Title buttons like CombinedBags: broom = 1:1 copy of the live BagItemAutoSortButton
  state art + size; gear = same size, flat gear icon (verified atlas), same square
  highlight, 1px press offset. Atlases are checked with C_Texture.GetAtlasInfo —
  SetNormalAtlas does not error on unknown names, so pcall alone never fell back.
]]
local function StyleAutoSortTwin(btn, kind, w, h)
  btn:SetSize(w, h)
  pcall(function()
    btn:SetDisabledTexture(nil)
  end)
  local native = _G.BagItemAutoSortButton
  local nativeHl = native and NativeArt(native.GetHighlightTexture and native:GetHighlightTexture(), native)
  if kind == "tidy" then
    local n = native and NativeArt(native:GetNormalTexture(), native)
    local p = native and NativeArt(native:GetPushedTexture(), native)
    if not n and AtlasExists("bags-button-autosort-up") then
      n = { atlas = "bags-button-autosort-up" }
    end
    if not p and AtlasExists("bags-button-autosort-down") then
      p = { atlas = "bags-button-autosort-down" }
    end
    n = n or { file = "Interface\\Buttons\\UI-RefreshButton" }
    SetStateArt(btn, "Normal", n)
    SetStateArt(btn, "Pushed", p or n)
    SetStateArt(btn, "Highlight", nativeHl or SQUARE_HILIGHT)
  else
    -- Flat options gear, no plate (CombinedBags has no native gear).
    SetStateArt(btn, "Normal", nil)
    SetStateArt(btn, "Pushed", nil)
    SetStateArt(btn, "Highlight", nativeHl or SQUARE_HILIGHT)
    if btn._bbFill then
      btn._bbFill:Hide()
    end
    btn._bbPlateFill = nil

    local icon = btn._bbIcon
    if not icon then
      icon = btn:CreateTexture(nil, "OVERLAY")
      btn._bbIcon = icon
      btn:HookScript("OnMouseDown", function(self)
        if self._bbIcon then
          self._bbIcon:SetPoint("CENTER", self, "CENTER", 1, -1)
        end
      end)
      btn:HookScript("OnMouseUp", function(self)
        if self._bbIcon then
          self._bbIcon:SetPoint("CENTER", self, "CENTER", 0, 0)
        end
      end)
    end
    local size = math.floor(math.min(w, h) - 4)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetSize(size, size)
    local done = false
    for _, atlas in ipairs(GEAR_ATLASES) do
      if not done and AtlasExists(atlas) then
        done = pcall(icon.SetAtlas, icon, atlas)
      end
    end
    if not done then
      icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
      icon:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    end
    icon:SetVertexColor(1, 1, 1)
    icon:Show()
  end
  btn._bbChromeStyled = true
end

local function EnsureChromeButton(existing, globalName, frame)
  local btn = existing
  if btn and btn._bbChrome17 then
    pcall(function()
      btn:SetParent(frame)
    end)
    return btn
  end
  btn = _G[globalName]
  if not (btn and btn._bbChrome17) then
    btn = CreateFrame("Button", globalName, frame)
    btn._bbChrome17 = true
  else
    pcall(function()
      btn:SetParent(frame)
    end)
  end
  return btn
end

local function EnsureBagShelvesTitleChrome(frame, close)
  HideLegacyChromeOnce()

  -- broom | gear | X: all three exactly the Close button's size, flush in one row.
  local w, h = MeasureAutoSortSize()
  if close then
    local cw, ch = close:GetWidth(), close:GetHeight()
    if type(cw) == "number" and cw >= 8 and type(ch) == "number" and ch >= 8 then
      w, h = cw, ch
    end
  end
  local level = (close and close:GetFrameLevel()) or ((frame:GetFrameLevel() or 1) + 520)
  local gap = 0

  -- gear immediately left of Close (broom | gear | X)
  local priorGear = frame.settingsBtn
  if priorGear and not priorGear._bbChrome17 then
    priorGear = nil
  end
  local gear = EnsureChromeButton(priorGear, "BetterBackpackGearBtn17", frame)
  gear:ClearAllPoints()
  if close then
    gear:SetPoint("RIGHT", close, "LEFT", -gap, 0)
  else
    gear:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -4)
  end
  gear:SetFrameLevel(level)
  StyleAutoSortTwin(gear, "settings", w, h)
  if not gear._bbChromeWired then
    gear._bbChromeWired = true
    gear:SetScript("OnEnter", function(self)
      if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Nastavení")
        GameTooltip:AddLine("Kategorie zapnout / vypnout.", 0.7, 0.7, 0.7, true)
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
  end
  gear:SetAlpha(1)
  gear:EnableMouse(true)
  gear:Show()
  frame.settingsBtn = gear

  local native = AdoptNativeAutoSort(frame, gear, level, gap, w, h)
  local twin = _G.BetterBackpackTidyBtn17
  if native then
    if twin then
      pcall(function()
        twin:Hide()
        twin:EnableMouse(false)
      end)
    end
    frame.sortBtn = native
    LogChromeOnce(native, gear, close)
    return native, gear
  end

  local priorTidy = frame.sortBtn
  if priorTidy and (priorTidy == _G.BagItemAutoSortButton or not priorTidy._bbChrome17) then
    priorTidy = nil
  end
  local tidy = EnsureChromeButton(priorTidy, "BetterBackpackTidyBtn17", frame)
  tidy:ClearAllPoints()
  tidy:SetPoint("RIGHT", gear, "LEFT", -gap, 0)
  tidy:SetFrameLevel(level)
  StyleAutoSortTwin(tidy, "tidy", w, h)
  if not tidy._bbChromeWired then
    tidy._bbChromeWired = true
    tidy:SetScript("OnEnter", function(self)
      if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Úklid")
        GameTooltip:AddLine("SortBags + stack. Mimo boj.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
      end
    end)
    tidy:SetScript("OnLeave", function()
      if GameTooltip then
        GameTooltip:Hide()
      end
    end)
    tidy:SetScript("OnClick", function()
      local T = BetterBackpack.Modules.Tidy
      if T and T.SortBags then
        T.SortBags()
      end
    end)
  end
  tidy:SetAlpha(1)
  tidy:EnableMouse(true)
  tidy:Show()
  frame.sortBtn = tidy

  LogChromeOnce(tidy, gear, close)
  return tidy, gear
end

--[[
  Assign into forward-declared EnsureTitleChrome (must NOT use `local function` here).
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
    -- BagShelves: TOPRIGHT 2,1
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 1)
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
      -- Forever ButtonFrameOffsetTop≈2; leave room for broom|gear|X.
      tt:SetPoint("LEFT", anchor, "LEFT", BF_OFFSET + 4, BF_OFFSET_TOP > 0 and 0 or 0)
      tt:SetPoint("RIGHT", frame, "RIGHT", -110, 0)
      if tt.SetJustifyH then
        tt:SetJustifyH("LEFT")
      end
      if tt.SetFontObject then
        pcall(tt.SetFontObject, tt, GameFontNormal)
      end
      tt:SetText(title)
      tt:Show()
    end
  end)

  local tidy, gear = EnsureBagShelvesTitleChrome(frame, close)
  sortBtn = tidy
  settingsBtn = gear

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
  if not main then
    local orphan = _G.BetterBackpackFrame
    if orphan and not orphan._bbBuilt then
      -- Prior SetFrameStrata BLOCKED aborted build — reuse shell, finish below.
      main = nil
      content = nil
    end
  end
  if main then
    pcall(function()
      if main:GetParent() ~= UIParent then
        main:SetParent(UIParent)
      end
    end)
    KillPortrait(main)
    ApplyCombinedBagsChrome(main)
    pcall(EnsureTitleChrome, main)
    pcall(InstallBagHoverHighlight)
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
    pcall(function()
      if main:GetParent() ~= UIParent then
        main:SetParent(UIParent)
      end
      main:SetFrameLevel(500)
    end)
    pcall(EnsureTitleChrome, main)
    pcall(InstallBagHoverHighlight)
    return main
  end
  built:SetSize(456, 360)
  -- Forever: never SetFrameStrata on BetterBackpackFrame (ADDON_ACTION_BLOCKED
  -- still fires inside pcall and previously aborted EnsureMain). Level only.
  pcall(function()
    built:SetFrameLevel(500)
  end)
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
    if BetterBackpack._bbBuilding or BetterBackpack._bbClosing then
      return
    end
    local OpenClose = BetterBackpack.Modules.OpenClose
    if OpenClose and OpenClose._openBusy then
      return
    end
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

  -- Footer = CombinedBags CountContainer strip (free left, money right).
  local footer = CreateFrame("Frame", nil, built)
  footer:SetHeight(FOOTER_H)
  footer:EnableMouse(false)
  footer:SetPoint("BOTTOMLEFT", built, "BOTTOMLEFT", BF_OFFSET + 4, 6)
  footer:SetPoint("BOTTOMRIGHT", built, "BOTTOMRIGHT", -(BF_OFFSET + 4), 6)
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
    moneyFrame:SetPoint("BOTTOMRIGHT", built, "BOTTOMRIGHT", -(BF_OFFSET + 2), 6)
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
  BetterBackpack._bbBuilding = true
  pcall(EnsureTitleChrome, main)
  pcall(InstallBagHoverHighlight)
  pcall(PlaceOnScreen)
  BetterBackpack._bbBuilding = false
  -- Stay hidden until Layout.Show; do not fire NotifyHidden close race.
  pcall(function()
    main:Hide()
  end)
  return main
end

function Layout.IsShown()
  return main and main:IsShown() and true or false
end

function Layout.Show()
  local okEns = pcall(Layout.EnsureMain)
  if not okEns or not main then
    if BetterBackpack.RecordError then
      BetterBackpack.RecordError("Show", "EnsureMain failed")
    end
    return false
  end
  local p = Profile()
  if not p.enabled or p.safeMode then
    return false
  end

  pcall(function()
    if main:GetParent() ~= UIParent then
      main:SetParent(UIParent)
    end
    main:SetFrameLevel(500)
    main:SetAlpha(1)
    main:SetScale(1)
  end)
  if not main:GetWidth() or main:GetWidth() < 100 then
    pcall(function()
      main:SetSize(456, 360)
    end)
  end
  pcall(PlaceOnScreen)
  KillPortrait(main)
  ApplyCombinedBagsChrome(main)
  pcall(EnsureTitleChrome, main)
  pcall(InstallBagHoverHighlight)
  pcall(function()
    main:Show()
  end)
  pcall(Layout.Raise)
  pcall(DoLayout)
  pcall(function()
    main:SetAlpha(1)
    main:Show()
  end)
  pcall(PlaceOnScreen)
  ApplyCombinedBagsChrome(main)
  pcall(EnsureTitleChrome, main)
  local SearchChrome = Feat("Search")
  if SearchChrome and SearchChrome.EnsureChrome then
    pcall(SearchChrome.EnsureChrome, main)
  end
  UpdateFreeSpace()
  UpdateMoney()
  pcall(Layout.Raise)
  UpdateFreeSpace()
  local shown = main:IsShown() and true or false
  if not shown and BetterBackpack.RecordError then
    BetterBackpack.RecordError("Show", "IsShown=false after Show()")
  end
  return shown
end

function Layout.Hide()
  focusBagID = nil
  ClearBagMatchGlows()
  local p = Profile()
  if not p.enabled or p.safeMode then
    Layout.ReleaseNativeAutoSort()
  end
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
  -- Forever: no SetToplevel / SetFrameStrata on our frame — level only.
  pcall(function()
    if main:GetParent() ~= UIParent then
      main:SetParent(UIParent)
    end
    main:SetFrameLevel(500)
    if main.Raise then
      main:Raise()
    end
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
  local ranges = (Slots.InventoryBagRanges and Slots.InventoryBagRanges())
    or (Slots.PlayerBagRanges and Slots.PlayerBagRanges())
    or Slots.BagRanges()
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
