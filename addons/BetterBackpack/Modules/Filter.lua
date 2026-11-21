--[[
  BetterBackpack.Filter — filter by category key or "all" (v1 nice-to-have).
  Empty / "all" = show every enabled lane. Otherwise only that category lane.
]]

BetterBackpack = BetterBackpack or {}
BetterBackpack.Modules = BetterBackpack.Modules or {}

local Filter = {}
BetterBackpack.Modules.Filter = Filter

local Config = BetterBackpack.Config

local function Profile()
  return Config.GetProfile()
end

function Filter.GetCategory()
  local p = Profile()
  local f = p.filterCategory
  if type(f) ~= "string" or f == "" or f == "all" then
    return nil
  end
  return f
end

function Filter.SetCategory(key)
  local p = Profile()
  if type(key) ~= "string" or key == "" or key == "all" then
    p.filterCategory = nil
  else
    p.filterCategory = key
  end
  local Layout = BetterBackpack.Modules.Layout
  if Layout and Layout.Relayout then
    Layout.Relayout()
  end
end

--- Category key already resolved. Return false to skip the slot.
function Filter.Passes(cat)
  local want = Filter.GetCategory()
  if not want then
    return true
  end
  return cat == want
end

function Filter.ListKeys()
  local Layout = BetterBackpack.Modules.Layout
  local order = (Layout and Layout.GetCategoryOrder and Layout.GetCategoryOrder())
    or (Layout and Layout.CATEGORY_ORDER)
    or { "junk", "consumable", "reagent", "gem", "gear", "quest", "keys", "container", "other" }
  local out = { "all" }
  for i = 1, #order do
    out[#out + 1] = order[i]
  end
  return out
end
