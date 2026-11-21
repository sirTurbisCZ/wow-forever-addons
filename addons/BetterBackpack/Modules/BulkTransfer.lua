-- BulkTransfer - lane header Shift+RMB bulk (OOC only).
-- Context: merchant = sell, mail = attach, bank = UseContainerItem deposit.
-- Never touches OpenClose / Toggle* globals.

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

local function OOC()
  if InCombatLockdown and InCombatLockdown() then
    return false
  end
  return true
end

local function ContainerAPI(bag, slot)
  if Slots and Slots.ContainerAPI then
    local b, s = Slots.ContainerAPI(bag, slot)
    if b ~= nil and s ~= nil then
      return b, s
    end
  end
  return bag, slot
end

local function ItemID(bag, slot)
  local b, s = ContainerAPI(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local ok, info = pcall(C_Container.GetContainerItemInfo, b, s)
    if ok and info and info.itemID then
      return info.itemID
    end
  end
  if GetContainerItemID then
    local ok, id = pcall(GetContainerItemID, b, s)
    if ok then
      return id
    end
  end
  return nil
end

local function SlotQuality(bag, slot)
  local b, s = ContainerAPI(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local ok, info = pcall(C_Container.GetContainerItemInfo, b, s)
    if ok and info and info.quality ~= nil then
      if Slots and Slots.SafeNum then
        return Slots.SafeNum(info.quality, nil)
      end
      return info.quality
    end
  end
  return nil
end

local function SlotLocked(bag, slot)
  local b, s = ContainerAPI(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local ok, info = pcall(C_Container.GetContainerItemInfo, b, s)
    if ok and info and info.isLocked then
      return true
    end
  end
  return false
end

local function PickupSlot(bag, slot)
  local b, s = ContainerAPI(bag, slot)
  if ClearCursor then
    pcall(ClearCursor)
  end
  if C_Container and C_Container.PickupContainerItem then
    return select(1, pcall(C_Container.PickupContainerItem, b, s))
  end
  if PickupContainerItem then
    return select(1, pcall(PickupContainerItem, b, s))
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

local function StackCount(bag, slot)
  local b, s = ContainerAPI(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local ok, info = pcall(C_Container.GetContainerItemInfo, b, s)
    if ok and info and info.stackCount ~= nil then
      return info.stackCount
    end
  end
  return nil
end

local function SlotChanged(bag, slot, idBefore, countBefore)
  local b, s = ContainerAPI(bag, slot)
  if not Slots or not Slots.SlotOccupied then
    return true
  end
  if not Slots.SlotOccupied(b, s) then
    return true
  end
  local idAfter = ItemID(b, s)
  if idBefore and idAfter and idBefore ~= idAfter then
    return true
  end
  local countAfter = StackCount(b, s)
  if countBefore and countAfter and countAfter < countBefore then
    return true
  end
  return false
end

local function DetectContext()
  if Context and Context.SpecialRmbContext then
    return Context.SpecialRmbContext()
  end
  return nil
end

local function MerchantFrameOpen()
  if Context and Context.SpecialRmbContext and Context.SpecialRmbContext() == "merchant" then
    return true
  end
  if MerchantFrame then
    if MerchantFrame.IsVisible then
      local ok, v = pcall(MerchantFrame.IsVisible, MerchantFrame)
      if ok and v then
        return true
      end
    end
    if MerchantFrame.IsShown then
      local ok, v = pcall(MerchantFrame.IsShown, MerchantFrame)
      if ok and v then
        return true
      end
    end
  end
  return false
end

local function MerchantAllowed(bag, slot)
  local b, s = ContainerAPI(bag, slot)
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
  local b, s = ContainerAPI(bag, slot)
  local idBefore = ItemID(b, s)
  local countBefore = StackCount(b, s)
  local used = false
  if C_Container and C_Container.UseContainerItem then
    used = select(1, pcall(C_Container.UseContainerItem, b, s))
  elseif UseContainerItem then
    used = select(1, pcall(UseContainerItem, b, s))
  end
  if not used then
    return false, false
  end
  if SlotChanged(b, s, idBefore, countBefore) then
    return true, true
  end
  return true, false
end

local function MerchantPickupSell(bag, slot)
  local b, s = ContainerAPI(bag, slot)
  local idBefore = ItemID(b, s)
  local countBefore = StackCount(b, s)
  if not PickupSlot(b, s) or not CursorHasSomething() then
    return false, false
  end
  local sold = false
  if SellCursorItem then
    sold = select(1, pcall(SellCursorItem))
  end
  if ClearCursor then
    pcall(ClearCursor)
  end
  if sold then
    return true, true
  end
  if SlotChanged(b, s, idBefore, countBefore) then
    return true, true
  end
  return false, false
end

local function TransferMerchant(bag, slot)
  local b, s = ContainerAPI(bag, slot)
  if not MerchantAllowed(b, s) then
    return false
  end
  local okPick, _ = MerchantPickupSell(b, s)
  if okPick then
    return true
  end
  local okUse, changed = MerchantUseContainer(b, s)
  if okUse and changed then
    return true
  end
  return false
end

local function TransferMail(bag, slot)
  local b, s = ContainerAPI(bag, slot)
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
  local b, s = ContainerAPI(bag, slot)
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

local function BulkPrint(msg)
  if BetterBackpack.Print then
    BetterBackpack.Print("|cff88ccffBulk|r " .. tostring(msg))
  end
end

local function FinishMerchantPump(q)
  if not q or q.ctx ~= "merchant" then
    return
  end
  BulkPrint(string.format(
    "sold %d / %d%s",
    q.sold or 0,
    q.total or 0,
    q.label and (" · " .. q.label) or ""
  ))
  if q.diag and q.diag ~= "" then
    BulkPrint(q.diag)
  end
end

local function PumpStep(limit)
  if not pumpQueue or not OOC() then
    return false
  end
  local ctx = pumpQueue.ctx
  limit = limit or 1
  local moved = 0
  while #pumpQueue.slots > 0 and moved < limit do
    local e = table.remove(pumpQueue.slots, 1)
    local b, s = e and e.bag, e and e.slot
    if b ~= nil and s ~= nil then
      b, s = ContainerAPI(b, s)
    end
    if b ~= nil and s ~= nil and Slots.SlotOccupied and Slots.SlotOccupied(b, s) then
      if TransferOne(b, s, ctx) then
        moved = moved + 1
        pumpQueue.sold = (pumpQueue.sold or 0) + 1
      end
    end
  end
  return moved > 0
end

local function PumpAsync()
  if not pumpQueue then
    return
  end
  if not OOC() then
    local q = pumpQueue
    pumpQueue = nil
    FinishMerchantPump(q)
    return
  end
  if #pumpQueue.slots == 0 then
    local q = pumpQueue
    pumpQueue = nil
    FinishMerchantPump(q)
    if Layout and Layout.Refresh then
      Layout.Refresh()
    end
    return
  end
  PumpStep(12)
  if #pumpQueue.slots > 0 then
    if C_Timer and C_Timer.After then
      C_Timer.After(0.04, PumpAsync)
    else
      PumpAsync()
    end
  else
    local q = pumpQueue
    pumpQueue = nil
    FinishMerchantPump(q)
    if Layout and Layout.Refresh then
      Layout.Refresh()
    end
  end
end

local function StartQueue(ctx, slots, label, diag, syncMax)
  if not slots or #slots == 0 then
    return false, "empty"
  end
  pumpToken = pumpToken + 1
  pumpQueue = {
    ctx = ctx,
    slots = {},
    token = pumpToken,
    sold = 0,
    total = #slots,
    label = label,
    diag = diag,
  }
  for i = 1, #slots do
    pumpQueue.slots[i] = { bag = slots[i].bag, slot = slots[i].slot }
  end
  BulkPrint(string.format(
    "pump start · ctx=%s queued=%d token=%d sync=%s",
    tostring(ctx),
    #pumpQueue.slots,
    pumpToken,
    tostring(syncMax or "async")
  ))
  if ctx == "merchant" or ctx == "mail" then
    syncMax = syncMax or 48
    local steps = 0
    while pumpQueue and #pumpQueue.slots > 0 and steps < syncMax and OOC() do
      PumpStep(1)
      steps = steps + 1
    end
    local q = pumpQueue
    pumpQueue = nil
    if q and q.ctx == "merchant" then
      FinishMerchantPump(q)
    elseif q and BetterBackpack.Print then
      BulkPrint(string.format("moved %d / %d%s", q.sold or 0, q.total or 0, q.label and (" · " .. q.label) or ""))
    end
    if Layout and Layout.Refresh then
      Layout.Refresh()
    end
    return true
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, PumpAsync)
  else
    PumpAsync()
  end
  return true
end

local function MerchantProbe(first)
  if not first then
    return ""
  end
  local b, s = ContainerAPI(first.bag, first.slot)
  local mVis = MerchantFrameOpen()
  local repair = false
  if CanMerchantRepair then
    local ok, v = pcall(CanMerchantRepair)
    repair = ok and v and true or false
  end
  local id = ItemID(b, s)
  local allowed = id and MerchantAllowed(b, s)
  local useApi = (C_Container and C_Container.UseContainerItem) and true or (UseContainerItem and true or false)
  local sellApi = SellCursorItem and true or false
  return string.format(
    "probe id=%s allowed=%s useApi=%s sellApi=%s merchant=%s CanMerchantRepair=%s bag=%s slot=%s",
    tostring(id),
    tostring(allowed),
    tostring(useApi),
    tostring(sellApi),
    tostring(mVis),
    tostring(repair),
    tostring(b),
    tostring(s)
  )
end

function BulkTransfer.TransferLane(laneKey)
  BulkPrint("TransferLane enter · " .. tostring(laneKey))
  if not OOC() then
    BulkPrint("abort · in combat lockdown")
    return false
  end
  if not laneKey or laneKey == TRASH then
    BulkPrint("abort · invalid lane")
    return false
  end
  local ctx = DetectContext()
  BulkPrint("DetectContext · ctx=" .. tostring(ctx))
  if not ctx then
    BulkPrint("abort · open vendor, mail, or bank first")
    return false
  end
  if not Layout or not Layout.ListLaneSlots then
    BulkPrint("abort · Layout.ListLaneSlots missing")
    return false
  end
  local slots = Layout.ListLaneSlots(laneKey, true)
  BulkPrint(string.format("ListLaneSlots · lane=%s count=%d", tostring(laneKey), #slots))
  local mOpen = MerchantFrameOpen()
  local repair = false
  if CanMerchantRepair then
    local ok, v = pcall(CanMerchantRepair)
    repair = ok and v and true or false
  end
  if ctx == "merchant" then
    local first = slots[1]
    local fb, fs = first and ContainerAPI(first.bag, first.slot)
    BulkPrint(string.format(
      "merchant=%s CanMerchantRepair=%s first=%s:%s",
      tostring(mOpen),
      tostring(repair),
      tostring(fb),
      tostring(fs)
    ))
  end
  if #slots == 0 then
    BulkPrint(tostring(laneKey) .. " — nothing to move")
    return true
  end
  if ctx == "merchant" and not mOpen then
    BulkPrint("warn · merchant UI not detected — trying sell anyway (ctx=merchant)")
  end
  local label = tostring(Layout.GetCategoryLabel and Layout.GetCategoryLabel(laneKey) or laneKey)
  local diag = ctx == "merchant" and MerchantProbe(slots[1]) or nil
  BulkPrint(string.format("%s · %s · %d stacks · queue…", label, tostring(ActionVerb(ctx) or ctx), #slots))
  local ok = StartQueue(ctx, slots, label, diag)
  if not ok then
    BulkPrint("abort · StartQueue failed")
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