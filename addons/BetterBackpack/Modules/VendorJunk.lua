--[[
  VendorJunk — auto-sell at merchant (≠ Trash destroy).
  Per character: poor (grey), optional Junk lane, optional marked itemIDs.
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local VendorJunk = {}
BetterBackpack.Modules.VendorJunk = VendorJunk

local Config = BetterBackpack.Config
local BulkTransfer = BetterBackpack.Modules.BulkTransfer
local Layout = BetterBackpack.Modules.Layout
local Slots = BetterBackpack.Modules.Slots

local sellScheduled = false

local function CharProfile()
  return Config.GetCharProfile()
end

local function MarkedMap()
  local c = CharProfile()
  local m = c and c.autoSellMarked
  return type(m) == "table" and m or {}
end

local function OOC()
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  return true
end

local function GreyQuality(q)
  return q == 0
end

local function InJunkLane(bag, slot)
  if not Layout or not Layout.ClassifyBagSlot then
    return false
  end
  local cat = Layout.ClassifyBagSlot(bag, slot)
  return cat == "junk"
end

local function ItemID(bag, slot)
  if C_Container and C_Container.GetContainerItemID then
    local ok, id = pcall(C_Container.GetContainerItemID, bag, slot)
    if ok and id then
      return id
    end
  end
  if C_Container and C_Container.GetContainerItemInfo then
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and info and info.itemID then
      return info.itemID
    end
  end
  return nil
end

local function ItemInfoByID(itemID)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not fn or not itemID then
    return nil, nil
  end
  local ok, name, link = pcall(fn, itemID)
  if not ok then
    return nil, nil
  end
  return name, link
end

function VendorJunk.ItemName(itemID)
  local name = ItemInfoByID(itemID)
  return name or ("item:" .. tostring(itemID))
end

function VendorJunk.ItemIcon(itemID)
  if C_Item and C_Item.GetItemIconByID then
    local ok, tex = pcall(C_Item.GetItemIconByID, itemID)
    if ok and tex then
      return tex
    end
  end
  local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(itemID)
  return tex
end

local function IsMarked(itemID)
  if not itemID then
    return false
  end
  return MarkedMap()[itemID] == true
end

function VendorJunk.HasMarked()
  for id, on in pairs(MarkedMap()) do
    if on and id then
      return true
    end
  end
  return false
end

function VendorJunk.MarkedIDs()
  local out, seen = {}, {}
  for id, on in pairs(MarkedMap()) do
    local n = tonumber(id)
    if on and n and not seen[n] then
      seen[n] = true
      out[#out + 1] = n
    end
  end
  table.sort(out)
  return out
end

function VendorJunk.Mark(itemID)
  itemID = tonumber(itemID)
  if not itemID then
    return false
  end
  CharProfile().autoSellMarked[itemID] = true
  return true
end

function VendorJunk.Unmark(itemID)
  itemID = tonumber(itemID)
  if not itemID then
    return false
  end
  CharProfile().autoSellMarked[itemID] = nil
  return true
end

local function CursorItemID()
  if not GetCursorInfo then
    return nil
  end
  local ok, kind, id = pcall(GetCursorInfo)
  if ok and kind == "item" then
    return tonumber(id)
  end
  return nil
end

function VendorJunk.MarkFromCursor()
  local id = CursorItemID()
  if not id then
    return false
  end
  VendorJunk.Mark(id)
  if ClearCursor then
    pcall(ClearCursor)
  end
  return true
end

local function SellReason(bag, slot, itemID)
  local c = CharProfile()
  if itemID and IsMarked(itemID) then
    return "marked"
  end
  local q = BulkTransfer.SlotQuality and BulkTransfer.SlotQuality(bag, slot)
  if c.autoSellJunk and GreyQuality(q) then
    return "grey"
  end
  if c.autoSellJunkLane and InJunkLane(bag, slot) then
    return "junk lane"
  end
  return nil
end

local function ShouldAutoSell(bag, slot)
  if not BulkTransfer or not BulkTransfer.MerchantCanSell then
    return false
  end
  if not BulkTransfer.MerchantCanSell(bag, slot) then
    return false
  end
  local id = ItemID(bag, slot)
  return SellReason(bag, slot, id) ~= nil
end

local function CollectSellList()
  local out = {}
  local ranges = Slots and Slots.BagRanges and Slots.BagRanges() or {}
  for i = 1, #ranges do
    local bag, n = ranges[i].bag, ranges[i].slots
    for slot = 1, n do
      if Slots.SlotOccupied(bag, slot) and ShouldAutoSell(bag, slot) then
        out[#out + 1] = { bag = bag, slot = slot }
      end
    end
  end
  return out
end

function VendorJunk.PreviewBagItems()
  local byID = {}
  local list = CollectSellList()
  for i = 1, #list do
    local e = list[i]
    local id = ItemID(e.bag, e.slot)
    if id then
      local row = byID[id]
      if not row then
        row = {
          itemID = id,
          stacks = 0,
          reason = SellReason(e.bag, e.slot, id),
        }
        byID[id] = row
      end
      row.stacks = row.stacks + 1
    end
  end
  local out = {}
  for _, row in pairs(byID) do
    out[#out + 1] = row
  end
  table.sort(out, function(a, b)
    return (a.itemID or 0) < (b.itemID or 0)
  end)
  return out
end

function VendorJunk.AutoSellActive()
  local c = CharProfile()
  if c.autoSellJunk or c.autoSellJunkLane then
    return true
  end
  return VendorJunk.HasMarked()
end

function VendorJunk.IsEnabled()
  local c = CharProfile()
  return c.autoSellJunk == true
end

function VendorJunk.SetEnabled(on)
  CharProfile().autoSellJunk = on and true or false
end

function VendorJunk.LaneOptIn()
  local c = CharProfile()
  return c.autoSellJunkLane == true
end

function VendorJunk.SetLaneOptIn(on)
  CharProfile().autoSellJunkLane = on and true or false
end

local function FormatSellSummary(list)
  local byID = {}
  for i = 1, #list do
    local id = ItemID(list[i].bag, list[i].slot)
    if id then
      byID[id] = (byID[id] or 0) + 1
    end
  end
  local names = {}
  local n = 0
  for id, stacks in pairs(byID) do
    n = n + 1
    if n <= 6 then
      local label = VendorJunk.ItemName(id)
      if stacks > 1 then
        label = label .. " x" .. stacks
      end
      names[#names + 1] = label
    end
  end
  local extra = 0
  for _ in pairs(byID) do
    extra = extra + 1
  end
  if extra > 6 then
    names[#names + 1] = string.format("+%d more", extra - 6)
  end
  return table.concat(names, ", ")
end

local function RunSell(list)
  sellScheduled = false
  if not OOC() or #list == 0 then
    return
  end
  list = CollectSellList()
  if #list == 0 then
    return
  end
  if BetterBackpack.Print then
    local summary = FormatSellSummary(list)
    BetterBackpack.Print(
      string.format("|cff88ccffVendor|r auto-sell · %d stacks%s", #list, summary ~= "" and (" · " .. summary) or "")
    )
  end
  if BulkTransfer and BulkTransfer.TransferSlotList then
    BulkTransfer.TransferSlotList(list, "auto-sell")
  else
    for i = 1, #list do
      local e = list[i]
      if BulkTransfer and BulkTransfer.TransferSlot then
        BulkTransfer.TransferSlot(e.bag, e.slot, "merchant")
      end
    end
    if Layout and Layout.Refresh then
      Layout.Refresh()
    end
  end
end

function VendorJunk.OnMerchantShow()
  if not VendorJunk.AutoSellActive() or not OOC() or sellScheduled then
    return
  end
  local list = CollectSellList()
  if #list == 0 then
    return
  end
  sellScheduled = true
  if C_Timer and C_Timer.After then
    C_Timer.After(0.12, function()
      RunSell(list)
    end)
  else
    RunSell(list)
  end
end

function VendorJunk.OnMerchantClosed()
  sellScheduled = false
end

return VendorJunk