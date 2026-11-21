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
    out[#out + 1] = groups[order[i]]
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
  end
end
