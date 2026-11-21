--[[
  BetterBackpack.Tidy — OOC Úklid: SortBags then stack merge.
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

local function Pickup(bag, slot)
  if C_Container and C_Container.PickupContainerItem then
    return pcall(C_Container.PickupContainerItem, bag, slot)
  end
  if PickupContainerItem then
    return pcall(PickupContainerItem, bag, slot)
  end
  return false
end

local function SlotItemID(bag, slot)
  if C_Container and C_Container.GetContainerItemID then
    local ok, id = pcall(C_Container.GetContainerItemID, bag, slot)
    if ok and type(id) == "number" and not Slots.IsSecret(id) then
      return id
    end
  end
  return nil
end

local function SlotCount(bag, slot)
  if not (C_Container and C_Container.GetContainerItemInfo) then
    return 0
  end
  local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
  if not ok or type(info) ~= "table" then
    return 0
  end
  local c = info.stackCount or info.Count
  if type(c) == "number" and not Slots.IsSecret(c) then
    return c
  end
  return 1
end

local function SlotMaxStack(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if ok and type(info) == "table" then
      local m = info.maxStack or info.stackSize
      if type(m) == "number" and not (Slots.IsSecret and Slots.IsSecret(m)) and m > 1 then
        return m
      end
    end
  end
  return 9999
end

local function StackBagsOnce()
  local bags = { 0, 1, 2, 3, 4 }
  local merges = 0
  for bi = 1, #bags do
    local bag = bags[bi]
    local n = Slots.NumSlotsForBag(bag)
    for slot = 1, n do
      local id = SlotItemID(bag, slot)
      if id then
        local count = SlotCount(bag, slot)
        local maxStack = SlotMaxStack(bag, slot)
        if count > 0 and count < maxStack then
          for bj = bi, #bags do
            local bag2 = bags[bj]
            local n2 = Slots.NumSlotsForBag(bag2)
            local start = (bj == bi) and (slot + 1) or 1
            for slot2 = start, n2 do
              if SlotItemID(bag2, slot2) == id then
                local c2 = SlotCount(bag2, slot2)
                if c2 > 0 and c2 < maxStack then
                  ClearCur()
                  if Pickup(bag, slot) then
                    Pickup(bag2, slot2)
                    merges = merges + 1
                    if merges >= 50 then
                      ClearCur()
                      return merges
                    end
                  end
                  ClearCur()
                end
              end
            end
          end
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
  if Layout and Layout.Refresh then
    Layout.Refresh()
  end
  return true
end
