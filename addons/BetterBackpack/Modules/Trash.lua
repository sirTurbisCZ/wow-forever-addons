--[[
  BetterBackpack.Trash — auto-destroy lane (0.5.21).
  Drop a stack on the Trash lane → destroyed now (first time per item asks), itemID taught
  to "trash" (profile.itemRules). Its grey ghost stays in the lane (0 bag slots); drag the
  ghost to another lane, or click it → Keep / Move to, to stop destroying it.
  Future loot of taught items waits in Trash (red) and is destroyed on the next click in the
  bag — Forever allows DeleteCursorItem only inside a hardware event. Never in combat.
  Design: docs/auto-destroy-lane.md (v2).
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local Trash = {}
BetterBackpack.Modules.Trash = Trash

local Config = BetterBackpack.Config
local Slots = BetterBackpack.Modules.Slots

local LANE = "trash"
Trash.LANE = LANE

local SLOT = 37
local LOG_MAX = 20
-- Never destroyable, whatever the rules say.
local PROTECTED_IDS = {
  [6948] = true, -- Hearthstone
}

local function Feat(name)
  return BetterBackpack.Modules and BetterBackpack.Modules[name]
end

local function Print(...)
  local f = BetterBackpack.Print
  if f then
    f(...)
  else
    print("[BetterBackpack]", ...)
  end
end

local function SafeNum(v)
  return Slots.SafeNum(v)
end

local function InCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

local function TrashDB()
  local p = Config.GetProfile()
  if type(p.trash) ~= "table" then
    p.trash = {}
  end
  local t = p.trash
  if t.confirm == nil then
    t.confirm = true
  end
  for _, k in ipairs({ "confirmed", "destroyed", "log" }) do
    if type(t[k]) ~= "table" then
      t[k] = {}
    end
  end
  return t
end

local function Rules()
  local p = Config.GetProfile()
  if type(p.itemRules) ~= "table" then
    p.itemRules = {}
  end
  return p.itemRules
end

local function IsTaught(itemID)
  local r = Rules()
  return itemID ~= nil and (r[itemID] == LANE or r[tostring(itemID)] == LANE)
end
Trash.IsTaught = IsTaught

function Trash.Enabled()
  local Layout = Feat("Layout")
  return Layout and Layout.CategoryEnabled and Layout.CategoryEnabled(LANE) and true or false
end

function Trash.TaughtIDs()
  local out, seen = {}, {}
  for id, rule in pairs(Rules()) do
    local n = tonumber(id)
    if rule == LANE and n and not seen[n] then
      seen[n] = true
      out[#out + 1] = n
    end
  end
  table.sort(out)
  return out
end

function Trash.DestroyedCount(itemID)
  return TrashDB().destroyed[itemID] or 0
end

function Trash.ConfirmEnabled()
  return TrashDB().confirm ~= false
end

function Trash.SetConfirm(on)
  TrashDB().confirm = on and true or false
end

-- Item helpers ------------------------------------------------------------------------

local function SlotInfo(bag, slot)
  if not (C_Container and C_Container.GetContainerItemInfo) then
    return nil
  end
  local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
  if ok and type(info) == "table" then
    return info
  end
  return nil
end

local function SlotItemID(bag, slot)
  if C_Container and C_Container.GetContainerItemID then
    local ok, id = pcall(C_Container.GetContainerItemID, bag, slot)
    if ok then
      return SafeNum(id)
    end
  end
  local info = SlotInfo(bag, slot)
  return info and SafeNum(info.itemID)
end

local function ItemInfoByID(itemID)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not fn or not itemID then
    return nil, nil, nil
  end
  local ok, name, link, quality = pcall(fn, itemID)
  if not ok then
    return nil, nil, nil
  end
  if Slots.IsSecret(name) then
    name = nil
  end
  if Slots.IsSecret(link) then
    link = nil
  end
  return name, link, SafeNum(quality)
end

function Trash.ItemLabel(itemID)
  local name, link = ItemInfoByID(itemID)
  return link or name or ("item:" .. tostring(itemID))
end

function Trash.ItemName(itemID)
  local name = ItemInfoByID(itemID)
  return name or ("item:" .. tostring(itemID))
end

function Trash.ItemIcon(itemID)
  local tex
  if C_Item and C_Item.GetItemIconByID then
    local ok, t = pcall(C_Item.GetItemIconByID, itemID)
    if ok then
      tex = t
    end
  end
  if not tex and GetItemIcon then
    local ok, t = pcall(GetItemIcon, itemID)
    if ok then
      tex = t
    end
  end
  if tex and not Slots.IsSecret(tex) then
    return tex
  end
  return 134400 -- INV_Misc_QuestionMark
end

local function ItemQuality(itemID, info)
  local q = SafeNum(info and info.quality)
  if q then
    return q
  end
  if C_Item and C_Item.GetItemQualityByID then
    local ok, res = pcall(C_Item.GetItemQualityByID, itemID)
    if ok and SafeNum(res) then
      return SafeNum(res)
    end
  end
  local _, _, quality = ItemInfoByID(itemID)
  return quality
end

local function ItemClassID(itemID)
  local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not fn then
    return nil
  end
  local ok, _, _, _, _, _, classID = pcall(fn, itemID)
  if ok then
    return SafeNum(classID)
  end
  return nil
end

local function IsQuestSlot(bag, slot)
  local fn = (C_Container and C_Container.GetContainerItemQuestInfo) or GetContainerItemQuestInfo
  if not fn or bag == nil then
    return false
  end
  local ok, a, b = pcall(fn, bag, slot)
  if not ok then
    return false
  end
  if type(a) == "table" then
    return (a.isQuestItem == true) or (SafeNum(a.questID) or 0) > 0
  end
  return a == true or (SafeNum(b) or 0) > 0
end

local function ItemOnCursor(itemID)
  if not GetCursorInfo then
    return false
  end
  local ok, kind, id = pcall(GetCursorInfo)
  if not ok or kind ~= "item" then
    return false
  end
  local held = SafeNum(id)
  return held == itemID or (held == nil and itemID ~= nil)
end

--- Reason the item must never be destroyed, or nil. Hard filters: quest, green+, locked.
function Trash.Refuse(itemID, bag, slot)
  if not itemID then
    return "unknown item"
  end
  if PROTECTED_IDS[itemID] then
    return "protected item"
  end
  if ItemClassID(itemID) == 12 or IsQuestSlot(bag, slot) then
    return "quest item"
  end
  local info = bag ~= nil and SlotInfo(bag, slot) or nil
  local quality = ItemQuality(itemID, info)
  if quality == nil and C_Item and C_Item.GetItemQualityByID then
    local ok, res = pcall(C_Item.GetItemQualityByID, itemID)
    if ok then
      quality = SafeNum(res)
    end
  end
  if quality == nil then
    local classID = ItemClassID(itemID)
    if classID == 15 then
      quality = 0
    else
      return "item quality not known yet — try again"
    end
  end
  if quality >= 2 then
    return "green or better quality"
  end
  if info and info.isLocked and not ItemOnCursor(itemID) then
    return "item is locked (trade / mail / moving)"
  end
  return nil
end

local function CursorItem()
  if not GetCursorInfo then
    return nil
  end
  local ok, kind, id = pcall(GetCursorInfo)
  if ok and kind == "item" then
    return SafeNum(id) or true
  end
  return nil
end

local function Pickup(bag, slot)
  if C_Container and C_Container.PickupContainerItem then
    pcall(C_Container.PickupContainerItem, bag, slot)
  elseif PickupContainerItem then
    pcall(PickupContainerItem, bag, slot)
  end
end

--- Delete the stack at bag/slot (already on the cursor, or picked up here).
--- Never touches a different item the player holds.
local function DeleteStack(bag, slot, itemID)
  local held = CursorItem()
  if held then
    if held ~= true and held ~= itemID then
      return false, "busy"
    end
  else
    if SlotItemID(bag, slot) ~= itemID then
      return false, "moved"
    end
    Pickup(bag, slot)
    held = CursorItem()
    if not held then
      return false, "pickup"
    end
    if held ~= true and held ~= itemID then
      pcall(ClearCursor)
      return false, "mismatch"
    end
  end
  local ok = DeleteCursorItem and pcall(DeleteCursorItem)
  if CursorItem() then
    pcall(ClearCursor)
    return false, "blocked"
  end
  return ok and true or false, ok and nil or "error"
end

local function Record(itemID, count)
  local t = TrashDB()
  t.destroyed[itemID] = (t.destroyed[itemID] or 0) + (count or 1)
  table.insert(t.log, 1, { id = itemID, n = count or 1, t = time and time() or 0 })
  while #t.log > LOG_MAX do
    table.remove(t.log)
  end
end

function Trash.Log()
  return TrashDB().log
end

local function Changed()
  local Layout = Feat("Layout")
  if Layout and Layout.IsShown and Layout.IsShown() and Layout.Relayout then
    Layout.Relayout()
  end
  local Settings = Feat("Settings")
  if Settings and Settings.Refresh then
    Settings.Refresh()
  end
end

local function Teach(itemID)
  local CC = Feat("CustomCategories")
  if CC and CC.AssignItem then
    CC.AssignItem(itemID, LANE)
  end
end

local function StackCount(bag, slot)
  local info = SlotInfo(bag, slot)
  return SafeNum(info and info.stackCount) or 1
end

--- Destroy + teach. Runs inside the drop click or the confirm click (hardware event).
local function DestroyAndTeach(src)
  local id = src.itemID
  local link = Slots.ItemLink(src.bag, src.slot) or Trash.ItemLabel(id)
  local count = StackCount(src.bag, src.slot)
  local ok, why = DeleteStack(src.bag, src.slot, id)
  if ok then
    Record(id, count)
  end
  Teach(id)
  if ok then
    Print(string.format("Destroyed %s x%d. Future loot of it is destroyed too — drag its grey icon out of Trash to keep it.",
      link, count))
  else
    Print(string.format("Couldn't destroy %s (%s). It stays in Trash and goes on your next click in the bag.",
      link, tostring(why)))
  end
end

-- Confirm popup ------------------------------------------------------------------------

local popupReady = false
local function EnsurePopup()
  if popupReady or not StaticPopupDialogs then
    return popupReady
  end
  popupReady = true
  StaticPopupDialogs.BETTERBACKPACK_TRASH_CONFIRM = {
    text = "Destroy %s?\n\nEvery stack of it you loot later is destroyed too. This is permanent.",
    button1 = "Destroy",
    button2 = CANCEL or "Cancel",
    showAlert = true,
    OnAccept = function(self, data)
      Trash.ConfirmAccepted(data or (self and self.data))
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
  return true
end

local function FindStack(itemID)
  local ranges = Slots.BagRanges()
  for i = 1, #ranges do
    local bag, n = ranges[i].bag, ranges[i].slots
    for slot = 1, n do
      if SlotItemID(bag, slot) == itemID then
        return bag, slot
      end
    end
  end
  return nil
end

function Trash.ConfirmAccepted(src)
  if type(src) ~= "table" or not src.itemID then
    return
  end
  if InCombat() then
    Print("Not destroyed — try again after combat.")
    return
  end
  TrashDB().confirmed[src.itemID] = true
  if SlotItemID(src.bag, src.slot) ~= src.itemID then
    src.bag, src.slot = FindStack(src.itemID)
  end
  if src.bag == nil then
    Teach(src.itemID)
    Print(Trash.ItemLabel(src.itemID) .. " is no longer in your bags — future loot of it is destroyed.")
    return
  end
  DestroyAndTeach(src)
end

--- Item from our bag dropped on the Trash lane (cursor still holds it).
function Trash.HandleDrop(src)
  if type(src) ~= "table" or src.bag == nil then
    pcall(ClearCursor)
    return
  end
  if not src.itemID and Slots.ItemIDForBagSlot then
    src.itemID = Slots.ItemIDForBagSlot(src.bag, src.slot)
  end
  if not src.itemID and GetCursorInfo then
    local ok, kind, id = pcall(GetCursorInfo)
    if ok and kind == "item" then
      src.itemID = SafeNum(id)
    end
  end
  if not src.itemID then
    pcall(ClearCursor)
    Print("Trash: couldn't read item — try again.")
    return
  end
  local id = src.itemID
  if InCombat() then
    pcall(ClearCursor)
    Print("Trash works out of combat only.")
    return
  end
  local why = Trash.Refuse(id, src.bag, src.slot)
  if why then
    pcall(ClearCursor)
    Print(string.format("Won't destroy %s: %s.", Slots.ItemLink(src.bag, src.slot) or Trash.ItemLabel(id), why))
    return
  end
  local t = TrashDB()
  if t.confirm ~= false and not t.confirmed[id] then
    pcall(ClearCursor)
    if EnsurePopup() and StaticPopup_Show then
      local label = string.format("%s x%d", Slots.ItemLink(src.bag, src.slot) or Trash.ItemLabel(id),
        StackCount(src.bag, src.slot))
      local data = { bag = src.bag, slot = src.slot, itemID = id }
      local dialog = StaticPopup_Show("BETTERBACKPACK_TRASH_CONFIRM", label, nil, data)
      if dialog then
        dialog.data = data
      end
    end
    return
  end
  DestroyAndTeach(src)
end

-- Ghost escape: keep / move -------------------------------------------------------------

local function NaturalLane(itemID)
  local Layout = Feat("Layout")
  return Layout and Layout.NaturalLaneForID and Layout.NaturalLaneForID(itemID) or "other"
end

function Trash.Forget(itemID)
  local CC = Feat("CustomCategories")
  if CC and CC.AssignItem then
    CC.AssignItem(itemID, nil)
  end
  Print(Trash.ItemLabel(itemID) .. " is kept again (back in its default lane).")
end

function Trash.MoveOut(itemID, laneKey)
  local CC = Feat("CustomCategories")
  if not CC or not laneKey or laneKey == LANE then
    return
  end
  if laneKey == "new" then
    if CC.PromptNew then
      CC.PromptNew(itemID)
    end
    return
  end
  local Layout = Feat("Layout")
  if Layout and Layout.CategoryEnabled and not Layout.CategoryEnabled(laneKey) then
    Print("That lane is turned off — turn it on in Settings first.")
    return
  end
  local natural = NaturalLane(itemID)
  if laneKey == natural then
    Trash.Forget(itemID)
    return
  end
  CC.Teach(itemID, laneKey, natural)
  local label = Layout and Layout.GetCategoryLabel and Layout.GetCategoryLabel(laneKey) or laneKey
  Print(string.format("%s is kept again — goes to %s.", Trash.ItemLabel(itemID), label))
end

-- Menu (click on a ghost) ---------------------------------------------------------------

local menu
local MENU_W, MENU_ROW = 190, 18

local function CloseMenu()
  if menu then
    menu:Hide()
  end
end
Trash.CloseMenu = CloseMenu

local function EnsureMenu()
  if menu then
    return menu
  end
  local ok, f = pcall(CreateFrame, "Frame", "BetterBackpackTrashMenu", UIParent, "BackdropTemplate")
  if not ok or not f then
    f = CreateFrame("Frame", "BetterBackpackTrashMenu", UIParent)
  end
  f:SetSize(MENU_W, 40)
  f:SetFrameLevel(700)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  if not (f.SetBackdrop and pcall(f.SetBackdrop, f, {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })) then
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.92)
  else
    pcall(f.SetBackdropColor, f, 0.05, 0.05, 0.05, 0.95)
  end
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.title:SetPoint("TOPLEFT", 10, -8)
  f.title:SetPoint("TOPRIGHT", -10, -8)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(false)
  f.rows = {}
  f:Hide()
  if UISpecialFrames then
    table.insert(UISpecialFrames, "BetterBackpackTrashMenu")
  end
  menu = f
  return f
end

local function MenuRow(i)
  local row = menu.rows[i]
  if row then
    return row
  end
  row = CreateFrame("Button", nil, menu)
  row:SetSize(MENU_W - 16, MENU_ROW)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  hl:SetBlendMode("ADD")
  hl:SetAlpha(0.5)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetPoint("LEFT", 4, 0)
  row.text:SetPoint("RIGHT", -4, 0)
  row.text:SetJustifyH("LEFT")
  menu.rows[i] = row
  return row
end

function Trash.OpenMenu(anchor, itemID)
  if InCombat() then
    Print("Trash: after combat.")
    return
  end
  local Layout = Feat("Layout")
  EnsureMenu()
  menu.title:SetText(Trash.ItemName(itemID))
  local natural = NaturalLane(itemID)
  local entries = {
    { text = "|cff40ff40Keep|r — stop destroying it", fn = function() Trash.Forget(itemID) end },
  }
  local order = Layout and Layout.GetCategoryOrder and Layout.GetCategoryOrder() or {}
  for i = 1, #order do
    local key = order[i]
    if key ~= LANE and Layout.CategoryEnabled(key) and key ~= natural then
      entries[#entries + 1] = {
        text = "Keep in " .. Layout.GetCategoryLabel(key),
        fn = function() Trash.MoveOut(itemID, key) end,
      }
    end
  end
  entries[#entries + 1] = { text = "Keep in a new lane…", fn = function() Trash.MoveOut(itemID, "new") end }
  entries[#entries + 1] = { text = "|cff999999Cancel|r", fn = function() end }
  local y = 24
  for i = 1, #entries do
    local row = MenuRow(i)
    local e = entries[i]
    row.text:SetText(e.text)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -y)
    row:SetScript("OnClick", function()
      CloseMenu()
      e.fn()
    end)
    row:Show()
    y = y + MENU_ROW
  end
  for i = #entries + 1, #menu.rows do
    menu.rows[i]:Hide()
  end
  menu:SetHeight(y + 8)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor, "BOTTOMRIGHT", -6, 6)
  local main = Layout and Layout.EnsureMain and Layout.EnsureMain()
  menu:SetFrameLevel(((main and main:GetFrameLevel()) or 200) + 300)
  menu:Show()
end

-- Fake drag: ghost is not a real item, so nothing goes on the cursor ----------------------

local floater
local dragID

local function EnsureFloater()
  if floater then
    return floater
  end
  floater = CreateFrame("Frame", nil, UIParent)
  floater:SetSize(SLOT, SLOT)
  floater:EnableMouse(false)
  floater.icon = floater:CreateTexture(nil, "OVERLAY")
  floater.icon:SetAllPoints()
  floater:SetAlpha(0.85)
  floater:Hide()
  return floater
end

local function FollowCursor(self)
  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale() or 1
  self:ClearAllPoints()
  self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
end

function Trash.BeginGhostDrag(itemID)
  if InCombat() or CursorItem() then
    return false
  end
  CloseMenu()
  local f = EnsureFloater()
  f.icon:SetTexture(Trash.ItemIcon(itemID))
  local Layout = Feat("Layout")
  local main = Layout and Layout.EnsureMain and Layout.EnsureMain()
  f:SetFrameLevel(((main and main:GetFrameLevel()) or 200) + 400)
  f:SetScript("OnUpdate", FollowCursor)
  FollowCursor(f)
  f:Show()
  dragID = itemID
  if Layout and Layout.SetDropHints then
    Layout.SetDropHints(true)
  end
  return true
end

function Trash.EndGhostDrag(cancel)
  if not dragID then
    return
  end
  local id = dragID
  dragID = nil
  if floater then
    floater:SetScript("OnUpdate", nil)
    floater:Hide()
  end
  local Layout = Feat("Layout")
  if Layout and Layout.SetDropHints then
    Layout.SetDropHints(false)
  end
  if cancel then
    return
  end
  local target = Layout and Layout.LaneUnderMouse and Layout.LaneUnderMouse()
  if target and target ~= LANE then
    Trash.MoveOut(id, target)
  end
end

function Trash.IsGhostDragging()
  return dragID ~= nil
end

-- Ghost buttons ------------------------------------------------------------------------

local ghosts = {}

local function GhostTooltip(self)
  local id = self.itemID
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if GameTooltip.SetItemByID then
    pcall(GameTooltip.SetItemByID, GameTooltip, id)
  else
    GameTooltip:SetText(Trash.ItemName(id))
  end
  GameTooltip:AddLine(string.format("Auto-destroyed (%d so far)", Trash.DestroyedCount(id)), 1, 0.35, 0.35, true)
  GameTooltip:AddLine("Drag to another lane to keep it.", 0.6, 0.8, 1, true)
  GameTooltip:AddLine("Click: Keep / Keep in…", 0.7, 0.7, 0.7, true)
  GameTooltip:Show()
end

local function HeldOwnItem()
  local src = Slots.GetDragSource and Slots.GetDragSource()
  return src and CursorItem() and true or false
end

local function EnsureGhost(itemID)
  local g = ghosts[itemID]
  if g then
    return g
  end
  g = CreateFrame("Button", nil, UIParent)
  g:SetSize(SLOT, SLOT)
  g.itemID = itemID
  g:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  g:RegisterForDrag("LeftButton")
  local bg = g:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  if not pcall(bg.SetAtlas, bg, "bags-item-slot64") or not bg:GetAtlas() then
    bg:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    bg:SetTexCoord(0.15, 0.85, 0.15, 0.85)
  end
  bg:SetAlpha(0.9)
  local icon = g:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", 2, -2)
  icon:SetPoint("BOTTOMRIGHT", -2, 2)
  pcall(icon.SetDesaturated, icon, true)
  icon:SetAlpha(0.45)
  g.icon = icon
  local x = g:CreateTexture(nil, "OVERLAY")
  x:SetSize(14, 14)
  x:SetPoint("TOPRIGHT", -1, -1)
  if not pcall(x.SetTexture, x, "Interface\\Buttons\\UI-GroupLoot-Pass-Up") then
    x:SetColorTexture(0.8, 0.1, 0.1, 0.8)
  end
  x:SetAlpha(0.8)
  local count = g:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  count:SetPoint("BOTTOMRIGHT", -3, 2)
  count:SetTextColor(0.75, 0.75, 0.75)
  g.count = count
  local hl = g:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  hl:SetBlendMode("ADD")
  g:SetScript("OnEnter", GhostTooltip)
  g:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  g:SetScript("OnReceiveDrag", function()
    local Layout = Feat("Layout")
    if Layout and Layout.DropOnLane then
      Layout.DropOnLane(LANE)
    end
  end)
  g:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    if Trash.BeginGhostDrag(self.itemID) then
      self._dragged = true
    end
  end)
  g:SetScript("OnDragStop", function()
    Trash.EndGhostDrag()
  end)
  g:SetScript("OnClick", function(self, button)
    if self._dragged then
      self._dragged = nil
      return
    end
    if HeldOwnItem() then
      local Layout = Feat("Layout")
      if Layout and Layout.DropOnLane then
        Layout.DropOnLane(LANE)
      end
      return
    end
    Trash.FlushOnClick()
    if button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then
      local _, link = ItemInfoByID(self.itemID)
      if link and Slots.InsertChatLink and Slots.InsertChatLink(link) then
        return
      end
    end
    Trash.OpenMenu(self, self.itemID)
  end)
  ghosts[itemID] = g
  return g
end

function Trash.PlaceGhost(itemID, parent, x, y)
  local g = EnsureGhost(itemID)
  if g:GetParent() ~= parent then
    g:SetParent(parent)
  end
  g.icon:SetTexture(Trash.ItemIcon(itemID))
  local n = Trash.DestroyedCount(itemID)
  g.count:SetText(n > 0 and ("x" .. n) or "")
  g:ClearAllPoints()
  g:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  g:SetFrameLevel(((parent.GetFrameLevel and parent:GetFrameLevel()) or 1) + 80)
  g:Show()
  return g
end

function Trash.HideGhosts(keep)
  for id, g in pairs(ghosts) do
    if not (keep and keep[id]) then
      g:Hide()
    end
  end
end

--- Red veil on a real stack waiting in the Trash lane (destroyed on the next click).
function Trash.SetPendingVeil(btn, on)
  if not btn then
    return
  end
  local v = btn._bbTrashVeil
  if not v then
    if not on then
      return
    end
    v = btn:CreateTexture(nil, "OVERLAY", nil, 6)
    v:SetAllPoints(btn)
    v:SetColorTexture(0.85, 0.1, 0.1, 0.38)
    btn._bbTrashVeil = v
  end
  v:SetShown(on and true or false)
end

function Trash.OnBagHide()
  CloseMenu()
  Trash.EndGhostDrag(true)
end

-- Future loot --------------------------------------------------------------------------
-- Forever blocks DeleteCursorItem outside a hardware event (trashtest 0.5.19: timer and
-- BAG_UPDATE_DELAYED both "Interface action failed"). Events only count waiting stacks;
-- deletes run solely inside the player's clicks.

local pending = 0
local busy = false

local function Scan()
  local out = {}
  if not Trash.Enabled() then
    return out
  end
  local ranges = Slots.BagRanges()
  for i = 1, #ranges do
    local bag, n = ranges[i].bag, ranges[i].slots
    for slot = 1, n do
      local id = SlotItemID(bag, slot)
      if id and IsTaught(id) and not Trash.Refuse(id, bag, slot) then
        out[#out + 1] = { bag = bag, slot = slot, itemID = id }
      end
    end
  end
  return out
end

function Trash.TestResult()
  local db = Config.EnsureDB()
  return type(db.trashTest) == "table" and db.trashTest or nil
end

function Trash.LootMode()
  return "click"
end

--- Called from our click handlers (hardware event): destroys every waiting stack.
function Trash.FlushOnClick()
  if pending <= 0 or busy or InCombat() or not Trash.Enabled() then
    return
  end
  busy = true
  local list = Scan()
  local done, parts = 0, {}
  for i = 1, #list do
    local e = list[i]
    local count = StackCount(e.bag, e.slot)
    local link = Slots.ItemLink(e.bag, e.slot) or Trash.ItemLabel(e.itemID)
    if not DeleteStack(e.bag, e.slot, e.itemID) then
      break
    end
    Record(e.itemID, count)
    done = done + 1
    if #parts < 6 then
      parts[#parts + 1] = string.format("%s x%d", link, count)
    end
  end
  busy = false
  pending = #list - done
  if done > 0 then
    Print("Trash destroyed: " .. table.concat(parts, ", ") .. (done > #parts and (" +" .. (done - #parts)) or ""))
    Changed()
  end
end

function Trash.PendingCount()
  return pending
end

local function Recount()
  if InCombat() then
    return
  end
  pending = #Scan()
end

function Trash.RulesChanged()
  Recount()
end

-- /bb trashtest: click-only probe (the slash command runs inside the Enter key press) -----

local function TestCandidate(itemID)
  local ranges = Slots.BagRanges()
  for i = 1, #ranges do
    local bag, n = ranges[i].bag, ranges[i].slots
    for slot = 1, n do
      local id = SlotItemID(bag, slot)
      if id and not PROTECTED_IDS[id] then
        local info = SlotInfo(bag, slot)
        local q = ItemQuality(id, info)
        local match
        if itemID then
          match = id == itemID and q ~= nil and q <= 1
        else
          match = q == 0
        end
        if match and not (info and info.isLocked) and not IsQuestSlot(bag, slot)
            and ItemClassID(id) ~= 12
        then
          return { bag = bag, slot = slot, itemID = id, link = Slots.ItemLink(bag, slot) }
        end
      end
    end
  end
  return nil
end

function Trash.RunTest(arg)
  arg = (arg or ""):lower():match("^%s*(.-)%s*$") or ""
  local itemID = tonumber(arg)
  local c = TestCandidate(itemID)
  if arg == "" then
    Print("/bb trashtest go — destroys 1 grey stack from this key press to check Forever still allows "
      .. "click destroy. /bb trashtest <itemID> — use a white or grey stack of that item.")
    Print(c and ("Would destroy: " .. (c.link or Trash.ItemLabel(c.itemID))) or "No grey items in bags to test with.")
    local r = Trash.TestResult()
    if r then
      Print(string.format("Last result (v%s): click=%s · loot is destroyed on your next click in the bag.",
        tostring(r.ver), tostring(r.click)))
    end
    return
  end
  if arg ~= "go" and not itemID then
    Print("Usage: /bb trashtest [go|<itemID>]")
    return
  end
  if not c then
    Print(itemID and "No white/grey stacks of that item in bags." or "No grey items in bags to test with.")
    return
  end
  if CursorItem() then
    Print("Empty your cursor first.")
    return
  end
  local ok, why = DeleteStack(c.bag, c.slot, c.itemID)
  local function Finish()
    local gone = ok and SlotItemID(c.bag, c.slot) ~= c.itemID
    Config.EnsureDB().trashTest = { at = time and time() or 0, ver = Config.VERSION, click = gone and true or false }
    if gone then
      Print("trashtest v" .. tostring(Config.VERSION) .. ": click=|cff40ff40OK|r — Trash works (click-only on Forever).")
    else
      Print("trashtest v" .. tostring(Config.VERSION) .. ": click=|cffff5050" .. tostring(why or "item still there")
        .. "|r — Trash can't destroy on this client. Send this line to tuma.")
    end
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(1.5, Finish)
  else
    Finish()
  end
end

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "BAG_UPDATE_DELAYED")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", Recount)
