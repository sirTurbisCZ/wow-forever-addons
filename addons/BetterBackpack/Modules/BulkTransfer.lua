--[[
  BulkTransfer - lane header Shift+RMB bulk (OOC only).
  Context: merchant = sell, mail = attach, bank = UseContainerItem deposit.
  Never touches OpenClose / Toggle* globals.
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local BulkTransfer = {}
BetterBackpack.Modules.BulkTransfer = BulkTransfer

local Context = BetterBackpack.Modules.Context
local Layout = BetterBackpack.Modules.Layout
local Slots = BetterBackpack.Modules.Slots

local TRASH = "trash"

local pumpToken = 0
local pumpQueue
local headerTraceOnce = false

local function OOC()
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  return true
end

local function ItemID(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and info and info.itemID then
      return info.itemID
    end
  end
  if GetContainerItemID then
    local ok, id = pcall(GetContainerItemID, bag, slot)
    if ok then
      return id
    end
  end
  return nil
end

local function SlotQuality(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and info and info.quality ~= nil then
      local SlotsMod = Slots
      if SlotsMod and SlotsMod.SafeNum then
        return SlotsMod.SafeNum(info.quality, nil)
      end
      return info.quality
    end
  end
  return nil
end

local function SlotLocked(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and info and info.isLocked then
      return true
    end
  end
  return false
end

local function PickupSlot(bag, slot)
  if ClearCursor then
    pcall(ClearCursor)
  end
  if C_Container and C_Container.PickupContainerItem then
    return select(1, pcall(C_Container.PickupContainerItem, bag, slot))
  end
  if PickupContainerItem then
    return select(1, pcall(PickupContainerItem, bag, slot))
  end
  return false
end

local function CursorHasSomething()
  if CursorHasItem then
    local ok, v = pcall(CursorHasItem)
    if ok and v then
      return true
    end
  end
  if GetCursorInfo then
    local ok, kind = pcall(GetCursorInfo)
    if ok and kind == "item" then
      return true
    end
  end
  return false
end

local function NormalizeBagSlot(bag, slot)
  if Slots and Slots.AttrBagSlot then
    local b, s = Slots.AttrBagSlot(bag, slot)
    if b ~= nil and s ~= nil then
      return b, s
    end
  end
  return bag, slot
end

local function StackCount(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and info and info.stackCount ~= nil then
      return info.stackCount
    end
  end
  return nil
end

local function SlotChanged(bag, slot, idBefore, countBefore)
  if not Slots or not Slots.SlotOccupied then
    return true
  end
  if not Slots.SlotOccupied(bag, slot) then
    return true
  end
  local idAfter = ItemID(bag, slot)
  if idBefore and idAfter and idBefore ~= idAfter then
    return true
  end
  local countAfter = StackCount(bag, slot)
  if countBefore and countAfter and countAfter < countBefore then
    return true
  end
  return false
end

local function MerchantAllowed(bag, slot)
  local b, s = NormalizeBagSlot(bag, slot)
  local id = ItemID(b, s)
  if not id then
    return false
  end
  local Trash = BetterBackpack.Modules.Trash
  if Trash and Trash.Refuse and Trash.Refuse(id, b, s) then
    return false
  end
  if SlotLocked(b, s) then
    return false
  end
  if C_MerchantFrame and C_MerchantFrame.IsSellItemAllowed then
    local ok, allow = pcall(C_MerchantFrame.IsSellItemAllowed, b, s)
    if not ok then
      ok, allow = pcall(C_MerchantFrame.IsSellItemAllowed, id)
    end
    if ok and allow == false then
      return false
    end
  end
  return true
end

local function MerchantUseContainer(bag, slot)
  local idBefore = ItemID(bag, slot)
  local countBefore = StackCount(bag, slot)
  local used = false
  if C_Container and C_Container.UseContainerItem then
    used = select(1, pcall(C_Container.UseContainerItem, bag, slot))
  elseif UseContainerItem then
    used = select(1, pcall(UseContainerItem, bag, slot))
  end
  if used and SlotChanged(bag, slot, idBefore, countBefore) then
    return true
  end
  return false
end

local function MerchantPickupSell(bag, slot)
  local idBefore = ItemID(bag, slot)
  local countBefore = StackCount(bag, slot)
  if not PickupSlot(bag, slot) or not CursorHasSomething() then
    return false
  end
  if SellCursorItem then
    pcall(SellCursorItem)
  end
  if ClearCursor then
    pcall(ClearCursor)
  end
  return SlotChanged(bag, slot, idBefore, countBefore)
end

local function TransferMerchant(bag, slot)
  local b, s = NormalizeBagSlot(bag, slot)
  if not MerchantAllowed(b, s) then
    return false
  end
  if MerchantUseContainer(b, s) then
    return true
  end
  return MerchantPickupSell(b, s)
end

local function TransferMail(bag, slot)
  local b, s = NormalizeBagSlot(bag, slot)
  if SlotLocked(b, s) then
    return false
  end
  if not PickupSlot(b, s) or not CursorHasSomething() then
    return false
  end
  if ClickSendMailItemButton then
    pcall(ClickSendMailItemButton)
  end
  if ClearCursor then
    pcall(ClearCursor)
  end
  return true
end

local function TransferBank(bag, slot)
  local b, s = NormalizeBagSlot(bag, slot)
  if SlotLocked(b, s) then
    return false
  end
  if C_Container and C_Container.UseContainerItem then
    return select(1, pcall(C_Container.UseContainerItem, b, s))
  end
  if UseContainerItem then
    return select(1, pcall(UseContainerItem, b, s))
  end
  return false
end

local function TransferOne(bag, slot, ctx)
  if ctx == "merchant" then
    return TransferMerchant(bag, slot)
  end
  if ctx == "mail" then
    return TransferMail(bag, slot)
  end
  if ctx == "bank" then
    return TransferBank(bag, slot)
  end
  return false
end

local function ActionVerb(ctx)
  if ctx == "merchant" then
    return "Sell lane at vendor"
  end
  if ctx == "mail" then
    return "Attach lane to mail"
  end
  if ctx == "bank" then
    return "Deposit lane in bank"
  end
  return nil
end

function BulkTransfer.HeaderTooltipLine()
  local ctx = Context and Context.SpecialRmbContext and Context.SpecialRmbContext()
  local verb = ActionVerb(ctx)
  if not verb then
    return nil
  end
  return "Shift+RMB header - " .. verb
end

local function Pump()
  if not OOC() or not pumpQueue or #pumpQueue == 0 then
    pumpQueue = nil
    if Layout and Layout.Refresh then
      Layout.Refresh()
    end
    return
  end
  local ctx = pumpQueue.ctx
  local moved = 0
  local limit = 12
  if ctx == "merchant" or ctx == "mail" then
    limit = 1
  end
  while #pumpQueue.slots > 0 and moved < limit do
    local e = table.remove(pumpQueue.slots, 1)
    if e and e.bag and e.slot and Slots.SlotOccupied and Slots.SlotOccupied(e.bag, e.slot) then
      if TransferOne(e.bag, e.slot, ctx) then
        moved = moved + 1
        pumpQueue.sold = (pumpQueue.sold or 0) + 1
      end
    end
  end
  if #pumpQueue.slots > 0 then
    local delay = (ctx == "merchant" or ctx == "mail") and 0.08 or 0.04
    if C_Timer and C_Timer.After then
      C_Timer.After(delay, Pump)
    else
      Pump()
    end
  else
    local q = pumpQueue
    pumpQueue = nil
    if q and q.ctx == "merchant" and BetterBackpack.Print then
      BetterBackpack.Print(string.format(
        "|cff88ccffBulk|r sold %d / %d%s",
        q.sold or 0,
        q.total or 0,
        q.label and (" · " .. q.label) or ""
      ))
    end
    if Layout and Layout.Refresh then
      Layout.Refresh()
    end
  end
end

local function StartQueue(ctx, slots, label)
  if not slots or #slots == 0 then
    return false, "empty"
  end
  pumpToken = pumpToken + 1
  pumpQueue = { ctx = ctx, slots = {}, token = pumpToken, sold = 0, total = #slots, label = label }
  for i = 1, #slots do
    pumpQueue.slots[i] = { bag = slots[i].bag, slot = slots[i].slot }
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, Pump)
  else
    Pump()
  end
  return true
end

function BulkTransfer.TransferLane(laneKey)
  local ctx = Context and Context.SpecialRmbContext and Context.SpecialRmbContext()
  if not headerTraceOnce and BetterBackpack.Print then
    headerTraceOnce = true
    local shift = IsShiftKeyDown and IsShiftKeyDown()
    BetterBackpack.Print(string.format(
      "|cff88ccffBulk|r header trace: lane=%s ctx=%s shift=%s ooc=%s",
      tostring(laneKey),
      tostring(ctx),
      tostring(shift),
      tostring(OOC())
    ))
  end
  if not OOC() or not laneKey or laneKey == TRASH then
    return false
  end
  if not ctx then
    if BetterBackpack.Print then
      BetterBackpack.Print("|cff88ccffBulk|r — open vendor, mail, or bank first")
    end
    return false
  end
  if not Layout or not Layout.ListLaneSlots then
    return false
  end
  local slots = Layout.ListLaneSlots(laneKey, true)
  if #slots == 0 then
    if BetterBackpack.Print then
      BetterBackpack.Print("|cff88ccffBulk|r " .. tostring(laneKey) .. " — nothing to move")
    end
    return true
  end
  local label = tostring(Layout.GetCategoryLabel and Layout.GetCategoryLabel(laneKey) or laneKey)
  local ok = StartQueue(ctx, slots, label)
  if ok and BetterBackpack.Print then
    BetterBackpack.Print(string.format(
      "|cff88ccffBulk|r %s · %s · %d stacks (selling…)",
      label,
      tostring(ActionVerb(ctx) or ctx),
      #slots
    ))
  end
  return ok
end

function BulkTransfer.LaneHeaderRmb(laneKey)
  return BulkTransfer.TransferLane(laneKey)
end

function BulkTransfer.TransferSlot(bag, slot, ctx)
  if not OOC() then
    return false
  end
  ctx = ctx or (Context and Context.SpecialRmbContext and Context.SpecialRmbContext())
  if not ctx then
    return false
  end
  return TransferOne(bag, slot, ctx)
end

function BulkTransfer.SlotQuality(bag, slot)
  return SlotQuality(bag, slot)
end

function BulkTransfer.MerchantCanSell(bag, slot)
  return MerchantAllowed(bag, slot)
end

return BulkTransfer