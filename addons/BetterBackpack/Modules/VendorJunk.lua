--[[
  VendorJunk — auto-sell at merchant (≠ Trash destroy).
  Default: poor (grey) quality only. Opt-in: non-grey items in Junk lane.
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local VendorJunk = {}
BetterBackpack.Modules.VendorJunk = VendorJunk

local Config = BetterBackpack.Config
local BulkTransfer = BetterBackpack.Modules.BulkTransfer
local Layout = BetterBackpack.Modules.Layout
local Slots = BetterBackpack.Modules.Slots

local selling = false

local function Profile()
  return Config.GetProfile()
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

local function ShouldAutoSell(bag, slot)
  if not BulkTransfer or not BulkTransfer.MerchantCanSell then
    return false
  end
  if not BulkTransfer.MerchantCanSell(bag, slot) then
    return false
  end
  local q = BulkTransfer.SlotQuality and BulkTransfer.SlotQuality(bag, slot)
  if GreyQuality(q) then
    return true
  end
  local p = Profile()
  if p.autoSellJunkLane and InJunkLane(bag, slot) then
    return true
  end
  return false
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

local function SellPump(list, idx)
  if not OOC() or selling == false then
    selling = false
    if Layout and Layout.Refresh then
      Layout.Refresh()
    end
    return
  end
  if not list or idx > #list then
    selling = false
    if BetterBackpack.Print then
      BetterBackpack.Print("|cff88ccffVendor|r auto-sell done")
    end
    if Layout and Layout.Refresh then
      Layout.Refresh()
    end
    return
  end
  local moved = 0
  local limit = 14
  while idx <= #list and moved < limit do
    local e = list[idx]
    idx = idx + 1
    if e and Slots.SlotOccupied(e.bag, e.slot) and ShouldAutoSell(e.bag, e.slot) then
      if BulkTransfer.TransferSlot(e.bag, e.slot, "merchant") then
        moved = moved + 1
      end
    end
  end
  if idx <= #list then
    if C_Timer and C_Timer.After then
      C_Timer.After(0.05, function()
        SellPump(list, idx)
      end)
    else
      SellPump(list, idx)
    end
  else
    selling = false
    if Layout and Layout.Refresh then
      Layout.Refresh()
    end
  end
end

function VendorJunk.IsEnabled()
  local p = Profile()
  return p.autoSellJunk == true
end

function VendorJunk.SetEnabled(on)
  Profile().autoSellJunk = on and true or false
end

function VendorJunk.LaneOptIn()
  local p = Profile()
  return p.autoSellJunkLane == true
end

function VendorJunk.SetLaneOptIn(on)
  Profile().autoSellJunkLane = on and true or false
end

function VendorJunk.OnMerchantShow()
  if not VendorJunk.IsEnabled() or not OOC() or selling then
    return
  end
  local list = CollectSellList()
  if #list == 0 then
    return
  end
  selling = true
  if BetterBackpack.Print then
    BetterBackpack.Print(string.format("|cff88ccffVendor|r auto-sell · %d stacks", #list))
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0.15, function()
      SellPump(list, 1)
    end)
  else
    SellPump(list, 1)
  end
end

function VendorJunk.OnMerchantClosed()
  selling = false
end

return VendorJunk