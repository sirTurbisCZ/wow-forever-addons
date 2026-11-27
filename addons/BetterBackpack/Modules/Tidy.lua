--[[
  BetterBackpack.Tidy — OOC tidy: SortBags then stack merge.
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local Tidy = {}
BetterBackpack.Modules.Tidy = Tidy

local Config = BetterBackpack.Config
local Slots = BetterBackpack.Modules.Slots
local Layout = BetterBackpack.Modules.Layout
local L = BetterBackpack.L or {}

local sortBusy = false
local sortToken = 0

local function Print(...)
  if BetterBackpack.Print then
    BetterBackpack.Print(...)
  end
end

local function ClearCur()
  if ClearCursor then
    pcall(ClearCursor)
  end
end

-- true only when the item really is on the cursor (pcall status alone says nothing).
local function Pickup(bag, slot)
  local ok
  if C_Container and C_Container.PickupContainerItem then
    ok = pcall(C_Container.PickupContainerItem, bag, slot)
  elseif PickupContainerItem then
    ok = pcall(PickupContainerItem, bag, slot)
  end
  if not ok then
    return false
  end
  if CursorHasItem then
    local has = CursorHasItem()
    return has and true or false
  end
  return GetCursorInfo ~= nil and GetCursorInfo() ~= nil
end

-- Max stack per item id (ContainerItemInfo has no maxStack field). Unknown -> nil -> no merge.
local maxStackCache = {}
local function MaxStackFor(id)
  local m = maxStackCache[id]
  if m then
    return m
  end
  if C_Item and C_Item.GetItemMaxStackCount then
    local ok, v = pcall(C_Item.GetItemMaxStackCount, id)
    if ok and type(v) == "number" and not Slots.IsSecret(v) and v > 0 then
      maxStackCache[id] = v
      return v
    end
  end
  return nil
end
Tidy.MaxStackFor = MaxStackFor

-- One GetContainerItemInfo per slot per pass: { bag, slot, id, count } for partial stacks.
local function ReadPartials(ranges)
  local list = {}
  if not (C_Container and C_Container.GetContainerItemInfo) then
    return list
  end
  for ri = 1, #ranges do
    local bag = ranges[ri].bag
    local n = Slots.NumSlotsForBag(bag)
    for slot = 1, n do
      local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
      if ok and type(info) == "table" then
        local id = info.itemID
        local c = info.stackCount or info.Count
        if type(id) == "number" and not Slots.IsSecret(id) and not info.isLocked then
          if type(c) ~= "number" or Slots.IsSecret(c) then
            c = 1
          end
          local max = MaxStackFor(id)
          if max and c > 0 and c < max then
            list[#list + 1] = { bag = bag, slot = slot, id = id, count = c, max = max }
          end
        end
      end
    end
  end
  return list
end

local function StackBagsOnce()
  local ranges = Slots.InventoryBagRanges()
  local list = ReadPartials(ranges)
  local merges = 0
  for i = 1, #list do
    local a = list[i]
    if not a.used then
      for j = i + 1, #list do
        local b = list[j]
        if not b.used and b.id == a.id then
          ClearCur()
          if Pickup(a.bag, a.slot) then
            Pickup(b.bag, b.slot)
            a.used, b.used = true, true -- stale now; the next pass re-reads
            merges = merges + 1
            ClearCur()
            if merges >= 50 then
              return merges
            end
            break
          end
          ClearCur()
          break -- source would not lift (locked); don't retry it against every partner
        end
      end
    end
  end
  ClearCur()
  return merges
end

local function CallNativeSort()
  if C_Container then
    if type(C_Container.SortBags) == "function" then
      local ok = pcall(C_Container.SortBags)
      if ok then
        return true
      end
    end
    if type(C_Container.SortBankBags) == "function" then
      -- ignore bank; bags only
    end
  end
  if type(SortBags) == "function" then
    local ok = pcall(SortBags)
    if ok then
      return true
    end
  end
  return false
end

function Tidy.SortBags()
  if InCombatLockdown and InCombatLockdown() then
    Print(L.SORT_COMBAT or "sort: not in combat")
    return false
  end
  if sortBusy then
    Print(L.SORT_BUSY or "sort already running…")
    return false
  end

  if Layout and Layout.ResetLaneOrder then
    Layout.ResetLaneOrder()
  end
  sortBusy = true
  sortToken = sortToken + 1
  local token = sortToken
  BetterBackpack._sortSuppressRefresh = true
  Print(L.SORT_START or "tidying…")

  local function finish()
    if token ~= sortToken then
      return
    end
    BetterBackpack._sortSuppressRefresh = false
    sortBusy = false
    ClearCur()
    if Layout and Layout.Refresh then
      Layout.Refresh()
    end
    Print(L.SORT_DONE or "tidy done")
  end

  local sorted = CallNativeSort()
  -- Always follow with a stack pass (SortBags leaves partial stacks).
  local function afterSort()
    if token ~= sortToken then
      return
    end
    if not (InCombatLockdown and InCombatLockdown()) then
      StackBagsOnce()
      StackBagsOnce()
    end
    if C_Timer and C_Timer.After then
      C_Timer.After(0.15, finish)
    else
      finish()
    end
  end

  if sorted then
    if C_Timer and C_Timer.After then
      C_Timer.After(0.45, afterSort)
    else
      afterSort()
    end
    return true
  end

  StackBagsOnce()
  StackBagsOnce()
  if C_Timer and C_Timer.After then
    C_Timer.After(0.1, finish)
  else
    finish()
  end
  return true
end

function Tidy.StackBags()
  if InCombatLockdown and InCombatLockdown() then
    Print(L.SORT_COMBAT or "sort: not in combat")
    return false
  end
  StackBagsOnce()
  StackBagsOnce()
  if Layout and Layout.ResetLaneOrder then
    Layout.ResetLaneOrder()
  end
  if Layout and Layout.Refresh then
    Layout.Refresh()
  end
  return true
end
