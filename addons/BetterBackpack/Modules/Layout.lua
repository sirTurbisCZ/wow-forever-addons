--[[
  BetterBackpack.Layout — category lanes + CombinedBags chrome (0.5.27).
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
  "junk", "consumable", "recipe", "reagent", "gem", "gear", "quest", "keys", "container", "trash", "other",
}

local TRASH = "trash"

local CATEGORY_LABELS = {
  trash = "Trash",
  junk = "Junk",
  consumable = "Consumables",
  recipe = "Recipes",
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
  if key == TRASH then
    return (CATEGORY_LABELS.trash or "Trash") .. "  |cffff6666(destroy)|r"
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
local combatVisuallyHidden = false
-- Forward decl: DoLayout runs before the definition body below (Lua 5.1 upvalue).
local EnsureTitleChrome
local ApplyCombinedBagsChrome
local SetBagMatchHighlight
local ClearBagMatchGlows
local InventoryOccupiedCount
local VisibleGridSignature

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
  if key == TRASH then
    return type(cats) == "table" and cats[key] == true
  end
  if not cats then
    return true
  end
  return cats[key] ~= false
end
Layout.CategoryEnabled = CategoryEnabled

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
  if eq(EC and EC.Recipe, CLASS.Recipe) or classID == CLASS.Recipe then
    return "recipe"
  end
  if eq(EC and EC.Reagent, CLASS.Reagent)
      or eq(EC and EC.Tradegoods, CLASS.Tradegoods)
      or eq(EC and EC.TradeGoods, CLASS.Tradegoods)
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
  if blob:find("recipe", 1, true) or blob:find("pattern", 1, true) or blob:find("plans", 1, true)
      or blob:find("schematic", 1, true) or blob:find("formula", 1, true)
  then
    return "recipe"
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

local function ItemLooksRecipe(itemID, itemType, itemSubType, classID, subClassID)
  if itemID and (classID == nil or itemType == nil) then
    if C_Item and C_Item.GetItemClassAndSubClass then
      local ok, c, s = pcall(C_Item.GetItemClassAndSubClass, itemID)
      if ok then
        classID = classID or c
        subClassID = subClassID or s
      end
    end
    local cid, sid, it, ist = InstantClass(itemID)
    classID = classID or cid
    subClassID = subClassID or sid
    itemType = itemType or it
    itemSubType = itemSubType or ist
  end
  if itemID and C_Item and C_Item.IsRecipeItem then
    local ok, yes = pcall(C_Item.IsRecipeItem, itemID)
    if ok and yes then
      return true
    end
  end
  if type(classID) == "number" and classID == CLASS.Recipe then
    return true
  end
  local EC = Enum and Enum.ItemClass
  if EC and type(EC.Recipe) == "number" and classID == EC.Recipe then
    return true
  end
  if classID == CLASS.Tradegoods and type(itemSubType) == "string" then
    local st = itemSubType:lower()
    if st:find("recipe", 1, true) or st == "recipe" then
      return true
    end
  end
  if itemID and C_Item and C_Item.GetItemName then
    local ok, name = pcall(C_Item.GetItemName, itemID)
    if ok and type(name) == "string" then
      local l = name:lower()
      if l:find("^recipe:", 1) or l:find("^pattern:", 1) or l:find("^plans:", 1)
          or l:find("^schematic:", 1) or l:find("^formula:", 1) then
        return true
      end
    end
  end
  local blob = (itemType or ""):lower() .. " " .. (itemSubType or ""):lower()
  if blob:find("recipe", 1, true) or blob:find("pattern", 1, true) or blob:find("plans", 1, true)
      or blob:find("schematic", 1, true) or blob:find("formula", 1, true)
  then
    return true
  end
  if itemID and C_Item and C_Item.GetItemSpell then
    local ok, spellName, spellID = pcall(C_Item.GetItemSpell, itemID)
    if ok and type(spellName) == "string" and spellName:lower():find("learn", 1, true) then
      return true
    end
    if ok and spellID and tonumber(spellID) then
      local name
      if C_Spell and C_Spell.GetSpellName then
        local okN, n = pcall(C_Spell.GetSpellName, spellID)
        if okN then
          name = n
        end
      elseif GetSpellInfo then
        local okN, n = pcall(GetSpellInfo, spellID)
        if okN then
          name = n
        end
      end
      if type(name) == "string" and name:lower():find("learn", 1, true) then
        return true
      end
    end
  end
  return false
end

-- Category from item class alone (no learned / custom rules).
local function ClassifyNatural(bag, slot, info, itemID)
  local quality = SafeNum(info.quality)
  local classID, subClassID, itemType, itemSubType, equipLoc = InstantClass(itemID)
  if ItemLooksRecipe(itemID, itemType, itemSubType, classID, subClassID) then
    return "recipe"
  end
  local mapped = MapClassID(classID, subClassID, quality)
  if mapped then
    return mapped
  end
  mapped = MapTypeString(itemType, itemSubType)
  if mapped then
    return mapped
  end
  if type(equipLoc) == "string" and equipLoc ~= "" then
    local el = equipLoc:upper()
    if el == "INVTYPE_FINGER" or el == "INVTYPE_NECK" or el == "INVTYPE_TRINKET"
        or el == "INVTYPE_CLOAK" or el:find("WEAPON", 1, true)
    then
      return "gear"
    end
  end
  if Slots.IsKeyringBag and Slots.IsKeyringBag(bag) then
    return "keys"
  end
  if classID == CLASS.Key then
    return "keys"
  end
  if quality == 0 and not Slots.IsReagentBag(bag) and not (Slots.IsKeyringBag and Slots.IsKeyringBag(bag)) then
    return "junk"
  end
  if Slots.IsReagentBag(bag) then
    return "reagent"
  end
  return "other"
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
  return ClassifyNatural(bag, slot, info, itemID), info
end

--- Lane an item lands in with no learned rule (disabled built-in → Other).
function Layout.NaturalLane(bag, slot)
  if not C_Container or not C_Container.GetContainerItemInfo then
    return "other"
  end
  local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
  if not ok or type(info) ~= "table" then
    return "other"
  end
  local cat = ClassifyNatural(bag, slot, info, ResolveItemID(bag, slot, info)) or "other"
  if cat == "weapon" or cat == "armor" then
    cat = "gear"
  end
  if not CategoryEnabled(cat) then
    cat = "other"
  end
  return cat
end

--- Natural lane for an itemID that may not be in the bags (Trash ghosts).
function Layout.NaturalLaneForID(itemID)
  local q
  if C_Item and C_Item.GetItemQualityByID then
    local ok, res = pcall(C_Item.GetItemQualityByID, itemID)
    q = ok and SafeNum(res) or nil
  end
  if q == nil and GetItemInfo then
    local ok, _, _, res = pcall(GetItemInfo, itemID)
    q = ok and SafeNum(res) or nil
  end
  local cat = ClassifyNatural(0, 0, { quality = q }, itemID) or "other"
  if cat == "weapon" or cat == "armor" then
    cat = "gear"
  end
  if not CategoryEnabled(cat) then
    cat = "other"
  end
  return cat
end

--[[
  Drag-teach (0.5.17): an item picked up from our bag and dropped on a lane header, on an
  item in another lane is not moved — its itemID is taught to that lane
  (profile.itemRules) and the cursor is cleared, so the item stays in its bag slot.
]]
function Layout.SetDropHints(on)
  for _, sf in pairs(sectionFrames) do
    if sf.header and sf.header.dropHl then
      sf.header.dropHl:SetShown(on and sf:IsShown() and true or false)
    end
  end
  local Settings = Feat("Settings")
  if Settings and Settings.SetDropHints then
    pcall(Settings.SetDropHints, on)
  end
end

local function CursorHoldingItem()
  if not GetCursorInfo then
    return false
  end
  local ok, kind = pcall(GetCursorInfo)
  return ok and kind == "item"
end

local function HeldDragSource()
  local src = Slots.GetDragSource and Slots.GetDragSource()
  if not src or not GetCursorInfo then
    return nil
  end
  local ok, kind, id = pcall(GetCursorInfo)
  if not ok or kind ~= "item" then
    return nil
  end
  if not src.itemID and src.bag ~= nil and src.slot ~= nil and Slots.ItemIDForBagSlot then
    src.itemID = Slots.ItemIDForBagSlot(src.bag, src.slot)
  end
  if not src.itemID then
    src.itemID = SafeNum(id)
  end
  if not src.itemID then
    return nil
  end
  local held = SafeNum(id)
  if held and held ~= src.itemID then
    return nil
  end
  return src
end

local function EndDrag()
  pcall(ClearCursor)
  if Slots.ClearDragSource then
    Slots.ClearDragSource()
  end
  Layout.SetDropHints(false)
end

function Layout.DropOnLane(key)
  if type(key) ~= "string" then
    return false
  end
  local src = HeldDragSource()
  if not src then
    return false
  end
  if key == TRASH then
    local T = Feat("Trash")
    if not T then
      return false
    end
    -- Cursor keeps the item: Trash deletes it inside this click.
    if Slots.ClearDragSource then
      Slots.ClearDragSource()
    end
    Layout.SetDropHints(false)
    T.HandleDrop(src)
    return true
  end
  local CC = Feat("CustomCategories")
  if not (CC and CC.Teach) then
    return false
  end
  EndDrag()
  CC.Teach(src.itemID, key, Layout.NaturalLane(src.bag, src.slot))
  return true
end

function Layout.DropNewLane()
  local src = HeldDragSource()
  if not src then
    return false
  end
  EndDrag()
  local CC = Feat("CustomCategories")
  if CC and CC.PromptNew then
    CC.PromptNew(src.itemID)
  end
  return true
end

--- Lane key under the mouse, for the Trash ghost fake drag.
function Layout.LaneUnderMouse()
  local function Over(f)
    return f and f:IsVisible() and f:IsMouseOver()
  end
  for key, sf in pairs(sectionFrames) do
    if Over(sf) and Over(sf.header) then
      return key
    end
  end
  local hit
  if Slots.ForEach then
    Slots.ForEach(function(btn)
      if not hit and btn._bbLane and (btn:GetAlpha() or 0) > 0 and Over(btn) then
        local ok, on = pcall(btn.IsMouseEnabled, btn)
        if not ok or on then
          hit = btn._bbLane
        end
      end
    end)
  end
  if hit then
    return hit
  end
  local Settings = Feat("Settings")
  if Settings and Settings.LaneUnderMouse then
    return Settings.LaneUnderMouse()
  end
  return nil
end

local cursorWatch = CreateFrame("Frame")
pcall(cursorWatch.RegisterEvent, cursorWatch, "CURSOR_CHANGED")
pcall(cursorWatch.RegisterEvent, cursorWatch, "CURSOR_UPDATE")
cursorWatch:SetScript("OnEvent", function()
  local ok, kind = pcall(GetCursorInfo)
  if not ok or kind ~= "item" then
    if Slots.ClearDragSource then
      Slots.ClearDragSource()
    end
    Layout.SetDropHints(false)
  end
end)

-- While open the frame only grows (new loot); collapse / search / using items never shrink it.
-- Reset on close, so the next open refits to the full unfiltered layout.
local stickyCols, stickyH

local function IsFiltering()
  local S, F = Feat("Search"), Feat("Filter")
  local q = S and S.GetQuery and S.GetQuery() or ""
  local f = F and F.GetCategory and F.GetCategory()
  return (type(q) == "string" and q ~= "") or f ~= nil
end

-- unfiltered=true ignores Search/Filter: used to size the frame so filtering never resizes it.
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
  for _, list in pairs(buckets) do
    table.sort(list, function(a, b)
      if a.bag ~= b.bag then
        return a.bag < b.bag
      end
      return a.slot < b.slot
    end)
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
    "slots %s used/total=%d/%d",
    tostring(parts or "?"),
    used or 0,
    total or 0
  )
  if BetterBackpack.TraceAction then
    BetterBackpack.TraceAction("BAGKEY " .. msg)
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

local function CharacterBagsPanelOpen()
  local cf = _G.CharacterFrame
  return cf and cf.IsShown and cf:IsShown()
end

local function EnsureBagIndicator(btn)
  if not btn then
    return nil
  end
  local ind = btn.BagIndicator
  if not ind then
    ind = btn:CreateTexture(nil, "ARTWORK", nil, -1)
    btn.BagIndicator = ind
  end
  pcall(function()
    local ok = pcall(ind.SetAtlas, ind, "bags-glow-white", true)
    if not ok then
      ind:SetColorTexture(0.2, 0.55, 0.85, 0.35)
    end
    if ind.SetBlendMode then
      ind:SetBlendMode("BLEND")
    end
    ind:SetAlpha(0.4)
    if ind.SetDrawLayer then
      ind:SetDrawLayer("ARTWORK", -2)
    end
    ind:ClearAllPoints()
    ind:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    ind:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
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
    if not Layout.IsShown() or CharacterBagsPanelOpen() then
      ClearBagMatchGlows()
      return
    end
    Slots.ForEach(function(btn)
      if not btn or (btn:GetAlpha() or 0) < 0.5 then
        ShowBagIndicator(btn and btn.BagIndicator, false)
        return
      end
      local occ = Slots.SlotOccupied and btn._bbBag ~= nil and btn._bbSlot ~= nil
          and Slots.SlotOccupied(btn._bbBag, btn._bbSlot)
      local show = highlight and occ and BagsMatchForHighlight(btn._bbBag, bagID)
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
  if bagID ~= nil then
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
      if not Layout.IsShown() or CharacterBagsPanelOpen() then
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
  pcall(HookBagBarButtons)
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
        if not Layout.IsShown() or CharacterBagsPanelOpen() then
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
  pcall(function()
    local cf = _G.CharacterFrame
    if cf and not cf._bbGlowSuppress and cf.HookScript then
      cf._bbGlowSuppress = true
      cf:HookScript("OnShow", function()
        ClearBagMatchGlows()
      end)
    end
  end)
end

local function HeaderShiftDown(header)
  if IsShiftKeyDown and IsShiftKeyDown() then
    return true
  end
  return header and header._bbShiftDown == true
end

local function HeaderCtrlDown(header)
  if IsControlKeyDown and IsControlKeyDown() then
    return true
  end
  return header and header._bbCtrlDown == true
end

--- Lane-wide bulk: Ctrl+Shift+RMB (Shift alone = collapse / drop only on header).
local function HeaderLaneBulkDown(header)
  return HeaderShiftDown(header) and HeaderCtrlDown(header)
end

local function HeaderInvokeBulkTransfer(header, laneKey)
  header._bbShiftDown = nil
  header._bbCtrlDown = nil
  if BetterBackpack.TraceAction then
    BetterBackpack.TraceAction("BULK header lane=" .. tostring(laneKey), "|cff88ccffBulk|r")
  elseif BetterBackpack.Print then
    BetterBackpack.Print("|cff88ccffBulk|r header Ctrl+Shift+RMB · lane=" .. tostring(laneKey))
  end
  local BT = BetterBackpack.Modules.BulkTransfer or Feat("BulkTransfer")
  if BT and BT.TransferLane then
    local ok, err = pcall(BT.TransferLane, laneKey)
    if not ok then
      if BetterBackpack.RecordError then
        BetterBackpack.RecordError("TransferLane", err)
      elseif BetterBackpack.Print then
        BetterBackpack.Print("|cff88ccffBulk|r TransferLane error · " .. tostring(err))
      end
    end
  elseif BetterBackpack.RecordError then
    BetterBackpack.RecordError("BulkTransfer", "module not loaded")
  elseif BetterBackpack.Print then
    BetterBackpack.Print("|cff88ccffBulk|r ERROR — BulkTransfer module not loaded (TOC/Core)")
  end
  return true
end

local function HeaderShiftRmb(header, laneKey)
  if CursorHoldingItem() then
    return false
  end
  if not HeaderLaneBulkDown(header) then
    return false
  end
  if Layout.DropOnLane(laneKey) then
    header._bbShiftDown = nil
    header._bbCtrlDown = nil
    return true
  end
  return HeaderInvokeBulkTransfer(header, laneKey)
end

local function WireSectionHeader(key, header)
  if not header then
    return
  end
  header._bbLane = key
  header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  header:SetScript("OnMouseDown", function(self, button)
    if button == "RightButton" then
      self._bbShiftDown = (IsShiftKeyDown and IsShiftKeyDown()) or false
      self._bbCtrlDown = (IsControlKeyDown and IsControlKeyDown()) or false
    elseif not (IsShiftKeyDown and IsShiftKeyDown()) then
      self._bbShiftDown = nil
      self._bbCtrlDown = nil
    end
  end)
  header:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and CursorHoldingItem() then
      Layout.DropOnLane(key)
      return
    end
    if button == "RightButton" then
      local bulk = HeaderLaneBulkDown(self)
      if bulk and not CursorHoldingItem() then
        if BetterBackpack.TraceAction then
          BetterBackpack.TraceAction(string.format(
            "BULK header MouseUp lane=%s ctrl+shift=%s",
            tostring(key),
            tostring(bulk)
          ))
        end
        if Layout.DropOnLane(key) then
          self._bbShiftDown = nil
          self._bbCtrlDown = nil
          self._bbBulkHandled = true
          return
        end
        HeaderInvokeBulkTransfer(self, key)
        self._bbBulkHandled = true
      end
    end
  end)
  header:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      if self._bbBulkHandled then
        self._bbBulkHandled = nil
        return
      end
      if HeaderShiftRmb(self, key) then
        return
      end
    end
    if Layout.DropOnLane(key) then
      return
    end
    if CursorHoldingItem() then
      return
    end
    local T = Feat("Trash")
    if T and T.FlushOnClick then
      T.FlushOnClick()
    end
    local p = Profile()
    if type(p.collapsed) ~= "table" then
      p.collapsed = {}
    end
    p.collapsed[key] = not p.collapsed[key]
    Layout.Relayout()
  end)
end

local function EnsureSection(key)
  local sf = sectionFrames[key]
  if sf then
    if sf.header then
      WireSectionHeader(key, sf.header)
    end
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
  header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  header:RegisterForDrag("LeftButton")
  header:EnableMouse(true)
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
  local dropHl = header:CreateTexture(nil, "BACKGROUND")
  dropHl:SetAllPoints()
  dropHl:SetColorTexture(1, 0.82, 0, 0.12)
  dropHl:Hide()
  header.dropHl = dropHl
  header:SetScript("OnReceiveDrag", function()
    Layout.DropOnLane(key)
  end)
  WireSectionHeader(key, header)
  header:SetScript("OnEnter", function(self)
    self.title:SetTextColor(1, 1, 1)
    local BT = Feat("BulkTransfer")
    local bulkLine = BT and BT.HeaderTooltipLine and BT.HeaderTooltipLine()
    if bulkLine and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:ClearLines()
      GameTooltip:SetText(Layout.GetCategoryLabel(key), 1, 1, 1)
      GameTooltip:AddLine(" ", 1, 1, 1, 0)
      GameTooltip:AddLine(bulkLine, 0.2, 1, 0.4, true)
      GameTooltip:Show()
    elseif key == TRASH and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText("Trash — destroys items")
      GameTooltip:AddLine("Not the Junk lane (grey loot only sorts there).", 1, 0.82, 0, true)
      GameTooltip:AddLine("Drop a white/grey stack here to destroy it and auto-destroy future loot.", 0.7, 0.7, 0.7, true)
      GameTooltip:Show()
    end
  end)
  header:SetScript("OnLeave", function(self)
    local c = NORMAL_FONT_COLOR
    if c and c.r then
      self.title:SetTextColor(c.r, c.g, c.b)
    else
      self.title:SetTextColor(1, 0.82, 0)
    end
    if GameTooltip then
      GameTooltip:Hide()
    end
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
    local filtering = IsFiltering()
    local sizing = filtering and MergedLists(CollectBuckets(true)) or lists
    -- Custom lanes and Trash are drop targets: drawn even when empty (header + "(0)"),
    -- except while a search / filter hides lanes without matches.
    local function IsCustom(key)
      return key == TRASH or (type(key) == "string" and key:find("^custom_", 1) ~= nil)
    end

    -- Trash ghosts: one per taught itemID, UI-only (no bag slot), appended after real stacks.
    local TrashMod = Feat("Trash")
    local ghostIDs = {}
    if TrashMod and lists[TRASH] and TrashMod.TaughtIDs then
      ghostIDs = TrashMod.TaughtIDs()
      local target = filtering and sizing or lists
      if target[TRASH] then
        for g = 1, #ghostIDs do
          target[TRASH][#target[TRASH] + 1] = { ghost = ghostIDs[g] }
        end
      end
    end
    local ghostUsed = {}

    -- Grid width = widest unfiltered lane (capped at maxCols), never narrower than this open's max.
    local widest = 0
    for _, list in pairs(sizing) do
      if #list > widest then
        widest = #list
      end
    end
    local cols = math.max(math.min(widest, maxCols), math.min(MIN_COLS, maxCols))
    if stickyCols and stickyCols > cols then
      cols = math.min(stickyCols, maxCols)
    end
    local contentW = cols * SLOT + (cols - 1) * PAD

    local lanesH = 0
    for i = 1, #order do
      local list = sizing[order[i]]
      if list and (#list > 0 or IsCustom(order[i])) then
        lanesH = lanesH + HEADER_H + HEADER_PAD
        if #list > 0 then
          lanesH = lanesH + math.ceil(#list / cols) * (SLOT + PAD) - PAD
        end
        lanesH = lanesH + SECTION_GAP
      end
    end

    for i = 1, #order do
      local key = order[i]
      if CategoryEnabled(key) then
        local list = lists[key] or {}
        if #list > 0 or (IsCustom(key) and not filtering) then
          any = true
          local sf = EnsureSection(key)
          sf:ClearAllPoints()
          sf:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
          sf:SetWidth(contentW)
          sf:Show()
          local collapsed = IsCollapsed(key)
          local shownCount = #list
          if key == TRASH and not filtering then
            shownCount = #ghostIDs
          end
          SetHeaderState(sf.header, Layout.GetCategoryLabel(key), shownCount, collapsed)
          y = y + HEADER_H + HEADER_PAD
          if not collapsed and #list > 0 then
            local col, row = 0, 0
            local rows = math.ceil(#list / cols)
            -- Parent to main (absolute), not content — content sat under Inset.Bg.
            local parentFrame = main or content
            for j = 1, #list do
              local entry = list[j]
              local px = INSET_X + col * (SLOT + PAD)
              local py = TOP_CHROME + y + row * (SLOT + PAD)
              if entry.ghost then
                if TrashMod and TrashMod.PlaceGhost then
                  TrashMod.PlaceGhost(entry.ghost, parentFrame, px, py)
                  ghostUsed[entry.ghost] = true
                end
              else
                local btn = Slots.Acquire(entry.bag, entry.slot)
                if btn then
                  used[btn] = true
                  btn._bbLane = key
                  Slots.Place(btn, parentFrame, px, py, true)
                  if SM and SM.ApplyDisplayCount then
                    SM.ApplyDisplayCount(btn, entry)
                  end
                  if TrashMod and TrashMod.SetPendingVeil then
                    TrashMod.SetPendingVeil(btn, key == TRASH)
                  end
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

    if TrashMod and TrashMod.HideGhosts then
      TrashMod.HideGhosts(ghostUsed)
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
    if stickyH and stickyH > height then
      height = stickyH
      contentH = height - TOP_CHROME - BOT_CHROME
    end
    stickyCols, stickyH = cols, height
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
    pcall(ApplyCombinedBagsChrome, main)
    pcall(EnsureTitleChrome, main)
    local SearchChrome = Feat("Search")
    if SearchChrome and SearchChrome.EnsureChrome then
      pcall(SearchChrome.EnsureChrome, main)
    end
    UpdateFreeSpace()
    UpdateMoney()
    if focusBagID ~= nil then
      SetBagMatchHighlight(focusBagID, true)
    end
    BetterBackpack._bbLastOccupiedCount = InventoryOccupiedCount()
    BetterBackpack._bbGridSig = VisibleGridSignature()
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

local function CreateChromedFrame(globalName)
  -- Named frame persists across failed EnsureMain — always reuse, never double-create.
  -- Prefer ButtonFrameTemplate (CombinedBags-class chrome: TitleContainer, Close, Inset, Bg).
  -- Forever may fire ADDON_ACTION_BLOCKED on template SetFrameStrata — that is an *event*,
  -- not a hard abort when CreateFrame is pcall'd. Never call SetFrameStrata ourselves.
  local frame = _G[globalName]
  if not frame then
    local templates = {
      "ButtonFrameTemplate",
      "BasicFrameTemplateWithInset",
      "BasicFrameTemplate",
    }
    for i = 1, #templates do
      local tmpl = templates[i]
      local ok, f = pcall(function()
        return CreateFrame("Frame", globalName, UIParent, tmpl)
      end)
      frame = _G[globalName]
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
    frame = CreateFrame("Frame", globalName, UIParent)
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

local function CreateBagPanel()
  return CreateChromedFrame("BetterBackpackFrame")
end

--- Same CombinedBags chrome as the bag (Settings panel).
function Layout.CreateChromedPanel(globalName)
  return CreateChromedFrame(globalName)
end

function Layout.ApplyChrome(frame)
  KillPortrait(frame)
  ApplyCombinedBagsChrome(frame)
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

local CHROME_VER = 33 -- 0.5.27: broom Close-twin size sync every layout
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

local function CloseButtonSize(close)
  if not close then
    return MeasureAutoSortSize()
  end
  local cw, ch = close:GetWidth(), close:GetHeight()
  if type(cw) == "number" and cw >= 8 and type(ch) == "number" and ch >= 8 then
    return cw, ch
  end
  return MeasureAutoSortSize()
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
    "chrome tidy=%s gear=%s close=%s ver=%d",
    wh(tidy),
    wh(gear),
    wh(close),
    CHROME_VER
  )
  if BetterBackpack.TraceAction then
    BetterBackpack.TraceAction("BAGKEY " .. msg)
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
      if d.w and btn._bbCloseRef then
        t:SetAllPoints(btn)
      elseif d.w then
        t:SetSize(d.w, d.h)
        t:SetPoint(d.p, btn, d.rp, d.x, d.y)
      else
        t:SetAllPoints(btn)
      end
    end
  end)
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
local function StretchButtonStateArt(btn)
  for _, which in ipairs({ "Normal", "Pushed", "Highlight" }) do
    local t = btn["Get" .. which .. "Texture"] and btn["Get" .. which .. "Texture"](btn)
    if t then
      pcall(function()
        t:ClearAllPoints()
        t:SetAllPoints(btn)
      end)
    end
  end
end

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
    StretchButtonStateArt(btn)
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

--[[
  broom | gear in the Close button's own chrome (0.5.15): plate = Close normal / pushed /
  highlight art read live (same atlas or file, same size). Its X is covered by a patch of
  the same plate's interior (top-middle band, clear of the X arms); a gold glyph sits on
  top. Broom glyph = autosort atlas cropped inside its bevel, drawn ADD so its dark plate
  drops out and only the gold broom remains. No foreign plates, no BagItemAutoSortButton reparent.
]]
local function TexRegion(tex)
  if not tex then
    return nil
  end
  local atlas = SafeAtlas(tex)
  if atlas then
    if not (C_Texture and C_Texture.GetAtlasInfo) then
      return nil
    end
    local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
    local file = ok and info and (info.file or info.filename)
    if file and info.leftTexCoord then
      return file, info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    end
    return nil
  end
  local file = SafeTexture(tex)
  if not file then
    return nil
  end
  local ok, ulx, uly, _, _, _, _, lrx, lry = pcall(tex.GetTexCoord, tex)
  if not ok or type(ulx) ~= "number" or IsSecret(ulx) or type(lry) ~= "number" then
    ulx, uly, lrx, lry = 0, 0, 1, 1
  end
  return file, ulx, lrx, uly, lry
end

local function SubRegion(t, file, l, r, top, b, u0, u1, v0, v1)
  t:SetTexture(file)
  t:SetTexCoord(l + (r - l) * u0, l + (r - l) * u1, top + (b - top) * v0, top + (b - top) * v1)
end

local function PaintCover(btn, pushed)
  local close, cover = btn._bbCloseRef, btn._bbCover
  if not (close and cover) then
    return
  end
  local file, l, r, t, b = TexRegion(pushed and close:GetPushedTexture() or close:GetNormalTexture())
  if not file then
    file, l, r, t, b = TexRegion(close:GetNormalTexture())
  end
  if file then
    SubRegion(cover, file, l, r, t, b, 0.44, 0.56, 0.20, 0.30)
    cover:Show()
  else
    cover:Hide()
  end
end

local function PaintGlyph(icon, kind, w, h)
  icon:SetBlendMode("BLEND")
  icon:SetDesaturated(false)
  icon:SetVertexColor(1, 1, 1)
  icon:SetTexCoord(0, 1, 0, 1)
  local m = math.min(w, h)
  if kind == "tidy" then
    -- Same glyph footprint as gear; crop autosort atlas padding so broom fills the bevel.
    icon:SetSize(math.floor(m * 0.62 + 0.5), math.floor(m * 0.62 + 0.5))
    local ok, info = false, nil
    if C_Texture and C_Texture.GetAtlasInfo then
      ok, info = pcall(C_Texture.GetAtlasInfo, "bags-button-autosort-up")
    end
    local file = ok and info and (info.file or info.filename)
    if file and info.leftTexCoord then
      SubRegion(icon, file, info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord,
        0.28, 0.72, 0.28, 0.72)
      icon:SetBlendMode("ADD")
      icon:SetDesaturated(true)
      icon:SetVertexColor(1, 0.82, 0.18)
    else
      icon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    end
    return
  end
  icon:SetSize(math.floor(m * 0.62 + 0.5), math.floor(m * 0.62 + 0.5))
  for _, atlas in ipairs(GEAR_ATLASES) do
    if AtlasExists(atlas) and pcall(icon.SetAtlas, icon, atlas) then
      icon:SetDesaturated(true)
      icon:SetVertexColor(1, 0.82, 0.18)
      return
    end
  end
  icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
  icon:SetTexCoord(0.15, 0.85, 0.15, 0.85)
end

local function StyleCloseTwin(btn, kind, close, w, h)
  btn:SetSize(w, h)
  pcall(function()
    btn:SetDisabledTexture(nil)
  end)
  local n = NativeArt(close:GetNormalTexture(), close)
  local p = NativeArt(close:GetPushedTexture(), close)
  local hl = NativeArt(close.GetHighlightTexture and close:GetHighlightTexture(), close)
  SetStateArt(btn, "Normal", n)
  SetStateArt(btn, "Pushed", p or n)
  SetStateArt(btn, "Highlight", hl or SQUARE_HILIGHT)
  btn._bbCloseRef = close

  if btn._bbFill then
    btn._bbFill:Hide()
  end
  local cover = btn._bbCover
  if not cover then
    cover = btn:CreateTexture(nil, "ARTWORK", nil, 7)
    btn._bbCover = cover
  end
  local inset = math.floor(math.min(w, h) * 0.18 + 0.5)
  cover:ClearAllPoints()
  cover:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset)
  cover:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
  PaintCover(btn, false)

  local icon = btn._bbIcon
  if not icon then
    icon = btn:CreateTexture(nil, "OVERLAY")
    btn._bbIcon = icon
  end
  if not btn._bbCloseHooks then
    btn._bbCloseHooks = true
    btn:HookScript("OnMouseDown", function(self)
      if self._bbCloseRef then
        PaintCover(self, true)
      end
      if self._bbIcon then
        self._bbIcon:SetPoint("CENTER", self, "CENTER", 1, -1)
      end
    end)
    btn:HookScript("OnMouseUp", function(self)
      if self._bbCloseRef then
        PaintCover(self, false)
      end
      if self._bbIcon then
        self._bbIcon:SetPoint("CENTER", self, "CENTER", 0, 0)
      end
    end)
  end
  icon:ClearAllPoints()
  icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
  PaintGlyph(icon, kind, w, h)
  icon:Show()
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

local function ApplyCloseTwinSize(btn, close, w, h)
  if not btn then
    return
  end
  btn:SetSize(w, h)
  pcall(function()
    btn:SetWidth(w)
    btn:SetHeight(h)
  end)
end

local function EnsureBagShelvesTitleChrome(frame, close)
  HideLegacyChromeOnce()

  -- broom | gear | X: live Close GetWidth/GetHeight every layout (never native 25×23).
  local w, h = CloseButtonSize(close)
  local level = (close and close:GetFrameLevel()) or ((frame:GetFrameLevel() or 1) + 520)
  local gap = 2

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
  ApplyCloseTwinSize(gear, close, w, h)
  if close then
    StyleCloseTwin(gear, "settings", close, w, h)
  else
    StyleAutoSortTwin(gear, "settings", w, h)
  end
  if not gear._bbChromeWired then
    gear._bbChromeWired = true
    gear:SetScript("OnEnter", function(self)
      if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Settings")
        GameTooltip:AddLine("Lanes on/off, custom lanes, learned items.", 0.7, 0.7, 0.7, true)
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

  local priorTidy = frame.sortBtn
  if priorTidy and (priorTidy == _G.BagItemAutoSortButton or not priorTidy._bbChrome17) then
    priorTidy = nil
  end
  local tidy = EnsureChromeButton(priorTidy, "BetterBackpackTidyBtn17", frame)
  tidy:ClearAllPoints()
  tidy:SetPoint("RIGHT", gear, "LEFT", -gap, 0)
  tidy:SetFrameLevel(level)
  ApplyCloseTwinSize(tidy, close, w, h)
  if close then
    StyleCloseTwin(tidy, "tidy", close, w, h)
  else
    StyleAutoSortTwin(tidy, "tidy", w, h)
  end
  if not tidy._bbChromeWired then
    tidy._bbChromeWired = true
    tidy:SetScript("OnEnter", function(self)
      if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Tidy")
        GameTooltip:AddLine("SortBags + stack merge. Out of combat only.", 0.7, 0.7, 0.7, true)
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

local function WireCloseButton(frame)
  if not frame then
    return
  end
  local close = frame.CloseButton
  if not close then
    return
  end
  if close._bbCloseWired then
    return
  end
  close._bbCloseWired = true
  close:SetScript("OnClick", function()
    local OC = BetterBackpack.Modules.OpenClose
    if OC and OC.CloseOurs then
      OC.CloseOurs({ closeBlizzard = true, suppress = 0.25 })
    elseif frame.Hide then
      frame:Hide()
    end
  end)
end

--[[
  Assign into forward-declared EnsureTitleChrome (must NOT use `local function` here).
]]
EnsureTitleChrome = function(frame)
  if not frame then
    return
  end
  if InCombatLockdown and InCombatLockdown() then
    return
  end
  local ok, err = pcall(function()
    local close = frame.CloseButton
    if not close then
      close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
      frame.CloseButton = close
    end
    if close then
      close:ClearAllPoints()
      close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 1)
      close:SetFrameLevel((frame:GetFrameLevel() or 1) + 520)
      close:Show()
      WireCloseButton(frame)
    end

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

    local tidy, gear = EnsureBagShelvesTitleChrome(frame, close)
    sortBtn = tidy
    settingsBtn = gear

    if frame._bbChrome then
      pcall(frame._bbChrome.Hide, frame._bbChrome)
    end
    frame._bbChromeVer = CHROME_VER

    if frame.TitleContainer then
      local need = (frame:GetFrameLevel() or 1) + 50
      if (frame.TitleContainer:GetFrameLevel() or 1) >= need then
        frame.TitleContainer:SetFrameLevel(need)
      end
    end
  end)
  if not ok and BetterBackpack and BetterBackpack.RecordError then
    BetterBackpack.RecordError("EnsureTitleChrome", err)
  end
end

function Layout.EnsureMain()
  -- Recover half-built frame (error mid-EnsureMain left empty chrome).
  if main and not content then
    DestroyHalfBuilt()
  end
  if main and content and main._bbBuilt then
    pcall(function()
      if main:GetParent() ~= UIParent then
        main:SetParent(UIParent)
      end
    end)
    return main
  end
  local inCombat = InCombatLockdown and InCombatLockdown()
  if inCombat then
    local orphan = _G.BetterBackpackFrame
    if orphan and orphan._bbBuilt and orphan._bbContent then
      main = orphan
      content = orphan._bbContent
      freeFs = orphan.freeFs or freeFs
      moneyFs = orphan._bbMoneyFs or moneyFs
      emptyLabel = orphan._bbEmpty or emptyLabel
      return main
    end
    return nil
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
    pcall(ApplyCombinedBagsChrome, main)
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
    pcall(ApplyCombinedBagsChrome, self)
    local title = CombinedBagTitle()
    if self.SetTitle then
      pcall(self.SetTitle, self, title)
    elseif self.TitleText then
      self.TitleText:SetText(title)
    elseif self.title then
      self.title:SetText(title)
    end
  end)
  built:SetScript("OnHide", function(self)
    if BetterBackpack._bbBuilding or BetterBackpack._bbClosing or BetterBackpack._bbEscRearm then
      if BetterBackpack._bbEscRearm and Layout.SyncBagUISpecialFrame then
        Layout.SyncBagUISpecialFrame()
      end
      return
    end
    local OpenClose = BetterBackpack.Modules.OpenClose
    if OpenClose and OpenClose._openBusy then
      return
    end
    if OpenClose and OpenClose.NotifyHidden then
      OpenClose.NotifyHidden()
    end
    if Layout.SyncBagUISpecialFrame then
      Layout.SyncBagUISpecialFrame()
    end
    if BetterBackpack._bbKeepShown and self and self.IsShown and not self:IsShown() then
      local repark = function()
        if InCombatLockdown and InCombatLockdown() then
          return
        end
        if Layout.EnsureCombatShell then
          pcall(Layout.EnsureCombatShell)
        end
      end
      if C_Timer and C_Timer.After then
        C_Timer.After(0, repark)
      else
        repark()
      end
    end
  end)

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
    WireCloseButton(built)
  end

  -- Native CombinedBags chrome (AutoSort + gear).
  pcall(EnsureTitleChrome, built)

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

local function FrameAlpha(f)
  if not f or not f.GetAlpha then
    return 0
  end
  local a = 1
  pcall(function()
    a = f:GetAlpha() or 1
  end)
  return a
end

-- Open for B XOR: combat uses alpha + flag (Show may fail in lockdown).
function Layout.IsBagFrameVisible()
  if combatVisuallyHidden then
    return false
  end
  local f = main or _G.BetterBackpackFrame
  if not f then
    return false
  end
  if FrameAlpha(f) < 0.05 then
    return false
  end
  if InCombatLockdown and InCombatLockdown() then
    return f._bbBuilt and FrameAlpha(f) >= 0.05 and true or false
  end
  if not f.IsShown or not f:IsShown() then
    return false
  end
  return true
end

function Layout.IsShown()
  return Layout.IsBagFrameVisible()
end

local BAG_SPECIAL_FRAME = "BetterBackpackFrame"
local ALPHA_ESC_MIN = 0.05

local function BagFrameListedInUISpecial()
  if not UISpecialFrames then
    return false
  end
  for i = 1, #UISpecialFrames do
    if UISpecialFrames[i] == BAG_SPECIAL_FRAME then
      return true
    end
  end
  return false
end

-- Always purge BB from UISpecialFrames first (hard-remove when alpha 0 / parked).
function Layout.StripBagSpecialFrame()
  if not UISpecialFrames then
    return
  end
  for i = #UISpecialFrames, 1, -1 do
    if UISpecialFrames[i] == BAG_SPECIAL_FRAME then
      table.remove(UISpecialFrames, i)
    end
  end
end

function Layout.EscDebugTrace(phase, detail)
  local p = Profile()
  local silent = BetterBackpack.SilentTraceEnabled and BetterBackpack.SilentTraceEnabled()
  if not silent and not (p and p.debug) then
    return
  end
  local f = main or _G.BetterBackpackFrame
  local alpha = f and FrameAlpha(f) or 0
  local line = string.format(
    "esc · %s · vis=%s listed=%s a=%.2f fh=%s keep=%s %s",
    tostring(phase or "?"),
    tostring(Layout.IsBagFrameVisible() and true or false),
    tostring(BagFrameListedInUISpecial()),
    alpha,
    tostring(combatVisuallyHidden),
    tostring(BetterBackpack._bbKeepShown),
    detail and tostring(detail) or ""
  )
  if BetterBackpack.TraceAction then
    BetterBackpack.TraceAction("BAGKEY ESC " .. line, nil)
  elseif BetterBackpack.Modules and BetterBackpack.Modules.SessionLog and BetterBackpack.Modules.SessionLog.RecordAction then
    pcall(BetterBackpack.Modules.SessionLog.RecordAction, "BAGKEY ESC " .. line)
  end
  local db = Config and Config.EnsureDB and Config.EnsureDB()
  if db then
    db.bagEscTrace = db.bagEscTrace or {}
    db.bagEscTrace[#db.bagEscTrace + 1] = {
      t = (time and time()) or 0,
      phase = tostring(phase),
      detail = detail and tostring(detail) or "",
      userVisible = Layout.IsBagFrameVisible() and true or false,
      listed = BagFrameListedInUISpecial(),
      alpha = alpha,
      combatHide = combatVisuallyHidden,
      keepShown = BetterBackpack._bbKeepShown and true or false,
      frameShown = f and f.IsShown and f:IsShown() and true or false,
    }
    while #db.bagEscTrace > 20 do
      table.remove(db.bagEscTrace, 1)
    end
  end
end

function Layout.SyncBagUISpecialFrame()
  if not UISpecialFrames then
    return
  end
  local f = main or _G.BetterBackpackFrame
  local alpha = f and FrameAlpha(f) or 0
  Layout.StripBagSpecialFrame()
  local userVisible = Layout.IsBagFrameVisible()
  local want = userVisible and alpha >= ALPHA_ESC_MIN and not combatVisuallyHidden
  if want then
    table.insert(UISpecialFrames, BAG_SPECIAL_FRAME)
  end
  local db = Config and Config.EnsureDB and Config.EnsureDB()
  if db then
    db.bagEsc = {
      t = (time and time()) or 0,
      ver = Config.VERSION,
      alpha = alpha,
      combatHide = combatVisuallyHidden,
      keepShown = BetterBackpack._bbKeepShown and true or false,
      frameShown = f and f.IsShown and f:IsShown() and true or false,
      inUISpecialFrames = BagFrameListedInUISpecial(),
      wantEscClose = want and true or false,
      userVisible = userVisible and true or false,
      keepShownPark = BetterBackpack._bbKeepShown and true or false,
    }
  end
end

local function SyncBagUISpecialFrame()
  Layout.SyncBagUISpecialFrame()
end

local function RearmCombatParkFrame(f)
  if not f then
    return
  end
  BetterBackpack._bbKeepShown = true
  combatVisuallyHidden = true
  pcall(function()
    f:Show()
    f:SetAlpha(0)
    f:EnableMouse(false)
  end)
  Layout.SyncBagUISpecialFrame()
end

function Layout.InstallEscGuard()
  if Layout._escGuardInstalled then
    return
  end
  if type(CloseSpecialWindows) ~= "function" then
    return
  end
  Layout._escGuardInstalled = true
  local orig = CloseSpecialWindows
  CloseSpecialWindows = function(...)
    Layout.SyncBagUISpecialFrame()
    local userVisible = Layout.IsBagFrameVisible()
    Layout.EscDebugTrace("pre", string.format("vis=%s", tostring(userVisible)))

    if userVisible then
      BetterBackpack._bbEscPass = true
      local ret = orig(...)
      BetterBackpack._bbEscPass = nil
      Layout.SyncBagUISpecialFrame()
      Layout.EscDebugTrace("post-open", string.format("ret=%s stillVis=%s", tostring(ret), tostring(Layout.IsBagFrameVisible())))
      if Layout.IsBagFrameVisible() then
        local OC = BetterBackpack.Modules and BetterBackpack.Modules.OpenClose
        if OC and OC.CloseFromEsc then
          return OC.CloseFromEsc() and true or ret
        end
      end
      return ret
    end

    -- Parked keep-shown (Show+alpha0): not in UISpecialFrames but ButtonFrame IsShown
    -- still breaks ESC stack on Forever — transient Hide for orig only, then re-arm (combat B).
    local f = main or _G.BetterBackpackFrame
    local rearm = false
    if f and BetterBackpack._bbKeepShown and f.IsShown and f:IsShown()
        and (combatVisuallyHidden or FrameAlpha(f) < ALPHA_ESC_MIN) then
      if not (InCombatLockdown and InCombatLockdown()) then
        rearm = true
        BetterBackpack._bbEscRearm = true
        pcall(function()
          f:Hide()
        end)
      end
    end

    local ret = orig(...)
    if rearm then
      BetterBackpack._bbEscRearm = nil
      RearmCombatParkFrame(f)
    end
    Layout.EscDebugTrace("post-park", string.format("ret=%s rearm=%s", tostring(ret), tostring(rearm)))
    return ret
  end
end

--- Reuse prebuilt UI for lockdown — no CreateFrame / EnsureTitleChrome / DoLayout.
function Layout.CombatAttachMain()
  if main and (main._bbBuilt or main._bbContent) then
    if not content and main._bbContent then
      content = main._bbContent
    end
    return main
  end
  local orphan = _G.BetterBackpackFrame
  if orphan then
    main = orphan
    content = orphan._bbContent or content
    freeFs = orphan.freeFs or freeFs
    moneyFs = orphan._bbMoneyFs or moneyFs
    emptyLabel = orphan._bbEmpty or emptyLabel
    return main
  end
  return main
end

-- OOC only: PreCreate + EnsureMain shell (_bbBuilt). Parks Show+alpha0 (combat B needs IsShown).
-- ESC: user-visible ↔ UISpecialFrames; parked uses transient Hide in CloseSpecialWindows (1.1.8).
function Layout.EnsureCombatShell()
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  if Layout.IsBagFrameVisible and Layout.IsBagFrameVisible() then
    return false
  end
  local f = main or _G.BetterBackpackFrame
  if f and f._bbBuilt then
    if not BetterBackpack._bbLayoutWarm then
      pcall(PlaceOnScreen)
      pcall(DoLayout)
      BetterBackpack._bbLayoutWarm = true
    end
    BetterBackpack._bbKeepShown = true
    combatVisuallyHidden = true
    pcall(function()
      f:Show()
      f:SetAlpha(0)
      f:EnableMouse(false)
    end)
    Layout.SyncBagUISpecialFrame()
    return true
  end
  if Slots and Slots.PreCreate then
    pcall(Slots.PreCreate)
  end
  pcall(Layout.EnsureMain)
  f = main or _G.BetterBackpackFrame
  if not f or not f._bbBuilt then
    return false
  end
  pcall(PlaceOnScreen)
  if not BetterBackpack._bbLayoutWarm then
    pcall(DoLayout)
    BetterBackpack._bbLayoutWarm = true
  end
  BetterBackpack._bbKeepShown = true
  combatVisuallyHidden = true
  pcall(function()
    f:Show()
    f:SetAlpha(0)
    f:EnableMouse(false)
  end)
  Layout.SyncBagUISpecialFrame()
  return true
end

local function CombatPlaceFrame(frame)
  pcall(function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 180, 60)
  end)
end

local function DumpCombatFrameMetrics(frame)
  local OC = BetterBackpack.Modules and BetterBackpack.Modules.OpenClose
  if not OC or not OC.CombatTraceOnce or not frame then
    return
  end
  local w, h, a, sh, l, b, r, t, sc, parName, cw, ch
  pcall(function()
    w = frame:GetWidth()
    h = frame:GetHeight()
    a = frame:GetAlpha()
    sh = frame:IsShown() and 1 or 0
    l = frame:GetLeft()
    b = frame:GetBottom()
    r = frame:GetRight()
    t = frame:GetTop()
    sc = frame:GetScale()
    local par = frame:GetParent()
    parName = par and par.GetName and par:GetName() or "?"
  end)
  local c = frame._bbContent or content
  if c then
    pcall(function()
      cw = c:GetWidth()
      ch = c:GetHeight()
    end)
  end
  OC.CombatTraceOnce("metrics", string.format(
    "w=%.0f h=%.0f a=%.2f shown=%s L=%.0f B=%.0f R=%.0f T=%.0f scale=%.2f parent=%s cw=%.0f ch=%.0f warm=%s keep=%s",
    tonumber(w) or 0,
    tonumber(h) or 0,
    tonumber(a) or 0,
    tostring(sh),
    tonumber(l) or -9999,
    tonumber(b) or -9999,
    tonumber(r) or -9999,
    tonumber(t) or -9999,
    tonumber(sc) or 1,
    tostring(parName),
    tonumber(cw) or 0,
    tonumber(ch) or 0,
    tostring(BetterBackpack._bbLayoutWarm),
    tostring(BetterBackpack._bbKeepShown)
  ))
end

local function CombatPresentFrame(frame)
  if not frame then
    return false
  end
  main = frame
  if frame._bbContent then
    content = frame._bbContent
  end
  combatVisuallyHidden = false
  pcall(function()
    if frame.GetParent and frame:GetParent() ~= UIParent then
      frame:SetParent(UIParent)
    end
    frame:SetFrameLevel(500)
    if frame.SetScale then
      frame:SetScale(1)
    end
  end)
  CombatPlaceFrame(frame)
  pcall(function()
    local fw = frame:GetWidth() or 0
    local fh = frame:GetHeight() or 0
    local targetW = (stickyH and stickyCols) and (INSET_X * 2 + stickyCols * SLOT + math.max(0, stickyCols - 1) * PAD) or nil
    local targetH = stickyH
    if fw < 100 or fh < 100 then
      frame:SetSize(targetW or 456, targetH or 360)
    elseif targetH and targetH > fh then
      frame:SetSize(fw, targetH)
    end
  end)
  local inCombat = InCombatLockdown and InCombatLockdown()
  pcall(function()
    if inCombat then
      frame:SetAlpha(1)
      frame:EnableMouse(true)
    else
      frame:Show()
      frame:SetAlpha(1)
      frame:EnableMouse(true)
    end
  end)
  if content then
    pcall(function()
      if not inCombat and content.Show then
        content:Show()
      end
      content:SetAlpha(1)
      content:EnableMouse(true)
    end)
  end
  pcall(Layout.Raise)
  pcall(ApplyCombinedBagsChrome, frame)
  pcall(RefreshCooldowns)
  UpdateFreeSpace()
  UpdateMoney()
  DumpCombatFrameMetrics(frame)
  local left
  pcall(function()
    left = frame:GetLeft()
  end)
  if left ~= nil and left < -200 then
    CombatPlaceFrame(frame)
    pcall(function()
      if (frame:GetWidth() or 0) < 100 then
        frame:SetSize(456, 360)
      end
    end)
  end
  Layout.SyncBagUISpecialFrame()
  return Layout.IsBagFrameVisible()
end

-- Combat open: alpha 1 (no DoLayout in lockdown).
function Layout.CombatShow()
  local frame = Layout.CombatAttachMain() or _G.BetterBackpackFrame
  if not frame or not frame._bbBuilt then
    return Layout.ShowCombatMinimal()
  end
  return CombatPresentFrame(frame)
end

-- Combat close: alpha 0 only (never Hide in lockdown).
function Layout.CombatHide()
  combatVisuallyHidden = true
  local frame = main or _G.BetterBackpackFrame
  if not frame then
    Layout.SyncBagUISpecialFrame()
    return true
  end
  pcall(function()
    frame:SetAlpha(0)
    frame:EnableMouse(false)
  end)
  Layout.SyncBagUISpecialFrame()
  return not Layout.IsBagFrameVisible()
end

function Layout.ForceCombatShow()
  return Layout.CombatShow()
end

function Layout.ShowCombatMinimal()
  local p = Profile()
  if not p.enabled or p.safeMode then
    local OC = BetterBackpack.Modules and BetterBackpack.Modules.OpenClose
    if OC and OC.CombatTraceOnce then
      OC.CombatTraceOnce("ShowCombatMinimal", string.format("disabled enabled=%s safe=%s", tostring(p.enabled), tostring(p.safeMode)))
    end
    return false
  end
  local frame = Layout.CombatAttachMain() or _G.BetterBackpackFrame
  if not frame then
    local OC = BetterBackpack.Modules and BetterBackpack.Modules.OpenClose
    if OC and OC.CombatTraceOnce then
      OC.CombatTraceOnce("ShowCombatMinimal", "no BetterBackpackFrame")
    end
    return false
  end
  return CombatPresentFrame(frame)
end

function Layout.Show()
  local inCombat = InCombatLockdown and InCombatLockdown()
  if inCombat then
    return Layout.ShowCombatMinimal()
  end

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

  BetterBackpack._bbKeepShown = false
  combatVisuallyHidden = false
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
  local orphan = _G.BetterBackpackNewLaneBtn
  if orphan and orphan.Hide then
    orphan:Hide()
  end
  UpdateFreeSpace()
  UpdateMoney()
  pcall(Layout.Raise)
  UpdateFreeSpace()
  local shown = main:IsShown() and true or false
  if not shown and BetterBackpack.RecordError then
    BetterBackpack.RecordError("Show", "IsShown=false after Show()")
  end
  SyncBagUISpecialFrame()
  return shown
end

function Layout.Hide()
  focusBagID = nil
  stickyCols, stickyH = nil, nil
  Layout.SetDropHints(false)
  ClearBagMatchGlows()
  local T = Feat("Trash")
  if T and T.OnBagHide then
    pcall(T.OnBagHide)
  end
  local S = BetterBackpack.Modules.Settings
  if S and S.Hide then
    S.Hide()
  end
  if BetterBackpack._bbKeepShown or (InCombatLockdown and InCombatLockdown()) then
    Layout.CombatHide()
    return
  end
  combatVisuallyHidden = false
  BetterBackpack._bbKeepShown = false
  if main then
    pcall(function()
      main:Hide()
    end)
  end
  local g = _G.BetterBackpackFrame
  if g and g.Hide and g ~= main then
    pcall(function()
      g:Hide()
    end)
  end
  Layout.SyncBagUISpecialFrame()
end

function Layout.ForceHidden()
  Layout.Hide()
  if BetterBackpack._bbKeepShown then
    Layout.SyncBagUISpecialFrame()
    return
  end
  local g = _G.BetterBackpackFrame
  if g and g.Hide and (not main or g ~= main) then
    pcall(function()
      g:Hide()
    end)
  end
  Layout.SyncBagUISpecialFrame()
end

-- Exported for BulkTransfer / VendorJunk lane bulk (resolve Layout at call time).
function Layout.ListLaneSlots(laneKey, unfiltered)
  if not laneKey then
    return {}
  end
  local buckets = CollectBuckets(unfiltered == true)
  local list = buckets[laneKey]
  if not list then
    return {}
  end
  return list
end

function Layout.Relayout()
  if Layout.IsShown() then
    DoLayout()
  end
end

InventoryOccupiedCount = function()
  local ranges = Slots.InventoryBagRanges and Slots.InventoryBagRanges()
  if type(ranges) ~= "table" then
    return 0
  end
  local n = 0
  for ri = 1, #ranges do
    local b = ranges[ri].bag
    local numSlots = ranges[ri].slots
    if b ~= nil and type(numSlots) ~= "number" then
      if Slots.NumSlotsForBag then
        numSlots = Slots.NumSlotsForBag(b)
      elseif C_Container and C_Container.GetContainerNumSlots then
        local okN, ns = pcall(C_Container.GetContainerNumSlots, b)
        if okN then
          numSlots = ns
        end
      end
    end
    if b ~= nil and type(numSlots) == "number" and numSlots > 0 then
      for s = 1, numSlots do
        if Slots.SlotOccupied and Slots.SlotOccupied(b, s) then
          n = n + 1
        end
      end
    end
  end
  return n
end

VisibleGridSignature = function()
  local order = Layout.GetCategoryOrder()
  local SM = Feat("StackMerge")
  local buckets = CollectBuckets(false)
  local parts = {}
  for i = 1, #order do
    local key = order[i]
    if CategoryEnabled(key) then
      local list = buckets[key] or {}
      if SM and SM.Collapse then
        list = SM.Collapse(list)
      end
      parts[#parts + 1] = string.format("%s:%d", key, #list)
      for j = 1, #list do
        local e = list[j]
        if e and e.bag ~= nil and e.slot ~= nil then
          parts[#parts + 1] = string.format("%d.%d", e.bag, e.slot)
        end
      end
    end
  end
  return table.concat(parts, "|") .. "|occ:" .. tostring(InventoryOccupiedCount())
end

local function NeedsMergedGridRepaint()
  local SM = Feat("StackMerge")
  return SM and SM.VisibleRepaintNeeded and SM.VisibleRepaintNeeded()
end

--- Bag events: sync icons/counts only — no full grid reflow (merged stacks stay put).
function Layout.RefreshLight()
  if not Layout.IsShown() then
    return
  end
  if NeedsMergedGridRepaint() then
    DoLayout()
    return
  end
  local SM = Feat("StackMerge")
  if SM and SM.RefreshMergedButtons then
    SM.RefreshMergedButtons()
  end
  Slots.ForEach(function(btn)
    if btn and btn:GetAlpha() > 0.5 and btn._bbBag ~= nil then
      Slots.SyncCooldown(btn, btn._bbBag, btn._bbSlot)
      Slots.SyncVisual(btn, btn._bbBag, btn._bbSlot)
      if Slots.Normalize then
        Slots.Normalize(btn)
      end
    end
  end)
end

function Layout.Refresh()
  if InCombatLockdown and InCombatLockdown() then
    Layout.RefreshCooldowns()
    return
  end
  if BetterBackpack._combatFrozen or BetterBackpack._sortSuppressRefresh then
    return
  end
  if not Layout.IsShown() then
    return
  end
  local occ = InventoryOccupiedCount()
  local prevOcc = BetterBackpack._bbLastOccupiedCount
  local sig = VisibleGridSignature()
  local prevSig = BetterBackpack._bbGridSig
  BetterBackpack._bbLastOccupiedCount = occ
  BetterBackpack._bbGridSig = sig
  if prevOcc == nil or prevOcc ~= occ or prevSig == nil or prevSig ~= sig or NeedsMergedGridRepaint() then
    DoLayout()
    return
  end
  Layout.RefreshLight()
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
    tidy = tidyOn and true or false,
    settings = gearOn and true or false,
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
  ok(type(InventoryOccupiedCount) == "function", "InventoryOccupiedCount missing")
  ok(type(VisibleGridSignature) == "function", "VisibleGridSignature missing")
  local occOk = pcall(function()
    local _ = InventoryOccupiedCount()
  end)
  ok(occOk, "InventoryOccupiedCount call failed")
  local sigOk = pcall(function()
    local _ = VisibleGridSignature()
  end)
  ok(sigOk, "VisibleGridSignature call failed")
  ok(type(Layout.RefreshLight) == "function", "RefreshLight missing")
  ok(type(NeedsMergedGridRepaint) == "function" or Feat("StackMerge") ~= nil, "merge repaint hook missing")
  local SM = Feat("StackMerge")
  if SM and SM.RunSelfTest then
    local smOk, _, smFail, smNotes = SM.RunSelfTest()
    if smOk then
      pass = pass + 1
    else
      fail = fail + (smFail or 1)
      if smNotes then
        for i = 1, #smNotes do
          notes[#notes + 1] = "stack:" .. smNotes[i]
        end
      end
    end
  end
  local BT = Feat("BulkTransfer")
  if BT and BT.RunSelfTest then
    local btOk, _, btFail, btNotes = BT.RunSelfTest()
    if btOk then
      pass = pass + 1
    else
      fail = fail + (btFail or 1)
      if btNotes then
        for i = 1, #btNotes do
          notes[#notes + 1] = "bulk:" .. btNotes[i]
        end
      end
    end
  end
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
