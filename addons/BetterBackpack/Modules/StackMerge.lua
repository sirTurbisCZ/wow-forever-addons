--[[
  BetterBackpack.StackMerge — visual merge of stacks (v1).
  Merge key: itemID + isLocked (locked lockboxes never merge with unlocked same ID).
  One icon with summed count; click/RMB maps to the first real bag:slot.
  Other merged slots stay in inventory but are parked (not shown).
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local StackMerge = {}
BetterBackpack.Modules.StackMerge = StackMerge

local Config = BetterBackpack.Config
local Slots = BetterBackpack.Modules.Slots

local function Profile()
  return Config.GetProfile()
end

function StackMerge.IsEnabled()
  local p = Profile()
  return p.stackMerge ~= false
end

function StackMerge.SetEnabled(on)
  Profile().stackMerge = on and true or false
  local Layout = BetterBackpack.Modules.Layout
  if Layout and Layout.Relayout then
    Layout.Relayout()
  end
end

local function SafeNum(v)
  if Slots and Slots.SafeNum then
    return Slots.SafeNum(v)
  end
  if type(v) == "number" then
    return v
  end
  return nil
end

local function ResolveItemID(bag, slot)
  if not (C_Container and C_Container.GetContainerItemInfo) then
    return nil
  end
  local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
  if not ok or type(info) ~= "table" then
    return nil
  end
  local id = SafeNum(info.itemID)
  if id then
    return id, info
  end
  if C_Container.GetContainerItemID then
    local ok2, res = pcall(C_Container.GetContainerItemID, bag, slot)
    if ok2 then
      id = SafeNum(res)
      if id then
        return id, info
      end
    end
  end
  local link = info.hyperlink
  if type(link) == "string" and not (Slots.IsSecret and Slots.IsSecret(link)) then
    local fromLink = link:match("item:(%d+)")
    if fromLink then
      return tonumber(fromLink), info
    end
  end
  return nil, info
end

local function StackCount(bag, slot, info)
  if type(info) == "table" then
    for _, key in ipairs({ "stackCount", "Count", "quantity", "stack", "num" }) do
      local n = SafeNum(info[key])
      if n and n > 0 then
        return n
      end
    end
  end
  return 1
end

--- true / false / nil when isLocked is secret or unknown (do not merge with others).
local function SlotLockedFlag(info)
  if type(info) ~= "table" then
    return false
  end
  local raw = info.isLocked
  if raw == true or raw == 1 then
    return true
  end
  if raw == false or raw == 0 or raw == nil then
    return false
  end
  if Slots.IsSecret and Slots.IsSecret(raw) then
    return nil
  end
  return false
end

local function MergeGroupKey(id, bag, slot, info)
  local locked = SlotLockedFlag(info)
  if locked == nil then
    return id .. ":?:" .. tostring(bag) .. ":" .. tostring(slot)
  end
  return id .. ":" .. (locked and "L" or "U")
end

local mergeAnchors = {} -- mergeKey → last stable representative bag:slot

local function SortBagSlots(list)
  if type(list) ~= "table" then
    return
  end
  table.sort(list, function(a, b)
    local ba, bb = a.bag or 0, b.bag or 0
    if ba ~= bb then
      return ba < bb
    end
    return (a.slot or 0) < (b.slot or 0)
  end)
end

local function SlotStillOccupied(bag, slot)
  if not Slots or not Slots.SlotOccupied then
    return true
  end
  return Slots.SlotOccupied(bag, slot) and true or false
end

local function PickStableAnchor(mergeKey, mergedFrom)
  SortBagSlots(mergedFrom)
  if #mergedFrom == 0 then
    mergeAnchors[mergeKey] = nil
    return nil
  end
  local anchor = mergeAnchors[mergeKey]
  if anchor then
    local inGroup = false
    for i = 1, #mergedFrom do
      if mergedFrom[i].bag == anchor.bag and mergedFrom[i].slot == anchor.slot then
        inGroup = true
        break
      end
    end
    if inGroup then
      if SlotStillOccupied(anchor.bag, anchor.slot) then
        return anchor
      end
      -- Cursor pickup: paint from another stack in the group (no empty grid hole).
      for i = 1, #mergedFrom do
        local b, s = mergedFrom[i].bag, mergedFrom[i].slot
        if SlotStillOccupied(b, s) then
          return { bag = b, slot = s }
        end
      end
      return anchor
    end
    mergeAnchors[mergeKey] = nil
  end
  local pick = mergedFrom[1]
  for i = 1, #mergedFrom do
    local b, s = mergedFrom[i].bag, mergedFrom[i].slot
    if SlotStillOccupied(b, s) then
      pick = mergedFrom[i]
      break
    end
  end
  mergeAnchors[mergeKey] = { bag = pick.bag, slot = pick.slot }
  return pick
end

local function SumMergedGroupCount(mergedFrom)
  if type(mergedFrom) ~= "table" then
    return 0
  end
  local total = 0
  for i = 1, #mergedFrom do
    local bag, slot = mergedFrom[i].bag, mergedFrom[i].slot
    local _, info = ResolveItemID(bag, slot)
    total = total + StackCount(bag, slot, info)
  end
  return total
end

--- True when a visible merged icon still points at an empty slot but siblings exist (cursor pickup).
function StackMerge.VisibleRepaintNeeded()
  if not StackMerge.IsEnabled() or not Slots or not Slots.ForEach or not Slots.SlotOccupied then
    return false
  end
  local needs = false
  Slots.ForEach(function(btn)
    if needs or not btn or (btn:GetAlpha() or 0) < 0.5 then
      return
    end
    if not btn._bbMergedFrom or #btn._bbMergedFrom < 2 then
      return
    end
    local b, s = btn._bbBag, btn._bbSlot
    if b == nil or s == nil or Slots.SlotOccupied(b, s) then
      return
    end
    for i = 1, #btn._bbMergedFrom do
      local mb, ms = btn._bbMergedFrom[i].bag, btn._bbMergedFrom[i].slot
      if mb ~= nil and ms ~= nil and Slots.SlotOccupied(mb, ms) then
        needs = true
        return
      end
    end
  end)
  return needs
end

--- Update summed stack text without Layout.DoLayout (BAG_UPDATE / pickup).
function StackMerge.RefreshMergedButtons()
  if not StackMerge.IsEnabled() or not Slots or not Slots.ForEach then
    return
  end
  Slots.ForEach(function(btn)
    if not btn or not btn._bbMergedFrom or #btn._bbMergedFrom < 2 then
      return
    end
    local total = SumMergedGroupCount(btn._bbMergedFrom)
    if total < 1 then
      return
    end
    StackMerge.ApplyDisplayCount(btn, {
      displayCount = total,
      mergedFrom = btn._bbMergedFrom,
    })
  end)
end

--- Collapse list of {bag,slot} into entries with displayCount / mergedFrom.
function StackMerge.Collapse(list)
  if not StackMerge.IsEnabled() or type(list) ~= "table" or #list == 0 then
    return list
  end
  local groups = {} -- mergeKey → entry
  local order = {}
  local noId = {}
  for i = 1, #list do
    local bag, slot = list[i].bag, list[i].slot
    local id, info = ResolveItemID(bag, slot)
    local count = StackCount(bag, slot, info)
    if not id then
      noId[#noId + 1] = { bag = bag, slot = slot, displayCount = count }
    else
      local key = MergeGroupKey(id, bag, slot, info)
      local g = groups[key]
      if not g then
        g = {
          bag = bag,
          slot = slot,
          itemID = id,
          displayCount = count,
          mergedFrom = { { bag = bag, slot = slot } },
        }
        groups[key] = g
        order[#order + 1] = key
      else
        g.displayCount = (g.displayCount or 0) + count
        g.mergedFrom[#g.mergedFrom + 1] = { bag = bag, slot = slot }
      end
    end
  end
  local out = {}
  for i = 1, #order do
    local key = order[i]
    local g = groups[key]
    if g and g.mergedFrom and #g.mergedFrom > 0 then
      local anchor = PickStableAnchor(key, g.mergedFrom)
      if anchor then
        g.bag = anchor.bag
        g.slot = anchor.slot
      end
    end
    out[#out + 1] = g
  end
  for i = 1, #noId do
    out[#out + 1] = noId[i]
  end
  return out
end

function StackMerge.ApplyDisplayCount(btn, entry)
  if not btn or not entry then
    return
  end
  local count = entry.displayCount
  if type(count) ~= "number" or count <= 1 then
    return
  end
  local fs = btn.Count
  if not fs then
    pcall(function()
      fs = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
      fs:SetPoint("BOTTOMRIGHT", -3, 2)
      btn.Count = fs
    end)
  end
  if not fs then
    return
  end
  pcall(function()
    fs:SetText(tostring(count))
    -- Same white NumberFontNormalSmall as any Blizzard stack — merge is invisible chrome-wise.
    fs:SetTextColor(1, 1, 1, 1)
    fs:Show()
  end)
  local n = entry.mergedFrom and #entry.mergedFrom or 1
  if n > 1 then
    btn._bbMergedStacks = n
    btn._bbMergedFrom = entry.mergedFrom
  else
    btn._bbMergedStacks = nil
    btn._bbMergedFrom = nil
  end
end

--- All bag:slot stacks sharing the same merge key as anchor (inventory scan).
--- mergedFromHint: optional button._bbMergedFrom when anchor bag:slot is briefly empty.
function StackMerge.CollectMergeGroup(anchorBag, anchorSlot, mergedFromHint)
  local single = { { bag = anchorBag, slot = anchorSlot } }
  if not StackMerge.IsEnabled() then
    return single
  end
  if type(mergedFromHint) == "table" and #mergedFromHint > 0 then
    local resolved = false
    for i = 1, #mergedFromHint do
      local b, s = mergedFromHint[i].bag, mergedFromHint[i].slot
      if b ~= nil and s ~= nil then
        local emptyOk = not Slots or not Slots.SlotOccupied or Slots.SlotOccupied(b, s)
        if emptyOk then
          local id = ResolveItemID(b, s)
          if id then
            anchorBag, anchorSlot = b, s
            resolved = true
            break
          end
        end
      end
    end
    if not resolved then
      for i = 1, #mergedFromHint do
        local id = ResolveItemID(mergedFromHint[i].bag, mergedFromHint[i].slot)
        if id then
          anchorBag = mergedFromHint[i].bag
          anchorSlot = mergedFromHint[i].slot
          break
        end
      end
    end
  end
  local anchorID, anchorInfo = ResolveItemID(anchorBag, anchorSlot)
  if not anchorID then
    return single
  end
  local anchorKey = MergeGroupKey(anchorID, anchorBag, anchorSlot, anchorInfo)
  local out = {}
  local ranges = Slots and Slots.InventoryBagRanges and Slots.InventoryBagRanges()
  if type(ranges) ~= "table" then
    return single
  end
  for ri = 1, #ranges do
    local b = ranges[ri].bag
    local numSlots = ranges[ri].slots
    if b ~= nil and type(numSlots) ~= "number" then
      if Slots and Slots.NumSlotsForBag then
        numSlots = Slots.NumSlotsForBag(b)
      elseif C_Container and C_Container.GetContainerNumSlots then
        local okN, n = pcall(C_Container.GetContainerNumSlots, b)
        if okN then
          numSlots = n
        end
      elseif GetContainerNumSlots then
        local okN, n = pcall(GetContainerNumSlots, b)
        if okN then
          numSlots = n
        end
      end
    end
    if b ~= nil and type(numSlots) == "number" and numSlots > 0 then
      for s = 1, numSlots do
        if Slots and Slots.SlotOccupied and not Slots.SlotOccupied(b, s) then
          -- skip empty
        else
          local id, info = ResolveItemID(b, s)
          if id and MergeGroupKey(id, b, s, info) == anchorKey then
            out[#out + 1] = { bag = b, slot = s }
          end
        end
      end
    end
  end
  SortBagSlots(out)
  if #out == 0 then
    return single
  end
  return out
end

--- Regression wiring for /bb selftest (no live vendor).
function StackMerge.RunSelfTest()
  local pass, fail, notes = 0, 0, {}
  local function ok(cond, msg)
    if cond then
      pass = pass + 1
    else
      fail = fail + 1
      notes[#notes + 1] = msg
    end
  end
  ok(StackMerge.Collapse ~= nil, "Collapse missing")
  ok(StackMerge.CollectMergeGroup ~= nil, "CollectMergeGroup missing")
  ok(StackMerge.VisibleRepaintNeeded ~= nil, "VisibleRepaintNeeded missing")
  ok(StackMerge.RefreshMergedButtons ~= nil, "RefreshMergedButtons missing")
  ok(StackMerge.IsEnabled() == true or StackMerge.IsEnabled() == false, "IsEnabled broken")
  local list = { { bag = 0, slot = 1 }, { bag = 0, slot = 2 } }
  local collapsed = StackMerge.Collapse(list)
  ok(type(collapsed) == "table", "Collapse not table")
  ok(#collapsed >= 1, "Collapse returned no entries")
  ok(type(StackMerge.CollectMergeGroup(0, 1)) == "table", "CollectMergeGroup not table")
  return fail == 0, pass, fail, notes
end
