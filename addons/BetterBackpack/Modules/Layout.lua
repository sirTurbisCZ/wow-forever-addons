--[[
  BetterBackpack.Layout — category lanes + CombinedBags chrome (0.1.5).
  Forever: never SetToplevel (ADDON_ACTION_BLOCKED).
  Money: SmallMoneyFrameTemplate coins. Slots: N/M only. Bag-bar hover glow.
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

local main, content, freeFs, moneyFs, emptyLabel, sortBtn
local sectionFrames = {}
local layoutBusy = false
local bagHoverHooked = false
local bagBarHoverHooked = {}

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

-- Occupied/total only — no "Free N" label.
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
  freeFs:SetText(string.format("%d/%d", used, total))
  -- used/total: ≤50% green, ≤75% yellow, ≤90% orange, else red
  local ratio = (total > 0) and (used / total) or 0
  if ratio <= 0.50 then
    freeFs:SetTextColor(0.25, 0.85, 0.35) -- green
  elseif ratio <= 0.75 then
    freeFs:SetTextColor(0.95, 0.85, 0.20) -- yellow
  elseif ratio <= 0.90 then
    freeFs:SetTextColor(1.0, 0.55, 0.15) -- orange
  else
    freeFs:SetTextColor(0.95, 0.25, 0.20) -- red
  end
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

local function SetBagMatchHighlight(bagID, highlight)
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

local function ClearBagMatchGlows()
  pcall(function()
    Slots.ForEach(function(btn)
      if btn and btn.BagIndicator then
        ShowBagIndicator(btn.BagIndicator, false)
      end
    end)
  end)
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
  bagBarHoverHooked[btn] = true
  btn:HookScript("OnEnter", function(self)
    if not Layout.IsShown() then
      return
    end
    local bagID = ResolveBagBarBagID(self, forcedBag)
    if bagID ~= nil then
      SetBagMatchHighlight(bagID, true)
    end
  end)
  btn:HookScript("OnLeave", function()
    ClearBagMatchGlows()
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
  local frame
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
  if not frame then
    frame = CreateFrame("Frame", "BetterBackpackFrame", UIParent)
  end
  pcall(function()
    if ButtonFrameTemplate_HidePortrait then
      ButtonFrameTemplate_HidePortrait(frame)
    end
  end)
  KillPortrait(frame)
  ApplyCombinedBagsChrome(frame)
  return frame
end

function Layout.EnsureMain()
  if main then
    KillPortrait(main)
    ApplyCombinedBagsChrome(main)
    InstallBagHoverHighlight()
    if sortBtn then
      sortBtn:Show()
    end
    return main
  end

  main = CreateBagPanel()
  main:SetSize(400, 320)
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
  main:SetScript("OnHide", function()
    local OpenClose = BetterBackpack.Modules.OpenClose
    if OpenClose and OpenClose.NotifyHidden then
      OpenClose.NotifyHidden()
    end
  end)
  if UISpecialFrames then
    table.insert(UISpecialFrames, "BetterBackpackFrame")
  end

  local titleText = CombinedBagTitle()
  if main.SetTitle then
    pcall(main.SetTitle, main, titleText)
  end
  if not main.TitleText and not main.title then
    local title = main:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -6)
    title:SetText(titleText)
    main.title = title
  elseif main.TitleText then
    main.TitleText:SetText(titleText)
  end

  local close = main.CloseButton
  if not close then
    pcall(function()
      close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
    end)
  end
  if close then
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", 2, 1)
    close:SetScript("OnClick", function()
      local OpenClose = BetterBackpack.Modules.OpenClose
      if OpenClose and OpenClose.CloseOurs then
        OpenClose.CloseOurs({ closeBlizzard = true, suppress = 0.25 })
      else
        main:Hide()
      end
    end)
  end

  -- Sort (title bar) — always create, template optional.
  pcall(function()
    sortBtn = CreateFrame("Button", "BetterBackpackSortButton", main, "UIPanelButtonTemplate")
  end)
  if not sortBtn then
    sortBtn = CreateFrame("Button", "BetterBackpackSortButton", main)
    sortBtn:SetSize(56, 22)
    local fs = sortBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    fs:SetText("Sort")
    sortBtn:SetFontString(fs)
    local bg = sortBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.18, 0.9)
  end
  sortBtn:SetSize(56, 22)
  if close then
    sortBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -6, -6)
  else
    sortBtn:SetPoint("TOPRIGHT", -28, -8)
  end
  sortBtn:SetText("Sort")
  sortBtn:SetFrameLevel((main:GetFrameLevel() or 1) + 20)
  sortBtn:Show()
  sortBtn:SetScript("OnClick", function()
    local Tidy = BetterBackpack.Modules.Tidy
    if Tidy and Tidy.SortBags then
      Tidy.SortBags()
    end
  end)
  main.sortBtn = sortBtn

  -- Occupied/total (left) — no "Free N"
  freeFs = main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  freeFs:SetPoint("BOTTOMLEFT", 14, 12)
  freeFs:SetJustifyH("LEFT")
  freeFs:SetText("—/—")
  main.freeFs = freeFs

  -- Classic coin money (right)
  local moneyFrame
  pcall(function()
    moneyFrame = CreateFrame("Frame", "BetterBackpackMoneyFrame", main, "SmallMoneyFrameTemplate")
  end)
  if moneyFrame then
    moneyFrame:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -8, 10)
    pcall(function()
      if MoneyFrame_SetType then
        MoneyFrame_SetType(moneyFrame, "STATIC")
      end
    end)
    main.moneyFrame = moneyFrame
  else
    moneyFs = main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    moneyFs:SetPoint("BOTTOMRIGHT", -14, 12)
  end

  content = CreateFrame("Frame", nil, main)
  content:EnableMouse(false)
  if main.Inset then
    content:SetPoint("TOPLEFT", main.Inset, "TOPLEFT", 4, -4)
    content:SetPoint("BOTTOMRIGHT", main.Inset, "BOTTOMRIGHT", -4, 24)
  else
    content:SetPoint("TOPLEFT", INSET_X, -TOP_CHROME)
    content:SetSize(100, 100)
  end

  emptyLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  emptyLabel:SetPoint("TOPLEFT", 4, -4)
  emptyLabel:Hide()

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
  InstallBagHoverHighlight()
  if sortBtn then
    sortBtn:Show()
    sortBtn:SetFrameLevel((main:GetFrameLevel() or 1) + 20)
  end
  main:Show()
  pcall(function()
    main:Raise()
  end)
  DoLayout()
  main:SetAlpha(1)
  main:Show()
  PlaceOnScreen()
  ApplyCombinedBagsChrome(main)
  UpdateMoney()
  pcall(function()
    main:Raise()
  end)
  return main:IsShown() and true or false
end

function Layout.Hide()
  ClearBagMatchGlows()
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
